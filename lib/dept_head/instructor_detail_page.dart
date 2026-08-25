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
  
  // Real sentiment data instead of hardcoded
  Map<String, dynamic> _sentimentSummary = {'positive': 0, 'neutral': 0, 'negative': 0, 'total': 0};
  List<String> _sentimentTags = [];

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

      // Parallel fetch: historical totals + current subjects + term metadata + sentiment
      // Future.wait runs all four at the same time — much faster than sequential awaits
      final results = await Future.wait([
        // 1. All historical overall_total_survey rows for this instructor
        // Ordered by year so we get chronological chart data
        _supabase
            .from('overall_total_survey')
            .select('overall_mean, combined_score_mean, management_mean, performance_mean, term_id, academic_terms(semester, academic_year)')
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
            
        // 4. Student remarks for sentiment percentages
        _supabase
            .from('student_remarks')
            .select('tone')
            .eq('instructor_id', instructorId)
            .eq('term_id', widget.currentTermId),
            
        // 5. AI Wordcloud for the tags
        _supabase
            .from('instructor_wordcloud')
            .select('word')
            .eq('instructor_id', instructorId)
            .eq('term_id', widget.currentTermId)
            .order('count', ascending: false)
            .limit(3),
      ]);

      // Extract results — each item in results[] matches Future.wait order above
      final historyRows = (results[0] as List? ?? []);
      final subjectRows = (results[1] as List? ?? []);
      final termData = results[2] as Map<String, dynamic>?;
      final remarksData = (results[3] as List? ?? []);
      final wordcloudData = (results[4] as List? ?? []);

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
          // Compact label: "1st\n25-26" — two lines fit nicely under each bar
          final ordinal = sem.split(' ').isNotEmpty ? sem.split(' ').first : sem;
          final ayParts = yr.split('-');
          final yearShort = ayParts.length == 2
              ? '${ayParts[0].length >= 2 ? ayParts[0].substring(ayParts[0].length - 2) : ayParts[0]}-'
                '${ayParts[1].length >= 2 ? ayParts[1].substring(ayParts[1].length - 2) : ayParts[1]}'
              : yr;
          label = '$ordinal\n$yearShort';
        }
        // Add to chart data — includes label, overall score, mgmt, perf, and current flag
        history.add(_TermScore(
          label: label,
          score: (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0,
          mgmt: (row['management_mean'] as num?)?.toDouble() ?? 0.0,
          perf: (row['performance_mean'] as num?)?.toDouble() ?? 0.0,
          isCurrent: termId == widget.currentTermId, // Highlight current term bar in the chart
          termInfo: row['academic_terms'] as Map?, // store for sorting
        ));
      }

      // Sort semantically: oldest year first, then 1st → 2nd → Summer within year
      // DB orders only by academic_year which doesn't handle 1st vs 2nd within same year
      const semOrder = {'1st': 0, '2nd': 1, 'Summer': 2};
      history.sort((a, b) {
        final aYear = int.tryParse(a.termInfo?['academic_year']?.toString().split('-').first ?? '0') ?? 0;
        final bYear = int.tryParse(b.termInfo?['academic_year']?.toString().split('-').first ?? '0') ?? 0;
        if (aYear != bYear) return aYear.compareTo(bYear);
        final aSem = a.termInfo?['semester']?.toString() ?? '';
        final bSem = b.termInfo?['semester']?.toString() ?? '';
        final aSemKey = semOrder.keys.firstWhere((k) => aSem.startsWith(k), orElse: () => '');
        final bSemKey = semOrder.keys.firstWhere((k) => bSem.startsWith(k), orElse: () => '');
        return (semOrder[aSemKey] ?? 99).compareTo(semOrder[bSemKey] ?? 99);
      });

      // If no subjects came from subjects table, try management_results as fallback
      // basin naa data there even if instructor_subjects is empty — we try our best
      List<Subject> subjects = [];
      if (subjectRows.isNotEmpty) {
        // Primary path: subjects came from instructor_subjects join
        subjects = subjectRows.map((row) {
          final s = row['subjects'];
          // Handle subjects field being either Map or List — Supabase is unpredictable sometimes
          final subjectData = s is Map ? s : (s is List && s.isNotEmpty ? s[0] : null);
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

      // Process Sentiment
      int pos = 0;
      int neu = 0;
      int neg = 0;
      for (final r in remarksData) {
        final tone = r['tone'] ?? 'Neutral';
        if (tone == 'Positive') pos++;
        else if (tone == 'Critical') neg++;
        else neu++;
      }
      final totalRemarks = pos + neu + neg;
      int posPct = totalRemarks > 0 ? ((pos / totalRemarks) * 100).round() : 0;
      int neuPct = totalRemarks > 0 ? ((neu / totalRemarks) * 100).round() : 0;
      int negPct = totalRemarks > 0 ? ((neg / totalRemarks) * 100).round() : 0;
      
      // Ensure it adds up exactly to 100 if there's data
      if (totalRemarks > 0) {
        final totalPct = posPct + neuPct + negPct;
        if (totalPct > 0 && totalPct != 100) {
          // Adjust the largest one to make it exactly 100
          if (posPct >= neuPct && posPct >= negPct) {
            posPct += (100 - totalPct);
          } else if (neuPct >= posPct && neuPct >= negPct) {
            neuPct += (100 - totalPct);
          } else {
            negPct += (100 - totalPct);
          }
        }
      }

      final sentimentSummary = {
        'positive': posPct,
        'neutral': neuPct,
        'negative': negPct,
        'total': totalRemarks,
      };

      // Process Tags
      final tags = wordcloudData.map((w) {
        String word = w['word'].toString();
        // Capitalize first letter of each word
        return word.split(' ').map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '').join(' ');
      }).toList();

      // All data ready — update state and re-render the page
      if (mounted) {
        setState(() {
          _history = history;
          _subjects = subjects;
          _termMeta = termData; // Store term info for the report button
          _sentimentSummary = sentimentSummary;
          _sentimentTags = tags;
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
    if (score >= 3.40) return AppColors.primaryText; // Very Satisfactory — blue
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
            elevation: 0,
            backgroundColor: AppColors.textPrimary,
            iconTheme: const IconThemeData(color: AppColors.surface),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E1608), AppColors.textPrimary], // Espresso hero — matches login
                  ),
                ),
                child: Stack(
                  children: [
                    // Soft orange glow, upper right — login's Positioned glow pattern
                    Positioned(
                      top: -70,
                      right: -50,
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.35),
                              AppColors.primary.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
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
                                  // Full name — heavy vanilla display type on the dark gradient
                                  Text(name, style: const TextStyle(color: AppColors.textInverted, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                                  Text(title, style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  // Show department name if it exists
                                  if (dept.isNotEmpty)
                                    Text(dept, style: const TextStyle(color: AppColors.textInvertedFaint, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            // Score badge — colored box with current score and verbal desc
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _scoreColor(score).withValues(alpha: 0.18), // Tinted pill — no hairline border
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    score > 0 ? score.toStringAsFixed(2) : '—', // Show dash if no score
                                    style: TextStyle(color: _scoreColor(score), fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  // Verbal desc below the number — e.g. "Outstanding"
                                  Text(_verbalDesc(score), style: TextStyle(color: _scoreColor(score), fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                  ],
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
                      _buildDeactivateButton(instructor),
                      const SizedBox(height: 24),
                      _buildSentimentAnalysis(), // NEW: Sentiment analysis widget
                      const SizedBox(height: 24),
                      _buildTrendSection(),
                      const SizedBox(height: 32),

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
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
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
    return Container(
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDeep]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
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
        icon: const Icon(Icons.description_rounded, color: AppColors.textPrimary),
        label: const Text('View Official SAST Report', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // Action button to permanently deactivate a fired instructor
  Widget _buildDeactivateButton(Map<String, dynamic> instructor) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.error, Color(0xFF9A3412)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: AppColors.error.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () async {
            // Confirm first
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Deactivate Account?'),
                content: Text('Are you sure you want to deactivate ${instructor['name']}? They will be permanently locked out of the system.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Deactivate', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );

            if (confirm == true) {
              try {
                // Deactivate in user_info
                await Supabase.instance.client
                    .from('user_info')
                    .update({'account_status': 'disabled'})
                    .eq('id', instructor['id'])
                    .select()
                    .single(); // enforce RLS fail
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deactivated successfully.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.success));
                  Navigator.pop(context); // Go back to roster
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e'), backgroundColor: AppColors.error));
              }
            }
          },
          icon: const Icon(Icons.person_off_rounded),
          label: const Text('Deactivate Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ),
    );
  }

  // ─── Sentiment Analysis UI (Added from Mockup) ──────────────────────────────
  Widget _buildSentimentAnalysis() {
    // If no remarks exist, we can show a placeholder or hide it. 
    // Let's show a placeholder state so it still looks good.
    final hasData = _sentimentSummary['total'] > 0;
    
    final int posPct = hasData ? _sentimentSummary['positive'] : 0;
    final int neuPct = hasData ? _sentimentSummary['neutral'] : 100; // default to 100% neutral if no data
    final int negPct = hasData ? _sentimentSummary['negative'] : 0;
    
    final tags = _sentimentTags.isNotEmpty ? _sentimentTags : ['No Data Yet'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'SENTIMENT ANALYSIS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface, // Clean white card — soft shadow, no border
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Comment Polarity Distribution',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              // Stacked Bar Chart
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    if (posPct > 0)
                      Expanded(
                        flex: posPct,
                        child: Container(height: 10, color: AppColors.success), // Green
                      ),
                    if (neuPct > 0)
                      Expanded(
                        flex: neuPct,
                        child: Container(height: 10, color: AppColors.warning), // Gold/Orange
                      ),
                    if (negPct > 0)
                      Expanded(
                        flex: negPct,
                        child: Container(height: 10, color: AppColors.error), // Red/Deep Orange
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSentimentLegendItem('Positive', '${hasData ? posPct : 0}%', AppColors.success),
                  _buildSentimentLegendItem('Neutral', '${hasData ? neuPct : 0}%', AppColors.warning),
                  _buildSentimentLegendItem('Negative', '${hasData ? negPct : 0}%', AppColors.error),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: AppColors.borderHairline, height: 1),
              ),
              const Text(
                'Key Sentiment Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags.map((t) => _buildSentimentTag(t)).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSentimentLegendItem(String label, String percent, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        Text(
          percent,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSentimentTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryTint, // Tonal pill fill — no border
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primaryText, // Accessible orange on the tint
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
        // Section header — small caps overline
        const Text('PERFORMANCE TREND', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        const Text('Historical score across all evaluation terms', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        // If no history, show a placeholder box — dili ta crash with empty list
        if (_history.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: const Center(
              child: Text('No historical data available.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
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
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ts.isCurrent ? AppColors.primaryText : AppColors.textSecondary),
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
                          fontSize: 11,
                          color: ts.isCurrent ? AppColors.primaryText : AppColors.textSecondary,
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
            const Text('SUBJECTS THIS TERM', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const Spacer(),
            // Subject count badge — tonal pill, so dean can see at a glance how many subjects
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(20)),
              child: Text('${_subjects.length}', style: const TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // No subjects found — show a placeholder card
        if (_subjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
            ),
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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            // Book icon container — primary-tint square, gives the tile some visual character
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.book_rounded, color: AppColors.primaryText, size: 22),
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
                  Text(subject.verbalDescription, style: TextStyle(color: _scoreColor(score), fontSize: 11)), // e.g. "Very Satisfactory"
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
  final String label;    // Short label shown under the bar chart — e.g. "1st\n25-26"
  final double score;    // Overall score for this term
  final double mgmt;     // Management score — separate tracking
  final double perf;     // Performance score — separate tracking
  final bool isCurrent;  // If true, this term's bar is highlighted in primary color
  final Map? termInfo;   // Raw academic_terms map — used only for sorting, not displayed

  const _TermScore({
    required this.label,
    required this.score,
    required this.mgmt,
    required this.perf,
    required this.isCurrent,
    this.termInfo,
  });
}
