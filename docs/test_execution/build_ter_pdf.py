# -*- coding: utf-8 -*-
"""Render the five Test Execution Reports into one CTU-letterheaded HTML document.

The HTML is then printed to PDF with headless Chrome (see build.sh / the command
printed at the end of this script).
"""
import html
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from data_modules import MODULES  # noqa: E402

OUT = os.path.dirname(os.path.abspath(__file__))
LOGO = "ctu_logo.png"

PROJECT_TITLE = ("iEvaluate: An AI-Driven Mobile Instructor Evaluation and Performance "
                 "Analysis System Using N8n Workflow Automation")
TEAM = "ERMM"
MEMBERS = [("Project Leader", "Rodz Harvey Licayan"),
           ("Front-End Programmer", "Michael Thomas Gonzaga"),
           ("QA Engineer", "Mark Lawrence Medillo"),
           ("Technical Writer", "Evangeline Caruana")]

ENV = [("Application under test", "iEvaluate Mobile Application"),
       ("Build", "debug, Flutter 3.41.6"),
       ("Package", "com.example.ievaluateapp_final"),
       ("Device", "Infinix X6525, Android 13 (API 33)"),
       ("Back end", "Supabase (PostgreSQL, Auth, Edge Functions)"),
       ("Automation", "n8n workflow engine, live endpoint"),
       ("Active academic term", "2nd Semester, 2027-2028"),
       ("Network", "Campus Wi-Fi, 5 GHz")]

EXEC_WINDOW = "01 - 03 September 2026"
EXEC_BY = "Mark Lawrence Medillo (QA Engineer)"
PREPARED_BY = "Evangeline Caruana (Technical Writer)"
REVIEWED_BY = "Rodz Harvey Licayan (Project Leader)"
TEST_LEVEL = "System Testing / User Acceptance Testing"
TEST_TYPE = "Functional, negative-path and UI-layout verification, executed manually"

e = html.escape


def steps_html(text):
    return "<br>".join(e(l) for l in text.split("\n"))


def status_cell(st):
    cls = {"PASS": "pass", "FAIL": "fail", "BLOCKED": "blk"}[st]
    label = {"PASS": "PASS", "FAIL": "FAIL", "BLOCKED": "NOT EXEC."}[st]
    return '<td class="stat %s">%s</td>' % (cls, label)


def tally(cases):
    p = sum(1 for c in cases if c["st"] == "PASS")
    f = sum(1 for c in cases if c["st"] == "FAIL")
    b = sum(1 for c in cases if c["st"] == "BLOCKED")
    total = len(cases)
    ex = p + f
    rate = (100.0 * p / ex) if ex else 0.0
    return dict(total=total, p=p, f=f, b=b, ex=ex, rate=rate)


def bar(t):
    """Stacked proportion bar, widths as percentages of the total case count."""
    if not t["total"]:
        return ""
    w = lambda n: 100.0 * n / t["total"]
    segs = []
    if t["p"]:
        segs.append('<span class="sg sp" style="width:%.4f%%">%d</span>' % (w(t["p"]), t["p"]))
    if t["f"]:
        segs.append('<span class="sg sf" style="width:%.4f%%">%d</span>' % (w(t["f"]), t["f"]))
    if t["b"]:
        segs.append('<span class="sg sb" style="width:%.4f%%">%d</span>' % (w(t["b"]), t["b"]))
    return '<div class="bar">%s</div>' % "".join(segs)


def letterhead():
    return """
<div class="head">
  <img class="seal" src="%s" alt="">
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
""" % LOGO


# ---------------------------------------------------------------- cover page
def cover(mods):
    tots = [tally(m["cases"]) for m in mods]
    g = dict(total=sum(t["total"] for t in tots), p=sum(t["p"] for t in tots),
             f=sum(t["f"] for t in tots), b=sum(t["b"] for t in tots))
    g["ex"] = g["p"] + g["f"]
    g["rate"] = 100.0 * g["p"] / g["ex"] if g["ex"] else 0.0

    all_def = [(m, d) for m in mods for d in m["defects"]]
    sev = {}
    for _, d in all_def:
        key = d["sev"].split()[0]
        sev[key] = sev.get(key, 0) + 1

    idx = "".join(
        '<tr><td class="c">%d</td><td class="c">%s</td><td>%s</td>'
        '<td class="c">%d</td><td class="c">%d</td><td class="c">%d</td>'
        '<td class="c">%d</td><td class="c b">%.1f%%</td>'
        '<td class="c">%d</td></tr>'
        % (m["no"], e(m["code"]), e(m["page"]), t["total"], t["p"], t["f"], t["b"],
           t["rate"], len(m["defects"]))
        for m, t in zip(mods, tots))

    members = "".join(
        '<tr><th>%s</th><td>%s</td><th>%s</th><td>%s</td></tr>'
        % (e(MEMBERS[i][0]), e(MEMBERS[i][1]), e(MEMBERS[i + 1][0]),
           e(MEMBERS[i + 1][1]))
        for i in range(0, len(MEMBERS), 2))
    env = "".join('<tr><th>%s</th><td>%s</td></tr>' % (e(k), e(v)) for k, v in ENV)

    sevrow = ", ".join("%s: %d" % (k.title(), v) for k, v in
                       sorted(sev.items(), key=lambda x: {"HIGH": 0, "MEDIUM": 1,
                                                          "LOW": 2}.get(x[0], 3)))

    return """
<section class="page">
  %s
  <div class="doctitle">TEST EXECUTION REPORT</div>
  <div class="docsub">Consolidated report covering five pages / modules</div>

  <table class="kv quad">
    <tr><th>Capstone Project Title</th><td class="b" colspan="3">%s</td></tr>
    <tr><th>Team</th><td colspan="3">%s</td></tr>
    %s
  </table>

  <div class="cols">
    <div class="col">
      <div class="h2">1.&nbsp;&nbsp;Test Environment</div>
      <table class="kv narrow">%s</table>
    </div>
    <div class="col">
      <div class="h2">2.&nbsp;&nbsp;Execution Details</div>
      <table class="kv narrow">
        <tr><th>Test level</th><td>%s</td></tr>
        <tr><th>Test type</th><td>%s</td></tr>
        <tr><th>Execution window</th><td>%s</td></tr>
        <tr><th>Executed by</th><td>%s</td></tr>
        <tr><th>Report prepared by</th><td>%s</td></tr>
        <tr><th>Reviewed by</th><td>%s</td></tr>
      </table>
    </div>
  </div>

  <div class="h2">3.&nbsp;&nbsp;Consolidated Summary</div>
  <table class="grid idx">
    <thead><tr>
      <th style="width:5%%">#</th><th style="width:9%%">Report ID</th>
      <th>Page / Module Under Test</th>
      <th style="width:9%%">Total<br>Cases</th><th style="width:9%%">Passed</th>
      <th style="width:9%%">Failed</th><th style="width:11%%">Not<br>Executed</th>
      <th style="width:10%%">Pass<br>Rate</th><th style="width:10%%">Defects<br>Logged</th>
    </tr></thead>
    <tbody>%s
      <tr class="tot"><td class="c" colspan="3">TOTAL</td>
        <td class="c">%d</td><td class="c">%d</td><td class="c">%d</td>
        <td class="c">%d</td><td class="c">%.1f%%</td><td class="c">%d</td></tr>
    </tbody>
  </table>
  %s
  <div class="legend">
    <span><i class="sw sp"></i>Passed</span>
    <span><i class="sw sf"></i>Failed</span>
    <span><i class="sw sb"></i>Not executed / blocked</span>
    <span class="note">Pass rate = passed &divide; executed cases (blocked cases excluded).</span>
  </div>

  <div class="h2">4.&nbsp;&nbsp;Overall Verdict</div>
  <div class="verdict">
    <p><b>%d of %d</b> cases were executed: <b>%d passed</b>, <b>%d failed</b> &mdash;
    an overall pass rate of <b>%.1f%%</b>. The other <b>%d</b> are carried forward.</p>
    <p><b>%d defects</b> were logged (%s). The six failures fall on three pages &mdash;
    My Dashboard, Student Feedback and the Official Evaluation Report &mdash; and five
    of them are presentation faults rather than data faults: the underlying value was
    correct in every case but was clipped, truncated or duplicated on its way to the
    screen or the exported PDF. The sixth, DEF-07, is an unreachable screen left in the
    build.</p>
    <p><b>Recommendation: CONDITIONALLY ACCEPTED.</b> Authentication, registration and
    core navigation passed without a single defect and are fit for release. The two
    reporting pages must be rebuilt and re-tested against the fixes applied on
    31/08/2026 before sign-off, because DEF-01 affects an official document that leaves
    the system.</p>
  </div>

  <table class="sign">
    <tr><th>Prepared by</th><th>Executed by</th><th>Reviewed by</th><th>Noted by</th></tr>
    <tr class="sigline"><td></td><td></td><td></td><td></td></tr>
    <tr class="signame"><td>%s<br><span>Technical Writer</span></td>
        <td>%s<br><span>QA Engineer</span></td>
        <td>%s<br><span>Project Leader</span></td>
        <td><br><span>Capstone Adviser</span></td></tr>
  </table>
</section>
""" % (letterhead(), e(PROJECT_TITLE), e(TEAM), members, env,
       e(TEST_LEVEL), e(TEST_TYPE), e(EXEC_WINDOW), e(EXEC_BY), e(PREPARED_BY),
       e(REVIEWED_BY), idx, g["total"], g["p"], g["f"], g["b"], g["rate"],
       len(all_def), bar(g), g["ex"], g["total"], g["p"], g["f"], g["rate"], g["b"],
       len(all_def), sevrow,
       e(PREPARED_BY.split(" (")[0]), e(EXEC_BY.split(" (")[0]),
       e(REVIEWED_BY.split(" (")[0]))


# ------------------------------------------------------------- module report
def module_page(m):
    t = tally(m["cases"])

    rows = "".join(
        '<tr><td class="c mono">%s</td><td>%s</td><td class="stp">%s</td>'
        '<td class="sm">%s</td><td>%s</td><td>%s</td>%s<td class="c mono sm">%s</td></tr>'
        % (e(c["id"]), e(c["scen"]), steps_html(c["steps"]), e(c["data"]),
           e(c["exp"]), e(c["act"]), status_cell(c["st"]), e(c["dfr"]))
        for c in m["cases"])

    if m["defects"]:
        drows = "".join(
            '<tr><td class="c mono">%s</td><td class="c sev-%s">%s</td>'
            '<td class="c">%s</td><td>%s</td><td>%s</td><td>%s</td>'
            '<td class="c sm">%s</td><td class="c mono sm">%s</td></tr>'
            % (e(d["id"]), d["sev"].split()[0].lower(), e(d["sev"]), e(d["pri"]),
               e(d["desc"]), e(d["root"]), e(d["fix"]), e(d["st"]), e(d["tc"]))
            for d in m["defects"])
        defects = """
  <div class="h2">Defect Log</div>
  <table class="grid def">
    <thead><tr>
      <th style="width:6%%">Defect ID</th><th style="width:8%%">Severity</th>
      <th style="width:6%%">Priority</th><th style="width:21%%">Description</th>
      <th style="width:23%%">Root Cause</th><th style="width:19%%">Fix Applied</th>
      <th style="width:11%%">Status</th><th style="width:6%%">Test Case</th>
    </tr></thead><tbody>%s</tbody>
  </table>""" % drows
    else:
        defects = ('<div class="h2">Defect Log</div>'
                   '<div class="nodef">No defect was raised against this page. '
                   'Every executed test case passed.</div>')

    notes = "".join("<li>%s</li>" % e(n) for n in m["notes"])

    return """
<section class="page">
  %s
  <div class="doctitle sm2">TEST EXECUTION REPORT</div>
  <div class="rid">Report %s&nbsp;&nbsp;&middot;&nbsp;&nbsp;Page / Module %d of 5</div>

  <table class="kv two">
    <tr><th>Page / Module Under Test</th><td class="b" colspan="3">%s</td></tr>
    <tr><th>Source File(s)</th><td class="mono" colspan="3">%s</td></tr>
    <tr><th>Entry Point</th><td colspan="3">%s</td></tr>
    <tr><th>User Role(s)</th><td colspan="3">%s</td></tr>
    <tr><th>Test Objective</th><td colspan="3">%s</td></tr>
    <tr><th>In Scope</th><td colspan="3">%s</td></tr>
    <tr><th>Out of Scope</th><td colspan="3">%s</td></tr>
    <tr><th>Executed By / Date</th><td>%s</td>
        <th style="width:15%%">Build / Device</th><td>%s</td></tr>
  </table>

  <div class="h2">Execution Summary</div>
  <table class="grid sum">
    <thead><tr>
      <th>Total Cases</th><th>Executed</th><th>Passed</th><th>Failed</th>
      <th>Not Executed</th><th>Pass Rate</th><th>Defects Logged</th>
    </tr></thead>
    <tbody><tr class="big">
      <td>%d</td><td>%d</td><td class="pv">%d</td><td class="fv">%d</td>
      <td class="bv">%d</td><td class="b">%.1f%%</td><td>%d</td>
    </tr></tbody>
  </table>
  %s

  <div class="h2">Test Execution Details</div>
  <table class="grid det">
    <thead><tr>
      <th style="width:7%%">Test Case ID</th>
      <th style="width:13%%">Test Scenario</th>
      <th style="width:19%%">Test Steps</th>
      <th style="width:10%%">Test Data</th>
      <th style="width:19%%">Expected Result</th>
      <th style="width:20%%">Actual Result</th>
      <th style="width:6%%">Status</th>
      <th style="width:6%%">Defect Ref.</th>
    </tr></thead><tbody>%s</tbody>
  </table>
  %s

  <div class="h2">Observations and Follow-up</div>
  <ul class="obs">%s</ul>

  <table class="sign">
    <tr><th>Executed by</th><th>Reviewed by</th><th>Noted by</th></tr>
    <tr class="sigline"><td></td><td></td><td></td></tr>
    <tr class="signame"><td>%s<br><span>QA Engineer</span></td>
        <td>%s<br><span>Project Leader</span></td>
        <td><br><span>Capstone Adviser</span></td></tr>
  </table>
</section>
""" % (letterhead(), e(m["code"]), m["no"], e(m["page"]), e(m["file"]), e(m["entry"]),
       e(m["role"]), e(m["objective"]), e(m["scope_in"]), e(m["scope_out"]),
       e(EXEC_BY.split(" (")[0] + ", " + EXEC_WINDOW),
       e("Flutter 3.41.6 debug / Infinix X6525, Android 13"),
       t["total"], t["ex"], t["p"], t["f"], t["b"], t["rate"], len(m["defects"]),
       bar(t), rows, defects, notes,
       e(EXEC_BY.split(" (")[0]), e(REVIEWED_BY.split(" (")[0]))


CSS = """
@page { size: Letter landscape; margin: 10mm 9mm; }
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
            margin:4px 0 1px; }
.doctitle.sm2 { font-size:13.5pt; margin:6px 0 1px; }
.docsub { text-align:center; font-size:8pt; font-style:italic; margin-bottom:3px; }
.rid { text-align:center; font-size:8.2pt; font-weight:bold; margin-bottom:6px; }

.h2 { font-weight:bold; font-size:9.2pt; margin:4px 0 2px; padding-bottom:2px;
      border-bottom:1.6px solid #000; }

table { width:100%; border-collapse:collapse; table-layout:fixed; }
table.kv th, table.kv td { border:1px solid #000; padding:2px 6px;
                           vertical-align:top; }
table.kv th { width:19%; text-align:left; font-weight:bold; background:#ececec; }
table.kv.two th { width:15%; }
table.kv.quad th { width:16%; } table.kv.quad td { width:34%; }
table.kv.narrow th { width:38%; }
.cols { display:flex; gap:12px; align-items:flex-start; }
.cols .col { flex:1 1 0; min-width:0; }

table.grid th, table.grid td { border:1px solid #000; padding:2px 5px;
                               vertical-align:top; }
table.grid thead th { background:#d9d9d9; text-align:center; font-weight:bold;
                      font-size:7.6pt; }
table.grid thead { display:table-header-group; }
tr, td, th { page-break-inside:avoid; }

td.c, th.c { text-align:center; }
td.b, .b { font-weight:bold; }
.mono { font-family:"Consolas","Courier New",monospace; font-size:7.1pt;
        word-break:break-word; }
.sm { font-size:7.4pt; }
td.stp { font-size:7.5pt; line-height:1.35; }

table.det td { font-size:7.6pt; line-height:1.32; }
table.idx td { padding:2px 5px; }
tr.tot td { font-weight:bold; background:#ececec; }

table.sum tbody tr.big td { text-align:center; font-size:15pt; font-weight:bold;
                            padding:7px 4px; }
table.sum .pv { color:#0b6b2f; }
table.sum .fv { color:#a4101a; }
table.sum .bv { color:#8a6100; }

td.stat { text-align:center; font-weight:bold; font-size:7.4pt; letter-spacing:.2px; }
td.stat.pass { background:#d6efd9; color:#0b6b2f; }
td.stat.fail { background:#f7d5d7; color:#a4101a; }
td.stat.blk  { background:#fbeacb; color:#8a6100; }

.sev-high   { background:#f7d5d7; color:#a4101a; font-weight:bold; }
.sev-medium { background:#fbeacb; color:#8a6100; font-weight:bold; }
.sev-low    { background:#e6e6e6; font-weight:bold; }
table.def td { font-size:7.4pt; line-height:1.3; }

.bar { display:flex; width:100%; height:13px; margin:4px 0 2px;
       border:1px solid #000; overflow:hidden; }
.sg { display:flex; align-items:center; justify-content:center; font-size:7.2pt;
      font-weight:bold; color:#fff; }
.sp { background:#1e7a3e; } .sf { background:#b5202c; } .sb { background:#c08a13; }
.legend { font-size:7.2pt; display:flex; gap:14px; align-items:center;
          margin-bottom:2px; }
.legend i.sw { display:inline-block; width:9px; height:9px; margin-right:4px;
               border:1px solid #000; vertical-align:-1px; }
.legend .note { font-style:italic; margin-left:auto; }

.verdict { border:1px solid #000; padding:5px 7px; font-size:7.8pt; line-height:1.25; }
.verdict p { margin:0 0 4px; } .verdict p:last-child { margin:0; }

.nodef { border:1px solid #000; padding:6px 8px; font-size:8pt; font-style:italic;
         background:#f4f4f4; }
ul.obs { margin:0; padding-left:16px; font-size:8pt; line-height:1.4; }
ul.obs li { margin-bottom:3px; }

table.sign { margin-top:5px; }
table.sign th { border:none; font-size:7.6pt; text-align:center; padding-bottom:11px;
                font-weight:bold; }
tr.sigline td { border:none; border-top:1px solid #000; height:1px; }
tr.signame td { border:none; text-align:center; font-size:8pt; font-weight:bold;
                padding-top:3px; }
tr.signame td span { font-weight:normal; font-size:7.2pt; font-style:italic; }
"""


def main():
    pages = [cover(MODULES)] + [module_page(m) for m in MODULES]
    doc = ("<!doctype html><html><head><meta charset='utf-8'>"
           "<title>iEvaluate - Test Execution Report</title>"
           "<style>%s</style></head><body>%s</body></html>"
           % (CSS, "".join(pages)))
    path = os.path.join(OUT, "iEvaluate_Test_Execution_Report.html")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(doc)
    total = sum(len(m["cases"]) for m in MODULES)
    defs = sum(len(m["defects"]) for m in MODULES)
    print("modules=%d  cases=%d  defects=%d  sections=%d"
          % (len(MODULES), total, defs, len(pages)))
    print("wrote %s" % path)


main()
