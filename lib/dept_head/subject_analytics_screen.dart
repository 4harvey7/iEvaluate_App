// lib/dept_head/subject_analytics_screen.dart
// The "Subject Performance" screen — shows how each subject is performing dept-wide.
// If a subject look weird (anomaly), the AI will flag it. murag detective work.
// Dean can tap a subject to see which instructor is causing the score situation.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/evaluation_service.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/apple_ui.dart';
import '../core/utils/sast_rating.dart';
import '../core/services/eval_results_service.dart';
import '../widgets/eval_report_widgets.dart';

// The main widget — stateful because data is fetched async
class SubjectAnalyticsScreen extends StatefulWidget {
  final String userId; // The dept head's user ID — used to scope data to their dept
  const SubjectAnalyticsScreen({super.key, required this.userId});

  @override
  State<SubjectAnalyticsScreen> createState() => _SubjectAnalyticsScreenState();
}

class _SubjectAnalyticsScreenState extends State<SubjectAnalyticsScreen> {
  final _evaluationService = EvaluationService();
  final _supabase = Supabase.instance.client;
  
  // ─── CACHE FOR INSTANT TAB SWITCHING ─────────────────────────────────────────
  static final Map<String, List<SubjectAnalytic>> _analyticsCache = {};

  bool _isLoading = true; // Show spinner on first open
  List<SubjectAnalytic> _subjectAnalytics = []; // All subject data for this dept

  // New-form term (SET-15): per-subject % built from eval_results. Null = old term.
  String? _termId;
  List<_SetSubject>? _setSubjects;

  // Load data when screen first appears
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Fetches all subject analytics for this department.
  // One API call and we get everything — scores, sentiment, difficulty, anomalies.
  // If userId is empty for some reason, we try the auth session as fallback — wala choice.
  Future<void> _loadData() async {
    final userId = widget.userId.isNotEmpty
        ? widget.userId
        : (_supabase.auth.currentUser?.id ?? '');
        
    // Check cache first for instant load
    if (_analyticsCache.containsKey(userId)) {
      if (mounted) {
        setState(() {
          _subjectAnalytics = _analyticsCache[userId]!;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = true);
    }
    
    try {
      if (userId.isNotEmpty) {
        // New-form term first: if SET-15 results exist, show those (student only).
        final setSubjects = await _loadSetSubjects(userId);
        if (setSubjects != null && setSubjects.isNotEmpty) {
          if (mounted) {
            setState(() {
              _setSubjects = setSubjects;
              _isLoading = false;
            });
          }
          return;
        }
        if (mounted) setState(() => _setSubjects = null);
        // Get all subject analytics — the service handles all the complex queries
        final data = await _evaluationService.getSubjectAnalyticsForDept(userId);
        if (mounted) {
          setState(() {
            _analyticsCache[userId] = data; // Save to cache
            _subjectAnalytics = data; // Store and display
            _isLoading = false; // Done loading — show content
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading subject analytics: $e');
      if (mounted) setState(() => _isLoading = false); // Stop spinner on error
    }
  }

  // SET-15 % per subject for the current term (department scope by RLS).
  // Instructor names only; student ids never reach this screen. SUP-15 is
  // never read here.
  Future<List<_SetSubject>?> _loadSetSubjects(String userId) async {
    try {
      final settings = await _supabase.from('system_settings').select('current_term_id').maybeSingle();
      final termId = settings?['current_term_id']?.toString();
      if (termId == null) return null;
      _termId = termId;
      final rows = (await EvalResultsService.deptSubjectRows(termId)).where((r) => r.instructorId != userId).toList();
      if (rows.isEmpty) return null;
      final subjectIds = rows.map((r) => r.subjectId).toSet().toList();
      final instructorIds = rows.map((r) => r.instructorId).toSet().toList();
      final subs = await _supabase.from('subjects').select('id, subject_code, subject_name').inFilter('id', subjectIds);
      final people = await _supabase.from('user_info').select('id, first_name, last_name').inFilter('id', instructorIds);
      final subById = {for (final r in subs as List) r['id'].toString(): r};
      final nameById = {
        for (final r in people as List) r['id'].toString(): '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim()
      };
      final grouped = <String, _SetSubject>{};
      for (final r in rows) {
        final sub = subById[r.subjectId];
        final g = grouped.putIfAbsent(
          r.subjectId,
          () => _SetSubject(r.subjectId, '${sub?['subject_code'] ?? ''}', '${sub?['subject_name'] ?? 'Subject'}'),
        );
        g.instructors.add(_SetInstructor(r.instructorId, nameById[r.instructorId] ?? 'Instructor', r.pct, r.respondents));
      }
      return grouped.values.toList()..sort((a, b) => a.code.compareTo(b.code));
    } catch (e) {
      debugPrint('Error loading SET subject analytics: $e');
      return null;
    }
  }

  // One instructor's SET section and item % for a subject (student scope only).
  void _showSetInstructor(_SetSubject subject, _SetInstructor inst) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<EvalReport?>(
          future: EvalResultsService.load(instructorId: inst.id, termId: _termId!, subjectId: subject.id),
          builder: (context, snap) {
            final scope = snap.data?.student;
            return ListView(
              children: [
                Text('${subject.code} ${subject.name}'.trim(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(inst.name, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                if (snap.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (scope == null)
                  const Text('No student evaluation results for this subject.')
                else
                  EvalScopeCard(scope: scope, heading: 'Student evaluation (SET)'),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showSetSubjectDetails(_SetSubject subject) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subject.code, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            Text(subject.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            const Text('Instructors (tap for sections and items)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final i in subject.instructors)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${i.respondents} respondent${i.respondents == 1 ? '' : 's'}'),
                      trailing: EvalPctBadge(pct: i.pct),
                      onTap: () => _showSetInstructor(subject, i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetBody() {
    return Column(
      children: [
        for (final sub in _setSubjects!)
          Card(
            color: AppColors.surface,
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showSetSubjectDetails(sub),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sub.code, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12)),
                          const SizedBox(height: 6),
                          Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text('${sub.instructors.length} instructor${sub.instructors.length == 1 ? '' : 's'} - SET %',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    EvalPctBadge(pct: sub.avgPct),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Opens a bottom sheet with the instructor breakdown for a specific subject.
  // Shows each instructor who teaches this subject + their avg score and a mini bar.
  // Importente to see WHO is dragging the subject score down — dili ta guess.
  void _showSubjectDetails(SubjectAnalytic subject) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allow full-height sheet
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7, // 70% of screen height — enough room
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle — visual hint that this is a bottom sheet
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 24),
            // Subject code in primary color — easy to identify at a glance
            Text(subject.code, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            // Full subject name — big and bold
            Text(subject.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 24),
            const Text('Instructor Performance Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            // List of instructors teaching this subject — scrollable in case many
            Expanded(
              child: subject.instructorBreakdown.isEmpty 
                ? const Center(child: Text("No detailed instructor data available.")) // Fallback if data missing
                : ListView.separated(
                    itemCount: subject.instructorBreakdown.length,
                    separatorBuilder: (context, index) => const Divider(), // Thin line between instructors
                    itemBuilder: (context, index) {
                      final item = subject.instructorBreakdown[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Instructor's name — the main identifier
                                      Text(item.instructorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                                      // How many students rated them for this subject
                                      Text('${item.totalResponses} student surveys', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // Their average score — red if below 3.0, blue if okay
                                    Text(SastRating.format(item.avgScore), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: item.avgScore < 3.0 ? AppColors.error : AppColors.primary)),
                                    const Text('Avg Score', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Simple bar graph for comparison — shows score as % of max 5.0
                            // Very visual — dean can see who is below average at a glance
                            Stack(
                              children: [
                                // Background track — full width gray
                                Container(height: 8, width: double.infinity, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4))),
                                // Foreground fill — proportional to score, red if bad
                                FractionallySizedBox(
                                  widthFactor: (item.avgScore / 5.0).clamp(0.0, 1.0), // Never exceed 100%
                                  child: Container(height: 8, decoration: BoxDecoration(color: item.avgScore < 3.0 ? AppColors.error : AppColors.primary, borderRadius: BorderRadius.circular(4))),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // Main build — full list of subject analytics cards
  // Each card has: code, name, avg score, difficulty, sentiment, bar chart vs dept avg
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Subject Performance', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData, // Pull down to refresh the subject list
          child: _isLoading 
            ? const AppleLoadingState(label: 'Loading subject performance…')
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Always scrollable for pull-to-refresh
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Page title — "Subject Performance" sounds official and descriptive
                    const ApplePageHeader(
                      eyebrow: 'Department Subjects',
                      title: 'Subject Performance',
                      subtitle: 'Performance patterns that may require review or teaching support.',
                    ),
                    const SizedBox(height: 24),

                    // No subject data yet — either new term or service returned empty
                    if (_setSubjects != null)
                      _buildSetBody()
                    else if (_subjectAnalytics.isEmpty)
                      const AppleEmptyState(
                        icon: Icons.analytics_outlined,
                        title: 'No subject data',
                        message: 'Analytics will appear after this term receives evaluations.',
                      )
                    else
                      Column(
                        children: _subjectAnalytics.map((subject) {
                          // If aiNote is not null, the AI detected something unusual about this subject
                          bool isAnomaly = subject.aiNote != null;

                          return Card(
                            color: AppColors.surface,
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              // Orange border for anomalies — stand out from the rest
                              side: BorderSide(color: isAnomaly ? AppColors.warning.withValues(alpha: 0.5) : Colors.transparent, width: 2),
                            ),
                            child: InkWell(
                              onTap: () => _showSubjectDetails(subject), // Tap to see instructor breakdown
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Subject code chip — pill shape, primary color
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                          child: Text(subject.code, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12)),
                                        ),
                                        // Show anomaly badge only if AI flagged it — murag warning sign
                                        if (isAnomaly)
                                          const Row(
                                            children: [
                                              Icon(Icons.auto_graph, color: AppColors.warning, size: 16),
                                              SizedBox(width: 4),
                                              Text('System Anomaly', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 12)),
                                            ],
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Full subject name — the main title of the card
                                    Text(subject.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                                    // Owning program tag -- the subject may belong to another program
                                    if (subject.ownerCode != null && subject.ownerCode!.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('${subject.ownerCode} subject', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                    ],
                                    const SizedBox(height: 20),

                                    // Three mini stats in a row — avg score, difficulty, sentiment
                                    Row(
                                      children: [
                                        // Average score — the overall number for this subject
                                        _buildMiniStat('Avg Score', SastRating.format(subject.avgScore), isAnomaly ? AppColors.warning : AppColors.textPrimary),
                                        // Difficulty rating — how hard students find this subject
                                        _buildMiniStat('Difficulty', subject.difficulty, AppColors.primary),
                                        // Sentiment — "Critical" turns red, others stay green
                                        _buildMiniStat('Sentiment', subject.sentiment, subject.sentiment == 'Critical' ? AppColors.error : AppColors.success),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Progress bar comparing subject score vs dept average
                                    // The dept avg is shown as a vertical line marker — clever trick
                                    const Text('Score vs. Department Average', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Stack(
                                      children: [
                                        // Full-width gray background track
                                        Container(
                                          height: 12,
                                          width: double.infinity,
                                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(6)),
                                        ),
                                        // Colored fill showing subject's avg score out of 5.0
                                        FractionallySizedBox(
                                          widthFactor: (subject.avgScore / 5.0).clamp(0.0, 1.0),
                                          child: Container(
                                            height: 12,
                                            decoration: BoxDecoration(
                                              // Orange if anomaly, blue if normal
                                              color: isAnomaly ? AppColors.warning : AppColors.primary,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                        // Dept avg marker — vertical dark line so dean can compare
                                        Positioned(
                                          left: (MediaQuery.of(context).size.width - 88) * (subject.deptAvg / 5.0).clamp(0.0, 1.0),
                                          child: Container(width: 2, height: 12, color: AppColors.textPrimary), // Thin dark marker
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Scale labels: 0.0 on left, dept avg in middle, 5.0 on right
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('0.0', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                        Text('Dept Avg: ${SastRating.format(subject.deptAvg)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                                        const Text('5.0', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                      ],
                                    ),

                                    // AI anomaly note — only shown if isAnomaly is true
                                    // Contains the AI explanation of what seems odd — importente read this
                                    if (isAnomaly) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          subject.aiNote!, // The AI-generated explanation text
                                          style: const TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    // Small tap hint at the bottom — so user know they can tap for more
                                    const Center(
                                      child: Text('Tap to view instructor breakdown', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w500)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  // A single mini stat widget — label on top, value below in specified color
  // Used three times per subject card — avg score, difficulty, sentiment
  // Reusable so we don't repeat the same Column code three times. dili ta lazy, we just DRY.
  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label — small secondary text above the value
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          // The actual value — colored and bold so it readable at a glance
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SetInstructor {
  final String id;
  final String name;
  final double pct;
  final int respondents;
  _SetInstructor(this.id, this.name, this.pct, this.respondents);
}

class _SetSubject {
  final String id;
  final String code;
  final String name;
  final List<_SetInstructor> instructors = [];
  _SetSubject(this.id, this.code, this.name);

  // Plain average of the instructors' SET overall % for this subject.
  double? get avgPct => SastRating.averageOfPresent(instructors.map((i) => i.pct));
}
