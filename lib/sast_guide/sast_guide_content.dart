// lib/sast_guide/sast_guide_content.dart
// Text shared with the website. Keep identical to the website version.
import 'package:flutter/material.dart';
import '../core/config/env.dart';

class SastItem {
  final String text;
  final String? label;
  final IconData? icon;
  final bool isSub;
  const SastItem(this.text, this.label, this.icon) : isSub = false;
  const SastItem.sub(this.text)
      : label = null,
        icon = null,
        isSub = true;
}

class SastGuideSection {
  final String title;
  final IconData icon;
  final List<SastItem> dos;
  final List<SastItem> donts;
  const SastGuideSection(this.title, this.icon, this.dos, this.donts);
}

const sastGuideTitle = 'SAST Guidelines';
const sastGuideSubtitle =
    'Read this every semester. Following it keeps SAST results accurate and saves review work.';
const sastGuideFooter = 'Questions? Contact the SAO admin.';

/// Items starting with two spaces are rendered as sub-bullets.
List<SastGuideSection> sastGuideSections() => [
      const SastGuideSection('1. Preparing the SAST forms (stamp)', Icons.approval, [
        SastItem('Stamp every form with the numbering machine BEFORE handing it out. One stamp per form.', 'Stamp before handing out', Icons.approval),
        SastItem('Stamp upright, in the same spot on every form (top margin, away from the table and the student ID).', 'Upright, same spot', Icons.vertical_align_top),
        SastItem('Use dark, fresh ink so every digit is sharp and complete.', 'Dark, fresh ink', Icons.water_drop),
        SastItem('Check the stamp: all digits visible, nothing smudged or cut off.', 'All digits visible', Icons.visibility),
      ], [
        SastItem("Don't stamp a form twice or stamp over the rating table, the header or the student ID.", 'No double stamp', Icons.content_copy),
        SastItem("Don't photocopy stamped forms or reuse a stamp number. A stamp number already saved this semester is rejected automatically as a duplicate.", 'No photocopies / reused numbers', Icons.block),
        SastItem("Don't let a worn or dry stamp pad print faint or broken digits; replace the ink first.", 'No faint stamp', Icons.invert_colors_off),
      ]),
      const SastGuideSection('2. Filling in the form (for students; read it to them)', Icons.edit_note, [
        SastItem('Use a black or blue ballpen.', 'Black or blue ballpen', Icons.edit),
        SastItem("Write the instructor's full name, the subject code and title, and your student ID clearly in the header.", 'Clear header', Icons.badge),
        SastItem('Mark each answer with a check (✓) or a slash (/) inside the box of the column you choose.', 'Check ✓ or slash /', Icons.check),
        SastItem('Make the mark about the size of the box: not a tiny dot, and not so long that it runs into the next box or row.', 'Box-sized mark', Icons.crop_square),
        SastItem('Give exactly one mark per row and answer all 20 items. A form with fewer than 5 answers is not counted.', 'One mark per row, all 20', Icons.format_list_numbered),
        SastItem('Write comments only in the Remarks box. Leave it blank if you have none.', 'Remarks box only', Icons.comment),
      ], [
        SastItem("Don't use an X, shading, a circle or a dot. These are NOT counted.", 'No X, shading, circle, dot', Icons.close),
        SastItem("Don't put two marks in one row.", 'No two marks in a row', Icons.looks_two),
        SastItem("Don't cross out or scribble over an answer; ask for a new form instead.", 'No crossing out', Icons.backspace),
        SastItem("Don't use pencil (light pencil can be missed), and don't write over the stamp or the table lines.", 'No pencil, no writing on stamp', Icons.edit_off),
        SastItem("Don't fold, staple or tear the form through the table.", 'No folding or stapling', Icons.description),
      ]),
      const SastGuideSection('3. Scanning with the phone or the scanner', Icons.photo_camera, [
        SastItem('Lay the form flat on a plain, darker surface so the paper edges stand out.', 'Flat, darker surface', Icons.layers),
        SastItem('Use even light with no shadows or glare. Turn off the flash if it makes a shiny spot.', 'Good light, no glare', Icons.wb_sunny),
        SastItem('Fit the whole page inside the frame, hold the phone straight above the page and keep it still.', 'Whole page, phone straight', Icons.crop_free),
        SastItem('Pick the right paper size (Short or Long).', 'Right paper size', Icons.straighten),
        SastItem('Check the preview: the stamp, the header and all 20 rows must be readable.', 'Check the preview', Icons.preview),
      ], [
        SastItem("Don't scan tilted, curled or folded pages, or with fingers or objects on the paper.", 'No tilted or folded pages', Icons.rotate_right),
        SastItem("Don't scan the same form twice.", 'No double scans', Icons.content_copy),
        SastItem("Don't crop off the stamp or the edges of the table.", 'Don\'t crop stamp or table', Icons.crop),
      ]),
      const SastGuideSection('4. Reviewing flagged scans', Icons.fact_check, [
        SastItem('Open the scan image and compare every flagged item with the paper.', 'Compare with the paper', Icons.compare),
        SastItem('Type the stamp number exactly as printed when it was not read, including leading zeros.', 'Type stamp exactly', Icons.pin),
        SastItem('Fill in answers the scan missed; discard forms that break the rules above.', 'Fill missing, discard bad', Icons.edit_document),
      ], [
        SastItem("Don't approve a form you have not checked against the image.", 'Don\'t approve unchecked', Icons.do_not_disturb_on),
        SastItem("Don't type a stamp number you cannot read on the paper; check the physical form first.", 'Don\'t guess a stamp', Icons.help_outline),
      ]),
      SastGuideSection('5. Importing a Google Sheet', Icons.table_chart, [
        SastItem('Name the tab exactly: SAST Survey Data', 'Tab: SAST Survey Data', Icons.tab),
        SastItem('Put the column headers in the first row. Accepted headers:', 'Headers in row 1', Icons.view_column),
        SastItem.sub('  New layout: ID Number, Name of the Instructor/Professor, Course Handled by the Instructor, items "1. …" to "20. …", Comments'),
        SastItem.sub('  Old layout: Student ID, Instructor/Professor, Subject Taught, M1–M10, P1–P10, Remarks & Suggestions, Date'),
        SastItem('Items 1–10 are Management and 11–20 are Performance, like the paper form.', 'Items 1–10 / 11–20', Icons.format_list_numbered),
        SastItem('Enter ratings as numbers 1 to 5 (5 = Outstanding, 4 = Very Satisfactory, 3 = Satisfactory, 2 = Fair, 1 = Unsatisfactory).', 'Ratings 1 to 5', Icons.looks_5),
        SastItem('Write the instructor as "Family, First M." or "First Family", the same name as in iEvaluate.', 'Instructor name format', Icons.person),
        SastItem('Write the course as "CODE TITLE", for example: MOBAPP 330 MOBILE APPLICATION DEVELOPMENT', 'Course "CODE TITLE"', Icons.menu_book),
        SastItem('Use one row per student evaluation.', 'One row per student', Icons.table_rows),
        SastItem('Share the sheet with the iEvaluate service account as Viewer: ${Env.sheetServiceAccountEmail}', 'Share as Viewer', Icons.share),
        SastItem('Paste the full link (https://docs.google.com/spreadsheets/d/…) and wait until the app says the import finished. It can take several minutes; unmatched rows go to Import Errors for review.', 'Paste link and wait', Icons.link),
      ], [
        SastItem("Don't rename the tab, merge cells, or add title rows, total rows or empty rows between the data.", 'No renamed tab or merged/extra rows', Icons.grid_off),
        SastItem('Don\'t type words (like "Outstanding") instead of numbers in the rating columns.', 'Numbers, not words', Icons.pin),
        SastItem('Don\'t leave the Comments empty with spaces or dashes; leave it truly blank. "N/A" is fine (it is saved as empty).', 'Truly blank comments', Icons.comment),
        SastItem("Don't import the same sheet twice.", 'No double import', Icons.content_copy),
        SastItem('If the app says Google denied access, the sheet was not shared with the service account.', '"Access denied" = not shared', Icons.lock),
      ]),
    ];
