# n8n workflow patches

## Why there are three files, not one

n8n's importer requires a full workflow envelope — a top-level `nodes` array and
a `connections` object. A bare node object is rejected with *"The imported data
does not contain valid workflow data"*.

So the importable artifact is generated, not hand-written. The Code node's
JavaScript has to survive being escaped into a single JSON string; doing that by
hand is how you get a file that imports cleanly and then runs broken code.

| File | Role |
|---|---|
| `reconcile-ocr-omr.js` | **Edit this.** Source of truth for the reconciler logic. |
| `ai-validation-ocr-omr.node.json` | **Edit this.** Source for the Gemini node's prompt and schema. |
| `patch-ocr-omr-reconciliation.json` | **Generated. Import this.** Do not hand-edit. |
| `build-patch.py` | Regenerates the importable file from the two sources. |

After changing either source:

```
python n8n/build-patch.py
```

It asserts the result before writing: `nodes` is a list of two, `connections`
is an object, the `jsCode` round-trips byte-for-byte against the `.js` file, and
the Gemini `jsonBody` still parses as JSON once the `{{ }}` placeholder is
substituted out.

## Importing

**Do NOT use "Import from File".** On an existing workflow it *replaces* the
whole canvas — you would lose every other node. Paste instead.

1. Back up first: workflow menu → **Download**. Keep that file.
2. **Delete** `scan crop image via ai` and `separate it` — the patch replaces
   both, and leaving them creates two nodes with the same job.
3. Open `patch-ocr-omr-reconciliation.json`, select all, copy. Click an empty
   spot on the n8n canvas and press **Ctrl+V**. The two nodes appear, already
   connected to each other, with nothing else touched.
4. Rewire:

```
image to ocr and omr python
   └─ If1 (grid found?)
        ├─ false → GET TERM BY ID3 → failed_scan_queue
        └─ true  → Respond to Webhook
                     └─ ai validation ocr and omr
                          └─ reconcile ocr and omr
                               ├─ needs_review = true  → failed_scan_queue
                               └─ needs_review = false → get instructor id1 → …
```

`reconcile ocr and omr` emits `instructor` and `subject` at the top level, so
`get instructor id1` needs no change.

4. The Gemini node ships with **no API key**. Create a credential
   (Header Auth, header name `x-goog-api-key`) and select it on the node. The
   key that was in the exported workflow travelled in plaintext and must be
   rotated, along with the Supabase `service_role` JWT that was inline in six
   HTTP Request nodes.

## Before trusting the bubble reader

The prompt assumes two sections of ten statements, each on a 1–5 scale,
Management then Performance. If the real CTU Argao SAST form differs — reversed
scale, different row order, a 4-point scale — Gemini will read it *consistently*
wrong and every scan will look like a disagreement. Check it against a real form.
