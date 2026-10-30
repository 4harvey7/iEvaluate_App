import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../evaluation_service.dart';
import '../eval_results_service.dart';
import '../../utils/sast_rating.dart';
import '../../utils/theme_list_parser.dart';
import '../../utils/word_cloud_layout.dart';


class PdfService {
  // ─────────────────────────────────────────────────────────
  //  Helper: save bytes → file, then share/download
  // ─────────────────────────────────────────────────────────
  Future<void> _saveAndShare(Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      // On web: trigger a browser download via Printing.sharePdf (uses anchor download)
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return;
    }

    // On mobile / desktop: save to Downloads or Documents directory
    Directory? dir;
    try {
      if (Platform.isAndroid) {
        // Try the public Downloads directory first
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) dir = await getExternalStorageDirectory();
      } else if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        // Windows / macOS / Linux → user downloads folder
        dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = null; // no local copy; the share below still runs
      }
    }

    // Best effort only. getExternalStorageDirectory() can return null, and on
    // Android 10+ writing straight into /storage/emulated/0/Download without
    // storage permission throws -- either one used to abort the export before
    // the share sheet below, which is the part the user actually needs.
    if (dir != null) {
      try {
        final filePath = '${dir.path}/$fileName';
        await File(filePath).writeAsBytes(bytes);
        debugPrint('PDF saved to: $filePath');
      } catch (e) {
        debugPrint('PDF local save skipped: $e');
      }
    }

    // Share the saved file so the user can open/view it
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  // ─────────────────────────────────────────────────────────
  //  Performance Report (SAO Admin)
  // ─────────────────────────────────────────────────────────
  Future<void> generatePerformanceReport({
    required String title,
    required Map<String, dynamic> overviewStats,
    required List<InstructorPerformance> topInstructors,
  }) async {
    final pdf = pw.Document();

    // Load logo from assets
    pw.MemoryImage? logo;
    try {
      final ByteData logoData = await rootBundle.load('assets/images/CTU_logo.png');
      logo = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Logo not found: $e');
    }

    // Define colors for the prestige look
    final primaryColor = PdfColor.fromHex('#F58220'); // CTU Orange/Primary
    final headerBgColor = PdfColor.fromHex('#F8F9FA'); // Light gray background
    final darkTextColor = PdfColor.fromHex('#1E293B'); // Slate 800

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // ── Official University Header ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null) pw.SizedBox(height: 60, width: 60, child: pw.Image(logo))
                else pw.SizedBox(width: 60),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Republic of the Philippines', style: pw.TextStyle(fontSize: 10, color: darkTextColor)),
                    pw.Text('CEBU TECHNOLOGICAL UNIVERSITY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: darkTextColor)),
                    pw.Text('ARGAO CAMPUS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: primaryColor)),
                    pw.Text('Ed Kintanar Street, Lamacan, Argao, Cebu', style: pw.TextStyle(fontSize: 10, color: darkTextColor)),
                  ],
                ),
                pw.SizedBox(width: 60), // Balance the logo
              ],
            ),
            pw.SizedBox(height: 20),
            
            // ── Report Title ──
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 12),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: primaryColor, width: 2), bottom: pw.BorderSide(color: primaryColor, width: 2)),
              ),
              child: pw.Column(
                children: [
                  pw.Text('UNIVERSITY PERFORMANCE REPORT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: darkTextColor)),
                  pw.SizedBox(height: 4),
                  pw.Text(title.replaceAll('University Performance Report - ', ''), style: pw.TextStyle(fontSize: 12, color: darkTextColor)),
                ]
              )
            ),
            pw.SizedBox(height: 30),

            // ── Overview Statistics ──
            pw.Text('OVERVIEW STATISTICS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor)),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: headerBgColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPremiumStatItem('University Average', (overviewStats['overall'] ?? 'N/A').toString(), primaryColor),
                  _buildPremiumStatItem('Total Evaluations', (overviewStats['totalEvals'] ?? 'N/A').toString(), darkTextColor),
                ],
              ),
            ),
            pw.SizedBox(height: 30),



            // ── Top Performing Instructors Table ──
            pw.Text('TOP PERFORMING INSTRUCTORS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['Rank', 'Instructor', 'Department', 'Score', if (topInstructors.any((i) => i.isPct)) 'Rating', 'Evals'],
              data: topInstructors.asMap().entries.map((e) => [
                '#${e.key + 1}',
                e.value.name,
                e.value.department.replaceAll('College of ', ''), // Shorten long names
                e.value.isPct ? SastRating.formatPct(e.value.setPct) : e.value.overallScore.toStringAsFixed(2),
                if (topInstructors.any((i) => i.isPct)) e.value.verbalLabel,
                e.value.subjectCount.toString(),
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
              headerDecoration: pw.BoxDecoration(color: primaryColor), // Highlight the top performers table
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {0: pw.Alignment.center, 3: pw.Alignment.center, 4: pw.Alignment.center, if (topInstructors.any((i) => i.isPct)) 5: pw.Alignment.center},
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
              ),
            ),
            
            pw.SizedBox(height: 40),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Generated on: ${DateTime.now().toString().split('.')[0]}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
            )
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final fileName = '${title.replaceAll(' ', '_')}.pdf';
    await _saveAndShare(bytes, fileName);
  }

  pw.Widget _buildPremiumStatItem(String label, String value, PdfColor valueColor) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: valueColor)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Instructor Detailed Report (Instructor + Department Head)
  //  Two landscape pages matching the university's official samples:
  //  1) SAST Individual Report  2) SAST Individual Report and Comments
  // ─────────────────────────────────────────────────────────
  Future<void> generateInstructorDetailedReport({
    required String instructorName,
    String universityId = '',
    required String department,
    String college = '',
    String courseTaught = '',
    List<SastSubjectReport> subjectReports = const [],
    required String term,
    required String academicYear,
    // Stored values; null = no answers (printed as "—", never as 0.00).
    required double? mgmtScore,
    required double? perfScore,
    required double? overallScore,
    required int totalEvals,
    required List<double?> managementMeans,
    required List<double?> performanceMeans,
    required String aiSuggestion,
    String studentInterpretation = '',
    String positiveThemes = '',
    String improvementInsights = '',
    String overallTone = '',
    required List<Map<String, dynamic>> wordCloudData,
    SastSignatories signatories = SastSignatories.defaults,
  }) async {
    final bytes = await buildInstructorDetailedReport(
      instructorName: instructorName,
      universityId: universityId,
      department: department,
      college: college,
      courseTaught: courseTaught,
      subjectReports: subjectReports,
      term: term,
      academicYear: academicYear,
      mgmtScore: mgmtScore,
      perfScore: perfScore,
      overallScore: overallScore,
      totalEvals: totalEvals,
      managementMeans: managementMeans,
      performanceMeans: performanceMeans,
      aiSuggestion: aiSuggestion,
      studentInterpretation: studentInterpretation,
      positiveThemes: positiveThemes,
      improvementInsights: improvementInsights,
      overallTone: overallTone,
      wordCloudData: wordCloudData,
      signatories: signatories,
    );
    final fileName = 'SAST_Report_${instructorName.replaceAll(' ', '_')}.pdf';
    await _saveAndShare(bytes, fileName);
  }

  // ─────────────────────────────────────────────────────────
  //  SET report (new 15-item student evaluation, new terms only)
  // ─────────────────────────────────────────────────────────
  Future<void> generateSetReport({
    required EvalScope scope,
    required String instructorName,
    required String department,
    String college = '',
    String courseTaught = '',
    required String term,
    required String academicYear,
    List<String> comments = const [],
  }) async {
    final bytes = await buildSetReport(
      scope: scope,
      instructorName: instructorName,
      department: department,
      college: college,
      courseTaught: courseTaught,
      term: term,
      academicYear: academicYear,
      comments: comments,
    );
    await _saveAndShare(bytes, 'SET_Report_${instructorName.replaceAll(' ', '_')}.pdf');
  }

  Future<Uint8List> buildSetReport({
    required EvalScope scope,
    required String instructorName,
    required String department,
    String college = '',
    String courseTaught = '',
    required String term,
    required String academicYear,
    List<String> comments = const [],
  }) async {
    final pdf = pw.Document();
    pw.Widget line(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 130, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9))),
            pw.Text(': ', style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          ]),
        );

    // SET RATING Computation: blanks are skipped, so the denominator is
    // 5 x (items answered), which is 75 when all 15 items are answered.
    final answered = scope.items.where((i) => scope.itemMean[i.no] != null).toList();
    final total = answered.fold<double>(0, (a, i) => a + scope.itemMean[i.no]!);
    final denom = 5 * answered.length;
    final pct = scope.pct;
    final codes = scope.sectionTitles.keys.toList()..sort();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 20,
        build: (ctx) => [
          pw.Center(
            child: pw.Column(children: [
              if (college.trim().isNotEmpty)
                pw.Text(college.trim().toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('STUDENT EVALUATION OF TEACHING (SET) INDIVIDUAL REPORT',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('AY ${_shortTerm(term)} $academicYear'.trim(),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.SizedBox(height: 10),
          line('Name of Faculty', instructorName),
          line('Department', department),
          line('Course Taught', courseTaught),
          line('No. of Student-evaluators', '${scope.respondents}'),
          pw.SizedBox(height: 8),
          for (final c in codes) ...[
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FixedColumnWidth(44)},
              children: [
                pw.TableRow(children: [
                  _cell('$c. ${scope.sectionTitles[c]}', size: 9, bold: true, bg: PdfColors.grey200),
                  _cell('Mean', size: 9, bold: true, align: pw.TextAlign.center, bg: PdfColors.grey200),
                ]),
                for (final i in scope.items.where((x) => x.section == c))
                  pw.TableRow(children: [
                    _cell('${i.no}. ${i.text}'),
                    _cell(SastRating.format(scope.itemMean[i.no]), align: pw.TextAlign.center),
                  ]),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('SET RATING Computation', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Total Score = sum of the item ratings = ${total.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                  'SET Rating = Total Score / ${denom == 75 ? '75' : denom} x 100'
                  ' = ${total.toStringAsFixed(2)} / $denom x 100 = ${SastRating.formatPct(pct)}',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 3),
              pw.Text(
                  'Blank (unanswered) items are skipped, not counted as zero: answered total / (5 x items answered). '
                  'All 15 items answered gives a denominator of 75. This form: ${answered.length} of ${scope.items.length} items answered.',
                  style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
              pw.SizedBox(height: 6),
              pw.Text('Verbal Rating: ${scope.verbalLabel.toUpperCase()}',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('84-100 Outstanding | 68-83.99 Very Satisfactory | 52-67.99 Satisfactory | 36-51.99 Fair | below 36 Unsatisfactory',
                  style: const pw.TextStyle(fontSize: 7)),
            ]),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Comments of the students', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          if (comments.isEmpty)
            pw.Text('No comments.', style: const pw.TextStyle(fontSize: 9))
          else
            for (final c in comments)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text('- $c', style: const pw.TextStyle(fontSize: 9)),
              ),
        ],
      ),
    );
    return pdf.save();
  }

  /// Pure builder: data in, PDF bytes out (no saving / sharing).
  Future<Uint8List> buildInstructorDetailedReport({
    required String instructorName,
    String universityId = '',
    required String department,
    String college = '',
    String courseTaught = '',
    List<SastSubjectReport> subjectReports = const [],
    required String term,
    required String academicYear,
    required double? mgmtScore,
    required double? perfScore,
    required double? overallScore,
    required int totalEvals,
    required List<double?> managementMeans,
    required List<double?> performanceMeans,
    required String aiSuggestion,
    String studentInterpretation = '',
    String positiveThemes = '',
    String improvementInsights = '',
    String overallTone = '',
    required List<Map<String, dynamic>> wordCloudData,
    SastSignatories signatories = SastSignatories.defaults,
  }) async {
    final pdf = pw.Document();

    Future<pw.MemoryImage?> loadImage(String path) async {
      try {
        final ByteData data = await rootBundle.load(path);
        return pw.MemoryImage(data.buffer.asUint8List());
      } catch (e) {
        debugPrint('Image not found ($path): $e');
        return null;
      }
    }

    final seal = await loadImage('assets/images/ctu_seal.png');
    final bagong = await loadImage('assets/images/bagong_pilipinas.png');

    const format = PdfPageFormat.a4;
    final pageFormat = format.landscape;
    const margin = 24.0;
    final contentWidth = pageFormat.width - margin * 2;

    pw.Widget fit(pw.Widget child) => pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          alignment: pw.Alignment.topCenter,
          child: pw.SizedBox(width: contentWidth, child: child),
        );

    // One page 1 per subject; fall back to the combined page when there is
    // no per-subject data.
    // With subjects: OVERALL page first (dashboard figures), then one per subject.
    final overallPage = SastSubjectReport(
      courseTaught: courseTaught,
      totalEvals: totalEvals,
      mgmtScore: mgmtScore,
      perfScore: perfScore,
      overallScore: overallScore,
      managementMeans: managementMeans,
      performanceMeans: performanceMeans,
    );
    final hasSubjects = subjectReports.isNotEmpty;
    final page1s = hasSubjects ? [overallPage, ...subjectReports] : [overallPage];
    void addPage1s() {
    for (var i = 0; i < page1s.length; i++) {
      final r = page1s[i];
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(margin),
          build: (ctx) => fit(_pwIndividualReportPage(
            college: college,
            term: term,
            academicYear: academicYear,
            instructorName: instructorName,
            courseTaught: r.courseTaught,
            totalEvals: r.totalEvals,
            mgmtScore: r.mgmtScore,
            perfScore: r.perfScore,
            overallScore: r.overallScore,
            managementMeans: r.managementMeans,
            performanceMeans: r.performanceMeans,
            isOverall: hasSubjects && i == 0,
          )),
        ),
      );
    }
    }

    final narrative = buildSastCommentText(
      instructorName: instructorName,
      mgmt: mgmtScore,
      perf: perfScore,
      overall: overallScore,
      studentInterpretation: studentInterpretation,
      positiveThemes: positiveThemes,
      improvementInsights: improvementInsights,
      overallTone: overallTone,
      aiSuggestion: aiSuggestion,
      wordCloudData: wordCloudData,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(margin),
        maxPages: 20,
        build: (ctx) => _pwCommentsPage(
          seal: seal,
          bagong: bagong,
          term: term,
          academicYear: academicYear,
          college: college,
          department: department,
          instructorName: instructorName,
          totalEvals: totalEvals,
          mgmtScore: mgmtScore,
          perfScore: perfScore,
          overallScore: overallScore,
          narrative: narrative,
          wordCloudData: wordCloudData,
              signatories: signatories,
        ),
      ),
    );

    // Order: comments page(s) first, then OVERALL, then per-subject pages.
    addPage1s();

    return pdf.save();
  }

  // ───────────────────────── Page 1 ─────────────────────────

  static String _shortTerm(String term) =>
      term.trim().toUpperCase().replaceAll('SEMESTER', 'SEM');

  pw.Widget _cell(String text, {double size = 8, bool bold = false, pw.TextAlign align = pw.TextAlign.left, PdfColor? bg}) {
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  pw.Widget _pwSastTable(String title, List<String> items, List<double?> means) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FixedColumnWidth(36),
        2: pw.FixedColumnWidth(28),
      },
      children: [
        pw.TableRow(children: [
          _cell(title, size: 9, bold: true),
          _cell('Mean', size: 9, bold: true, align: pw.TextAlign.center),
          _cell('VD', size: 9, bold: true, align: pw.TextAlign.center),
        ]),
        for (var i = 0; i < items.length; i++)
          pw.TableRow(children: [
            _cell('${i + 1}. ${items[i].toLowerCase()}'),
            _cell(SastRating.format(i < means.length ? means[i] : null), align: pw.TextAlign.center),
            _cell(SastRating.code(i < means.length ? means[i] : null), align: pw.TextAlign.center),
          ]),
      ],
    );
  }

  pw.Widget _pwIndividualReportPage({
    required String college,
    required String term,
    required String academicYear,
    required String instructorName,
    required String courseTaught,
    required int totalEvals,
    required double? mgmtScore,
    required double? perfScore,
    required double? overallScore,
    required List<double?> managementMeans,
    required List<double?> performanceMeans,
    bool isOverall = false,
  }) {
    pw.Widget infoRow(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 110, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9))),
            pw.Text(': ', style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          ]),
        );

    final legend = <List<String>>[
      ['4.20 - 5.00', 'Outstanding (O)'],
      ['3.40 - 4.19', 'Very Satisfactory (VS)'],
      ['2.60 - 3.39', 'Satisfactory (S)'],
      ['1.80 - 2.59', 'Fair (F)'],
      ['1.00 - 1.79', 'Unsatisfactory (US)'],
    ];

    final verbal = overallScore == null ? 'NO DATA' : SastRating.verbal(overallScore).toUpperCase();

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Column(children: [
              if (college.trim().isNotEmpty)
                pw.Text(college.trim().toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text("STUDENTS' ASSESSMENT SURVEY FOR TEACHERS (SAST) INDIVIDUAL REPORT${isOverall ? ' \u2014 OVERALL' : ''}",
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('AY ${_shortTerm(term)} $academicYear'.trim(),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.SizedBox(height: 10),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              flex: 5,
              child: pw.Column(children: [
                infoRow('Name of Instructor/Professor', instructorName),
                infoRow('Course Taught', courseTaught),
                infoRow('No. of Student-evaluators', '$totalEvals'),
              ]),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 2,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.RichText(
                  text: pw.TextSpan(children: [
                    const pw.TextSpan(text: 'Campus: ', style: pw.TextStyle(fontSize: 9)),
                    pw.TextSpan(text: 'ARGAO', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ]),
                ),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('RANGE & Verbal Description (VD)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                for (final l in legend)
                  pw.Text('${l[0]}  ${l[1]}', style: const pw.TextStyle(fontSize: 8)),
              ]),
            ),
          ]),
          pw.SizedBox(height: 10),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: _pwSastTable('I. Management', _managementCriteria, managementMeans)),
            pw.SizedBox(width: 6),
            pw.Expanded(child: _pwSastTable('II. Performance', _performanceCriteria, performanceMeans)),
          ]),
          pw.SizedBox(height: 4),
          pw.Text('*Comments made by the students are herewith attached.',
              style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 4),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Summary Statistics', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Row(children: [
                  pw.SizedBox(width: 130, child: pw.Text('Management Mean (MM)', style: const pw.TextStyle(fontSize: 9))),
                  pw.Text(': ${SastRating.format(mgmtScore)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.Row(children: [
                  pw.SizedBox(width: 130, child: pw.Text('Performance Mean (PM)', style: const pw.TextStyle(fontSize: 9))),
                  pw.Text(': ${SastRating.format(perfScore)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ]),
              ]),
            ),
            pw.Expanded(
              child: pw.Center(
                child: pw.Column(children: [
                  pw.Text('You are a/an', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(verbal, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('General Average ${SastRating.format(overallScore)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Instructor/Professor', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ───────────────────────── Page 2 ─────────────────────────

  static String _endSentence(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(RegExp(r'[.!?;,:\s]+$'), '');
    return t.isEmpty ? '' : '$t.';
  }

  /// One flowing paragraph for the COMMENTS block, combining the ratings, the
  /// word cloud terms and all five stored AI columns. Empty parts are skipped.
  static String buildSastCommentText({
    required String instructorName,
    required double? mgmt,
    required double? perf,
    required double? overall,
    String studentInterpretation = '',
    String positiveThemes = '',
    String improvementInsights = '',
    String overallTone = '',
    String aiSuggestion = '',
    List<Map<String, dynamic>> wordCloudData = const [],
  }) {
    if (overall == null && mgmt == null && perf == null) {
      return 'No evaluation results yet.';
    }
    final vm = SastRating.verbal(mgmt), vp = SastRating.verbal(perf), vo = SastRating.verbal(overall);
    final ratings = (vm == vp && vp == vo)
        ? 'Management = ${SastRating.format(mgmt)}, Performance = ${SastRating.format(perf)}, Overall = ${SastRating.format(overall)}, all $vo'
        : 'Management = ${SastRating.format(mgmt)} ($vm), Performance = ${SastRating.format(perf)} ($vp), Overall = ${SastRating.format(overall)} ($vo)';

    final words = wordCloudData
        .map((w) => (w['word'] ?? '').toString().trim())
        .where((w) => w.isNotEmpty)
        .take(5)
        .toList();

    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Text without trailing punctuation, so exactly one period is added later.
    String bare(String s) => flat(s).replaceAll(RegExp(r'[.!?;,:\s]+$'), '');
    // Lower-case the first letter unless it starts an acronym / proper noun.
    String lowerFirst(String s) {
      if (s.length > 1 && s[0] == s[0].toUpperCase() && s[1] == s[1].toLowerCase() && s[1] != ' ') {
        return '${s[0].toLowerCase()}${s.substring(1)}';
      }
      return s;
    }

    final sb = StringBuffer('Integrated with the quantitative ratings ($ratings)');
    if (words.isNotEmpty) {
      sb.write(' and the dominant terms in the word cloud (${words.join(', ')})');
    }
    // Prose is kept as its own sentence(s); only a single short clause is
    // folded into the opener.
    final interp = bare(studentInterpretation);
    final shortClause = interp.isNotEmpty &&
        interp.length <= 120 &&
        !RegExp(r'[.!?]\s').hasMatch(interp);
    if (shortClause) {
      sb.write(", the students' feedback indicates that ${lowerFirst(interp)}.");
    } else {
      sb.write(', the overall evaluation of $instructorName is $vo.');
      if (interp.isNotEmpty) sb.write(' ${_endSentence(interp)}');
    }

    // List -> lead-in phrase + natural list; prose -> its own sentence(s).
    void themes(String raw, String leadIn) {
      final v = parseThemeValue(raw);
      if (v.items.isNotEmpty) {
        final list = ThemeValue(items: v.items.map((i) => lowerFirst(bare(i))).toList()).toNaturalList();
        sb.write(' $leadIn $list.');
      } else if (v.text.isNotEmpty) {
        sb.write(' ${_endSentence(v.text)}');
      }
    }

    themes(positiveThemes, 'Students particularly appreciated');
    themes(improvementInsights, 'Areas identified for improvement include');

    final rec = bare(aiSuggestion);
    if (rec.isNotEmpty) {
      final reads = RegExp(r'recommend|^(the )?instructor\b|^you\b|^it (is|would)\b', caseSensitive: false).hasMatch(rec);
      sb.write(reads ? ' $rec.' : ' It is recommended that the instructor ${lowerFirst(rec)}.');
    }
    final tone = bare(overallTone);
    if (tone.isNotEmpty) {
      sb.write(" Overall, the tone of the students' feedback is ${tone.toLowerCase()}.");
    }
    return flat(sb.toString());
  }

  pw.Widget _pwLetterhead(pw.MemoryImage? seal, pw.MemoryImage? bagong) {
    const s = pw.TextStyle(fontSize: 8);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(width: 70, height: 70, child: seal != null ? pw.Image(seal) : pw.SizedBox()),
        pw.Expanded(
          child: pw.Column(children: [
            pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('CEBU TECHNOLOGICAL UNIVERSITY', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text('ARGAO CAMPUS', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Ed Kintanar Street, Lamacan, Argao, Cebu', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Website: www.argao.ctu.edu.ph  Email: dargao@ctu.edu.ph', style: s),
            pw.Text('Phone No.: (032) 401-0737 local 1780', style: s),
          ]),
        ),
        pw.SizedBox(width: 70, height: 70, child: bagong != null ? pw.Image(bagong) : pw.SizedBox()),
      ],
    );
  }

  // Viridis-style, darkened at the yellow end so it stays legible in print.
  static const List<PdfColor> _cloudColors = [
    PdfColor.fromInt(0xFF440154),
    PdfColor.fromInt(0xFF3B528B),
    PdfColor.fromInt(0xFF21918C),
    PdfColor.fromInt(0xFF2FA04F),
    PdfColor.fromInt(0xFF7FA800),
    PdfColor.fromInt(0xFFB59B00),
  ];

  pw.Widget _pwWordCloud(String name, List<Map<String, dynamic>> data, {double width = 290}) {
    final freq = sumWordCounts([
      for (final w in data) MapEntry((w['word'] ?? '').toString(), SastRating.parseInt(w['count']) ?? 1),
    ]);
    const height = 150.0;
    final placed = layoutWordCloud(freq, width: width, height: height, minSize: 7, maxSize: 40);

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text("Students' Feedback on $name's Performance", style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 4),
      pw.SizedBox(
        width: width,
        height: height,
        child: placed.isEmpty
            ? pw.Center(child: pw.Text('No feedback terms yet.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)))
            : pw.Stack(
                children: [
                  for (var i = 0; i < placed.length; i++)
                    pw.Positioned(
                      left: placed[i].x,
                      top: placed[i].y,
                      child: _pwCloudWord(placed[i], i),
                    ),
                ],
              ),
      ),
    ]);
  }

  pw.Widget _pwCloudWord(CloudWord w, int index) {
    final text = pw.Text(
      w.word,
      style: pw.TextStyle(
        fontSize: w.fontSize,
        fontWeight: pw.FontWeight.bold,
        color: index == 0 ? _cloudColors.first : _cloudColors[(index * 5 + 1) % _cloudColors.length],
      ),
    );
    return w.rotated ? pw.Transform.rotateBox(angle: math.pi / 2, child: text) : text;
  }

  List<pw.Widget> _pwCommentsPage({
    required pw.MemoryImage? seal,
    required pw.MemoryImage? bagong,
    required String term,
    required String academicYear,
    required String college,
    required String department,
    required String instructorName,
    required int totalEvals,
    required double? mgmtScore,
    required double? perfScore,
    required double? overallScore,
    required String narrative,
    required List<Map<String, dynamic>> wordCloudData,
    required SastSignatories signatories,
  }) {
    final paragraph = pw.Text(
      narrative,
      textAlign: pw.TextAlign.justify,
      style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
    );
    // A Row cannot split across pages: very long text goes below the cloud.
    final longText = narrative.length > 1800;

    pw.Widget field(String label, String value) => pw.Row(children: [
          pw.Text('$label: ', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, decoration: pw.TextDecoration.underline)),
        ]);

    pw.Widget hdr(String t, {int span = 1}) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(2),
          child: pw.Text(t, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        );
    pw.Widget val(String t) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(t, style: const pw.TextStyle(fontSize: 9)),
        );

    pw.Widget pair(double? score, {bool header = false}) => pw.Row(children: [
          pw.Expanded(child: header ? hdr('Mean') : val(SastRating.format(score))),
          pw.Expanded(child: header ? hdr('VD') : val(SastRating.code(score))),
        ]);

    pw.Widget sign(String label, String name, String title) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 22),
            pw.Text(name.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
            pw.Text(title, style: const pw.TextStyle(fontSize: 8)),
          ]),
        );

    return [
        _pwLetterhead(seal, bagong),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Column(children: [
            pw.Text("STUDENTS' ASSESSMENT SURVEY FOR TEACHERS (SAST)", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text('INDIVIDUAL REPORT AND COMMENTS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          field('Term', term),
          field('Academic Year', academicYear),
        ]),
        pw.SizedBox(height: 3),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          if (college.trim().isNotEmpty) field('College', college.trim()) else pw.SizedBox(),
          field('Department', department),
        ]),
        pw.SizedBox(height: 3),
        field('Name of Faculty', instructorName.toUpperCase()),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(50),
            1: pw.FlexColumnWidth(),
            2: pw.FlexColumnWidth(),
            3: pw.FlexColumnWidth(),
          },
          children: [
            pw.TableRow(children: [hdr('N'), hdr('MANAGEMENT'), hdr('PERFORMANCE'), hdr('OVERALL')]),
            pw.TableRow(children: [
              hdr(''),
              pair(null, header: true),
              pair(null, header: true),
              pair(null, header: true),
            ]),
            pw.TableRow(children: [
              val('$totalEvals'),
              pair(mgmtScore),
              pair(perfScore),
              pair(overallScore),
            ]),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text('COMMENTS:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        if (longText) ...[
          pw.Center(child: pw.SizedBox(width: 420, child: _pwWordCloud(instructorName, wordCloudData, width: 420))),
          pw.SizedBox(height: 8),
          paragraph,
        ] else
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(flex: 3, child: paragraph),
            pw.SizedBox(width: 14),
            pw.Expanded(flex: 2, child: _pwWordCloud(instructorName, wordCloudData)),
          ]),
        pw.SizedBox(height: 18),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          sign('Prepared by:', signatories.preparedByName, signatories.preparedByTitle),
          sign('Checked and Verified:', signatories.checkedByName, signatories.checkedByTitle),
          sign('Certified Proper and In Order:', signatories.certifiedByName, signatories.certifiedByTitle),
        ]),
    ];
  }

  static const List<String> _managementCriteria = [
    'Gives reasonable course / subject assignments',
    'Earns appreciation and kind attention from the students',
    'Gives orientation about the subject and how the students are evaluated',
    'Gives tests and/or projects which are within the objectives of the course',
    'Shows deep interest and concern in assisting the students',
    'Manifests sympathetic insight into students\' feelings',
    'Checks and records test papers/term papers',
    'Is on time and regular in meeting the class',
    'Apportions fair subject/course assignments',
    'Sustains the attention of the class for the whole period',
  ];

  static const List<String> _performanceCriteria = [
    'Presents lesson clearly, methodically, and substantially',
    'Motivates the students to learn',
    'Facilitates learning with the application of appropriate educational methods and techniques',
    'Shows mastery of the lesson',
    'Is ready for the class',
    'Inspires students\' self-reliance in their quest for knowledge',
    'Knows when the students have difficulty understanding the lesson and find ways to make it easy',
    'Integrates values into the lesson',
    'Speaks the language of instruction (English or Filipino) clearly and fluently',
    'Delivers thought provoking questions',
  ];
}

/// Names and titles printed at the foot of the SAST comments page.
/// Loaded from public.report_signatories (id = 1); [defaults] when unavailable.
/// One subject's SAST figures for the per-subject page 1.
class SastSubjectReport {
  final String courseTaught;
  final int totalEvals;
  final double? mgmtScore;
  final double? perfScore;
  final double? overallScore;
  final List<double?> managementMeans;
  final List<double?> performanceMeans;
  const SastSubjectReport({
    required this.courseTaught,
    required this.totalEvals,
    required this.mgmtScore,
    required this.perfScore,
    required this.overallScore,
    required this.managementMeans,
    required this.performanceMeans,
  });
}

class SastSignatories {
  final String preparedByName, preparedByTitle;
  final String checkedByName, checkedByTitle;
  final String certifiedByName, certifiedByTitle;

  const SastSignatories({
    required this.preparedByName,
    required this.preparedByTitle,
    required this.checkedByName,
    required this.checkedByTitle,
    required this.certifiedByName,
    required this.certifiedByTitle,
  });

  static const SastSignatories defaults = SastSignatories(
    preparedByName: 'MELANIE R. ABARRACIN',
    preparedByTitle: 'OFA Focal/Dean, Student Life',
    checkedByName: 'CHRISTINE JOY A. TOMOL',
    checkedByTitle: 'Dean of Instruction',
    certifiedByName: 'EINGILBERT C. BENOLOIRAO',
    certifiedByTitle: 'Campus Director',
  );

  /// Row from report_signatories; any blank/missing field keeps its default.
  factory SastSignatories.fromRow(Map<String, dynamic>? row) {
    String pick(String key, String fallback) {
      final v = row?[key]?.toString().trim() ?? '';
      return v.isEmpty ? fallback : v;
    }

    const d = defaults;
    return SastSignatories(
      preparedByName: pick('prepared_by_name', d.preparedByName),
      preparedByTitle: pick('prepared_by_title', d.preparedByTitle),
      checkedByName: pick('checked_by_name', d.checkedByName),
      checkedByTitle: pick('checked_by_title', d.checkedByTitle),
      certifiedByName: pick('certified_by_name', d.certifiedByName),
      certifiedByTitle: pick('certified_by_title', d.certifiedByTitle),
    );
  }
}
