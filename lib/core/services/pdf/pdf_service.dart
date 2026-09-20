import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../evaluation_service.dart';

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
      dir = await getApplicationDocumentsDirectory();
    }

    final filePath = '${dir!.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    debugPrint('PDF saved to: $filePath');

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
                  _buildPremiumStatItem('University Average', overviewStats['overall'] ?? 'N/A', primaryColor),
                  _buildPremiumStatItem('Total Evaluations', overviewStats['totalEvals'] ?? 'N/A', darkTextColor),
                ],
              ),
            ),
            pw.SizedBox(height: 30),



            // ── Top Performing Instructors Table ──
            pw.Text('TOP PERFORMING INSTRUCTORS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['Rank', 'Instructor', 'Department', 'Score', 'Evals'],
              data: topInstructors.asMap().entries.map((e) => [
                '#${e.key + 1}',
                e.value.name,
                e.value.department.replaceAll('College of ', ''), // Shorten long names
                e.value.overallScore.toStringAsFixed(2),
                e.value.subjectCount.toString(),
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
              headerDecoration: pw.BoxDecoration(color: primaryColor), // Highlight the top performers table
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {0: pw.Alignment.center, 3: pw.Alignment.center, 4: pw.Alignment.center},
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
  //  Instructor Detailed Report (Instructor view)
  // ─────────────────────────────────────────────────────────
  Future<void> generateInstructorDetailedReport({
    required String instructorName,
    String universityId = '',
    required String department,
    required String term,
    required String academicYear,
    required double mgmtScore,
    required double perfScore,
    required double overallScore,
    required int totalEvals,
    required List<double> managementMeans,
    required List<double> performanceMeans,
    required String aiSuggestion,
    required List<Map<String, dynamic>> wordCloudData,
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _pwHeader(logo, term, academicYear, department, instructorName, universityId),
            pw.Divider(),
            pw.SizedBox(height: 10),
            _pwSummaryTable(totalEvals, mgmtScore, perfScore, overallScore),
            pw.SizedBox(height: 20),
            _pwCriteriaSection('I. Management', _managementCriteria, mgmtScore, managementMeans),
            pw.SizedBox(height: 20),
            _pwCriteriaSection('II. Performance', _performanceCriteria, perfScore, performanceMeans),
            pw.SizedBox(height: 20),
            _pwCommentsSection(aiSuggestion, wordCloudData, mgmtScore, perfScore, overallScore),
            pw.SizedBox(height: 20),
            _pwLegend(),
            pw.SizedBox(height: 40),
            _pwSignatures(instructorName),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'SAST_Report_${instructorName.replaceAll(' ', '_')}.pdf';
    await _saveAndShare(bytes, fileName);
  }

  pw.Widget _pwHeader(pw.MemoryImage? logo, String term, String ay, String dept, String name, String universityId) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null) pw.SizedBox(height: 50, width: 50, child: pw.Image(logo))
            else pw.SizedBox(width: 50),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('CEBU TECHNOLOGICAL UNIVERSITY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text('ARGAO CAMPUS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text('Ed Kintanar Street, Lamacan, Argao, Cebu', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('SS Form No. 2', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('Revised Oct. 2023', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Text(
          "STUDENTS' ASSESSMENT SURVEY FOR TEACHERS (SAST)",
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
        ),
        pw.Text("INDIVIDUAL SUMMARY REPORT", textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.SizedBox(height: 15),
        pw.Row(
          children: [
            pw.Expanded(child: _pwHeaderField('Instructor Name', name)),
            pw.SizedBox(width: 16),
            pw.Expanded(child: _pwHeaderField('Instructor ID', universityId.isNotEmpty ? universityId : 'N/A')),
          ],
        ),
        pw.Row(
          children: [
            // term already carries the word "Semester" (e.g. "1st Semester"), so don't add it again
            pw.Expanded(child: _pwHeaderField('Academic Year', '$term $ay'.trim())),
            pw.SizedBox(width: 16),
            pw.Expanded(child: _pwHeaderField('Department', dept)),
          ],
        ),
      ],
    );
  }

  pw.Widget _pwHeaderField(String label, String value) {
    return pw.Row(
      children: [
        pw.Text('$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10, decoration: pw.TextDecoration.underline)),
      ],
    );
  }

  pw.Widget _pwSummaryTable(int n, double mgmt, double perf, double overall) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: pw.Text('N', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))),
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: pw.Text('MANAGEMENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))),
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: pw.Text('PERFORMANCE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))),
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: pw.Text('OVERALL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))),
          ],
        ),
        pw.TableRow(
          children: [
            pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('$n', style: const pw.TextStyle(fontSize: 10)))),
            pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(mgmt.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))),
            pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(perf.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))),
            pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(overall.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))),
          ],
        ),
      ],
    );
  }

  pw.Widget _pwCriteriaSection(String title, List<String> criteria, double sectionMean, List<double> questionMeans) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(4),
          color: PdfColors.grey800,
          child: pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(8),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('No.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Criteria', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Mean', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)))),
                pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('VD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)))),
              ],
            ),
            ...criteria.asMap().entries.map((entry) {
              double score = questionMeans.length > entry.key ? questionMeans[entry.key] : 0.0;
              return pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${entry.key + 1}', style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(entry.value, style: const pw.TextStyle(fontSize: 8))),
                  pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(score.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8)))),
                  pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_getVDCode(score), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))),
                ],
              );
            }),
          ],
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Section Mean: ${sectionMean.toStringAsFixed(2)} (${_getVerbalDescription(sectionMean)})',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
        ),
      ],
    );
  }

  pw.Widget _pwCommentsSection(String aiSuggestion, List<Map<String, dynamic>> wordCloudData, double mgmt, double perf, double overall) {
    final summaryText = aiSuggestion.isNotEmpty
        ? aiSuggestion
        : "Integrated ratings (Management = ${mgmt.toStringAsFixed(2)}, Performance = ${perf.toStringAsFixed(2)}, Overall = ${overall.toStringAsFixed(2)}, all ${_getVerbalDescription(overall)}) reflect a positive overall evaluation.";

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('COMMENTS & FEEDBACK SUMMARY:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                child: pw.Text(summaryText, style: const pw.TextStyle(fontSize: 9)),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              flex: 1,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Top Terms:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  ...wordCloudData.take(5).map((w) => pw.Text('- ${w['word']} (${w['count']})', style: const pw.TextStyle(fontSize: 8))),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _pwLegend() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('RANGE & Verbal Description (VD):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
        pw.Text('4.21 - 5.00 : Outstanding (O)  |  3.41 - 4.20 : Very Satisfactory (VS)  |  2.61 - 3.40 : Satisfactory (S)', style: const pw.TextStyle(fontSize: 7)),
        pw.Text('1.81 - 2.60 : Fair (F)  |  1.00 - 1.80 : Unsatisfactory (US)', style: const pw.TextStyle(fontSize: 7)),
      ],
    );
  }

  pw.Widget _pwSignatures(String name) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
            pw.SizedBox(height: 4),
            pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text('Faculty Member', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
            pw.SizedBox(height: 4),
            pw.Text('Department Chair / Dean', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text('Date Signed', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ],
    );
  }

  String _getVerbalDescription(double score) {
    if (score >= 4.21) return 'Outstanding';
    if (score >= 3.41) return 'Very Satisfactory';
    if (score >= 2.61) return 'Satisfactory';
    if (score >= 1.81) return 'Fair';
    return 'Unsatisfactory';
  }

  String _getVDCode(double score) {
    if (score >= 4.21) return 'O';
    if (score >= 3.41) return 'VS';
    if (score >= 2.61) return 'S';
    if (score >= 1.81) return 'F';
    return 'US';
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
