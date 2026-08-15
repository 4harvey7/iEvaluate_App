import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'models/subject.dart';
import 'subject_detail_screen.dart';
import 'widgets/subject_card.dart';

class TermSubjectsScreen extends StatefulWidget {
  final String userId;
  final String termId;
  final String termName;

  const TermSubjectsScreen({
    super.key,
    required this.userId,
    required this.termId,
    required this.termName,
  });

  @override
  State<TermSubjectsScreen> createState() => _TermSubjectsScreenState();
}

class _TermSubjectsScreenState extends State<TermSubjectsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Subject> _subjects = [];

  @override
  void initState() {
    super.initState();
    _fetchTermSubjects();
  }

  Future<void> _fetchTermSubjects() async {
    try {
      setState(() => _isLoading = true);

      // 1. Get subjects for this instructor+term via instructor_subjects junction table
      final assignmentRows = await _supabase
          .from('instructor_subjects')
          .select('subject_id, subjects(id, subject_code, subject_name, created_at, department_id)')
          .eq('instructor_id', widget.userId)
          .eq('term_id', widget.termId);

      // Build unique subject map by subject_id
      final Map<String, Map<String, dynamic>> subjectById = {};
      for (var row in (assignmentRows as List)) {
        final subjectData = row['subjects'];
        if (subjectData == null) continue;
        final meta = Map<String, dynamic>.from(
          subjectData is List ? subjectData[0] : subjectData,
        );
        final id = meta['id']?.toString();
        if (id == null) continue;
        subjectById.putIfAbsent(id, () => meta);
      }

      if (subjectById.isEmpty) {
        if (mounted) setState(() { _subjects = []; _isLoading = false; });
        return;
      }

      final validSubjectIds = subjectById.keys.toList();

      // 2. Fetch pre-computed results
      final results = await Future.wait<dynamic>([
        _supabase.from('management_results')
            .select('subject_id, overall_management_mean')
            .eq('instructor_id', widget.userId)
            .eq('term_id', widget.termId)
            .filter('subject_id', 'in', validSubjectIds),
        _supabase.from('performance_results')
            .select('subject_id, overall_performance_mean')
            .eq('instructor_id', widget.userId)
            .eq('term_id', widget.termId)
            .filter('subject_id', 'in', validSubjectIds),
      ]);

      final Map<String, double> mgmtMap = {};
      for (var row in (results[0] as List)) {
        final sid = row['subject_id']?.toString();
        if (sid != null) mgmtMap[sid] = (row['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
      }
      final Map<String, double> perfMap = {};
      for (var row in (results[1] as List)) {
        final sid = row['subject_id']?.toString();
        if (sid != null) perfMap[sid] = (row['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
      }

      // 3. Build subject list
      List<Subject> processedSubjects = [];
      for (var entry in subjectById.entries) {
        final id = entry.key;
        final meta = entry.value;
        double mMean = mgmtMap[id] ?? 0.0;
        double pMean = perfMap[id] ?? 0.0;

        // Fallback to raw if no pre-computed
        if (mMean == 0.0 && pMean == 0.0) {
          final rawData = await _supabase.from('sast_all_raw_data_survey')
              .select()
              .eq('subject_id', id)
              .eq('instructor_ID', widget.userId)
              .eq('term_id', widget.termId);

          if ((rawData as List).isNotEmpty) {
            double mSum = 0, pSum = 0;
            for (var row in rawData) {
              for (int i = 1; i <= 10; i++) {
                mSum += (row['m$i'] as num?)?.toDouble() ?? 0.0;
                pSum += (row['p$i'] as num?)?.toDouble() ?? 0.0;
              }
            }
            mMean = mSum / (rawData.length * 10);
            pMean = pSum / (rawData.length * 10);
          }
        }

        processedSubjects.add(Subject.fromJson({
          ...meta,
          'management_mean': mMean,
          'performance_mean': pMean,
          'all_ids': <String>{id},
        }));
      }

      processedSubjects.sort((a, b) => a.code.compareTo(b.code));

      if (mounted) {
        setState(() {
          _subjects = processedSubjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching term subjects: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.termName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _fetchTermSubjects,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _fetchTermSubjects,
              color: AppColors.primary,
              child: _subjects.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [_buildEmptyState()],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      itemCount: _subjects.length,
                      itemBuilder: (context, index) {
                        final subject = _subjects[index];
                        return SubjectCard(
                          subject: subject,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SubjectDetailScreen(
                                subject: subject,
                                userId: widget.userId,
                                termId: widget.termId,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.subject_rounded, size: 80, color: AppColors.textPrimary.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('No subjects found for this term.', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

}
