# -*- coding: utf-8 -*-
"""Render the UAT text documents into template-styled HTML (then PDF via Chrome)."""
import base64, html, os, re, sys

DOCS = r"c:\Projects\ievaluateapp_final\docs"
OUT  = r"c:\Projects\ievaluateapp_final\docs\uat_pdf"
LOGO = r"c:\Projects\ievaluateapp_final\assets\images\CTU_logo.png"

FILES = [
    ("UAT_Instructor_Module.txt", "Instructor Module",               "UAT_Instructor_Module"),
    ("UAT_Department_Head.txt",   "Department Head Module",          "UAT_Department_Head"),
    ("UAT_SAO_Staff.txt",         "SAO Staff (Data Gatherer) Module","UAT_SAO_Staff"),
    ("UAT_SAO_Admin.txt",         "SAO Administrator Module",        "UAT_SAO_Admin"),
]

PROJECT_TITLE = ("iEvaluate: An AI-Driven Mobile Instructor Evaluation and "
                 "Performance Analysis System Using N8n Workflow Automation")
TEAM = "ERMM"
MEMBERS = [("Project Leader:", "Rodz Harvey Licayan"),
           ("Front-End Programmer:", "Michael Thomas Gonzaga"),
           ("QA Engineer:", "Mark Lawrence Medillo"),
           ("Technical Writer:", "Evangeline Caruana")]

RULE = re.compile(r'^={70,}\s*$')
FIELD = re.compile(r"^(?P<label>[A-Za-z][A-Za-z0-9 /'()-]*?)\s*:\s?(?P<value>.*)$")
STEP  = re.compile(r'^\s{0,3}(?P<n>\d{1,2})\.\s+(?P<text>.*)$')

TRAILING = ["Expected Result", "Actual Result", "Comments", "Tester / Date",
            "Panelist Remarks"]
LEADING  = ["Title / Business Scenario", "Preconditions", "Test Data", "NOTE",
            "Note"]


def read_blocks(path):
    """Split a document into (title, body_lines) blocks on the ==== rules."""
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    blocks, i = [], 0
    pre = []
    while i < len(lines):
        close = None
        if RULE.match(lines[i]):
            for k in range(i + 1, min(i + 5, len(lines))):
                if RULE.match(lines[k]):
                    close = k
                    break
        if close is not None and close > i + 1:
            title = " ".join(l.strip() for l in lines[i + 1:close] if l.strip())
            j = close + 1
            body = []
            while j < len(lines):
                if RULE.match(lines[j]) and j + 2 < len(lines) and RULE.match(lines[j + 2]):
                    break
                if RULE.match(lines[j]):
                    break
                body.append(lines[j])
                j += 1
            blocks.append((title, body))
            i = j
        else:
            if not blocks:
                pre.append(lines[i])
            i += 1
    return pre, blocks


def parse_case(body):
    """Return (fields, steps) for one test case block."""
    fields, steps, order = {}, [], []
    cur_label, mode = None, "fields"
    step = None
    stray = []
    for raw in body:
        line = raw.rstrip()
        if not line.strip():
            if cur_label:
                fields[cur_label].append("")
            continue
        if line.strip().upper() == "STEPS":
            mode, cur_label = "steps", None
            continue
        m = STEP.match(line)
        if mode == "steps" and m:
            step = {"n": m.group("n"), "text": [m.group("text").strip()],
                    "expected": [], "note": [x for x in stray if x]}
            stray = []
            steps.append(step)
            cur_label = None
            continue
        fm = FIELD.match(line)
        known = fm and (fm.group("label").strip() in LEADING + TRAILING)
        if known:
            lbl = fm.group("label").strip()
            fields[lbl] = [fm.group("value").strip()]
            order.append(lbl)
            cur_label = lbl
            if lbl in TRAILING:
                mode = "trailing"
                step = None
            continue
        if mode == "steps" and step is not None:
            s = line.strip()
            if s.startswith("Expected:"):
                step["expected"].append(s[len("Expected:"):].strip())
            elif s.startswith("----"):
                stray.append(s.strip("- ").strip())
                step = None
            elif step["expected"]:
                step["expected"].append(s)
            else:
                step["text"].append(s)
            continue
        if mode == "steps" and step is None:
            stray.append(line.strip().strip("- ").strip())
            continue
        if cur_label:
            fields[cur_label].append(line.strip())
    return fields, steps


def para(chunks):
    out, cur = [], []
    for c in chunks:
        if c == "":
            if cur:
                out.append(" ".join(cur)); cur = []
        else:
            cur.append(c)
    if cur:
        out.append(" ".join(cur))
    return out


def esc_par(chunks):
    ps = para(chunks)
    if not ps:
        return "&nbsp;"
    return "".join("<p>%s</p>" % html.escape(p) for p in ps)


def letterhead(logo_uri):
    return """
<div class="head">
  <img class="seal" src="%s" alt="">
  <div class="htext">
    <div class="l1">Republic of the Philippines</div>
    <div class="l2">CEBU TECHNOLOGICAL UNIVERSITY</div>
    <div class="l3">ARGAO CAMPUS</div>
    <div class="l4">Ed Kintanar Street, Lamacan, Argao, Cebu</div>
    <div class="l5">Website: http://www.argao.ctu.edu.ph&nbsp;&nbsp;E-mail: cdargao@ctu.edu.ph</div>
    <div class="l5">Phone No.: (032) 401-0737 local 1700</div>
  </div>
  <div class="seal spacer"></div>
</div>
<div class="college">COLLEGE OF TECHNOLOGY AND ENGINEERING</div>
<div class="dept">Information Technology Department</div>
<div class="uat-title">USER ACCEPTANCE TESTING</div>
""" % logo_uri


def case_html(case_id, title, fields, steps, logo_uri):
    rows = []
    rows.append('<tr><th>Test Case ID</th><td colspan="2">%s</td></tr>' % html.escape(case_id))
    rows.append('<tr><th>Capstone Project Title:</th><td colspan="2" class="ctr">%s</td></tr>'
                % html.escape(PROJECT_TITLE))
    rows.append('<tr><th>Team</th><td colspan="2" class="ctr">%s</td></tr>' % TEAM)
    for lbl, val in MEMBERS:
        rows.append('<tr><th></th><td class="mlbl">%s</td><td class="ctr">%s</td></tr>'
                    % (html.escape(lbl), html.escape(val)))
    scenario = fields.get("Title / Business Scenario")
    if scenario:
        cell = ('<p class="hl">%s</p>' % html.escape(title)) + esc_par(scenario)
    else:
        cell = esc_par([title])
    rows.append('<tr><th>Title / Business Scenario</th><td colspan="2">%s</td></tr>' % cell)
    rows.append('<tr><th>Preconditions</th><td colspan="2">%s</td></tr>'
                % esc_par(fields.get("Preconditions", [])))
    rows.append('<tr><th>Test Data</th><td colspan="2">%s</td></tr>'
                % esc_par(fields.get("Test Data", [])))
    note = fields.get("NOTE") or fields.get("Note")
    if note:
        rows.append('<tr><th>Note</th><td colspan="2">%s</td></tr>' % esc_par(note))
    n = len(steps) if steps else 1
    for i, s in enumerate(steps):
        head = '<th rowspan="%d">Steps</th>' % n if i == 0 else ''
        marker = "".join('<div class="marker">%s</div>' % html.escape(x) for x in s["note"])
        body = '%s<div class="stp">%s. %s</div>' % (
            marker, s["n"], html.escape(" ".join(s["text"])))
        if s["expected"]:
            body += '<div class="exp"><span>Expected:</span> %s</div>' % html.escape(
                " ".join(s["expected"]))
        rows.append('<tr>%s<td colspan="2">%s</td></tr>' % (head, body))
    if not steps:
        rows.append('<tr><th>Steps</th><td colspan="2">&nbsp;</td></tr>')
    rows.append('<tr><th>Expected Result</th><td colspan="2">%s</td></tr>'
                % esc_par(fields.get("Expected Result", [])))
    rows.append('<tr><th>Actual Result<br>(Pass/Fail)</th><td colspan="2">%s</td></tr>'
                % esc_par(fields.get("Actual Result", [])))
    rows.append('<tr><th>Comments /<br>Attachments<br>(Screenshots, Logs)</th>'
                '<td colspan="2" class="tall">%s</td></tr>'
                % esc_par(fields.get("Comments", [])))
    rows.append('<tr><th>Tester Name / Date</th><td colspan="2">%s</td></tr>'
                % esc_par(fields.get("Tester / Date", [])))
    rows.append("<tr><th>Panelist's Remarks</th><td colspan=\"2\" class=\"remarks\">%s</td></tr>"
                % esc_par(fields.get("Panelist Remarks", [])))
    return ('<section class="page">%s<table class="uat">%s</table></section>'
            % (letterhead(logo_uri), "".join(rows)))


def text_page(title, lines, logo_uri):
    body = html.escape("\n".join(lines).strip("\n"))
    return ('<section class="page">%s<h2 class="sect">%s</h2><pre class="raw">%s</pre></section>'
            % (letterhead(logo_uri), html.escape(title), body))


CSS = """
@page { size: Letter; margin: 12mm; }
* { box-sizing: border-box; }
body { font-family: Arial, Helvetica, sans-serif; font-size: 9.2pt; color:#000; margin:0; }
.page { page-break-after: always; }
.page:last-child { page-break-after: auto; }
.head { display:flex; align-items:center; justify-content:center; gap:10px; }
.seal { width:62px; height:62px; object-fit:contain; }
.seal.spacer { visibility:hidden; }
.htext { text-align:center; line-height:1.15; }
.htext .l1 { font-size:8.5pt; }
.htext .l2 { font-size:11pt; font-weight:bold; }
.htext .l3 { font-size:7.5pt; }
.htext .l4 { font-size:7.5pt; }
.htext .l5 { font-size:6.8pt; }
.college { text-align:center; font-weight:bold; font-size:11pt; margin-top:10px; }
.dept { text-align:center; font-weight:bold; font-size:10.5pt; }
.uat-title { text-align:center; font-weight:bold; font-size:19pt; margin:10px 0 8px; }
table.uat { width:100%; border-collapse:collapse; table-layout:fixed; }
table.uat th, table.uat td { border:1px solid #000; padding:3px 5px; vertical-align:middle; }
table.uat th { width:22%; text-align:right; font-weight:bold; }
table.uat td.mlbl { width:34%; font-weight:bold; }
td.ctr { text-align:center; }
p { margin:0 0 4px; }
p:last-child { margin-bottom:0; }
.exp { margin-top:2px; padding-left:12px; }
.exp span { font-weight:bold; font-style:italic; }
p.hl { font-weight:bold; }
.marker { font-weight:bold; font-style:italic; text-align:center; margin-bottom:3px; }
.tall { height:52px; }
.remarks { height:66px; }
tr, td, th { page-break-inside:avoid; }
h2.sect { text-align:center; font-size:12.5pt; margin:4px 0 8px; }
pre.raw { font-family:"Consolas","Courier New",monospace; font-size:8pt; white-space:pre-wrap;
          border:1px solid #000; padding:8px; margin:0; line-height:1.25; }
"""


def build(fname, module, stem, logo_uri):
    pre, blocks = read_blocks(os.path.join(DOCS, fname))
    pages = []
    front = []
    for title, body in blocks:
        if re.match(r'^TC[-0-9]', title):
            break
        front.append((title, body))
    lead = [l for l in pre if l.strip()]
    if front:
        t0, b0 = front[0]
        head_lines = ([t0] if t0 else []) + b0
    else:
        head_lines = []
    cover = lead + [""] + head_lines
    pages.append(text_page("USER ACCEPTANCE TESTING - %s" % module.upper(), cover, logo_uri))
    for title, body in front[1:]:
        pages.append(text_page(title, body, logo_uri))

    ncase = 0
    for idx, (title, body) in enumerate(blocks):
        if idx < len(front):
            continue
        m = re.match(r'^(TC[-A-Za-z0-9]+)\s*[- ]\s*(.*)$', title)
        if m and re.match(r'^TC[-0-9]', title):
            ncase += 1
            fields, steps = parse_case(body)
            pages.append(case_html(m.group(1), m.group(2).strip(), fields, steps, logo_uri))
        else:
            pages.append(text_page(title, body, logo_uri))

    doc = ("<!doctype html><html><head><meta charset='utf-8'><title>%s</title>"
           "<style>%s</style></head><body>%s</body></html>"
           % (html.escape("iEvaluate UAT - " + module), CSS, "".join(pages)))
    out = os.path.join(OUT, stem + ".html")
    open(out, "w", encoding="utf-8").write(doc)
    print("%-32s cases=%d pages=%d -> %s" % (fname, ncase, len(pages), out))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    import shutil
    shutil.copyfile(LOGO, os.path.join(OUT, "ctu_logo.png"))
    logo_uri = "ctu_logo.png"
    for f, mod, stem in FILES:
        build(f, mod, stem, logo_uri)


main()
