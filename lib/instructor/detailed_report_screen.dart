import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/pdf/pdf_service.dart';
import '../theme/app_colors.dart';

class DetailedReportScreen extends StatefulWidget {
  final String userId;
  final String? termId;
  final String instructorName;
  final String department;
  final String term;
  final String academicYear;
  final double managementScore;
  final double performanceScore;
  final double overallScore;
  final int totalEvaluations;

  const DetailedReportScreen({
    super.key,
    required this.userId,
    this.termId,
    required this.instructorName,
    required this.department,
    required this.term,
    required this.academicYear,
    this.managementScore = 0.0,
    this.performanceScore = 0.0,
    this.overallScore = 0.0,
    this.totalEvaluations = 0,
  });

  @override
  State<DetailedReportScreen> createState() => _DetailedReportScreenState();
}

class _DetailedReportScreenState extends State<DetailedReportScreen> {
  final _supabase = Supabase.instance.client;
  final _pdfService = PdfService();
  bool _isLoading = true;
  String? _aiSuggestion;
  String _summaryText = 'Loading analysis...';
  List<double> _managementMeans = List.filled(10, 0.0);
  List<double> _performanceMeans = List.filled(10, 0.0);
  List<Map<String, dynamic>> _wordCloudData = [];

  // State variables for summary metrics
  late double _mgmtScore;
  late double _perfScore;
  late double _overallScore;
  late int _totalEvals;

  @override
  void initState() {
    super.initState();
    _mgmtScore = widget.managementScore;
    _perfScore = widget.performanceScore;
    _overallScore = widget.overallScore;
    _totalEvals = widget.totalEvaluations;
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    try {
      // 1. Resolve Term ID first to enforce isolation
      final settings = await _supabase.from('system_settings').select('current_term_id').maybeSingle();
      final currentTermId = settings?['current_term_id'];
      final effectiveTermId = (widget.termId != null && widget.termId!.isNotEmpty) ? widget.termId! : currentTermId;

      if (effectiveTermId == null || effectiveTermId.isEmpty) {
        debugPrint('DetailedReportScreen: No effective term ID found.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Prepare queries with MANDATORY term filtering
      final questionQuery = _supabase
          .from('overall_question_means')
          .select('category, question_number, mean_score')
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);
      
      final wordQuery = _supabase
          .from('instructor_wordcloud')
          .select('word, count')
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);

      final aiQuery = _supabase
          .from('instructor_ai_suggestions')
          .select('ai_suggestion')
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);

      final summaryQuery = _supabase
          .from('overall_total_survey')
          .select()
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);

      final results = await Future.wait([
        questionQuery,
        wordQuery.order('count', ascending: false).limit(10),
        aiQuery.order('updated_at', ascending: false).limit(1).maybeSingle(),
        summaryQuery.order('created_at', ascending: false).limit(1).maybeSingle(),
      ]);

      List data = (results[0] as List?) ?? [];
      final words = (results[1] as List?) ?? [];
      final aiData = results[2] as Map<String, dynamic>?;
      final summaryData = results[3] as Map<String, dynamic>?;

      // FALLBACK: If summary tables are empty, calculate directly from RAW data
      if (data.isEmpty && effectiveTermId != null) {
        debugPrint('Summary tables empty for term $effectiveTermId. Calculating directly from RAW data...');
        try {
          final rawResults = await _supabase
              .from('raw_GoogleSheet_data_result')
              .select()
              .eq('instructor_ID', widget.userId)
              .eq('term_id', effectiveTermId);
          
          if (rawResults.isNotEmpty) {
            List<Map<String, dynamic>> fallbackData = [];
            int totalResp = rawResults.length;
            
            // Calculate Management Means (M1-M10)
            double mgmtSum = 0;
            for (int i = 1; i <= 10; i++) {
              double qSum = 0;
              for (var row in rawResults) {
                qSum += double.tryParse(row['m$i']?.toString() ?? '0') ?? 0;
              }
              double qMean = qSum / totalResp;
              mgmtSum += qMean;
              fallbackData.add({'category': 'Management', 'question_number': i, 'mean_score': qMean});
            }
            _mgmtScore = mgmtSum / 10;

            // Calculate Performance Means (P1-P10)
            double perfSum = 0;
            for (int i = 1; i <= 10; i++) {
              double qSum = 0;
              for (var row in rawResults) {
                qSum += double.tryParse(row['p$i']?.toString() ?? '0') ?? 0;
              }
              double qMean = qSum / totalResp;
              perfSum += qMean;
              fallbackData.add({'category': 'Performance', 'question_number': i, 'mean_score': qMean});
            }
            _perfScore = perfSum / 10;
            
            _overallScore = (_mgmtScore + _perfScore) / 2;
            _totalEvals = totalResp;
            data = fallbackData;
          }
        } catch (e) {
          debugPrint('Raw fallback calculation failed: $e');
        }
      }

      debugPrint('Fetched ${data.length} question means for user: ${widget.userId}');

      if (mounted) {
        setState(() {
          for (var row in data) {
            final cat = row['category'];
            final qNumRaw = row['question_number'];
            final qNum = (qNumRaw is int ? qNumRaw : int.tryParse(qNumRaw.toString()) ?? 0) - 1;
            
            // Extremely robust parsing for numeric strings or numbers
            final rawScore = row['mean_score'];
            double score = 0.0;
            if (rawScore is num) {
              score = rawScore.toDouble();
            } else if (rawScore != null) {
              score = double.tryParse(rawScore.toString()) ?? 0.0;
            }
            
            if (cat == 'Management' && qNum >= 0 && qNum < 10) {
              _managementMeans[qNum] = score;
            } else if (cat == 'Performance' && qNum >= 0 && qNum < 10) {
              _performanceMeans[qNum] = score;
            }
          }
          
          _wordCloudData = List<Map<String, dynamic>>.from(words);
          _aiSuggestion = aiData?['ai_suggestion'];
          _summaryText = _aiSuggestion ?? "No significant trends identified for this period.";

          if (summaryData != null) {
            debugPrint('Found summary data: $summaryData');
            final ms = double.tryParse(summaryData['management_mean']?.toString() ?? '');
            if (ms != null) _mgmtScore = ms;
            
            final ps = double.tryParse(summaryData['performance_mean']?.toString() ?? '');
            if (ps != null) _perfScore = ps;

            final ts = summaryData['total_responses'] as int?;
            if (ts != null) _totalEvals = ts;
            
            final os = double.tryParse(summaryData['overall_mean']?.toString() ?? '') 
                ?? double.tryParse(summaryData['combined_score_mean']?.toString() ?? '');
            if (os != null) _overallScore = os;
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching report data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generatePDF() async {
    try {
      await _pdfService.generateInstructorDetailedReport(
        instructorName: widget.instructorName,
        department: widget.department,
        term: widget.term,
        academicYear: widget.academicYear,
        mgmtScore: _mgmtScore,
        perfScore: _perfScore,
        overallScore: _overallScore,
        totalEvals: _totalEvals,
        managementMeans: _managementMeans,
        performanceMeans: _performanceMeans,
        aiSuggestion: _aiSuggestion ?? "",
        wordCloudData: _wordCloudData,
      );
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  String getVerbalDescription(double score) {
    if (score >= 4.20) return 'Outstanding';
    if (score >= 3.40) return 'Very Satisfactory';
    if (score >= 2.60) return 'Satisfactory';
    if (score >= 1.80) return 'Fair';
    return 'Unsatisfactory';
  }

  String getVDCode(double score) {
    if (score >= 4.20) return 'O';
    if (score >= 3.40) return 'VS';
    if (score >= 2.60) return 'S';
    if (score >= 1.80) return 'F';
    return 'US';
  }

  Color getVDColor(double score) {
    if (score >= 4.20) return AppColors.success;
    if (score >= 3.40) return AppColors.primary;
    if (score >= 1.80) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Official Evaluation Report', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: _generatePDF,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOfficialHeader(),
                  const Divider(height: 32),
                  _buildSummaryTable(),
                  const SizedBox(height: 24),
                  _buildCriteriaSection('I. Management', _managementCriteria, _mgmtScore, _managementMeans),
                  const SizedBox(height: 24),
                  _buildCriteriaSection('II. Performance', _performanceCriteria, _perfScore, _performanceMeans),
                  const SizedBox(height: 32),
                  _buildCommentsSection(),
                  const SizedBox(height: 32),
                  _buildLegend(),
                ],
              ),
            ),
    );
  }

  Widget _buildOfficialHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/CTU_logo.png', height: 60, errorBuilder: (c, e, s) => const Icon(Icons.school, size: 60)),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Republic of the Philippines', style: TextStyle(fontSize: 10)),
                  Text('CEBU TECHNOLOGICAL UNIVERSITY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('ARGAO CAMPUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('Ed Kintanar Street, Lamacan, Argao, Cebu', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.verified_user, size: 40, color: AppColors.primary),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          "STUDENTS' ASSESSMENT SURVEY FOR TEACHERS (SAST)",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const Text("INDIVIDUAL REPORT AND COMMENTS", textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _headerField('Term', widget.term)),
            const SizedBox(width: 16),
            Expanded(child: _headerField('Academic Year', widget.academicYear)),
          ],
        ),
        Row(
          children: [
            Expanded(child: _headerField('Department', widget.department)),
            const SizedBox(width: 16),
            Expanded(child: _headerField('Faculty', widget.instructorName)),
          ],
        ),
      ],
    );
  }

  Widget _headerField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
      ),
      child: Table(
        border: TableBorder.all(color: Colors.black),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(2),
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(color: Color(0xFFEEEEEE)),
            children: [
              TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text('N', style: TextStyle(fontWeight: FontWeight.bold))))),
              TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text('MANAGEMENT', style: TextStyle(fontWeight: FontWeight.bold))))),
              TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text('PERFORMANCE', style: TextStyle(fontWeight: FontWeight.bold))))),
              TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text('OVERALL', style: TextStyle(fontWeight: FontWeight.bold))))),
            ],
          ),
          TableRow(
            children: [
              TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text('$_totalEvals')))),
              _buildSummaryCell(_mgmtScore),
              _buildSummaryCell(_perfScore),
              _buildSummaryCell(_overallScore),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCell(double score) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(score.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(getVDCode(score), style: TextStyle(color: getVDColor(score), fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildCriteriaSection(String title, List<String> criteria, double sectionMean, List<double> questionMeans) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: AppColors.textPrimary,
          child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(8),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(1.5),
          },
          children: [
            const TableRow(
              decoration: BoxDecoration(color: Color(0xFFF9F9F9)),
              children: [
                TableCell(child: Padding(padding: EdgeInsets.all(8), child: Text('No.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                TableCell(child: Padding(padding: EdgeInsets.all(8), child: Text('Criteria', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Mean', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))))),
                TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text('VD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))))),
              ],
            ),
            ...criteria.asMap().entries.map((entry) {
              double score = questionMeans[entry.key];
              return TableRow(
                children: [
                  TableCell(child: Padding(padding: EdgeInsets.all(8), child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 10)))),
                  TableCell(child: Padding(padding: EdgeInsets.all(8), child: Text(entry.value, style: const TextStyle(fontSize: 10)))),
                  TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text(score.toStringAsFixed(2), style: const TextStyle(fontSize: 10))))),
                  TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text(getVDCode(score), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: getVDColor(score)))))),
                ],
              );
            }),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(8),
          alignment: Alignment.centerRight,
          child: Text(
            'Section Mean: ${sectionMean.toStringAsFixed(2)} (${getVerbalDescription(sectionMean)})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('COMMENTS & FEEDBACK SUMMARY:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _summaryText,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  const Text('Top Feedback Terms', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: _wordCloudData.take(5).map((w) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${w['word']} (${w['count']})',
                          style: TextStyle(
                            fontSize: 10 + (w['count'] as int).toDouble() * 0.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RANGE & Verbal Description (VD):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _legendItem('4.20 - 5.00', 'Outstanding (O)')),
              Expanded(child: _legendItem('2.60 - 3.39', 'Satisfactory (S)')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _legendItem('3.40 - 4.19', 'Very Satisfactory (VS)')),
              Expanded(child: _legendItem('1.80 - 2.59', 'Fair (F)')),
            ],
          ),
          _legendItem('1.00 - 1.79', 'Unsatisfactory (US)'),
        ],
      ),
    );
  }

  Widget _legendItem(String range, String desc) {
    return Text('$range : $desc', style: const TextStyle(fontSize: 9), overflow: TextOverflow.ellipsis);
  }

  static const List<String> _managementCriteria = [
    'gives reasonable course / subject assignments',
    'earns appreciation and kind attention from the students',
    'gives orientation about the subject and how the students are evaluated',
    'gives tests and/or projects which are within the objectives of the course',
    'shows deep interest and concern in assisting the students',
    'manifests sympathetic insight into students\' feelings',
    'checks and records test papers/term papers',
    'is on time and regular in meeting the class',
    'apportions fair subject/course assignments',
    'sustains the attention of the class for the whole period',
  ];

  static const List<String> _performanceCriteria = [
    'presents lesson clearly, methodically, and substantially',
    'motivates the students to learn',
    'facilitates learning with the application of appropriate educational methods and techniques',
    'shows mastery of the lesson',
    'is ready for the class',
    'inspires students\' self-reliance in their quest for knowledge',
    'knows when the students have difficulty understanding the lesson and find ways to make it easy',
    'integrates values into the lesson',
    'speaks the language of instruction (English or Filipino) clearly and fluently',
    'delivers thought provoking questions',
  ];
}
