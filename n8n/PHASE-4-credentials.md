# Phase 4 — move the Supabase key out of the workflow

Goal: the seven HTTP Request nodes stop carrying the `service_role` key in their
own header fields, and read it from the `Supabase account` credential instead.

Why it matters: `service_role` bypasses every Row Level Security policy in the
database. While it sits inline in the workflow, anyone who gets a copy of the
exported JSON has full read and write on every table — which makes the RLS work
in migration 10 decorative.

---

## Before you start: the order is not optional

1. Reset the key in Supabase
2. Update the `Supabase account` credential in n8n
3. **Then** attach that credential to the seven nodes

Attach first and rotate second and all seven nodes return 401 until you go back
and fix the credential.

---

## Step 1 — Reset the key in Supabase

1. Open your Supabase project in the browser
2. Left sidebar, bottom → **Project Settings** (gear icon)
3. Click **API**
4. Find the section **Project API keys**
5. Locate the row labelled **`service_role`** — it will say *"This key has the
   ability to bypass Row Level Security. Never share it publicly."*
6. Click the **Reset** / **Generate new key** control on that row
7. Confirm. The old key stops working immediately
8. Click **Reveal** / the copy icon and copy the new key somewhere temporary

While you are on this page, also copy the **Project URL**. It looks like:

```
https://lyorziqedepfsgblqewv.supabase.co
```

---

## Step 2 — Update the credential in n8n

1. Open n8n (`http://localhost:5678`)
2. **Left sidebar → Credentials**
3. Find **`Supabase account`** — it shows *Supabase API · Last updated 2 months
   ago*
4. Click it. A panel opens with a **Connection** tab

### Check the Host field

It must read **exactly**:

```
https://lyorziqedepfsgblqewv.supabase.co
```

Three things people get wrong here:

| Wrong | Why it fails |
|---|---|
| `https://lyorziqedepfsgblqewv.supabase.co/` | Trailing slash. n8n joins Host + path, so the request goes to `...co//rest/v1/...` — a double slash, which Supabase rejects. |
| `lyorziqedepfsgblqewv.supabase.co` | No `https://`. n8n cannot build a valid URL. |
| `https://lyorziqedepfsgblqewv.supabase.co/rest/v1` | Path included. The node adds `/rest/v1` itself, so you get it twice. |

A wrong Host and a wrong key produce the *same* 401, which is why this is worth
checking before you blame the key.

### Paste the new key

1. Field **Service Role Secret** → clear it → paste the new key from Step 1
2. Click **Save**
3. The panel should show a green **Connection tested successfully**. If it shows
   red, fix the Host first, then the key

### The 🔗 1 badge

The credential list showed `🔗 1` next to `Supabase account` — it is already
used by one node, possibly in a different workflow. Click that badge to see
which. Saving the new key changes that node's key too. That is what you want,
but be aware something else just started using the new key at the same moment.

---

## Step 3 — Attach it to the seven nodes

The seven, by exact name:

1. `GET TERM BY ID`
2. `GET TERM BY ID2`
3. `GET TERM BY ID3`
4. `GET TERM BY ID4`
5. `GET TERM BY ID5`
6. `save to failed_scan_queue`
7. `Insert import_errors`

### Worked example — do `GET TERM BY ID` first

1. Double-click the node. A side panel opens
2. Near the top you will see, in order: **Method**, **URL**, **Authentication**
3. **Authentication** currently reads **None**. Click it → choose
   **Predefined Credential Type**
4. A new field appears below: **Credential Type**. Click it, type `Supabase`,
   and pick **Supabase API** from the list
5. A third field appears: **Credential for Supabase API**. Click it and pick
   **`Supabase account`**
6. Scroll down to the **Send Headers** section. You will see four rows:

| Name | Value (abbreviated) | Do this |
|---|---|---|
| `apikey` | `eyJhbGciOi…` | **Delete** — click the 🗑 at the right of the row |
| `Authorization` | `Bearer eyJhbGciOi…` | **Delete** — 🗑 |
| `Content-Type` | `application/json` | **Keep** |
| `Prefer` | `resolution=merge-duplicates` | Delete (see note below) |

   Deleting `apikey` and `Authorization` is correct, not a leap of faith: the
   Supabase API credential injects those exact two headers itself. Leaving the
   inline ones would just override the credential with the old key, defeating
   the whole exercise.

7. Click **Test step** at the top right of the panel. It should return one row
   containing `current_term_id`
8. Close the panel

### Then repeat for nodes 2 through 7

Same six clicks. The credential already exists, so steps 4 and 5 are just two
dropdown picks each.

### Two differences you must respect

**`Prefer` is not always junk.** On the five `GET TERM BY ID*` nodes it says
`resolution=merge-duplicates`, which is an instruction for *upserts* and does
nothing on a GET — safe to delete. On the two POST nodes it is load-bearing:

| Node | `Prefer` header | Keep or delete |
|---|---|---|
| `GET TERM BY ID` … `GET TERM BY ID5` | `resolution=merge-duplicates` | delete, does nothing |
| `save to failed_scan_queue` | `return=minimal` | **KEEP** |
| `Insert import_errors` | `resolution=merge-duplicates` | **KEEP** |

**Do NOT click "Test step" on the two POST nodes.** They are inserts. Testing
`save to failed_scan_queue` writes a real row into your review queue, and
testing `Insert import_errors` writes a real error record. Only test the five
GET nodes; for the POST nodes, attach the credential, delete the two headers,
and close without testing.

---

## Step 4 — Verify the key is actually gone

1. Click **Save** on the workflow
2. Workflow **⋯** menu → **Download**
3. Open the downloaded `.json` in a text editor
4. Search (Ctrl+F) for `service_role`

**Zero hits** means the key is out of the workflow file for good. Any hit means
a node still has it inline — find that node and delete its `apikey` and
`Authorization` header rows.

Also search for `AQ.Ab8RN6` (the old Gemini key prefix). That should be zero too
once the `ai validation ocr and omr` node from the patch replaces
`scan crop image via ai`.

---

## If a node returns 401 after this

In this order:

1. Host has a trailing slash, or includes `/rest/v1` — the most common cause
2. The credential holds the **anon** key rather than **service_role**. The anon
   key is subject to RLS, so a `system_settings` read would come back empty or
   forbidden rather than erroring cleanly
3. You pasted the key with a leading or trailing space
4. The inline `apikey` header is still present and holds the pre-reset key,
   overriding the credential

## If a node returns 404

The URL is fine but the Host got doubled up — check for `//rest/v1` in the
resolved URL shown in the node's request preview.
