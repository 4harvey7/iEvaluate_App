import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../evaluation_service.dart';

class PdfService {
  Future<void> generatePerformanceReport({
    required String title,
    required Map<String, dynamic> overviewStats,
    required List<Map<String, dynamic>> departmentAverages,
    required List<InstructorPerformance> topInstructors,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(title,
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateTime.now().toString().split(' ')[0]),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Overview Statistics',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('University Average', overviewStats['overall'] ?? 'N/A'),
                _buildStatItem('Total Evaluations', overviewStats['totalEvals'] ?? 'N/A'),
                _buildStatItem('Completion Rate', overviewStats['completion'] ?? 'N/A'),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Text('Department Averages',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.TableHelper.fromTextArray(
              headers: ['Department', 'Average Score'],
              data: departmentAverages.map((dept) => [dept['dept'], dept['score'].toString()]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 30),
            pw.Text('Top Performing Instructors',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.TableHelper.fromTextArray(
              headers: ['Instructor', 'Department', 'Score', 'Subjects'],
              data: topInstructors.map((i) => [i.name, i.department, i.overallScore.toString(), i.subjectCount.toString()]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: '${title.replaceAll(' ', '_')}.pdf');
  }

  Future<void> generateInstructorDetailedReport({
    required String instructorName,
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
            _pwHeader(logo, term, academicYear, department, instructorName),
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

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'SAST_Report_${instructorName.replaceAll(' ', '_')}.pdf',
    );
  }

  pw.Widget _buildStatItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  pw.Widget _pwHeader(pw.MemoryImage? logo, String term, String ay, String dept, String name) {
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
            pw.Expanded(child: _pwHeaderField('Term', term)),
            pw.SizedBox(width: 16),
            pw.Expanded(child: _pwHeaderField('Academic Year', ay)),
          ],
        ),
        pw.Row(
          children: [
            pw.Expanded(child: _pwHeaderField('Department', dept)),
            pw.SizedBox(width: 16),
            pw.Expanded(child: _pwHeaderField('Faculty', name)),
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
        pw.Text('4.20 - 5.00 : Outstanding (O)  |  3.40 - 4.19 : Very Satisfactory (VS)  |  2.60 - 3.39 : Satisfactory (S)', style: const pw.TextStyle(fontSize: 7)),
        pw.Text('1.80 - 2.59 : Fair (F)  |  1.00 - 1.79 : Unsatisfactory (US)', style: const pw.TextStyle(fontSize: 7)),
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
    if (score >= 4.20) return 'Outstanding';
    if (score >= 3.40) return 'Very Satisfactory';
    if (score >= 2.60) return 'Satisfactory';
    if (score >= 1.80) return 'Fair';
    return 'Unsatisfactory';
  }

  String _getVDCode(double score) {
    if (score >= 4.20) return 'O';
    if (score >= 3.40) return 'VS';
    if (score >= 2.60) return 'S';
    if (score >= 1.80) return 'F';
    return 'US';
  }

  static const List<String> _managementCriteria = [
    'gives reasonable course/subject assignments',
    'earns appreciation and kind attention from the students',
    'gives orientation about the subject and how the students are evaluated',
    'gives tests and/or projects which are within the objectives of the course',
    'shows concern in assisting the students',
    'shows sympathetic insight into students\' feelings',
    'checks and records test papers/term papers promptly',
    'is on time and regular in meeting the class',
    'assigns fair subjects/course requirements',
    'sustains the attention of the class for the whole period',
  ];

  static const List<String> _performanceCriteria = [
    'presents lesson clearly, methodically, and substantially',
    'motivates the students to learn',
    'facilitates learning with the application of appropriate educational methods and techniques',
    'shows mastery of the lesson',
    'is prepared for the class',
    'inspires students\' self-reliance in their quest for knowledge',
    'knows when the students have difficulty understanding the lesson and finds ways to make it easy',
    'integrates values into the lesson',
    'speaks the language of instruction (English or Filipino) clearly and fluently',
    'delivers thought provoking questions',
  ];
}
