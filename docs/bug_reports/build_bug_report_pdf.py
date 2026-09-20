# -*- coding: utf-8 -*-
"""Render one Software QA Bug Report into a CTU-letterheaded HTML document.

Same letterhead and table styling as docs/test_execution/build_ter_pdf.py so the
two documents sit in the same folder without looking like they came from
different projects. The HTML is then printed to PDF with headless Chrome; the
exact command is echoed at the end of this script.

One report per file. The fields live in BUG below, so regenerating after a
retest is an edit to that dict and a re-run -- no template surgery.
"""
import html
import os

OUT = os.path.dirname(os.path.abspath(__file__))
LOGO = "ctu_logo.png"

e = html.escape

# Paragraph break inside a field. Spelled with chr() rather than an escape so
# that patching this file from a shell heredoc cannot silently eat a level of
# backslashes and turn it into a real line break mid-literal.
NL2 = chr(10) * 2

# ---------------------------------------------------------------- report data
BUG = {
    # 1. BUG IDENTIFICATION
    "id": "BUG-2026-TC-A07",
    "reported": "04 September 2026",
    "reporter": "Rodz Harvey D. Licayan",
    "project": "iEvaluate",
    "module": "Subject Management Module (SAO Administrator)",
    "build": "1 (debug, Flutter 3.41.6)",

    # 2. CLASSIFICATION
    "severity": "Critical",
    "priority": "High",
    "status": "Fixed - Pending Retest",
    "repro": "Always - both affected entry points, on every attempt",
    "env": [
        ("Application under test", "iEvaluate Mobile Application"),
        ("Build", "debug, Flutter 3.41.6"),
        ("Package", "com.example.ievaluateapp_final"),
        ("Device", "Infinix X6525, Android 13 (API 33)"),
        ("Back end", "Supabase (PostgreSQL, Auth, Edge Functions)"),
        ("Active academic term", "2nd Semester, 2027-2028"),
        ("Related UAT case", "UAT_SAO_Admin TC-A07, steps 4-5 and new 5a-5c"),
    ],

    # 3. BUG DETAILS
    "summary":
        "The SAO Administrator can save a subject reusing an existing subject "
        "code AND an existing subject name with no duplicate warning of any "
        "kind, provided the form is opened from \"Add Instructor\" or from "
        "\"Edit\" rather than from the Add Subject button. The save then "
        "behaves like an update: the instructor is quietly attached to the "
        "subject that already holds the code, and the operation is reported as "
        "a success.",

    "description":
        "The duplicate guard delivered with migration 20240130000018 is gated "
        "behind the getter _isFreshAdd, which is true only when the Add "
        "Subject sheet is opened from the floating action button. The very "
        "same sheet (_AddSubjectModal) has two other entry points -- \"Add "
        "Instructor\" on a subject detail card, which passes prefilledCode, "
        "and the Edit pencil, which passes editingAssignment -- and on both of "
        "those _isFreshAdd is false, so BOTH duplicate checks are skipped "
        "outright: the hard \"Subject Code Already Used\" refusal and the soft "
        "\"Possible Duplicate\" name warning.\n\n"
        "The gate would be harmless if those two sheets showed the subject "
        "code and name as fixed text, but they do not. Both are ordinary "
        "editable TextFormFields with no readOnly and no enabled: flag, so "
        "whatever the sheet was opened for, the tester can retype the code and "
        "the name into any other subject's identity and the save will accept "
        "it. In short, the guard is keyed to WHERE the form was opened from "
        "instead of to WHAT was typed into it.\n\n"
        "This defeats the stated outcome of UAT TC-A07 -- \"a subject code can "
        "never be given to a second subject\" -- because two of the three ways "
        "to reach the form do not enforce it. It also reintroduces, by a "
        "different door, the exact silent-rewrite behaviour that migration "
        "20240130000018 was written to close.",

    "preconditions":
        "Signed in as SAO Administrator. An active academic term is "
        "configured. Migration 20240130000018_one_subject_per_code is applied. "
        "At least two subjects already exist, each with a distinct code and "
        "name -- this report used PElec2 and IT101.",

    "steps": [
        "Sign in as SAO Administrator, open the navigation drawer and tap "
        "\"Subject Management\".",
        "Note two subjects already in the list and their exact codes and "
        "names, e.g. PElec2 (\"Human Computer Interaction\") and IT101 "
        "(\"Computer Programming 1\").",
        "Tap the IT101 card to open its subject detail sheet, then tap the "
        "\"Add Instructor\" button at the bottom of that sheet.",
        "In the sheet that opens, clear the Subject Code field and type "
        "PElec2. Note that the field accepts the edit -- it is not locked.",
        "Clear the Subject Name field and type the SAME name PElec2 already "
        "uses (\"Human Computer Interaction\").",
        "Select any instructor from the typeahead and tap Save.",
        "Observe the result: no dialog is raised. The sheet closes and the "
        "snackbar reads \"Instructor assigned successfully\".",
        "Reopen the list and open the PElec2 card, then the IT101 card, and "
        "compare both against what was entered in steps 4 to 6.",
    ],

    "expected":
        "The save is REFUSED and a dialog headed \"Subject Code Already Used\" "
        "names the subject that holds PElec2 and its department -- the same "
        "refusal the Add Subject button already gives, and the behaviour UAT "
        "TC-A07 step 4 requires. Independently of that, the Subject Code "
        "should not be editable on this sheet at all -- it is the subject's "
        "identity, and this sheet was opened against a specific subject. "
        "Subject Name and Department may remain editable (correcting them from "
        "here is reasonable) provided every such save is duplicate-checked and "
        "actually written.",

    "actual":
        "No dialog, no warning and no error. The save silently resolves "
        "PElec2 to the subject row that already holds that code and upserts "
        "the chosen instructor onto it, so the only visible change anywhere in "
        "the system is one extra instructor listed under PElec2 -- the add "
        "behaves like an update. IT101, the subject actually opened, receives "
        "nothing at all, and the admin is told the operation succeeded.",

    "variants": [
        ("A", "\"Add Instructor\" + code that ALREADY exists",
         "Both duplicate checks skipped. The instructor is attached to the "
         "existing subject; name and department are left as they were. "
         "Reported as \"Instructor assigned successfully\". This is the "
         "primary case stepped out above."),
        ("B", "\"Add Instructor\" + code that does NOT exist",
         "A brand-new subject row is INSERTED from a sheet whose only purpose "
         "is assigning an instructor to an existing subject -- and it is "
         "inserted carrying the prefilled NAME of the different subject that "
         "was opened, producing two subjects with the same name and no "
         "\"Possible Duplicate\" warning."),
        ("C", "Edit pencil + code changed to another existing subject's code",
         "The assignment row is silently repointed to that other subject "
         "(instructor_subjects.update), moving the instructor between subjects "
         "with no confirmation. Reported as \"Assignment updated "
         "successfully\"."),
        ("D", "Edit pencil + name changed to another existing subject's name",
         "subjects.subject_name is rewritten with no \"Possible Duplicate\" "
         "warning, leaving two subjects sharing one name. subject_name has no "
         "unique index by design, so nothing downstream catches this either."),
    ],

    # 4. TEST DATA & EVIDENCE
    "testdata":
        "Existing subjects: PElec2 - \"Human Computer Interaction\"; IT101 - "
        "\"Computer Programming 1\". Any instructor account in the selected "
        "department. Active term: 2nd Semester, 2027-2028. No special data "
        "preparation is needed -- any two pre-existing subjects reproduce it.",

    "evidence":
        "This defect was located by SOURCE INSPECTION of the save path, not by "
        "an on-device run, and the steps above are derived from that path -- "
        "they have not yet been executed against a build. The code evidence is "
        "cited line by line in section 5 and is conclusive as to the cause. A "
        "screen recording of steps 3 to 8 on the affected build (1) is still "
        "required from the QA Engineer to close the evidence trail, and "
        "UAT TC-A07 steps 5a-5c exist to capture it.",

    "console":
        "NONE - and that is the defining symptom of this defect. No "
        "PostgrestException is raised, no snackbar is shown and nothing is "
        "written to the debug console. The database unique index "
        "subjects_one_per_code is never violated because these paths REUSE the "
        "existing subject row rather than inserting a second one, so the "
        "database has nothing to reject. The Dart guard is the only control "
        "that could have caught this, and it is the control being bypassed.",

    # 5. QA INITIAL ANALYSIS
    "analysis":
        "Root cause is a guard keyed to the form's entry point instead of to "
        "the data submitted. _isFreshAdd is defined as (_editingAssignmentId "
        "== null && widget.prefilledCode == null), and both duplicate checks "
        "are written as `if (_isFreshAdd && match != null)`. The assumption "
        "encoded there -- \"reusing a code is always deliberate on the edit "
        "and add-instructor paths\" -- holds only while those paths cannot "
        "change the code, and they can. Two independent faults therefore have "
        "to be corrected together: the checks must run on identity (is the "
        "code I am about to save held by a DIFFERENT subject than the one this "
        "sheet is operating on?) rather than on entry point, and the code and "
        "name fields must be locked on the two sheets that have no business "
        "editing them. Fixing only the second would leave the edit path "
        "unguarded; fixing only the first would leave a form that invites an "
        "edit it then refuses.",

    "component": [
        ("lib/sao_admin/manage_subjects_screen.dart", "1010",
         "_AddSubjectModal._isFreshAdd - the entry-point gate"),
        ("lib/sao_admin/manage_subjects_screen.dart", "1279",
         "hard code-taken check, skipped when _isFreshAdd is false"),
        ("lib/sao_admin/manage_subjects_screen.dart", "1290",
         "soft name-clash check, skipped when _isFreshAdd is false"),
        ("lib/sao_admin/manage_subjects_screen.dart", "1301-1326",
         "subject resolve-or-insert branch that performs the silent reuse"),
        ("lib/sao_admin/manage_subjects_screen.dart", "1461, 1469",
         "Subject Code / Subject Name fields - editable on every path"),
    ],

    # 6. ASSIGNMENT & RESOLUTION
    "assigned": "Michael Thomas Gonzaga (Front-End Programmer)",
    "target": "05 September 2026",
    "devnotes":
        "Fixed in five parts." + NL2 +
        "(1) The rule was extracted out of the screen into "
        "lib/sao_admin/subject_duplicate_check.dart "
        "(checkSubjectDuplicates). It had already been written once in-line "
        "and still leaked, so it is now stated in one place, takes its context "
        "as arguments and is unit-testable." + NL2 +
        "(2) _isFreshAdd no longer gates either check. Both are keyed to "
        "_sheetSubjectId -- the subject the form is already operating on, "
        "carried in explicitly via the new prefilledSubjectId argument. The "
        "refusal now fires whenever the code is held by a subject OTHER than "
        "that one, which reads identically on all three entry points and needs "
        "no exception for any of them. The name warning is keyed the same way "
        "and additionally to originalName, the name the subject carried when "
        "the form opened, so it fires on a real CHANGE (variant D) and stays "
        "quiet when the name was left alone -- two subjects may legitimately "
        "share a name via \"Create anyway\", and warning about a value nobody "
        "touched would nag on every save for the rest of that subject's "
        "life." + NL2 +
        "(3) Subject Code is read-only unless the form is a genuine fresh add "
        "-- it is what tells the save which subject it is working on, and it is "
        "the only field that cannot move. Subject Name and Department stay "
        "EDITABLE on all three forms, by request: correcting them is a normal "
        "thing to want from wherever you are looking at the subject, and both "
        "now run the same duplicate check as anywhere else. Department was "
        "previously accepting changes on the add-instructor form, ignoring "
        "them on save and reporting success -- a quieter cousin of the same "
        "defect -- so the add-instructor form now writes the subject row too "
        "instead of skipping it. One consequence to note: a subject whose "
        "department was never set (bulk import) must now be given one before "
        "an instructor can be added to it." + NL2 +
        "(4) The INSERT branch is now reachable only from a fresh add, which "
        "closes variant B. A form anchored to a subject that no longer holds "
        "its own code refuses with a message instead of silently creating a "
        "replacement." + NL2 +
        "(5) Identity is compared with an explicit isSelf(rowId) that requires "
        "both ids to be present and equal. A bare != would let a row with a "
        "missing id read as self on a fresh add (null == null) and wave a real "
        "collision through -- the same shape of mistake as the guard being "
        "replaced. A test covers it." + NL2 +
        "(6) Form wording: the sheet announced itself as \"Add Subject / "
        "Assign a subject to an instructor\" even when adding one instructor "
        "to an existing subject, and its button read \"Assign Subject\". It "
        "now titles and labels itself per path. The locked field also lost the "
        "solid grey block and four-line paragraph it first shipped with -- "
        "which read as a broken control -- in favour of a light ground, a "
        "hairline border, a small lock and one line of helper text." + NL2 +
        "Verification: 19 unit tests in "
        "test/sao_admin/subject_duplicate_check_test.dart cover variants A, C "
        "and D, the original TC-A07 steps 4-5, normalisation against the DB "
        "index, and six legitimate paths that must stay open (including an "
        "unchanged colliding name, and a whitespace-only name edit). Full "
        "suite 185 passing, flutter analyze clean. NOT yet verified on device: "
        "the locked-code UI, variant B, and the new editable name/department "
        "save. UAT TC-A07 steps 5a-5c exist to cover those.",
    "fixversion": "1.0.1 (build 2)",
    "datefixed": "04 September 2026",

    # 7. RETEST & QA SIGN-OFF
    "retester": "Mark Lawrence Medillo (QA Engineer)",
    "retestdate": "",
    "retestresult": "Pending verification",
    "retestnotes":
        "Retest must cover all four variants A to D in section 3, not only the "
        "stepped-out case, and must re-run UAT_SAO_Admin TC-A07 steps 4 and 5 "
        "to confirm the original fresh-add refusals still behave as before. "
        "Confirm additionally that a legitimate \"Add Instructor\" with the "
        "code left untouched still succeeds -- the fix must not block the "
        "normal path.",
    "finalstatus": "OPEN - awaiting QA verification",
    "signoff": "",
    "qalead": "Mark Lawrence Medillo (QA Engineer)",
}

GUIDE = [
    ("Bug ID", "Use a unique identifier, e.g., BUG-2026-001 based on the UAT#"),
    ("Severity", "Impact of the defect on system functionality."),
    ("Priority", "Urgency with which the defect should be fixed."),
    ("Reproducibility", "How consistently the defect can be reproduced."),
    ("Steps to Reproduce", "Write exact, numbered actions another tester can follow."),
    ("Expected Result", "Describe what the system should do."),
    ("Actual Result", "Describe what the system actually does."),
    ("Evidence", "Attach or reference screenshots, recordings, logs, or console errors."),
    ("Retest Result", "Record whether the developer's fix passed QA verification."),
    ("Final Status", "Close only after the defect has been verified as resolved."),
]


# ---------------------------------------------------------------- helpers
def paras(text):
    """Blank-line-separated prose into <p> blocks."""
    return "".join("<p>" + e(b).replace("\n", "<br>") + "</p>"
                   for b in text.split("\n\n"))


def kv(rows, cls="kv"):
    body = "".join("<tr><th>" + e(k) + "</th><td>" + v + "</td></tr>"
                   for k, v in rows)
    return '<table class="' + cls + '">' + body + "</table>"


def letterhead():
    return """
<div class="head">
  <img class="seal" src="LOGOSRC" alt="">
  <div class="htext">
    <div class="l1">Republic of the Philippines</div>
    <div class="l2">CEBU TECHNOLOGICAL UNIVERSITY</div>
    <div class="l3">ARGAO CAMPUS</div>
    <div class="l4">Ed Kintanar Street, Lamacan, Argao, Cebu</div>
    <div class="l5">Website: http://www.argao.ctu.edu.ph&nbsp;&nbsp;&nbsp;E-mail: cdargao@ctu.edu.ph</div>
    <div class="l5">Phone No.: (032) 401-0737 local 1700</div>
  </div>
  <div class="seal spacer"></div>
</div>
<div class="college">COLLEGE OF TECHNOLOGY AND ENGINEERING</div>
<div class="dept">Information Technology Department</div>
""".replace("LOGOSRC", LOGO)


def sev_class(v):
    # Anything unrecognised gets its own loud style rather than defaulting to
    # sev-low: a mistyped "critical" reading as the least urgent tier on a
    # document whose whole job is to make severity unmistakable is the one
    # failure this function must not have.
    return {"Critical": "sev-crit", "High": "sev-high",
            "Medium": "sev-medium", "Low": "sev-low"}.get(v, "sev-unknown")


# ---------------------------------------------------------------- page 1
def page_one(b):
    ident = kv([
        ("Bug ID", '<span class="bid">' + e(b["id"]) + "</span>"),
        ("Date Reported", e(b["reported"])),
        ("Reported By", e(b["reporter"])),
        ("Project / System", '<span class="b">' + e(b["project"]) + "</span>"),
        ("Module / Feature", e(b["module"])),
        ("Build / Version", e(b["build"])),
    ], "kv two")

    classif = (
        '<table class="kv two">'
        '<tr><th>Severity</th><td class="' + sev_class(b["severity"]) + '">'
        + e(b["severity"]) + "</td>"
        '<th>Priority</th><td class="' + sev_class(b["priority"]) + '">'
        + e(b["priority"]) + "</td></tr>"
        '<tr><th>Status</th><td class="b">' + e(b["status"]) + "</td>"
        '<th>Reproducibility</th><td class="b">' + e(b["repro"]) + "</td></tr>"
        "</table>"
    )

    env = kv([(k, e(v)) for k, v in b["env"]], "kv narrow")

    return (
        '<section class="page">'
        + letterhead()
        + '<div class="doctitle">SOFTWARE QA BUG REPORT</div>'
          '<div class="docsub">Defect Tracking and Verification Form</div>'
          '<div class="rid">' + e(b["id"]) + "</div>"

        + '<div class="h2">1.&nbsp;&nbsp;Bug Identification</div>' + ident
        + '<div class="h2">2.&nbsp;&nbsp;Classification</div>' + classif
        + '<div class="h3">Environment</div>' + env

        + '<div class="h2">3.&nbsp;&nbsp;Bug Details</div>'
        + '<table class="kv two"><tr><th>Bug Summary</th><td class="prose">'
        + paras(b["summary"]) + "</td></tr></table>"
        + '<div class="h3">Description</div>'
        + '<div class="box prose">' + paras(b["description"]) + "</div>"
        + '<div class="h3">Preconditions</div>'
        + '<div class="box prose">' + paras(b["preconditions"]) + "</div>"
        + "</section>"
    )


# ---------------------------------------------------------------- page 2
def page_two(b):
    steps = "".join(
        '<tr><td class="c num">' + str(i + 1) + '</td><td class="stp">'
        + e(s) + "</td></tr>"
        for i, s in enumerate(b["steps"]))

    variants = "".join(
        '<tr><td class="c b">' + e(v[0]) + '</td><td class="stp">'
        + e(v[1]) + '</td><td class="stp">' + e(v[2]) + "</td></tr>"
        for v in b["variants"])

    return (
        '<section class="page">'
        + letterhead()
        + '<div class="doctitle sm2">SOFTWARE QA BUG REPORT</div>'
          '<div class="docsub">Section 3 (continued) &mdash; reproduction and '
          "result</div>"
          '<div class="rid">' + e(b["id"]) + "</div>"

        + '<div class="h3 first">Steps to Reproduce</div>'
        + '<table class="grid"><thead><tr><th style="width:6%">#</th>'
          "<th>Action</th></tr></thead><tbody>" + steps + "</tbody></table>"

        + '<div class="h3">Expected Result</div>'
        + '<div class="box exp prose">' + paras(b["expected"]) + "</div>"
        + '<div class="h3">Actual Result</div>'
        + '<div class="box act prose">' + paras(b["actual"]) + "</div>"

        + '<div class="h3">Affected Paths &mdash; all four reproduce from the '
          "same form</div>"
        + '<table class="grid"><thead><tr><th style="width:5%">Var</th>'
          '<th style="width:33%">Entry point and input</th>'
          "<th>Observed behaviour</th></tr></thead><tbody>"
        + variants + "</tbody></table>"
        + "</section>"
    )


# ---------------------------------------------------------------- page 3
def page_three(b):
    comp = "".join(
        '<tr><td class="mono">' + e(c[0]) + '</td><td class="c mono">'
        + e(c[1]) + '</td><td class="stp">' + e(c[2]) + "</td></tr>"
        for c in b["component"])

    return (
        '<section class="page">'
        + letterhead()
        + '<div class="doctitle sm2">SOFTWARE QA BUG REPORT</div>'
          '<div class="docsub">Sections 4 and 5</div>'
          '<div class="rid">' + e(b["id"]) + "</div>"

        + '<div class="h2">4.&nbsp;&nbsp;Test Data &amp; Evidence</div>'
        + kv([("Test Data", '<div class="prose">' + paras(b["testdata"]) + "</div>"),
              ("Evidence / Attachments", '<div class="prose">' + paras(b["evidence"]) + "</div>"),
              ("Console / Error Message", '<div class="prose">' + paras(b["console"]) + "</div>")],
             "kv two")

        + '<div class="h2">5.&nbsp;&nbsp;QA Initial Analysis</div>'
        + '<div class="h3 first">Initial Analysis</div>'
        + '<div class="box prose">' + paras(b["analysis"]) + "</div>"
        + '<div class="h3">Suspected Component</div>'
        + '<table class="grid"><thead><tr><th style="width:38%">File</th>'
          '<th style="width:11%">Line(s)</th><th>Element</th></tr></thead>'
          "<tbody>" + comp + "</tbody></table>"
        + "</section>"
    )


# ---------------------------------------------------------------- page 4
def page_four(b):
    resolution = kv([
        ("Assigned To", e(b["assigned"])),
        ("Target Fix Date", e(b["target"])),
        ("Developer Notes", '<div class="prose">' + paras(b["devnotes"]) + "</div>"),
        ("Fix Version", '<span class="b">' + e(b["fixversion"]) + "</span>"),
        ("Date Fixed", e(b["datefixed"])),
    ], "kv two")

    return (
        '<section class="page">'
        + letterhead()
        + '<div class="doctitle sm2">SOFTWARE QA BUG REPORT</div>'
          '<div class="docsub">Section 6</div>'
          '<div class="rid">' + e(b["id"]) + "</div>"

        + '<div class="h2">6.&nbsp;&nbsp;Assignment &amp; Resolution</div>'
        + resolution
        + "</section>"
    )


# ------------------------------------------------------- page 5: section 7
def page_retest(b):
    blank = '<span class="blank"></span>'
    retest = kv([
        ("Retested By", e(b["retester"])),
        ("Retest Date", e(b["retestdate"]) or blank),
        ("Retest Result", '<span class="pend">' + e(b["retestresult"]) + "</span>"),
        ("Retest Notes", '<div class="prose">' + paras(b["retestnotes"]) + "</div>"),
        ("Final Status", '<span class="pend">' + e(b["finalstatus"]) + "</span>"),
        ("QA Sign-Off", e(b["signoff"]) or blank),
        ("QA Lead", e(b["qalead"])),
    ], "kv two")

    return (
        '<section class="page">'
        + letterhead()
        + '<div class="doctitle sm2">SOFTWARE QA BUG REPORT</div>'
          '<div class="docsub">Section 7</div>'
          '<div class="rid">' + e(b["id"]) + "</div>"

        + '<div class="h2">7.&nbsp;&nbsp;Retest &amp; QA Sign-Off</div>'
        + retest
        + '<div class="note">This defect is recorded as OPEN. A fix has been '
          "applied and is stated in section 6, but no entry in section 7 may be "
          "completed by the developer: per this form&rsquo;s own guide, the "
          "defect is closed only after QA has independently verified it.</div>"
        + "</section>"
    )


# ---------------------------------------------------------------- page 5
def page_five(b):
    guide = "".join(
        "<tr><th>" + e(k) + "</th><td>" + e(v) + "</td></tr>" for k, v in GUIDE)

    return (
        '<section class="page">'
        + letterhead()
        + '<div class="doctitle sm2">SOFTWARE QA BUG REPORT</div>'
          '<div class="docsub">Reporting guide and sign-off</div>'
          '<div class="rid">' + e(b["id"]) + "</div>"

        + '<div class="h2">QA Bug Report &mdash; Reporting Guide</div>'
        + '<table class="kv two guide">' + guide + "</table>"

        + '<table class="sign"><tr>'
          "<th>Reported by</th><th>Fixed by</th><th>Verified by</th></tr>"
          '<tr class="sigline"><td></td><td></td><td></td></tr>'
          '<tr class="signame"><td>Rodz Harvey D. Licayan<br>'
          "<span>Project Leader</span></td>"
          "<td>Michael Thomas Gonzaga<br><span>Front-End Programmer</span></td>"
          "<td>Mark Lawrence Medillo<br><span>QA Engineer</span></td>"
          "</tr></table>"
        + "</section>"
    )


# ---------------------------------------------------------------- css
CSS = """
@page { size: Letter portrait; margin: 10mm 11mm; }
* { box-sizing: border-box; }
body { font-family: Arial, Helvetica, sans-serif; font-size: 8pt; color:#000;
       margin:0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.page { page-break-after: always; }
.page:last-child { page-break-after: auto; }

.head { display:flex; align-items:center; justify-content:center; gap:12px; }
.seal { width:40px; height:40px; object-fit:contain; }
.seal.spacer { visibility:hidden; }
.htext { text-align:center; line-height:1.14; }
.htext .l1 { font-size:7.6pt; }
.htext .l2 { font-size:10.5pt; font-weight:bold; letter-spacing:.3px; }
.htext .l3 { font-size:7pt; font-weight:bold; }
.htext .l4 { font-size:6.8pt; }
.htext .l5 { font-size:6.2pt; }
.college { text-align:center; font-weight:bold; font-size:9.2pt; margin-top:4px; }
.dept    { text-align:center; font-weight:bold; font-size:9pt; }

.doctitle { text-align:center; font-weight:bold; font-size:14.5pt; letter-spacing:1px;
            margin:6px 0 1px; }
.doctitle.sm2 { font-size:13pt; }
.docsub { text-align:center; font-size:8pt; font-style:italic; margin-bottom:2px; }
.rid { text-align:center; font-size:8.2pt; font-weight:bold; margin-bottom:6px; }

.h2 { font-weight:bold; font-size:9.2pt; margin:7px 0 2px; padding-bottom:2px;
      border-bottom:1.6px solid #000; }
.h3 { font-weight:bold; font-size:8.2pt; margin:5px 0 2px; }
.h3.first { margin-top:0; }

table { width:100%; border-collapse:collapse; table-layout:fixed; }
table.kv th, table.kv td { border:1px solid #000; padding:3px 6px;
                           vertical-align:top; }
table.kv th { width:19%; text-align:left; font-weight:bold; background:#ececec; }
table.kv.two th { width:21%; }
table.kv.narrow th { width:32%; }
table.kv.guide th { width:24%; }

table.grid th, table.grid td { border:1px solid #000; padding:3px 5px;
                               vertical-align:top; }
table.grid thead th { background:#d9d9d9; text-align:center; font-weight:bold;
                      font-size:7.6pt; }
table.grid thead { display:table-header-group; }
tr, td, th { page-break-inside:avoid; }

td.c, th.c { text-align:center; }
td.b, .b { font-weight:bold; }
td.num { font-weight:bold; }
.mono { font-family:"Consolas","Courier New",monospace; font-size:7.1pt;
        word-break:break-word; }
td.stp { font-size:7.6pt; line-height:1.35; }

.prose p { margin:0 0 4px; line-height:1.34; }
.prose p:last-child { margin:0; }
.box { border:1px solid #000; padding:4px 7px; font-size:7.8pt; }
.box.exp { background:#f1f7f2; border-left:3px solid #1e7a3e; }
.box.act { background:#fbf2f3; border-left:3px solid #b5202c; }

.bid { font-weight:bold; font-size:9pt; letter-spacing:.4px; }
.sev-crit   { background:#f3c9cc; color:#7d0d16; font-weight:bold; }
.sev-high   { background:#f7d5d7; color:#a4101a; font-weight:bold; }
.sev-medium { background:#fbeacb; color:#8a6100; font-weight:bold; }
.sev-low    { background:#e6e6e6; font-weight:bold; }
.sev-unknown { background:#e4d7f2; color:#4a2a6b; font-weight:bold; }
.pend { font-weight:bold; color:#8a6100; }
.blank { display:inline-block; width:60%; border-bottom:1px dotted #666;
         height:9px; }

.note { border:1px solid #000; background:#f4f4f4; padding:4px 7px;
        font-size:7.5pt; font-style:italic; line-height:1.32; margin-top:6px; }

table.sign { margin-top:16px; }
table.sign th { border:none; font-size:7.6pt; text-align:center;
                padding-bottom:22px; font-weight:bold; }
tr.sigline td { border:none; border-top:1px solid #000; height:1px; }
tr.signame td { border:none; text-align:center; font-size:8pt; font-weight:bold;
                padding-top:3px; }
tr.signame td span { font-weight:normal; font-size:7.2pt; font-style:italic; }
"""


def main():
    pages = (page_one(BUG) + page_two(BUG) + page_three(BUG)
             + page_four(BUG) + page_retest(BUG) + page_five(BUG))
    doc = ("<!doctype html><html><head><meta charset='utf-8'>"
           "<title>iEvaluate - QA Bug Report " + BUG["id"] + "</title>"
           "<style>" + CSS + "</style></head><body>" + pages + "</body></html>")
    path = os.path.join(OUT, BUG["id"] + ".html")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(doc)
    print("bug=%s  steps=%d  variants=%d  sections=7  pages=6"
          % (BUG["id"], len(BUG["steps"]), len(BUG["variants"])))
    print("wrote %s" % path)
    print("\nprint to PDF with:")
    print('  "%s" --headless --disable-gpu --no-pdf-header-footer '
          '--print-to-pdf="%s" "%s"'
          % (os.environ.get("CHROME", "chrome"),
             os.path.join(OUT, BUG["id"] + ".pdf"), path))


main()
