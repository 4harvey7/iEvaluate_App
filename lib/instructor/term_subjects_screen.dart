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

      // Discovery across all sources for this specific term
      final responses = await Future.wait<dynamic>([
        _supabase.from('subjects').select().eq('instructor_id', widget.userId).eq('term_id', widget.termId),
        _supabase.from('management_results').select('subject_id, overall_management_mean, subjects(*)').eq('instructor_id', widget.userId).eq('term_id', widget.termId),
        _supabase.from('performance_results').select('subject_id, overall_performance_mean, subjects(*)').eq('instructor_id', widget.userId).eq('term_id', widget.termId),
        _supabase.from('raw_GoogleSheet_data_result').select('subject_id').eq('instructor_ID', widget.userId).eq('term_id', widget.termId),
      ]);

      // Group by Code and Section
      Map<String, Map<String, dynamic>> uniqueSubjects = {};

      void register(dynamic item) {
        if (item == null) return;
        final metadata = item['subjects'] != null ? Map<String, dynamic>.from(item['subjects']) : Map<String, dynamic>.from(item);
        final code = metadata['subject_code']?.toString();
        if (code == null) return;
        
        final section = metadata['section']?.toString() ?? '';
        final key = '${code}_$section'.toUpperCase();
        final sid = (metadata['id'] ?? item['subject_id'])?.toString();
        if (sid == null) return;

        if (!uniqueSubjects.containsKey(key)) {
          uniqueSubjects[key] = metadata;
          uniqueSubjects[key]!['all_ids'] = <String>{sid};
        } else {
          if (item.containsKey('instructor_id')) uniqueSubjects[key] = metadata;
          (uniqueSubjects[key]!['all_ids'] as Set<String>).add(sid);
        }
      }

      for (var response in responses) {
        if (response is List) {
          for (var item in response) register(item);
        }
      }

      List<Subject> processedSubjects = [];
      for (var entry in uniqueSubjects.values) {
        final allRelatedIds = entry['all_ids'] as Set<String>;
        double mMean = 0.0, pMean = 0.0;
        
        for (var response in responses) {
          if (response is List) {
            for (var item in response) {
              final itemSid = (item['subject_id'] ?? item['id'])?.toString();
              if (itemSid != null && allRelatedIds.contains(itemSid)) {
                if (item.containsKey('overall_management_mean')) mMean = (item['overall_management_mean'] as num?)?.toDouble() ?? mMean;
                if (item.containsKey('overall_performance_mean')) pMean = (item['overall_performance_mean'] as num?)?.toDouble() ?? pMean;
              }
            }
          }
        }

        if (mMean == 0.0 || pMean == 0.0) {
          final rawData = await _supabase.from('raw_GoogleSheet_data_result')
              .select()
              .filter('subject_id', 'in', allRelatedIds.toList())
              .eq('instructor_ID', widget.userId)
              .eq('term_id', widget.termId);

          if (rawData.isNotEmpty) {
            double mSum = 0, pSum = 0;
            for (var row in rawData) {
              for (int i = 1; i <= 10; i++) {
                mSum += (row['m$i'] as num?)?.toDouble() ?? 0.0;
                pSum += (row['p$i'] as num?)?.toDouble() ?? 0.0;
              }
            }
            if (mMean == 0.0) mMean = mSum / (rawData.length * 10);
            if (pMean == 0.0) pMean = pSum / (rawData.length * 10);
          }
        }

        processedSubjects.add(Subject.fromJson({
          ...entry,
          'management_mean': mMean,
          'performance_mean': pMean,
        }));
      }

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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _subjects.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
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
