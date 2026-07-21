// lib/dept_head/instructor_detail_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../instructor/detailed_report_screen.dart';
import '../instructor/subject_detail_screen.dart';
import '../instructor/models/subject.dart';

/// Full-page view of an individual instructor, opened from the Faculty Roster.
/// Shows: current-term score card, historical trend bar chart,
/// subjects list (tappable → SubjectDetailScreen), and Official Report button.
class InstructorDetailPage extends StatefulWidget {
  /// The instructor map built by FacultyRosterScreen (id, name, title, etc.)
  final Map<String, dynamic> instructor;

  /// The dept head's own userId (for navigation context / intervention flows)
  final String deptHeadUserId;

  /// The current active term UUID
  final String currentTermId;

  const InstructorDetailPage({
    super.key,
    required this.instructor,
    required this.deptHeadUserId,
    required this.currentTermId,
  });

  @override
  State<InstructorDetailPage> createState() => _InstructorDetailPageState();
}

class _InstructorDetailPageState extends State<InstructorDetailPage> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<_TermScore> _history = [];
  List<Subject> _subjects = [];
  Map<String, dynamic>? _termMeta; // semester + academic_year for current term

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final instructorId = widget.instructor['id'] as String;

      // Parallel fetch: historical totals + current subjects + term metadata
      final results = await Future.wait([
        // 1. All historical overall_total_survey rows for this instructor
        _supabase
            .from('overall_total_survey')
            .select('overall_mean, management_mean, performance_mean, term_id, academic_terms(semester, academic_year)')
            .eq('instructor_id', instructorId)
            .order('academic_terms(academic_year)', ascending: true),

        // 2. Subjects for current term
        _supabase
            .from('subjects')
            .select('id, subject_code, subject_name, section, created_at, term_id')
            .eq('instructor_id', instructorId)
            .eq('term_id', widget.currentTermId),

        // 3. Current term metadata
        _supabase
            .from('academic_terms')
            .select('semester, academic_year')
            .eq('id', widget.currentTermId)
            .maybeSingle(),
      ]);

      final historyRows = (results[0] as List? ?? []);
      final subjectRows = (results[1] as List? ?? []);
      final termData = results[2] as Map<String, dynamic>?;

      // Build history list — deduplicate by term, keep first (latest) per term
      final seenTerms = <String>{};
      final history = <_TermScore>[];
      for (final row in historyRows) {
        final termId = row['term_id'] as String? ?? '';
        if (seenTerms.contains(termId)) continue;
        seenTerms.add(termId);

        final termInfo = row['academic_terms'];
        String label = 'Term';
        if (termInfo is Map) {
          final sem = termInfo['semester'] as String? ?? '';
          final yr = termInfo['academic_year'] as String? ?? '';
          // Short label: "1st 25-26" style
          label = '${sem.replaceAll(' Semester', '')} ${yr.replaceAll('20', '')}';
        }
        history.add(_TermScore(
          label: label,
          score: (row['overall_mean'] as num?)?.toDouble() ?? 0.0,
          mgmt: (row['management_mean'] as num?)?.toDouble() ?? 0.0,
          perf: (row['performance_mean'] as num?)?.toDouble() ?? 0.0,
          isCurrent: termId == widget.currentTermId,
        ));
      }

      // If no subjects came from subjects table, try management_results
      List<Subject> subjects = [];
      if (subjectRows.isNotEmpty) {
        subjects = subjectRows.map((row) {
          return Subject.fromJson({
            'id': row['id'],
            'subject_code': row['subject_code'] ?? 'N/A',
            'subject_name': row['subject_name'] ?? 'Unknown Subject',
            'section': row['section'],
            'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
            'management_mean': null,
            'performance_mean': null,
          });
        }).toList();
      } else {
        // Fallback: derive from management_results
        final mgmtRows = await _supabase
            .from('management_results')
            .select('subject_id, overall_management_mean, subjects(id, subject_code, subject_name, section, created_at)')
            .eq('instructor_id', instructorId)
            .eq('term_id', widget.currentTermId);

        for (final row in (mgmtRows as List)) {
          final s = row['subjects'];
          if (s == null) continue;
          subjects.add(Subject.fromJson({
            'id': s['id'],
            'subject_code': s['subject_code'] ?? 'N/A',
            'subject_name': s['subject_name'] ?? 'Subject',
            'section': s['section'],
            'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
            'management_mean': row['overall_management_mean'],
            'performance_mean': null,
          }));
        }
      }

      if (mounted) {
        setState(() {
          _history = history;
          _subjects = subjects;
          _termMeta = termData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('InstructorDetailPage fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── helpers ────────────────────────────────────────────────────────────────

  Color _scoreColor(double score) {
    if (score >= 4.20) return AppColors.success;
    if (score >= 3.40) return AppColors.primary;
    if (score >= 2.60) return AppColors.textPrimary;
    if (score >= 1.80) return AppColors.warning;
    if (score > 0) return AppColors.error;
    return AppColors.textSecondary;
  }

  String _verbalDesc(double score) {
    if (score >= 4.20) return 'Outstanding';
    if (score >= 3.40) return 'Very Satisfactory';
    if (score >= 2.60) return 'Satisfactory';
    if (score >= 1.80) return 'Fair';
    if (score > 0) return 'Unsatisfactory';
    return 'No data';
  }

  // ─── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final instructor = widget.instructor;
    final score = (instructor['score'] as num?)?.toDouble() ?? 0.0;
    final name = instructor['name'] as String? ?? 'Instructor';
    final title = instructor['title'] as String? ?? 'Faculty';
    final dept = instructor['department'] as String? ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.textPrimary,
            iconTheme: const IconThemeData(color: AppColors.surface),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.heroGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                  Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                  if (dept.isNotEmpty)
                                    Text(dept, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                            // Score badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _scoreColor(score).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _scoreColor(score).withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    score > 0 ? score.toStringAsFixed(2) : '—',
                                    style: TextStyle(color: _scoreColor(score), fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  Text(_verbalDesc(score), style: TextStyle(color: _scoreColor(score), fontSize: 9)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Content ──
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              : SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Score breakdown row
                      _buildScoreRow(instructor),
                      const SizedBox(height: 28),

                      // Official Report Button
                      _buildReportButton(instructor),
                      const SizedBox(height: 28),

                      // Historical Trend
                      _buildTrendSection(),
                      const SizedBox(height: 28),

                      // Subjects
                      _buildSubjectsSection(instructor),
                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
        ],
      ),
    );
  }

  // ─── Score breakdown ─────────────────────────────────────────────────────────

  Widget _buildScoreRow(Map<String, dynamic> instructor) {
    final mgmt = (instructor['mgmt_score'] as num?)?.toDouble() ?? 0.0;
    final perf = (instructor['perf_score'] as num?)?.toDouble() ?? 0.0;
    final evals = instructor['evals'] as int? ?? 0;
    return Row(
      children: [
        _scoreChip('Management', mgmt),
        const SizedBox(width: 12),
        _scoreChip('Performance', perf),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.04), blurRadius: 8)],
            ),
            child: Column(
              children: [
                Text('$evals', style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Evaluations', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreChip(String label, double score) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(
          children: [
            Text(
              score > 0 ? score.toStringAsFixed(2) : '—',
              style: TextStyle(color: _scoreColor(score), fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ─── Official Report Button ───────────────────────────────────────────────────

  Widget _buildReportButton(Map<String, dynamic> instructor) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailedReportScreen(
                userId: instructor['id'],
                instructorName: instructor['name'],
                department: instructor['department'] ?? '',
                termId: widget.currentTermId,
                term: _termMeta?['semester'] ?? 'N/A',
                academicYear: _termMeta?['academic_year'] ?? 'N/A',
                managementScore: (instructor['mgmt_score'] as num?)?.toDouble() ?? 0.0,
                performanceScore: (instructor['perf_score'] as num?)?.toDouble() ?? 0.0,
                overallScore: (instructor['score'] as num?)?.toDouble() ?? 0.0,
                totalEvaluations: instructor['evals'] as int? ?? 0,
              ),
            ),
          );
        },
        icon: const Icon(Icons.description_rounded, color: Colors.white),
        label: const Text('View Official SAST Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ─── Trend graph ─────────────────────────────────────────────────────────────

  Widget _buildTrendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.trending_up, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Performance Trend', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Historical score across all evaluation terms', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        if (_history.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text('No historical data available.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _history.map((ts) {
                      final barH = (ts.score / 5.0) * 120.0;
                      final color = ts.isCurrent ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.4);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                ts.score > 0 ? ts.score.toStringAsFixed(2) : '—',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ts.isCurrent ? AppColors.primary : AppColors.textSecondary),
                              ),
                              const SizedBox(height: 4),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOut,
                                height: ts.score > 0 ? barH.clamp(8.0, 120.0) : 4.0,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _history.map((ts) {
                    return Expanded(
                      child: Text(
                        ts.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: ts.isCurrent ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: ts.isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Subjects list ────────────────────────────────────────────────────────────

  Widget _buildSubjectsSection(Map<String, dynamic> instructor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.library_books_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Subjects This Term', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('${_subjects.length}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_subjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: const Center(
              child: Text('No subjects found for this term.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else
          ...(_subjects.map((subject) => _buildSubjectTile(subject, instructor))),
      ],
    );
  }

  Widget _buildSubjectTile(Subject subject, Map<String, dynamic> instructor) {
    final hasScore = subject.managementMean != null || subject.performanceMean != null;
    final score = hasScore ? subject.overallMean : 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubjectDetailScreen(
              subject: subject,
              userId: instructor['id'] as String,
              termId: widget.currentTermId,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.book_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.code,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    subject.name,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subject.section != null && subject.section!.isNotEmpty)
                    Text('Section ${subject.section}', style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (hasScore)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(score.toStringAsFixed(2), style: TextStyle(color: _scoreColor(score), fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subject.verbalDescription, style: TextStyle(color: _scoreColor(score), fontSize: 10)),
                ],
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Simple data class for one term's score in the trend chart.
class _TermScore {
  final String label;
  final double score;
  final double mgmt;
  final double perf;
  final bool isCurrent;

  const _TermScore({
    required this.label,
    required this.score,
    required this.mgmt,
    required this.perf,
    required this.isCurrent,
  });
}
