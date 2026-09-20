// n8n Code node: "reconcile ocr and omr"
// Sits immediately after "ai validation ocr and omr" (the Gemini node).
// Replaced "separate it", which read item.json.choices[0].message.content --
// the OpenAI response shape -- while the node calls Google's native
// generateContent endpoint returning candidates[0].content.parts[0].text. The
// throw was swallowed by its own try/catch, so the scan path produced empty OCR
// data silently.
//
// ── Priority, fixed by design ──────────────────────────────────────────────
//   OCR text fields   -> Gemini wins.  The Python OCR is unreliable.
//   OMR bubble scores -> Python wins.  That is what it was built for.
//
// Gemini's OMR is a cross-check, not a source. It never overrides a value
// Python actually read. It does two things only: fill a bubble Python missed,
// and vote on whether a human needs to look at this scan.

const FLAG_DIFF_MARGIN  = 2;   // smaller than this is noise; Python wins silently
const FLAG_DIFF_COUNT   = 5;   // this many ordinary differences -> needs a human
const MAX_AGREED_BLANKS = 10;  // more than half the form blank -> needs a human
const QUESTIONS         = 10;  // per section

// ── Confidence-based review, measured from live data ───────────────────────
// A row where Gemini disagrees by 3+ is not a rounding argument -- one of the
// two engines read a different row. Across the live executions, every such row
// was also one where Python's OWN confidence was near zero. So confidence, not
// the disagreement alone, is the useful trigger.
//
// NOTE ON grid_source: it is NOT used as a flag. It reads "fallback (forced)"
// on 100% of live runs (30 of 30 sampled), so it is a constant, and a constant
// carries no information -- flagging on it would flag every scan ever and the
// review queue would swallow all traffic. table_found DOES vary (23 true /
// 7 false) and is still checked below.
const SEVERE_DIFF_MARGIN   = 3;     // 3+ apart = a different row was read
const SEVERE_CONFLICT_LIMIT = 2;    // this many severe rows -> needs a human
const WEAK_TOP_SCORE       = 0.05;  // below this the row is barely marked at all
const WEAK_MARGIN          = 0.02;  // top vs runner-up this close is a coin flip
const WEAK_CONFLICT_LIMIT  = 2;     // this many weak-and-disputed -> needs a human

// ── The rating scale ───────────────────────────────────────────────────────
// The form's columns are LETTERED, not numbered. Confirmed three ways: the
// legend the app prints itself (pdf_service.dart:426); omr_ground_truth_merged
// .json, 24 labelled forms whose only answer values are O/VS/S/F/US/blank; and
// the Python service's own `rating_name` field, which emits exactly these
// letters alongside the numeric score it derives from them.
//   O  Outstanding       4.21-5.00 -> 5
//   VS Very Satisfactory 3.41-4.20 -> 4
//   S  Satisfactory      2.61-3.40 -> 3
//   F  Fair              1.81-2.60 -> 2
//   US Unsatisfactory    1.00-1.80 -> 1
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
  // The service reports BOTH a letter (rating_name) and a number (score).
  // Prefer the letter: it is what the form actually shows, and if the service
  // ever changes its letter->number mapping the letter stays correct.
  return toScore(cell.rating_name ?? cell.score ?? cell.answer);
}

// ── Python's own confidence, from omr_debug ────────────────────────────────
// Per row the service reports a score for each of the five columns, plus which
// column it chose. There is no per-cell confidence field, so the spread between
// the top score and the runner-up is the only available proxy -- and it is a
// good one: on the live data, high top score tracked agreement with Gemini and
// near-zero top score tracked the 3+ disagreements exactly.
const confByRow = {};
for (const d of (py.omr_debug ?? [])) {
  const ri = Number(d.row_index);
  if (!Number.isInteger(ri)) continue;
  const sorted = Object.values(d.scores ?? {})
    .map(Number)
    .filter(Number.isFinite)
    .sort((a, b) => b - a);
  const top = sorted[0] ?? 0;
  const second = sorted[1] ?? 0;
  confByRow[ri] = {
    top: Number(top.toFixed(4)),
    margin: Number((top - second).toFixed(4)),
    weak: top < WEAK_TOP_SCORE || (top - second) < WEAK_MARGIN,
  };
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
const scores         = {};
const comparisons    = [];
let agreedBlanks     = 0;
let filledByGemini   = 0;
let realDifferences  = 0;
let severeConflicts  = 0;
let weakConflicts    = 0;

for (const [section, prefix] of [['management', 'm'], ['performance', 'p']]) {
  for (let i = 0; i < QUESTIONS; i++) {
    const key = `${prefix}${i + 1}`;
    // omr_debug is one flat list: rows 0-9 are management, 10-19 performance.
    const rowIndex = (prefix === 'm' ? 0 : QUESTIONS) + i;
    const conf = confByRow[rowIndex] ?? { top: null, margin: null, weak: false };

    const p = pythonScore(section, i);
    const g = geminiScore(key);

    let used;
    let source;

    if (p !== null) {
      // Python read a mark. It wins, always -- Gemini only registers a vote.
      used = p;
      source = 'python';
      if (g !== null) {
        const diff = Math.abs(p - g);
        if (diff >= FLAG_DIFF_MARGIN) realDifferences++;
        if (diff >= SEVERE_DIFF_MARGIN) severeConflicts++;
        // The combination that matters: Python is unsure AND Gemini disagrees.
        if (conf.weak && diff >= FLAG_DIFF_MARGIN) weakConflicts++;
      }
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
    comparisons.push({
      question: key,
      python: p,
      gemini: g,
      used,
      source,
      // Carried so the review screen can say WHY Python's answer is doubted,
      // instead of just showing two numbers and leaving the reviewer to guess.
      python_confidence: conf.top,
      python_margin: conf.margin,
      python_weak: conf.weak,
    });
  }
}

// ── Decide whether a human is needed ───────────────────────────────────────
const reasons = [];
if (!geminiOk) reasons.push('gemini_unavailable');
if (realDifferences >= FLAG_DIFF_COUNT) {
  reasons.push(`omr_disagreement_${realDifferences}_of_20`);
}
if (severeConflicts >= SEVERE_CONFLICT_LIMIT) {
  reasons.push(`severe_omr_disagreement_${severeConflicts}_rows`);
}
if (weakConflicts >= WEAK_CONFLICT_LIMIT) {
  reasons.push(`low_confidence_omr_${weakConflicts}_rows`);
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

// Gemini has been seen returning the literal string 'true' for a field that is
// blank on the paper. Treat that as empty rather than writing 'true' into a
// date column.
const clean = (v) => {
  const s = (v ?? '').toString().trim();
  return (s === 'true' || s === 'false' || s === 'null' || s === 'undefined') ? '' : s;
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
    date:        clean(prefer(gemini.date,       pythonOcr.date)),
    student_id:  clean(prefer(gemini.student_id, pythonOcr.student_id)),

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
      severe_conflicts:   severeConflicts,
      weak_conflicts:     weakConflicts,
      agreed_blanks:      agreedBlanks,
      filled_from_gemini: filledByGemini,
      comparisons,
    },

    task_id:     scanMeta.task_id  ?? py.task_id  ?? null,
    user_id:     scanMeta.user_id  ?? py.user_id  ?? null,
    term_id:     scanMeta.term_id  ?? py.term_id  ?? null,
    table_found: py.table_found ?? null,
    grid_source: py.grid_source ?? null,

    // The composite OCR preview from Python. NOTE: this contains only the
    // handwritten TEXT crops -- it does not include the bubble grid, so it
    // cannot be used to settle an OMR dispute by eye.
    scan_image: py.n8n_ocr_image ?? null,
  },
}];
