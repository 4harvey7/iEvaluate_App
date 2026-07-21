import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/evaluation_service.dart';
import '../theme/app_colors.dart';

class SubjectAnalyticsScreen extends StatefulWidget {
  final String userId;
  const SubjectAnalyticsScreen({super.key, required this.userId});

  @override
  State<SubjectAnalyticsScreen> createState() => _SubjectAnalyticsScreenState();
}

class _SubjectAnalyticsScreenState extends State<SubjectAnalyticsScreen> {
  final _evaluationService = EvaluationService();
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<SubjectAnalytic> _subjectAnalytics = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = widget.userId.isNotEmpty
          ? widget.userId
          : (_supabase.auth.currentUser?.id ?? '');
      if (userId.isNotEmpty) {
        final data = await _evaluationService.getSubjectAnalyticsForDept(userId);
        if (mounted) {
          setState(() {
            _subjectAnalytics = data;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading subject analytics: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSubjectDetails(SubjectAnalytic subject) {
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
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 24),
            Text(subject.code, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            Text(subject.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 24),
            const Text('Instructor Performance Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Expanded(
              child: subject.instructorBreakdown.isEmpty 
                ? const Center(child: Text("No detailed instructor data available."))
                : ListView.separated(
                    itemCount: subject.instructorBreakdown.length,
                    separatorBuilder: (context, index) => const Divider(),
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
                                      Text(item.instructorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text('${item.totalResponses} student surveys', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${item.avgScore}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: item.avgScore < 3.0 ? AppColors.error : AppColors.primary)),
                                    const Text('Avg Score', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Simple bar graph for comparison
                            Stack(
                              children: [
                                Container(height: 8, width: double.infinity, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4))),
                                FractionallySizedBox(
                                  widthFactor: (item.avgScore / 5.0).clamp(0.0, 1.0),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Subject Analytics', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Curriculum Health', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Identifying subjects that may require curriculum review or additional teaching resources.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    const SizedBox(height: 24),

                    if (_subjectAnalytics.isEmpty)
                      const Center(child: Text("No subject data available for this term."))
                    else
                      Column(
                        children: _subjectAnalytics.map((subject) {
                          bool isAnomaly = subject.aiNote != null;

                          return Card(
                            color: AppColors.surface,
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: isAnomaly ? AppColors.warning.withValues(alpha: 0.5) : Colors.transparent, width: 2),
                            ),
                            child: InkWell(
                              onTap: () => _showSubjectDetails(subject),
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                          child: Text(subject.code, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12)),
                                        ),
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
                                    Text(subject.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                                    const SizedBox(height: 20),

                                    Row(
                                      children: [
                                        _buildMiniStat('Avg Score', '${subject.avgScore}', isAnomaly ? AppColors.warning : AppColors.textPrimary),
                                        _buildMiniStat('Difficulty', subject.difficulty, AppColors.primary),
                                        _buildMiniStat('Sentiment', subject.sentiment, subject.sentiment == 'Critical' ? AppColors.error : AppColors.success),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    const Text('Score vs. Department Average', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Stack(
                                      children: [
                                        Container(
                                          height: 12,
                                          width: double.infinity,
                                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(6)),
                                        ),
                                        FractionallySizedBox(
                                          widthFactor: (subject.avgScore / 5.0).clamp(0.0, 1.0),
                                          child: Container(
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: isAnomaly ? AppColors.warning : AppColors.primary,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: (MediaQuery.of(context).size.width - 88) * (subject.deptAvg / 5.0).clamp(0.0, 1.0),
                                          child: Container(width: 2, height: 12, color: AppColors.textPrimary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('0.0', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                        Text('Dept Avg: ${subject.deptAvg}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                                        const Text('5.0', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                      ],
                                    ),

                                    if (isAnomaly) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          subject.aiNote!,
                                          style: const TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
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

  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
