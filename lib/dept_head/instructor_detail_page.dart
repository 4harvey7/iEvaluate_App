// lib/dept_head/instructor_detail_page.dart
// Full profile page for one instructor — opened from the faculty roster.
// Shows score breakdown, trend chart, subject list, and the official report button.
// Lots of data here, fetch is done in parallel so it not too slow. pray lang.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../instructor/detailed_report_screen.dart';
import '../instructor/subject_detail_screen.dart';
import '../instructor/models/subject.dart';

/// Full-page view of an individual instructor, opened from the Faculty Roster.
/// Shows: current-term score card, historical trend bar chart,
/// subjects list (tappable -> SubjectDetailScreen), and Official Report button.
/// Dean can see everything about this person from here. importente page.
class InstructorDetailPage extends StatefulWidget {
  /// The instructor map built by FacultyRosterScreen (id, name, title, etc.)
  final Map<String, dynamic> instructor;

  /// The dept head's own userId (for navigation context / intervention flows)
  final String deptHeadUserId;

  /// The current active term UUID — needed to filter subjects and scores correctly
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

  bool _isLoading = true; // Show spinner until data is ready
  List<_TermScore> _history = []; // One entry per term — used for the bar chart
  List<Subject> _subjects = []; // Subjects this instructor teaches this term
  Map<String, dynamic>? _termMeta; // semester + academic_year for current term — for the report

  // Kick off data fetch on page load
  @override
  void initState() {
    super.initState();
    _fetchData(); // Get all the data we need in parallel
  }

  // Fetches: historical scores, current subjects, and term metadata.
  // All three requests run in parallel with Future.wait — faster than doing them one by one.
  // dili ta wait one by one, that is slow and inefficient.
  Future<void> _fetchData() async {
    try {
      final instructorId = widget.instructor['id'] as String;

      // Parallel fetch: historical totals + current subjects + term metadata
      // Future.wait runs all three at the same time — much faster than sequential awaits
      final results = await Future.wait([
        // 1. All historical overall_total_survey rows for this instructor
        // Ordered by year so we get chronological chart data
        _supabase
            .from('overall_total_survey')
            .select('overall_mean, management_mean, performance_mean, term_id, academic_terms(semester, academic_year)')
            .eq('instructor_id', instructorId)
            .order('academic_terms(academic_year)', ascending: true),

        // 2. Subjects for current term via junction table
        // Only subjects they teach THIS term — not all subjects ever
        _supabase
            .from('instructor_subjects')
            .select('subject_id, subjects(id, subject_code, subject_name, created_at)')
            .eq('instructor_id', instructorId)
            .eq('term_id', widget.currentTermId),

        // 3. Current term metadata — we need semester name and year for the report button
        _supabase
            .from('academic_terms')
            .select('semester, academic_year')
            .eq('id', widget.currentTermId)
            .maybeSingle(),
      ]);

      // Extract results — each item in results[] matches Future.wait order above
      final historyRows = (results[0] as List? ?? []);
      final subjectRows = (results[1] as List? ?? []);
      final termData = results[2] as Map<String, dynamic>?;

      // Build history list — deduplicate by term, keep first (latest) per term
      // Same instructor might have multiple rows per term if data is duplicated — filter that
      final seenTerms = <String>{};
      final history = <_TermScore>[];
      for (final row in historyRows) {
        final termId = row['term_id'] as String? ?? '';
        if (seenTerms.contains(termId)) continue; // Already processed this term, skip
        seenTerms.add(termId);

        final termInfo = row['academic_terms'];
        String label = 'Term'; // Default label if no term info found
        if (termInfo is Map) {
          final sem = termInfo['semester'] as String? ?? '';
          final yr = termInfo['academic_year'] as String? ?? '';
          // Short label: "1st 25-26" style — fits nicely under the bar chart
          label = '${sem.replaceAll(' Semester', '')} ${yr.replaceAll('20', '')}';
        }
        // Add to chart data — includes label, overall score, mgmt, perf, and current flag
        history.add(_TermScore(
          label: label,
          score: (row['overall_mean'] as num?)?.toDouble() ?? 0.0,
          mgmt: (row['management_mean'] as num?)?.toDouble() ?? 0.0,
          perf: (row['performance_mean'] as num?)?.toDouble() ?? 0.0,
          isCurrent: termId == widget.currentTermId, // Highlight current term bar in the chart
        ));
      }

      // If no subjects came from subjects table, try management_results as fallback
      // basin naa data there even if instructor_subjects is empty — we try our best
      List<Subject> subjects = [];
      if (subjectRows.isNotEmpty) {
        // Primary path: subjects came from instructor_subjects join
        subjects = subjectRows.map((row) {
          final s = row['subjects'];
          // Handle subjects field being either Map or List — Supabase is unpredictable sometimes
          final subjectData = s is Map ? s : (s is List && (s as List).isNotEmpty ? s[0] : null);
          return Subject.fromJson({
            'id': subjectData?['id'] ?? row['subject_id'],
            'subject_code': subjectData?['subject_code'] ?? 'N/A',
            'subject_name': subjectData?['subject_name'] ?? 'Unknown Subject',
            'created_at': subjectData?['created_at'] ?? DateTime.now().toIso8601String(),
            // Scores not included here — they come from management_results separately
            'management_mean': null,
            'performance_mean': null,
          });
        }).toList();
      } else {
        // Fallback: derive from management_results — when instructor_subjects has nothing
        final mgmtRows = await _supabase
            .from('management_results')
            .select('subject_id, overall_management_mean, subjects(id, subject_code, subject_name, created_at)')
            .eq('instructor_id', instructorId)
            .eq('term_id', widget.currentTermId);

        // Map the management_results rows into Subject objects
        for (final row in (mgmtRows as List)) {
          final s = row['subjects'];
          if (s == null) continue; // Skip if no subject data joined — dili ta add nulls
          subjects.add(Subject.fromJson({
            'id': s['id'],
            'subject_code': s['subject_code'] ?? 'N/A',
            'subject_name': s['subject_name'] ?? 'Subject',
            'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
            'management_mean': row['overall_management_mean'], // At least we have management score
            'performance_mean': null, // Performance not in this table — wala choice
          }));
        }
      }

      // All data ready — update state and re-render the page
      if (mounted) {
        setState(() {
          _history = history;
          _subjects = subjects;
          _termMeta = termData; // Store term info for the report button
          _isLoading = false; // Loading done — show the content now
        });
      }
    } catch (e) {
      debugPrint('InstructorDetailPage fetch error: $e');
      if (mounted) setState(() => _isLoading = false); // Stop spinner even on error
    }
  }

  // ─── helpers ────────────────────────────────────────────────────────────────

  // Returns a color based on the score value — like a traffic light for performance
  // Green = great, blue = good, dark = okay, orange = meh, red = bad
  Color _scoreColor(double score) {
    if (score >= 4.20) return AppColors.success; // Outstanding — green light
    if (score >= 3.40) return AppColors.primary; // Very Satisfactory — blue
    if (score >= 2.60) return AppColors.textPrimary; // Satisfactory — neutral dark
    if (score >= 1.80) return AppColors.warning; // Fair — orange, watch out
    if (score > 0) return AppColors.error; // Unsatisfactory — red, dean needs to act
    return AppColors.textSecondary; // No data — gray, literally wala pa
  }

  // Returns a verbal description of the score — what does the number actually mean
  // Used in the score badge and subject tiles so it readable not just a number
  String _verbalDesc(double score) {
    if (score >= 4.20) return 'Outstanding'; // The best — rare but beautiful
    if (score >= 3.40) return 'Very Satisfactory'; // Good — dean can relax
    if (score >= 2.60) return 'Satisfactory'; // Okay — nothing alarming
    if (score >= 1.80) return 'Fair'; // Borderline — monitor closely
    if (score > 0) return 'Unsatisfactory'; // Below acceptable — intervention time
    return 'No data'; // No evaluations yet — cannot judge fairly
  }

  // ─── build ───────────────────────────────────────────────────────────────────

  // The main screen — uses CustomScrollView with SliverAppBar for the expandable header
  // When user scrolls up, the header collapses to a small app bar. fancy but useful.
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
          // ── App Bar ── Expandable hero header with gradient background
          SliverAppBar(
            expandedHeight: 200, // Full height when scrolled to top
            pinned: true, // Stays visible as a small bar when scrolled down
            backgroundColor: AppColors.textPrimary,
            iconTheme: const IconThemeData(color: AppColors.surface),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.heroGradient, // Nice gradient — looks professional
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
                            // Avatar with first letter of instructor's name
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
                                  // Full name — bold and white on the dark gradient
                                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                  Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  // Show department name if it exists
                                  if (dept.isNotEmpty)
                                    Text(dept, style: const TextStyle(color: Colors.white54, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            // Score badge — colored box with current score and verbal desc
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _scoreColor(score).withValues(alpha: 0.15), // Tinted background
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _scoreColor(score).withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    score > 0 ? score.toStringAsFixed(2) : '—', // Show dash if no score
                                    style: TextStyle(color: _scoreColor(score), fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  // Verbal desc below the number — e.g. "Outstanding"
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

          // ── Content ── The actual scrollable content below the header
          _isLoading
              // Show spinner while data loads — dili ta show broken layout
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              : SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Score breakdown row — management, performance, and eval count
                      _buildScoreRow(instructor),
                      const SizedBox(height: 28),

                      // Official Report Button — goes to the full SAST report page
                      _buildReportButton(instructor),
                      const SizedBox(height: 28),

                      // Historical Trend — bar chart showing scores across all terms
                      _buildTrendSection(),
                      const SizedBox(height: 28),

                      // Subjects — list of subjects this instructor teaches this term
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

  // Row of three chips: Management score, Performance score, and Evaluation count
  // Side by side — compact and readable at a glance
  Widget _buildScoreRow(Map<String, dynamic> instructor) {
    final mgmt = (instructor['mgmt_score'] as num?)?.toDouble() ?? 0.0;
    final perf = (instructor['perf_score'] as num?)?.toDouble() ?? 0.0;
    final evals = instructor['evals'] as int? ?? 0;
    return Row(
      children: [
        _scoreChip('Management', mgmt), // How well they manage the class
        const SizedBox(width: 12),
        _scoreChip('Performance', perf), // How well they perform their duties
        const SizedBox(width: 12),
        // Eval count chip — shows how many students actually rated them
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

  // A single score chip — colored number on top, label below
  // Color adapts based on the score value — red if bad, green if good
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
              score > 0 ? score.toStringAsFixed(2) : '—', // Show dash if score is zero (no data)
              style: TextStyle(color: _scoreColor(score), fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ─── Official Report Button ───────────────────────────────────────────────────

  // The "View Official SAST Report" button — opens the detailed report screen
  // Passes all the scores and metadata needed for the report. importente all params are set.
  Widget _buildReportButton(Map<String, dynamic> instructor) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          // Navigate to DetailedReportScreen — pass all required data
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailedReportScreen(
                userId: instructor['id'],
                instructorName: instructor['name'],
                department: instructor['department'] ?? '',
                termId: widget.currentTermId,
                term: _termMeta?['semester'] ?? 'N/A', // Semester name for the report header
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

  // The performance trend section — shows a simple bar chart across all terms
  // Current term bar is colored primary blue, older terms are gray. Easy to read.
  Widget _buildTrendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with icon
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
        // If no history, show a placeholder box — dili ta crash with empty list
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
                // The bar chart itself — 140px tall, bars aligned to bottom
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _history.map((ts) {
                      // Bar height is proportional to score out of 5.0
                      final barH = (ts.score / 5.0) * 120.0;
                      // Current term = blue, older terms = faded gray
                      final color = ts.isCurrent ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.4);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Score label on top of each bar — small text
                              Text(
                                ts.score > 0 ? ts.score.toStringAsFixed(2) : '—',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ts.isCurrent ? AppColors.primary : AppColors.textSecondary),
                              ),
                              const SizedBox(height: 4),
                              // The actual bar — animated height when it first appears
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 600), // Smooth animation
                                curve: Curves.easeOut,
                                height: ts.score > 0 ? barH.clamp(8.0, 120.0) : 4.0, // Min 8px so bar is visible even for low scores
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
                // Term labels below each bar — short format like "1st 25-26"
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
                          fontWeight: ts.isCurrent ? FontWeight.bold : FontWeight.normal, // Bold for current term label
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

  // Shows all subjects the instructor teaches this term — each one tappable
  // Tap goes to SubjectDetailScreen for deeper analysis. importente this works.
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
            // Subject count badge — so dean can see at a glance how many subjects
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('${_subjects.length}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // No subjects found — show a placeholder card
        if (_subjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: const Center(
              child: Text('No subjects found for this term.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else
          // Show each subject as a tappable tile — using spread operator to flatten the list
          ...(_subjects.map((subject) => _buildSubjectTile(subject, instructor))),
      ],
    );
  }

  // A single tappable subject tile — shows subject code, name, and score if available
  // Tapping opens SubjectDetailScreen for full breakdown. always navigate, dili ta dead-end.
  Widget _buildSubjectTile(Subject subject, Map<String, dynamic> instructor) {
    // Check if we have a score for this subject — basin wala pa evaluation for it
    final hasScore = subject.managementMean != null || subject.performanceMean != null;
    final score = hasScore ? subject.overallMean : 0.0;

    return GestureDetector(
      onTap: () {
        // Navigate to subject detail — pass the subject, instructor ID, and term
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
            // Book icon container — gives the tile some visual character
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
            // Subject code and name — the identifying info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.code, // e.g. "CS101"
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subject.name, // Full subject name — can be long, so ellipsis
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Score and verbal desc — only shown if we have evaluation data for this subject
            if (hasScore)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(score.toStringAsFixed(2), style: TextStyle(color: _scoreColor(score), fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subject.verbalDescription, style: TextStyle(color: _scoreColor(score), fontSize: 10)), // e.g. "Very Satisfactory"
                ],
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20), // Tap hint arrow
          ],
        ),
      ),
    );
  }
}

/// Simple data class for one term's score in the trend chart.
/// Holds the term label (short), overall score, mgmt + perf, and whether it's the current term.
/// dili pwede just use a Map — this is cleaner and type-safe.
class _TermScore {
  final String label; // Short label shown under the bar chart — e.g. "1st 25-26"
  final double score; // Overall score for this term
  final double mgmt; // Management score — separate tracking
  final double perf; // Performance score — separate tracking
  final bool isCurrent; // If true, this term's bar is highlighted in primary color

  const _TermScore({
    required this.label,
    required this.score,
    required this.mgmt,
    required this.perf,
    required this.isCurrent,
  });
}
