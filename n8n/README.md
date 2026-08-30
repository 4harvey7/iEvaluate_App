# n8n — scan branch repair

**Status: APPLIED to the live workflow `9mfRRvWpzWlRJYzY` on 2026-08-30 14:32 UTC**
via the public API (`PUT /api/v1/workflows/…`), then re-fetched and verified.
Workflow is still `active: true`, 135 nodes, webhook still registered.

## Files

| File | What it is |
|---|---|
| `current-workflow.json` | The live workflow **before** the fix. This is the rollback. |
| `ievaluate-workflow-FIXED.json` | What was applied. |
| `reconcile-ocr-omr.js` | The reconciler's code as a readable file. Source of truth for review. |
| `ai-validation-ocr-omr.node.json` | The Gemini node, readable. |
| `PHASE-4-credentials.md` | Getting `service_role` out of the workflow. **Still outstanding.** |

### Rollback

```
PUT http://localhost:5678/api/v1/workflows/9mfRRvWpzWlRJYzY
X-N8N-API-KEY: <key>
body: {name, nodes, connections, settings} taken from current-workflow.json
```

There is also a staging copy, `DIMdUw555z1ElibM` ("STAGING - scan fix"), holding
the same content, inactive. Safe to delete.

---

## Why the scan path produced nothing

Confirmed against the running instance, not just an export.

### 1. `If13` had no outgoing connections

```
reconcile ocr and omr  ->  If13  ->  (nothing)
```

`get instructor id1` was fed by **nobody**. The whole second half of the scan
pipeline was orphaned.

### 2. Two nodes still called a deleted node

`Map to Target Format` and `2. Format Final Results` both called
`$('separate it')`. That node is gone, so n8n throws *"no node named 'separate
it'"* the moment either runs.

`2. Format Final Results` also read bubble scores straight from the Python
service, discarding every bubble the reconciler had recovered from Gemini.

---

## What the execution history showed

41 failed runs. Two distinct causes:

- **`hhttp://192.168.100.124:5000/process`** — a typo, double `h`. Runs 1441/1442.
  You had already fixed it.
- **"The service refused the connection - perhaps it is offline"** — run 1440.
  The Python OMR service. It was up 09:39–09:41 and is **down now**.

### Run 1448 — the silent halt, proven

```
reconcile ocr and omr  -> worked. instructor 'Mark Lawrence Medillo',
                          subject 'ITF 203', remarks 'Good', image present
get instructor id1     -> 1 row  (mark medello)
get subject id1        -> 0 rows
                       -> branch stopped. Execution marked "success".
```

Zero rows, no error, nothing written, nothing queued.

### The similarity threshold I added was WRONG. It is removed.

I added `similarity > 0.55` plus `account_status = 'approved'` to all three
instructor matchers, justifying 0.55 with "worst genuine match in the live data
is 0.909". **That figure came from the wrong dataset** — already-matched rows on
the Google Sheets path, where names are typed cleanly. OCR'd names carry a middle
name the database does not have, plus spelling drift:

| Form (OCR) | Database row | similarity | vs 0.55 |
|---|---|---|---|
| `Mark Lawrence Medillo` | `mark medello` | **0.375** | REJECTED — wrong |
| `Rody Harvey Licyan` | `Rodz Harvey Licayan` | 0.625 | passes |

Execution 1452 proved the damage: the threshold discarded the correct
instructor, `get instructor id1` emitted `[{}]`, and the next parameterised query
died with `42P02 there is no parameter $1`.

**Both the threshold and the `account_status` filter are removed.** `match_score`
stays in the `SELECT` so a real batch gives a distribution to choose a threshold
from. Setting a second number from one observation is how the first went wrong.

**`alwaysOutputData` does not degrade gracefully on a parameterised Postgres
node.** Zero rows emits `[{}]`, its `queryReplacement` resolves to nothing, and
the next query throws `42P02`. **Fixed** by the gates below: an IF node handles
an empty item fine, so `alwaysOutputData` is now safe where it sits.

### Wrong-subject attribution — FIXED

Execution 1460 (a real phone scan) matched:

```
form (OCR): ADBAS 301
matched   : IAS 301  "Information Assurance and Security"
```

Both end in `301`. That scan's scores went into `management_results` /
`performance_results` under the **wrong subject_id**, silently.

Two causes, both fixed:

**1. The similarity was computed against `subject_code || ' ' || subject_name`.**
The long name floods the trigram set and buries the difference:

| candidate vs OCR `ADBAS 301` | code + name | code only |
|---|---|---|
| `IAS 301` (wrong) | 0.1333 | 0.3846 |
| `ADBAS 301` (right) | 0.3030 | 1.0000 |
| **discriminating gap** | 0.1697 | **0.6154** |

`get subject id1` now orders by `similarity(subject_code, $2)` and selects the
score. Live confirmation: the replay scored the wrong match at **0.384615**,
matching the hand calculation exactly.

**2. Nothing rejected a weak match.** Two new IF gates:

```
If13[true] → get instructor id1 → instructor matched? ──true──→ get subject id1
                                        │                              │
                                        │                     subject matched? ──true──→ 2. Format Final Results → …
                                        │                              │
                                        └──false──→ build scan error record ←──false──┘
                                                             │
                                                             └──→ Insert import_errors
```

Threshold **0.45** on the subject: above the observed wrong match (0.3846),
below the worst simulated single-character OCR drift on a code (0.5385).

`build scan error record` exists because the pipeline's own
`Format error for import_errors` reads `j['Instructor/Professor']`, `j.M1` and
friends, which only exist after `Map to Target Format`. At the gate the data is
still in the reconciler's shape. It records the near-miss so a reviewer is not
guessing:

```json
"_match_diagnostics": {
  "instructor_candidate": "Rodz Harvey Licayan",
  "instructor_match_score": 0.56,
  "subject_candidate": "IAS 301 Information Assurance and Security",
  "subject_match_score": 0.384615,
  "subject_threshold": 0.45
}
```

**No instructor threshold was reintroduced.** Both observed legitimate matches
(0.375 and 0.56) are real people, and there is no observed *wrong* instructor
match to set a threshold above. Note 0.56 — my removed 0.55 threshold would have
passed that scan by 0.01. `match_score` is selected on all three matchers, so a
real batch will give a distribution to choose from.

Verified live (execution 1463): gate rejected the 0.3846 subject, wrote one
`import_errors` row with the image and diagnostics, and
`Insert or update rows in a table` / `send to managment table` /
`send to performance node` / `update to overall total` were **never reached**.

---

## What changed

**Wiring**

- `If13` **true** (clean) → `get instructor id1`.
- `If13` **false** (flagged) → `build flagged record` →
  `save flagged to failed_scan_queue`. This branch did not exist; `needs_review`
  was computed and then ignored.
- `Map to Target Format` → `If4`, bypassing the second `Respond to Webhook`.
  `Respond to Webhook6` already answers the phone earlier on this branch.

**Code**

- `2. Format Final Results` — reads the reconciler. Blanks become `0` because
  downstream sums them. `answered`/`total_score`/`average`/`percent` recomputed
  from reconciled values instead of Python's pre-reconciliation summary.
- `Map to Target Format` — both dead calls repointed at the reconciler.
- Reconciler now prefers Python's `rating_name` letter over its numeric `score`.
  The service emits both; the letter is what the form actually shows.
- Reconciler strips Gemini's `'true'` / `'false'` / `'null'` string artifacts from
  `date` and `student_id`. Gemini returned the literal string `'true'` for a date
  field that is blank on the paper.

**Confidence-based review (replaces the "flag fallback grids" idea)**

`grid_source` reads `fallback (forced)` on **100% of live runs** (30/30 sampled).
It is a constant, so flagging on it would flag every scan ever and the review
queue would swallow all traffic. It is recorded but **not** used as a trigger.

`omr_debug` is the real signal. Per row the Python service reports a score for
each of the five columns. Where its top score is tiny or its lead over the
runner-up is thin, the answer is a coin flip — and on the live data every row
Gemini disagreed with by 3+ was exactly such a row:

```
Q     py  gem  conf     margin   weak
m1    5   5    0.2264   0.1032   false     <- confident, agrees
p9    4   4    0.1548   0.0574   false     <- confident, agrees
m9    1   3    0.0732   0.0191   TRUE      <- unsure, disagrees by 2
p2    1   4    0.0348   0.0287   TRUE      <- unsure, disagrees by 3
p3    -   4    0.0214   0.0000   TRUE      <- not detected, Gemini filled it
```

Thresholds:

| Constant | Value | Meaning |
|---|---|---|
| `FLAG_DIFF_MARGIN` | 2 | below this a difference is camera noise |
| `FLAG_DIFF_COUNT` | 5 | ordinary differences before flagging |
| `SEVERE_DIFF_MARGIN` | 3 | 3+ apart means a *different row* was read |
| `SEVERE_CONFLICT_LIMIT` | 2 | severe rows before flagging |
| `WEAK_TOP_SCORE` | 0.05 | below this the row is barely marked at all |
| `WEAK_MARGIN` | 0.02 | top vs runner-up this close is a coin flip |
| `WEAK_CONFLICT_LIMIT` | 2 | weak-and-disputed rows before flagging |

**Python still wins every row it read** — your rule, unchanged. Confidence only
decides whether a human gets asked to look.

⚠️ **These thresholds are tuned on one distinct form.** Only 3 executions have
ever reached the reconciler with both engines, and two of those are the same
form scanned twice. Revisit after a real batch.

**Flagged records and failed scans show images**

`build flagged record` writes one row with:

| Column | Contents |
|---|---|
| `n8n_ocr_image` | the scan image |
| `review_reasons` | `severe_omr_disagreement_2_rows`, `low_confidence_omr_2_rows`, … |
| `omr_comparison` | per question: python, gemini, used, source, **and Python's confidence + margin** |
| `partial_data` | the reconciled reading, so staff correct a pre-filled form |

`import_errors` also carries `scan_image` now.

⚠️ **The stored image is the handwritten TEXT crops only** — Instructor, Subject,
AY/Semester, Date, Student ID, Remarks. **It does not contain the bubble grid.**
So a reviewer resolving an OMR disagreement sees handwriting and no bubbles.
Fixing that needs a change in the Python service to return a grid crop (or the
original scan).

---

## Verified against real data

The reconciler was replayed in node against executions 1445, 1447 and 1448
pulled from the API:

| Exec | Before | After | Reasons |
|---|---|---|---|
| 1448 | `auto` (passed silently) | **`flagged`** | `severe_omr_disagreement_2_rows`, `low_confidence_omr_2_rows` |
| 1447 | `auto` (passed silently) | **`flagged`** | same |
| 1445 | `auto_unverified` | `auto_unverified` | `gemini_unavailable`, still processed |

All 20 rating keys present in every case. `date` cleaned from `'true'` to empty,
which the extracted image confirms is correct — that field is blank on the paper.

Gemini is **not** deterministic even at `temperature: 0`. Runs 1447 and 1448 are
the same form and Gemini differed on m6, m8, p2, p3 and p5 between them. It is a
cross-check, not an oracle.

---

## How to verify end to end

The Python OMR service must be running first — **it is currently down**.

Scan one form, then check the execution:

1. It should reach the end, not stop at `If13`.
2. `reconcile ocr and omr` → `omr_agreement.comparisons`, 20 entries. `source`
   says which engine each value came from: `python`, `gemini_fill`, `blank`.
3. `validation_status`: `auto` (cross-checked clean) / `auto_unverified` (Gemini
   unreachable) / `flagged` (went to `failed_scan_queue`).
4. A clean scan ends with a new row in `sast_all_raw_data_survey`.

To force the flagged path: scan a form with most rows blank — more than 10 agreed
blanks trips `too_many_blanks_N_of_20`.

---

## Measured OMR accuracy — and a correction

Scored the **current** Python OMR service against
`last-man staning original omer and ocr/omr_ground_truth_merged.json` — 24
labelled forms, 480 rows, each sent at its own labelled `paper_type`:

```
OVERALL per-row accuracy: 442/480 = 92.1%
  14 of 24 forms perfect
  imperfect forms average 3.8 wrong of 20
  errors: 60.5% wrong letter, 39.5% missed (read as blank)

by grid_source:
  fallback (forced)   220 rows,  2 wrong =  0.9%   <-- best, and it is what production uses
  auto-detected       140 rows, 11 wrong =  7.9%
  fallback            120 rows, 25 wrong = 20.8%   <-- worst
```

**I was wrong earlier.** I suggested that `grid_source: "fallback (forced)"`
meant Python had guessed the geometry and was therefore the weaker signal, and
that forcing it might be giving up the better path. The opposite is true:
`fallback (forced)` has the **lowest** error rate of the three modes by a wide
margin, and it is the mode production runs in on 100% of scans.

**This vindicates the "OMR → Python wins" rule.** At 92% overall and 99% in
production's grid mode, Python's OMR is strong and Gemini disagreeing with it is
more often Gemini being wrong.

⚠️ **But the labelled set may not represent live capture.** Execution 1460, a
genuine phone scan in `fallback (forced)` mode, had Python miss **7 of 20**
marks — 35%, against 0.9% on the labelled scans in the same mode. Either live
lighting/angle is materially worse than the labelled batch, or that particular
form was faint. **Before tuning any threshold further, label a batch of
genuinely live scans.** The confidence signal from `omr_debug` is still the right
mechanism — in execution 1448 it flagged exactly the rows Gemini disputed — but
its thresholds are set on very little data.

## Still outstanding

- **`service_role` key inline in 14 places.** Bypasses every RLS policy you have.
  See `PHASE-4-credentials.md`.
- **The Python OMR service is down** (`192.168.100.124:5000`). Nothing in the scan
  branch works until it's back. The IP is hardcoded — if the machine's address
  changes, this breaks again with no warning.
- **No Flagged Records screen in the app.** Rows will accumulate in
  `failed_scan_queue` with `validation_status = 'flagged'` and nothing displays
  them. The `scan_review_queue` view from migration 11 is what it should read.
- **Empty `student_id` collides on upsert.** `sast_all_raw_data_survey` matches on
  `(subject_id, term_id, instructor_ID, student_id)`. The test form has no student
  ID, and the extracted image confirms the field is genuinely blank. Every scan
  for the same instructor+subject+term therefore collapses into one row, each
  overwriting the last. Needs a decision: require student_id, or add `task_id` to
  the match.
- **The stored image has no bubble grid** (see above).
- `Set Status - Auto` still hardcodes `validation_status: 'auto'`, so an
  `auto_unverified` scan is recorded as `auto` in `sast_all_raw_data_survey`.
