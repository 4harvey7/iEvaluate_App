// lib/dept_head/subject_analytics_screen.dart
// The "Curriculum Health" screen — shows how each subject is performing dept-wide.
// If a subject look weird (anomaly), the AI will flag it. murag detective work.
// Dean can tap a subject to see which instructor is causing the score situation.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/evaluation_service.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/apple_ui.dart';
import 'instructor_detail_page.dart';

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
                                    Text('${item.avgScore}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: item.avgScore < 3.0 ? AppColors.error : AppColors.primary)),
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
        title: const Text('Subject Analytics', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData, // Pull down to refresh the subject list
          child: _isLoading 
            ? const AppleLoadingState(label: 'Loading curriculum analytics…')
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Always scrollable for pull-to-refresh
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Page title — "Curriculum Health" sounds official and descriptive
                    const ApplePageHeader(
                      eyebrow: 'Curriculum',
                      title: 'Subject Health',
                      subtitle: 'Performance patterns that may require review or teaching support.',
                    ),
                    const SizedBox(height: 24),

                    // No subject data yet — either new term or service returned empty
                    if (_subjectAnalytics.isEmpty)
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
                                    const SizedBox(height: 20),

                                    // Three mini stats in a row — avg score, difficulty, sentiment
                                    Row(
                                      children: [
                                        // Average score — the overall number for this subject
                                        _buildMiniStat('Avg Score', '${subject.avgScore}', isAnomaly ? AppColors.warning : AppColors.textPrimary),
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
                                        Text('Dept Avg: ${subject.deptAvg}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
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
