import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/pdf/pdf_service.dart';
import '../theme/app_colors.dart';
import '../widgets/apple_ui.dart';
import '../core/services/term_aware_state.dart';
import '../core/utils/sast_rating.dart';

class DetailedReportScreen extends StatefulWidget {
  final String userId;
  final String? termId;
  final String instructorName;
  final String universityId;
  final String department;
  final String term;
  final String academicYear;
  // Null = no stored result yet (shown as "—", never as 0.00).
  final double? managementScore;
  final double? performanceScore;
  final double? overallScore;
  final int totalEvaluations;

  const DetailedReportScreen({
    super.key,
    required this.userId,
    this.termId,
    required this.instructorName,
    this.universityId = '',
    required this.department,
    required this.term,
    required this.academicYear,
    this.managementScore,
    this.performanceScore,
    this.overallScore,
    this.totalEvaluations = 0,
  });

  @override
  State<DetailedReportScreen> createState() => _DetailedReportScreenState();
}

class _DetailedReportScreenState extends State<DetailedReportScreen>
    with TermAwareState<DetailedReportScreen> {
  final _supabase = Supabase.instance.client;
  final _pdfService = PdfService();
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  String? _aiSuggestion;
  String _summaryText = 'Loading analysis...';
  // Stored per-question means (overall_question_means). Null = nobody
  // answered that question; it is never filled in as 0.
  final List<double?> _managementMeans = List<double?>.filled(10, null);
  final List<double?> _performanceMeans = List<double?>.filled(10, null);
  // How many forms answered each question (response_count, migration 013).
  // Null on rows written before that column existed -- then the
  // "(x of y answered)" note is simply left out.
  final List<int?> _managementCounts = List<int?>.filled(10, null);
  final List<int?> _performanceCounts = List<int?>.filled(10, null);
  // True once the term has a stored result row or any question means.
  bool _hasResults = false;
  List<Map<String, dynamic>> _wordCloudData = [];
  String _aiInterpretation = '';
  String _aiPositive = '';
  String _aiImprovement = '';
  String _aiTone = '';
  // Extra PDF data; each load is best-effort and falls back silently.
  String _college = '';
  String _courseTaught = '';
  List<SastSubjectReport> _subjectReports = [];
  SastSignatories _signatories = SastSignatories.defaults;

  // State variables for summary metrics
  late double? _mgmtScore;
  late double? _perfScore;
  late double? _overallScore;
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

  // Reload when the SAO office switches the active term, instead of
  // showing the previous term's figures until this screen is rebuilt.
  @override
  void onTermChanged() {
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
      // select('*') rather than an explicit list: response_count only exists
      // once migration 013 is applied, and naming a missing column makes
      // PostgREST reject the whole request.
      final questionQuery = _supabase
          .from('overall_question_means')
          .select('*')
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);
      
      final wordQuery = _supabase
          .from('instructor_wordcloud')
          .select('word, count')
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);

      final aiQuery = _supabase
          .from('instructor_ai_suggestions')
          .select('*')
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);

      final summaryQuery = _supabase
          .from('overall_total_survey')
          .select()
          .eq('instructor_id', widget.userId)
          .eq('term_id', effectiveTermId);

      final results = await Future.wait<dynamic>([
        questionQuery,
        wordQuery.order('count', ascending: false).limit(200),
        aiQuery.order('updated_at', ascending: false).limit(1).maybeSingle(),
        summaryQuery.order('created_at', ascending: false).limit(1).maybeSingle(),
      ]);

      final List data = (results[0] as List?) ?? [];
      final words = (results[1] as List?) ?? [];
      final aiData = results[2] as Map<String, dynamic>?;
      final summaryData = results[3] as Map<String, dynamic>?;

      // No fallback that recomputes means from sast_all_raw_data_survey: it
      // counted blank answers as 0 and divided by every form. The report shows
      // the stored values or says there are no results yet.
      debugPrint('Fetched ${data.length} question means for user: ${widget.userId}');

      if (mounted) {
        setState(() {
          // Reset first so a term switch never keeps the previous term's means.
          for (var i = 0; i < 10; i++) {
            _managementMeans[i] = null;
            _performanceMeans[i] = null;
            _managementCounts[i] = null;
            _performanceCounts[i] = null;
          }

          for (var row in data) {
            final cat = row['category'];
            final qNumRaw = row['question_number'];
            final qNum = (qNumRaw is int ? qNumRaw : int.tryParse(qNumRaw.toString()) ?? 0) - 1;

            // Numbers or numeric strings; null (nobody answered) stays null.
            final score = SastRating.parse(row['mean_score']);
            final answered = SastRating.parseInt(row['response_count']);

            if (cat == 'Management' && qNum >= 0 && qNum < 10) {
              _managementMeans[qNum] = score;
              _managementCounts[qNum] = answered;
            } else if (cat == 'Performance' && qNum >= 0 && qNum < 10) {
              _performanceMeans[qNum] = score;
              _performanceCounts[qNum] = answered;
            }
          }

          _wordCloudData = List<Map<String, dynamic>>.from(words);
          _aiSuggestion = aiData?['ai_suggestion'];
          _aiInterpretation = (aiData?['student_interpretation'] ?? '').toString();
          _aiPositive = (aiData?['positive_themes'] ?? '').toString();
          _aiImprovement = (aiData?['improvement_insights'] ?? '').toString();
          _aiTone = (aiData?['overall_tone'] ?? '').toString();
          _summaryText = _aiSuggestion ?? "No significant trends identified for this period.";

          // The summary row is the source of truth for this term: Management,
          // Performance and Overall exactly as stored. Without a row there is
          // nothing to show (not 0.00).
          if (summaryData != null) {
            debugPrint('Found summary data: $summaryData');
            _mgmtScore = SastRating.parse(summaryData['management_mean']);
            _perfScore = SastRating.parse(summaryData['performance_mean']);
            _totalEvals = SastRating.parseInt(summaryData['total_responses']) ?? 0;
            _overallScore = SastRating.parse(summaryData['combined_score_mean']) ??
                SastRating.parse(summaryData['overall_mean']);
          } else {
            _mgmtScore = null;
            _perfScore = null;
            _overallScore = null;
            _totalEvals = 0;
          }
          _hasResults = summaryData != null || data.isNotEmpty;

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching report data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// College (department_name.college_id -> colleges.name), every subject taught
  /// in the term, and the signatories. Each query fails soft: a missing
  /// table/column (migration not applied) just leaves the default.
  Future<void> _loadPdfExtras() async {
    final termId = (widget.termId != null && widget.termId!.isNotEmpty)
        ? widget.termId!
        : (await _supabase.from('system_settings').select('current_term_id').maybeSingle())?['current_term_id']?.toString();

    try {
      final row = await _supabase
          .from('department_table')
          .select('department_name:Department_name_ID(colleges(name))')
          .eq('user_id', widget.userId)
          .limit(1)
          .maybeSingle();
      final dn = row?['department_name'];
      final col = dn is Map ? dn['colleges'] : null;
      final name = col is Map ? col['name'] : (col is List && col.isNotEmpty ? col.first['name'] : null);
      _college = (name ?? '').toString().trim();
    } catch (e) {
      debugPrint('DetailedReportScreen: college lookup skipped: $e');
      _college = '';
    }

    try {
      if (termId != null && termId.isNotEmpty) {
        final rows = await _supabase
            .from('instructor_subjects')
            .select('subjects!inner(subject_code, subject_name)')
            .eq('instructor_id', widget.userId)
            .eq('term_id', termId);
        final names = <String>{};
        for (final r in (rows as List)) {
          final s = r['subjects'];
          if (s is! Map) continue;
          final code = (s['subject_code'] ?? '').toString().trim();
          final nm = (s['subject_name'] ?? '').toString().trim();
          final label = [code, nm].where((e) => e.isNotEmpty).join(' - ');
          if (label.isNotEmpty) names.add(label);
        }
        _courseTaught = names.join(', ');
      }
    } catch (e) {
      debugPrint('DetailedReportScreen: course lookup skipped: $e');
    }

    // Per-subject stored results: one row per instructor/subject/term in
    // management_results and performance_results (true per-item means).
    _subjectReports = [];
    try {
      if (termId != null && termId.isNotEmpty) {
        final mRows = List<Map<String, dynamic>>.from(await _supabase
            .from('management_results')
            .select('*')
            .eq('instructor_id', widget.userId)
            .eq('term_id', termId));
        final pRows = List<Map<String, dynamic>>.from(await _supabase
            .from('performance_results')
            .select('*')
            .eq('instructor_id', widget.userId)
            .eq('term_id', termId));
        final ids = <String>{
          for (final r in [...mRows, ...pRows])
            if (r['subject_id'] != null) r['subject_id'].toString(),
        };
        if (ids.isNotEmpty) {
          final subs = await _supabase
              .from('subjects')
              .select('id, subject_code, subject_name')
              .inFilter('id', ids.toList());
          final labels = <String, String>{};
          for (final s in (subs as List)) {
            final code = (s['subject_code'] ?? '').toString().trim();
            final nm = (s['subject_name'] ?? '').toString().trim();
            labels[s['id'].toString()] = [code, nm].where((e) => e.isNotEmpty).join(' - ');
          }
          Map<String, dynamic>? find(List<Map<String, dynamic>> rows, String id) {
            for (final r in rows) {
              if (r['subject_id']?.toString() == id) return r;
            }
            return null;
          }

          final reports = <SastSubjectReport>[];
          for (final id in ids) {
            final m = find(mRows, id);
            final p = find(pRows, id);
            final mm = List<double?>.generate(10, (i) => m == null ? null : SastRating.parse(m['m${i + 1}_mean']));
            final pm = List<double?>.generate(10, (i) => p == null ? null : SastRating.parse(p['p${i + 1}_mean']));
            if (mm.every((v) => v == null) && pm.every((v) => v == null)) continue;
            final mgmt = m == null ? null : SastRating.parse(m['overall_management_mean']);
            final perf = p == null ? null : SastRating.parse(p['overall_performance_mean']);
            final overall = (mgmt != null && perf != null) ? (mgmt + perf) / 2 : (mgmt ?? perf);
            reports.add(SastSubjectReport(
              courseTaught: labels[id] ?? '',
              totalEvals: SastRating.parseInt(m?['total_responses']) ?? SastRating.parseInt(p?['total_responses']) ?? 0,
              mgmtScore: mgmt,
              perfScore: perf,
              overallScore: overall,
              managementMeans: mm,
              performanceMeans: pm,
            ));
          }
          reports.sort((a, b) => a.courseTaught.compareTo(b.courseTaught));
          _subjectReports = reports;
          if (reports.isNotEmpty) {
            final codes = reports
                .map((r) => r.courseTaught.split(' - ').first.trim())
                .where((c) => c.isNotEmpty)
                .toList();
            _courseTaught = 'All subjects (${reports.length}): ${codes.join(', ')}';
          }
        }
      }
    } catch (e) {
      debugPrint('DetailedReportScreen: per-subject lookup skipped: $e');
      _subjectReports = [];
    }

    try {
      final row = await _supabase.from('report_signatories').select('*').eq('id', 1).maybeSingle();
      _signatories = SastSignatories.fromRow(row);
    } catch (e) {
      debugPrint('DetailedReportScreen: signatories lookup skipped: $e');
      _signatories = SastSignatories.defaults;
    }
  }

  Future<void> _generatePDF() async {
    // A second tap while the first PDF is still building would open a second
    // share sheet on top of the first.
    if (_isGeneratingPdf) return;
    _isGeneratingPdf = true;
    try {
      await _loadPdfExtras();
      await _pdfService.generateInstructorDetailedReport(
        instructorName: widget.instructorName,
        universityId: widget.universityId,
        department: widget.department,
        college: _college,
        courseTaught: _courseTaught,
        subjectReports: _subjectReports,
        studentInterpretation: _aiInterpretation,
        positiveThemes: _aiPositive,
        improvementInsights: _aiImprovement,
        overallTone: _aiTone,
        signatories: _signatories,
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
    } finally {
      _isGeneratingPdf = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Official SAST Report', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: _generatePDF,
          )
        ],
      ),
      body: _isLoading
          ? const AppleLoadingState(label: 'Preparing official report…')
          : !_hasResults
          ? const AppleEmptyState(
              icon: Icons.assessment_outlined,
              title: 'No evaluation results yet',
              message: 'Results for this term will appear here once evaluation forms have been processed.',
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppleSurface(child: _buildOfficialHeader()),
                  const Divider(height: 32),
                  _buildSummaryTable(),
                  const SizedBox(height: 24),
                  _buildCriteriaSection('I. Management', _managementCriteria, _mgmtScore, _managementMeans, _managementCounts),
                  const SizedBox(height: 24),
                  _buildCriteriaSection('II. Performance', _performanceCriteria, _perfScore, _performanceMeans, _performanceCounts),
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
            Expanded(child: _headerField('Instructor Name', widget.instructorName)),
            const SizedBox(width: 16),
            Expanded(child: _headerField('Instructor ID', widget.universityId.isNotEmpty ? widget.universityId : 'N/A')),
          ],
        ),
        Row(
          children: [
            // term already carries the word "Semester" (e.g. "1st Semester"), so don't add it again
            Expanded(child: _headerField('Academic Year', '${widget.term} ${widget.academicYear}'.trim())),
            const SizedBox(width: 16),
            Expanded(child: _headerField('Department', widget.department)),
          ],
        ),
      ],
    );
  }

  /// One "Label: value" line of the official header block.
  ///
  /// DEF-03: this used to ellipsize the value, and two of these share one Row,
  /// so each field had only half the screen width -- the instructor read
  /// "Instructor Name: Rodz...", "Academic Year: 1st Se..." and "Department:
  /// College o..." and could not confirm from the screen whose report it was or
  /// which term it covered. The data was never wrong: the PDF renders both in
  /// full.
  ///
  /// The value now WRAPS instead of being cut. The field grows downward by a
  /// line or two on a narrow screen, which is the correct trade: this block is
  /// an identity check, so being complete matters more than being one line.
  Widget _headerField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline),
              softWrap: true,
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

  Widget _buildSummaryCell(double? score) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(SastRating.format(score), style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(SastRating.code(score), style: TextStyle(color: SastRating.color(score), fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildCriteriaSection(String title, List<String> criteria, double? sectionMean, List<double?> questionMeans, List<int?> answeredCounts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: AppColors.primaryDeep,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
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
              final double? score = questionMeans[entry.key];
              // "2 of 3 answered": per-question count vs. forms for the term.
              final answered = SastRating.answeredLabel(answeredCounts[entry.key], _totalEvals);
              return TableRow(
                children: [
                  TableCell(child: Padding(padding: EdgeInsets.all(8), child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 10)))),
                  TableCell(child: Padding(padding: EdgeInsets.all(8), child: Text(entry.value, style: const TextStyle(fontSize: 10)))),
                  TableCell(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Text(SastRating.format(score), style: const TextStyle(fontSize: 10)),
                            if (answered != null)
                              Text(answered, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TableCell(child: Center(child: Padding(padding: EdgeInsets.all(8), child: Text(SastRating.code(score), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SastRating.color(score)))))),
                ],
              );
            }),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(8),
          alignment: Alignment.centerRight,
          child: Text(
            'Section Mean: ${SastRating.format(sectionMean)} (${SastRating.verbal(sectionMean)})',
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
                            fontSize: (10 + (w['count'] as int).toDouble() * 0.5).clamp(10.0, 18.0),
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
