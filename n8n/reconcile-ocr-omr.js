// n8n Code node: "reconcile ocr and omr"
// Place immediately after "ai validation ocr and omr" (the renamed Gemini node).
// This REPLACES "separate it", which cannot work -- it reads
// item.json.choices[0].message.content, the OpenAI response shape, while the
// node calls Google's native generateContent endpoint that returns
// candidates[0].content.parts[0].text. The throw is swallowed by its own
// try/catch, so the scan path has been producing empty OCR data silently.
//
// ── Priority, fixed by design ──────────────────────────────────────────────
//   OCR text fields   -> Gemini wins.  The Python OCR is unreliable.
//   OMR bubble scores -> Python wins.  That is what it was built for.
//
// Gemini's OMR is a cross-check, not a source. It never overrides a value
// Python actually read. It only does two things: fill in a bubble Python
// missed, and vote on whether a human needs to look at this scan.
//
// ── Thresholds ─────────────────────────────────────────────────────────────
// A 3-vs-4 disagreement is camera noise, not a problem, so a difference only
// counts when it is at least 2 apart. Five such differences out of twenty means
// the grid was probably misaligned rather than one bubble misread.

const FLAG_DIFF_MARGIN  = 2;   // smaller than this is noise; Python wins silently
const FLAG_DIFF_COUNT   = 5;   // this many real differences -> needs a human
const MAX_AGREED_BLANKS = 10;  // more than half the form blank -> needs a human
const QUESTIONS         = 10;  // per section

// ── The rating scale ───────────────────────────────────────────────────────
// The form's columns are LETTERED, not numbered. Mapping verified against the
// legend the app prints itself (pdf_service.dart:426) and against
// omr_ground_truth_merged.json, 24 labelled forms whose only answer values are
// O, VS, S, F, US and blank:
//   O  Outstanding       4.21-5.00
//   VS Very Satisfactory 3.41-4.20
//   S  Satisfactory      2.61-3.40
//   F  Fair              1.81-2.60
//   US Unsatisfactory    1.00-1.80
// Note F ranks ABOVE US. Swapping those two would invert the bottom of every
// instructor's score while still looking plausible.
const LETTER_TO_SCORE = { O: 5, VS: 4, S: 3, F: 2, US: 1 };

/** 'VS', 'vs', 4 and '4' all become 4. 'blank', '', junk -> null. */
function toScore(value) {
  if (value === null || value === undefined) return null;
  const raw = String(value).trim();
  if (raw === '' || raw.toLowerCase() === 'blank') return null;

  const letter = LETTER_TO_SCORE[raw.toUpperCase()];
  if (letter !== undefined) return letter;

  const n = Number(raw);
  return Number.isFinite(n) && n >= 1 && n <= 5 ? n : null;
}

// ── Python side ────────────────────────────────────────────────────────────
const py = $('image to ocr and omr python').first().json;

/** Python's reading for one question, or null when it detected no mark. */
function pythonScore(section, index) {
  const cell = (py.ratings?.[section] ?? [])[index];
  if (!cell || !cell.detected) return null;
  // Accepts a number or a letter code. The OMR service reports a numeric score
  // today, but the form itself is lettered, so do not assume either way.
  return toScore(cell.score ?? cell.answer);
}

// ── Gemini side ────────────────────────────────────────────────────────────
// Parsed defensively: a failed cross-check must not fail the scan. When Gemini
// is unavailable the row still processes on Python's values, but it is recorded
// as unverified rather than passed off as verified.
let gemini = {};
let geminiOk = false;
try {
  const text = $input.first().json?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (text) {
    // responseMimeType is application/json, but strip fences defensively.
    const match = String(text).match(/\{[\s\S]*\}/);
    if (match) {
      gemini = JSON.parse(match[0]);
      geminiOk = true;
    }
  }
} catch (e) {
  console.log('Gemini parse failed, continuing on Python alone:', e.message);
  geminiOk = false;
}

/** Gemini's reading for one question. 'blank' or anything invalid -> null. */
function geminiScore(key) {
  if (!geminiOk) return null;
  return toScore(gemini.ratings?.[key]);
}

// ── Reconcile the twenty bubbles ───────────────────────────────────────────
const scores        = {};
const comparisons   = [];
let agreedBlanks    = 0;
let filledByGemini  = 0;
let realDifferences = 0;

for (const [section, prefix] of [['management', 'm'], ['performance', 'p']]) {
  for (let i = 0; i < QUESTIONS; i++) {
    const key = `${prefix}${i + 1}`;
    const p = pythonScore(section, i);
    const g = geminiScore(key);

    let used;
    let source;

    if (p !== null) {
      // Python read a mark. It wins, always -- Gemini only registers a vote.
      used = p;
      source = 'python';
      if (g !== null && Math.abs(p - g) >= FLAG_DIFF_MARGIN) realDifferences++;
    } else if (g !== null) {
      // Python saw nothing where Gemini saw a mark. Recovering the answer is
      // better than dropping a student's response.
      used = g;
      source = 'gemini_fill';
      filledByGemini++;
    } else {
      // Both agree there is no mark. A genuine blank.
      used = null;
      source = 'blank';
      agreedBlanks++;
    }

    scores[key] = used;
    comparisons.push({ question: key, python: p, gemini: g, used, source });
  }
}

// ── Decide whether a human is needed ───────────────────────────────────────
const reasons = [];
if (!geminiOk) reasons.push('gemini_unavailable');
if (realDifferences >= FLAG_DIFF_COUNT) {
  reasons.push(`omr_disagreement_${realDifferences}_of_20`);
}
if (agreedBlanks > MAX_AGREED_BLANKS) {
  reasons.push(`too_many_blanks_${agreedBlanks}_of_20`);
}
if (py.table_found === false) reasons.push('grid_not_detected');

// A missing cross-check is not grounds for making staff re-read a scan Python
// handled fine. It is grounds for recording that nothing verified it.
const needsReview = reasons.some((r) => r !== 'gemini_unavailable');

const validationStatus = needsReview
  ? 'flagged'
  : geminiOk
    ? 'auto'
    : 'auto_unverified';

// ── OCR fields: Gemini first, Python only as a fallback ────────────────────
const pythonOcr = py.ocr_fields ?? {};
const prefer = (primary, fallback) => {
  const v = (primary ?? '').toString().trim();
  return v !== '' ? v : (fallback ?? '').toString().trim();
};

// ── Scan identity. Read from the node that built it, since the Python
// service does not echo term_id back.
let scanMeta = {};
try {
  scanMeta = $('Code in JavaScript4').first().json ?? {};
} catch (e) {
  scanMeta = {};
}

return [{
  json: {
    // Top-level instructor/subject keep "get instructor id1" working unchanged.
    instructor:  prefer(gemini.instructor,  pythonOcr.instructor),
    subject:     prefer(gemini.subject,     pythonOcr.subject),
    ay_semester: prefer(gemini.ay_semester, pythonOcr.ay_semester),
    remarks:     prefer(gemini.remarks,     pythonOcr.remarks),
    date:        prefer(gemini.date,        pythonOcr.date),
    student_id:  prefer(gemini.student_id,  pythonOcr.student_id),

    // Reconciled bubbles, m1..m10 / p1..p10. null means a genuine blank.
    ratings: scores,

    validation_status: validationStatus,
    needs_review:      needsReview,
    review_reasons:    reasons,

    // Kept for the Flagged Records screen: staff need to see WHY it was
    // flagged and what each engine actually read, side by side.
    omr_agreement: {
      cross_checked:      geminiOk,
      real_differences:   realDifferences,
      agreed_blanks:      agreedBlanks,
      filled_from_gemini: filledByGemini,
      comparisons,
    },

    task_id:     scanMeta.task_id  ?? py.task_id  ?? null,
    user_id:     scanMeta.user_id  ?? py.user_id  ?? null,
    term_id:     scanMeta.term_id  ?? py.term_id  ?? null,
    table_found: py.table_found ?? null,
    grid_source: py.grid_source ?? null,

    // The composite OCR preview from Python. Both the failed queue and the
    // flagged records screen need an image to show.
    scan_image: py.n8n_ocr_image ?? null,
  },
}];
