import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'models/subject.dart';
import 'subject_detail_screen.dart';
import 'detailed_report_screen.dart';
import 'widgets/subject_card.dart';

class PastSemestersScreen extends StatefulWidget {
  final String userId;
  const PastSemestersScreen({super.key, required this.userId});

  @override
  State<PastSemestersScreen> createState() => _PastSemestersScreenState();
}

class _PastSemestersScreenState extends State<PastSemestersScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isTermLoading = false;
  List<Map<String, dynamic>> _historicalData = [];
  String? _selectedTermId;
  List<Map<String, dynamic>> _selectedTermSubjects = [];
  
  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      if (mounted) setState(() => _isLoading = true);

      // Fetch all terms where this instructor has an overall summary
      final responses = await Future.wait<dynamic>([
        _supabase.from('system_settings').select('current_term_id').maybeSingle(),
        _supabase.from('overall_total_survey').select('*, academic_terms(*)').eq('instructor_id', widget.userId),
      ]);

      final currentTermId = responses[0]?['current_term_id'];
      final summaries = responses[1] as List;

      Map<String, Map<String, dynamic>> termsMap = {};

      for (var item in summaries) {
        final tid = item['term_id'];
        if (tid == null) continue;
        final termData = item['academic_terms'];
        
        termsMap[tid] = {
          'termId': tid,
          'semester': termData != null 
              ? '${termData['semester']} ${termData['academic_year']}'
              : 'Unknown Term',
          'created_at': termData?['created_at'] ?? item['created_at'] ?? '',
          'overallScore': (item['overall_mean'] as num?)?.toDouble() ?? 0.0,
          'managementScore': (item['management_mean'] as num?)?.toDouble() ?? 0.0,
          'performanceScore': (item['performance_mean'] as num?)?.toDouble() ?? 0.0,
          'evaluations': (item['total_responses'] as int?) ?? 0,
        };
      }

      List<Map<String, dynamic>> processedData = termsMap.values.toList();
      // Sort chronologically by term creation
      processedData.sort((a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''));

      if (mounted) {
        setState(() {
          _historicalData = processedData;
          
          if (_selectedTermId == null) {
            // Try to default to current term if it's in history, else last historical term
            if (processedData.any((t) => t['termId'] == currentTermId)) {
              _selectedTermId = currentTermId;
            } else if (processedData.isNotEmpty) {
              _selectedTermId = processedData.last['termId'];
            }
          }
          _isLoading = false;
        });

        if (_selectedTermId != null) {
          _loadSelectedTermData(_selectedTermId!);
        }
      }
    } catch (e) {
      debugPrint('Error fetching history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSelectedTermData(String termId) async {
    try {
      if (mounted) setState(() => _isTermLoading = true);
      
      // 1. Discovery across all possible sources for this term
      final responses = await Future.wait<dynamic>([
        _supabase.from('subjects').select().eq('instructor_id', widget.userId).eq('term_id', termId),
        _supabase.from('management_results').select('subject_id, overall_management_mean, subjects(*)').eq('instructor_id', widget.userId).eq('term_id', termId),
        _supabase.from('performance_results').select('subject_id, overall_performance_mean, subjects(*)').eq('instructor_id', widget.userId).eq('term_id', termId),
        _supabase.from('raw_GoogleSheet_data_result').select('subject_id').eq('instructor_ID', widget.userId).eq('term_id', termId),
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

      List<Map<String, dynamic>> processed = [];
      for (var entry in uniqueSubjects.values) {
        final allRelatedIds = entry['all_ids'] as Set<String>;

        double mMean = 0.0, pMean = 0.0;
        
        // Aggregate scores from any matching ID
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
              .eq('term_id', termId);

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

        processed.add({
          ...entry,
          'management_mean': mMean,
          'performance_mean': pMean,
        });
      }

      // Sort by subject code
      processed.sort((a, b) => (a['subject_code'] ?? '').compareTo(b['subject_code'] ?? ''));

      if (mounted) {
        setState(() {
          _selectedTermSubjects = processed;
          _isTermLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading term data: $e');
      if (mounted) setState(() => _isTermLoading = false);
    }
  }

  Map<String, dynamic>? get _selectedTermData {
    if (_selectedTermId == null || _historicalData.isEmpty) return null;
    final matches = _historicalData.where((t) => t['termId'] == _selectedTermId);
    return matches.isNotEmpty ? matches.first : _historicalData.last;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final termData = _selectedTermData;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        title: const Text('Past Semesters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Historical Growth', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('Track your evaluation scores across previous academic terms.', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),

            _buildTrendGraph(),

            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Term Filter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                if (termData != null && termData.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      final name = _supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Instructor';
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailedReportScreen(
                        userId: widget.userId,
                        instructorName: name,
                        department: 'Faculty',
                        termId: _selectedTermId,
                        term: termData['semester']?.toString().split(' ')[0] ?? '',
                        academicYear: termData['semester']?.toString().contains(' ') == true ? termData['semester']?.toString().split(' ').sublist(1).join(' ') ?? '' : '',
                        managementScore: (termData['managementScore'] as num?)?.toDouble() ?? 0.0,
                        performanceScore: (termData['performanceScore'] as num?)?.toDouble() ?? 0.0,
                        overallScore: (termData['overallScore'] as num?)?.toDouble() ?? 0.0,
                        totalEvaluations: (termData['evaluations'] as int?) ?? 0,
                      )));
                    },
                    icon: const Icon(Icons.description, size: 18),
                    label: const Text('Full Term Report'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (_historicalData.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.textTertiary.withOpacity(0.2))),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTermId,
                    isExpanded: true,
                    hint: const Text('Select Term'),
                    items: _historicalData.reversed.map((t) {
                      return DropdownMenuItem(
                        value: t['termId'] as String,
                        child: Text(t['semester']),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedTermId = val);
                        _loadSelectedTermData(val);
                      }
                    },
                  ),
                ),
              )
            else
              const Center(child: Text('No historical data found.')),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subjects Taught', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                if (!_isTermLoading)
                  Text('${_selectedTermSubjects.length} Subjects', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),

            if (_isTermLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_selectedTermSubjects.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No subjects found for this term.')))
            else
              ..._selectedTermSubjects.map((s) {
                final subjectObj = Subject.fromJson({
                  ...s,
                  'management_mean': s['management_mean'],
                  'performance_mean': s['performance_mean'],
                  'created_at': s['created_at'] ?? termData?['created_at'] ?? DateTime.now().toIso8601String(),
                });
                return SubjectCard(
                  subject: subjectObj,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectDetailScreen(subject: subjectObj, userId: widget.userId, termId: _selectedTermId!))),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendGraph() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.textPrimary, const Color(0xFF1E293B)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance Trend', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 32),
          SizedBox(
            height: 180,
            child: _historicalData.isEmpty
                ? const Center(child: Text('No data available', style: TextStyle(color: Colors.white54)))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: _historicalData.map((data) {
                      double score = (data['overallScore'] as num?)?.toDouble() ?? 0.0;
                      double h = (score / 5.0) * 120;
                      bool isSel = data['termId'] == _selectedTermId;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(score.toStringAsFixed(1), style: TextStyle(color: isSel ? AppColors.primary : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () {
                              setState(() => _selectedTermId = data['termId']);
                              _loadSelectedTermData(data['termId']);
                            },
                            child: Container(
                              width: 30,
                              height: h.clamp(5, 120),
                              decoration: BoxDecoration(
                                color: isSel ? AppColors.primary : Colors.white24,
                                borderRadius: BorderRadius.circular(4),
                                border: isSel ? Border.all(color: Colors.white, width: 1) : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(width: 40, child: Text(data['semester']?.toString().split(' ')[0] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 8), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
                        ],
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
