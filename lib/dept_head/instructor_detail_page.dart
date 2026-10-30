// lib/dept_head/instructor_detail_page.dart
// Full profile page for one instructor — opened from the faculty roster.
// Shows score breakdown, trend chart, subject list, and the official report button.
// Lots of data here, fetch is done in parallel so it not too slow. pray lang.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/identity_validator.dart';
import '../theme/app_colors.dart';
import '../instructor/detailed_report_screen.dart';
import '../instructor/models/subject.dart';
import '../widgets/apple_ui.dart';
import '../core/utils/sast_rating.dart';
import '../core/services/eval_results_service.dart';
import '../widgets/eval_report_widgets.dart';

/// Full-page view of an individual instructor, opened from the Faculty Roster.
/// Shows: current-term score card, historical trend bar chart,
/// subjects list (read-only), and Official Report button.
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
  EvalReport? _evalReport; // New 15-item report for the current term (null = old-form term)
  Map<String, dynamic>? _termMeta; // semester + academic_year for current term — for the report
  
  // Real sentiment data instead of hardcoded
  Map<String, dynamic> _sentimentSummary = {'positive': 0, 'neutral': 0, 'negative': 0, 'total': 0};
  List<String> _sentimentTags = [];

  // Re-entry guard for Deactivate. The button stays tappable while the edge
  // function runs, and a second confirm that also succeeded would pop twice --
  // taking the roster route down with this page.
  bool _isDeactivating = false;

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

      // Subjects shown here are every class this instructor teaches this term,
      // whatever program owns the subject. A department head sees subjects by
      // the department of the INSTRUCTOR teaching them, not the subject's
      // owning program (subjects.department_id), so an instructor listed on
      // this page is this head's own and all their classes belong here --
      // e.g. a BIT instructor teaching the BSIT-owned ASP 101 shows it to the
      // BIT head only. The head's department is still resolved so a head with
      // no department fails closed to an empty list.
      final headDeptRow = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', widget.deptHeadUserId)
          .maybeSingle();
      final headDeptId = headDeptRow?['Department_name_ID'];
      if (headDeptId == null) {
        // Fail closed. A head whose own department cannot be resolved gets an
        // empty subject list rather than every subject the instructor teaches.
        debugPrint(
            '[InstructorDetail] No department for head ${widget.deptHeadUserId}; '
            'subject list suppressed.');
      }

      // Parallel fetch: historical totals + current subjects + term metadata + sentiment
      // Future.wait runs all four at the same time — much faster than sequential awaits
      // Explicit <dynamic>: the subject entry is either a query builder or a
      // plain Future when the department could not be resolved, and inference
      // cannot find a common type across the two.
      final results = await Future.wait<dynamic>([
        // 1. All historical overall_total_survey rows for this instructor
        // Ordered by year so we get chronological chart data
        _supabase
            .from('overall_total_survey')
            .select('overall_mean, combined_score_mean, management_mean, performance_mean, term_id, created_at, academic_terms(semester, academic_year)')
            .eq('instructor_id', instructorId)
            .order('academic_terms(academic_year)', ascending: true)
            // Newest first WITHIN a year, so the dedup below -- which keeps the
            // first row it sees per term -- keeps the latest one. Ordering by
            // year alone cannot separate two rows sharing a term, which is
            // exactly the duplicate case that dedup exists for.
            .order('created_at', ascending: false),

        // 2. Subjects for current term via junction table
        // Only subjects they teach THIS term — not all subjects ever.
        // !inner makes the embed a real join so an orphan row is dropped; a
        // plain embed would return a null subject that the mapper below
        // would render as "Unknown Subject".
        if (headDeptId == null)
          Future.value(const <Map<String, dynamic>>[])
        else
          _supabase
              .from('instructor_subjects')
              .select(
                  'subject_id, subjects!inner(id, subject_code, subject_name, created_at, department_id)')
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

      // Build history list — deduplicate by term, keeping the newest row per
      // term (the query orders created_at descending within each year).
      // overall_total_survey is unique on (instructor_id, term_id), so this
      // should never fire; it stays for rows predating that constraint.
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
          // Stored values; null = no answers that term (drawn as an empty stub).
          // Trend is on the percent scale: old means convert as mean / 5 * 100.
          score: SastRating.meanToPct(SastRating.parse(row['combined_score_mean']) ?? SastRating.parse(row['overall_mean'])),
          mgmt: SastRating.parse(row['management_mean']),
          perf: SastRating.parse(row['performance_mean']),
          isCurrent: termId == widget.currentTermId, // Highlight current term bar in the chart
          termInfo: row['academic_terms'] as Map?, // store for sorting
          termId: termId,
        ));
      }

      // New-form terms (eval_results): pooled SET % joins the same trend.
      final newPcts = await EvalResultsService.termPcts(instructorId);
      final extraIds = newPcts.keys.where((id) => !seenTerms.contains(id)).toList();
      final extraMeta = <String, Map>{};
      if (extraIds.isNotEmpty) {
        final rows = await _supabase.from('academic_terms').select('id, semester, academic_year').filter('id', 'in', extraIds);
        for (final r in rows as List) {
          extraMeta[r['id'].toString()] = r;
        }
      }
      for (final e in newPcts.entries) {
        final existing = history.indexWhere((h) => h.termId == e.key);
        if (existing >= 0) {
          history[existing] = history[existing].withScore(e.value);
          continue;
        }
        final m = extraMeta[e.key];
        final sem = m?['semester']?.toString() ?? '';
        final yr = m?['academic_year']?.toString() ?? '';
        final ayParts = yr.split('-');
        final yearShort = ayParts.length == 2
            ? '${ayParts[0].length >= 2 ? ayParts[0].substring(ayParts[0].length - 2) : ayParts[0]}-'
              '${ayParts[1].length >= 2 ? ayParts[1].substring(ayParts[1].length - 2) : ayParts[1]}'
            : yr;
        history.add(_TermScore(
          label: '${sem.split(' ').first}\n$yearShort',
          score: e.value,
          mgmt: null,
          perf: null,
          isCurrent: e.key == widget.currentTermId,
          termInfo: m,
          termId: e.key,
        ));
      }
      final evalReport = await EvalResultsService.load(instructorId: instructorId, termId: widget.currentTermId);

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
      } else if (headDeptId != null) {
        // Fallback: derive from management_results — when instructor_subjects has nothing
        // Same rule as the primary path: the instructor's own classes.
        final mgmtRows = await _supabase
            .from('management_results')
            .select(
                'subject_id, overall_management_mean, subjects!inner(id, subject_code, subject_name, created_at, department_id)')
            .eq('instructor_id', instructorId)
            .eq('term_id', widget.currentTermId);

        // The matching stored performance means, so a tile's overall is
        // (Management + Performance) / 2 and not the management half alone.
        final perfBySubject = <String, double?>{};
        final mgmtSubjectIds = (mgmtRows as List)
            .map((r) => r['subject_id']?.toString())
            .whereType<String>()
            .toList();
        if (mgmtSubjectIds.isNotEmpty) {
          try {
            final perfRows = await _supabase
                .from('performance_results')
                .select('subject_id, overall_performance_mean')
                .eq('instructor_id', instructorId)
                .eq('term_id', widget.currentTermId)
                .filter('subject_id', 'in', mgmtSubjectIds);
            for (final r in (perfRows as List)) {
              final sid = r['subject_id']?.toString();
              if (sid != null) perfBySubject[sid] = SastRating.parse(r['overall_performance_mean']);
            }
          } catch (e) {
            debugPrint('InstructorDetailPage: performance_results lookup failed: $e');
          }
        }

        // Map the management_results rows into Subject objects
        for (final row in mgmtRows) {
          final s = row['subjects'];
          if (s == null) continue; // Skip if no subject data joined — dili ta add nulls
          subjects.add(Subject.fromJson({
            'id': s['id'],
            'subject_code': s['subject_code'] ?? 'N/A',
            'subject_name': s['subject_name'] ?? 'Subject',
            'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
            'management_mean': SastRating.parse(row['overall_management_mean']),
            'performance_mean': perfBySubject[row['subject_id']?.toString()],
          }));
        }
      }

      // Process Sentiment
      int pos = 0;
      int neu = 0;
      int neg = 0;
      for (final r in remarksData) {
        final tone = r['tone'] ?? 'Neutral';
        if (tone == 'Positive') {
          pos++;
        } else if (tone == 'Critical') {
          neg++;
        } else {
          neu++;
        }
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
          _evalReport = (evalReport?.student != null) ? evalReport : null;
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

  // Colour, label and thresholds all come from SastRating so this page, the
  // instructor's own screens and the PDF agree (4.20 / 3.40 / 2.60 / 1.80,
  // compared on the 2-decimal value). Null = no data.
  Color _scoreColor(double? score) => SastRating.color(score);

  // Same bands as _scoreColor, but for the dark hero gradient at the top of
  // this page. _scoreColor's Satisfactory band is textPrimary (near-black) and
  // its Very Satisfactory band is `primary` -- which is heroGradient's own end
  // stop. Both vanish into the header they are painted on.
  Color _scoreColorOnHero(double? score) {
    switch (SastRating.code(score)) {
      case 'O':
        return AppColors.onHeroOutstanding;
      case 'VS':
        return AppColors.onHeroGood;
      case 'S':
        return AppColors.onHeroNeutral;
      case 'F':
        return AppColors.onHeroFair;
      case 'US':
        return AppColors.onHeroPoor;
      default:
        return AppColors.textInvertedDim; // No data
    }
  }

  // Verbal description of the score, e.g. "Very Satisfactory", or "No data".
  String _verbalDesc(double? score) => SastRating.verbal(score);

  // ─── build ───────────────────────────────────────────────────────────────────

  // The main screen — uses CustomScrollView with SliverAppBar for the expandable header
  // When user scrolls up, the header collapses to a small app bar. fancy but useful.
  @override
  Widget build(BuildContext context) {
    final instructor = widget.instructor;
    final double? score = SastRating.parse(instructor['score']);
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
            backgroundColor: AppColors.primaryDeep,
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
                              backgroundColor: AppColors.textInverted.withValues(alpha: 0.22),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppColors.textInverted, fontSize: 24, fontWeight: FontWeight.bold),
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
                                color: _scoreColorOnHero(score).withValues(alpha: 0.22), // Tinted background
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _scoreColorOnHero(score).withValues(alpha: 0.55)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    SastRating.format(score), // Show dash if no score
                                    style: TextStyle(color: _scoreColorOnHero(score), fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  // Verbal desc below the number — e.g. "Outstanding"
                                  Text(_verbalDesc(score), style: TextStyle(color: _scoreColorOnHero(score), fontSize: 9)),
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
                  child: AppleLoadingState(label: 'Loading instructor profile…'),
                )
              : SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Score breakdown row — management, performance, and eval count
                      // (new-form terms show the SET / supervisor report instead)
                      if (_evalReport == null) ...[
                        _buildScoreRow(instructor),
                        const SizedBox(height: 28),
                      ],

                      // Official Report Button — goes to the full SAST report page
                      _buildReportButton(instructor),
                      _buildDeactivateButton(instructor),
                      const SizedBox(height: 24),
                      if (_evalReport != null)
                        EvalReportView(report: _evalReport!)
                      else
                        _buildSentimentAnalysis(), // NEW: Sentiment analysis widget
                      const SizedBox(height: 24),
                      _buildTrendSection(),
                      const SizedBox(height: 32),

                      // Subjects — list of subjects this instructor teaches this term
                      _buildSubjectsSection(),
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
    final mgmt = SastRating.parse(instructor['mgmt_score']);
    final perf = SastRating.parse(instructor['perf_score']);
    final evals = (instructor['evals'] as num?)?.toInt() ?? 0;
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
  Widget _scoreChip(String label, double? score) {
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
              SastRating.format(score), // Show dash if there is no data
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
                universityId: instructor['university_id']?.toString() ?? '',
                department: instructor['department'] ?? '',
                termId: widget.currentTermId,
                term: _termMeta?['semester'] ?? 'N/A', // Semester name for the report header
                academicYear: _termMeta?['academic_year'] ?? 'N/A',
                managementScore: SastRating.parse(instructor['mgmt_score']),
                performanceScore: SastRating.parse(instructor['perf_score']),
                overallScore: SastRating.parse(instructor['score']),
                totalEvaluations: (instructor['evals'] as num?)?.toInt() ?? 0,
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

  // Action button to permanently deactivate a fired instructor.
  //
  // An account that is ALREADY deactivated gets a standing notice instead. It
  // is still reachable from the roster while its results are part of the term's
  // average, so the head can open it -- but offering "Deactivate Account" on a
  // deactivated account invites a second attempt that can only be refused, and
  // reactivation is not this screen's to give.
  Widget _buildDeactivateButton(Map<String, dynamic> instructor) {
    // Absent means active: only the roster sets this key, and every other way
    // in has always shown a live account.
    if (instructor['is_active'] == false) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.person_off_rounded, color: AppColors.error, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This account is deactivated',
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'They can no longer sign in. The evaluations below were '
                      'collected while they were teaching and still count '
                      'toward this term\'s department average. Only the SAO '
                      'office can reactivate the account.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _isDeactivating ? null : () async {
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

            if (confirm == true && mounted && !_isDeactivating) {
              setState(() => _isDeactivating = true);
              try {
                // Deactivation goes through the edge function, NOT straight to
                // user_info (BUG-2026-TC-D08).
                //
                // The direct write that used to be here could never succeed.
                // user_info carries exactly one UPDATE policy -- "Users can
                // update own profile", auth.uid() = id -- so a head writing to
                // an instructor's row matched zero rows. Postgres does not
                // raise on an RLS-filtered UPDATE, so the .single() that
                // followed did it instead, as PGRST116 "The result contains 0
                // rows" printed raw in a red snackbar.
                //
                // Adding an UPDATE policy for heads would have hidden the error
                // and kept the bug: account_status is only the gate signIn()
                // reads, and Supabase still hands out a session for an account
                // that carries no Auth ban -- so the "deactivated" instructor
                // could still sign in with the anon key that ships in the app.
                // The function bans in Auth and writes audit_logs, which is the
                // whole reason to go through it.
                await Supabase.instance.client.functions.invoke(
                  'admin-accept-user',
                  body: {'targetUserId': instructor['id'], 'status': 'disabled'},
                );
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deactivated successfully.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.success));
                  // true tells the roster its cached list is now stale. It is a
                  // static cache that otherwise lives until the term changes, so
                  // the head would pop back to a list still showing the person
                  // they just locked out.
                  Navigator.pop(context, true); // Go back to roster
                }
              } catch (e) {
                if (mounted) setState(() => _isDeactivating = false);
                // A department head is not the person to show a
                // PostgrestException to. describeEdgeFunctionError digs out the
                // sentence the server actually wrote -- "that account is not in
                // your department", and so on -- and falls back to a plain line
                // for anything else.
                debugPrint('[DEPT HEAD] Deactivate failed: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        IdentityValidator.describeEdgeFunctionError(
                          e,
                          fallback:
                              'Could not deactivate this account. '
                              'Please check your connection and try again.',
                        ),
                      ),
                      backgroundColor: AppColors.error,
                      duration: const Duration(seconds: 6),
                    ),
                  );
                }
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
    
    // No remarks means no distribution to draw. Neutral used to default to 100
    // here, which painted a full gold bar directly above a legend reading
    // 0% / 0% / 0% -- the chart and the numbers under it contradicting each
    // other on the same card. Empty now means empty in both.
    final int posPct = hasData ? _sentimentSummary['positive'] : 0;
    final int neuPct = hasData ? _sentimentSummary['neutral'] : 0;
    final int negPct = hasData ? _sentimentSummary['negative'] : 0;
    
    final tags = _sentimentTags.isNotEmpty ? _sentimentTags : ['No Data Yet'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Sentiment Analysis',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F2EE), // Light beige from mockup
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Comment Polarity Distribution',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF888888), // Light gray text
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              // Stacked Bar Chart
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: hasData
                    ? Row(
                        children: [
                          if (posPct > 0)
                            Expanded(
                              flex: posPct,
                              child: Container(height: 10, color: const Color(0xFF457962)), // Green
                            ),
                          if (neuPct > 0)
                            Expanded(
                              flex: neuPct,
                              child: Container(height: 10, color: const Color(0xFFBC7631)), // Gold/Orange
                            ),
                          if (negPct > 0)
                            Expanded(
                              flex: negPct,
                              child: Container(height: 10, color: const Color(0xFFC34A2C)), // Red/Deep Orange
                            ),
                        ],
                      )
                    // Nothing to distribute yet — an empty track, not a filled
                    // bar in a colour nobody's remarks earned.
                    : Container(height: 10, color: const Color(0xFFE0DFDC)),
              ),
              const SizedBox(height: 12),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSentimentLegendItem('Positive', '$posPct%', const Color(0xFF457962)),
                  _buildSentimentLegendItem('Neutral', '$neuPct%', const Color(0xFFBC7631)),
                  _buildSentimentLegendItem('Negative', '$negPct%', const Color(0xFFC34A2C)),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Color(0xFFE0DFDC), height: 1),
              ),
              const Text(
                'Key Sentiment Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
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
          style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
        ),
        Text(
          percent,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  Widget _buildSentimentTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE8DB), // Light orange background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5B59F)), // Orange border
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFC34A2C), // Deep orange text
          fontSize: 12,
          fontWeight: FontWeight.w600,
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
                      // Bar height is proportional to the percent score
                      final double? tsScore = ts.score;
                      final barH = tsScore == null ? 0.0 : (tsScore / 100.0) * 120.0;
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
                                SastRating.formatPct(tsScore),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ts.isCurrent ? AppColors.primary : AppColors.textSecondary),
                              ),
                              const SizedBox(height: 4),
                              // The actual bar — animated height when it first appears
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 600), // Smooth animation
                                curve: Curves.easeOut,
                                height: tsScore != null ? barH.clamp(8.0, 120.0) : 4.0, // Min 8px so bar is visible even for low scores
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

  // Shows all subjects the instructor teaches this term. Read-only: the head
  // reads the load and the per-subject score here, nothing opens from it.
  Widget _buildSubjectsSection() {
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
          const AppleEmptyState(
            icon: Icons.library_books_outlined,
            title: 'No subjects this term',
            message: 'Assigned subjects will appear here when available.',
          )
        else
          // One tile per subject — using spread operator to flatten the list
          ...(_subjects.map((subject) => _buildSubjectTile(subject))),
      ],
    );
  }

  // A single subject tile — shows subject code, name, and score if available.
  //
  // Display only, on purpose: no tap target and no chevron, because an arrow
  // that leads nowhere is worse than no arrow. The per-subject breakdown is the
  // instructor's own screen; the head reads the summary here.
  Widget _buildSubjectTile(Subject subject) {
    // Check if we have a score for this subject — basin wala pa evaluation for it
    final double? score = subject.overallMean;
    final hasScore = score != null;

    return Container(
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
                Text(SastRating.format(score), style: TextStyle(color: _scoreColor(score), fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subject.verbalDescription, style: TextStyle(color: _scoreColor(score), fontSize: 10)), // e.g. "Very Satisfactory"
              ],
            ),
        ],
      ),
    );
  }
}

/// Simple data class for one term's score in the trend chart.
/// Holds the term label (short), overall score, mgmt + perf, and whether it's the current term.
/// dili pwede just use a Map — this is cleaner and type-safe.
class _TermScore {
  final String label;    // Short label shown under the bar chart — e.g. "1st\n25-26"
  final double? score;   // Overall score for this term on the percent scale (null = no answers)
  final double? mgmt;    // Management score — separate tracking
  final double? perf;    // Performance score — separate tracking
  final bool isCurrent;  // If true, this term's bar is highlighted in primary color
  final Map? termInfo;   // Raw academic_terms map — used only for sorting, not displayed
  final String termId;

  const _TermScore({
    required this.label,
    required this.score,
    required this.mgmt,
    required this.perf,
    required this.isCurrent,
    this.termInfo,
    this.termId = '',
  });

  _TermScore withScore(double? s) => _TermScore(
        label: label, score: s, mgmt: mgmt, perf: perf,
        isCurrent: isCurrent, termInfo: termInfo, termId: termId);
}
