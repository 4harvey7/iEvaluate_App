import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'models/subject.dart';

class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;
  final String userId;
  final String? termId;

  const SubjectDetailScreen({
    super.key,
    required this.subject,
    required this.userId,
    this.termId,
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  double _mgmtScore = 0;
  double _perfScore = 0;
  double _overallScore = 0;
  int _totalResponses = 0;
  List<Map<String, dynamic>> _questionMeans = [];
  List<Map<String, dynamic>> _subjectRemarks = [];
  Map<String, dynamic>? _mgmtData;
  Map<String, dynamic>? _perfData;
  String _selectedFilter = 'All';
  String _sortOrder = 'Date (Newest)';
  final List<String> _sortOptions = ['Date (Newest)', 'Date (Oldest)', 'Sentiment (Positive First)', 'Sentiment (Critical First)'];

  // Management criteria — SS Form 2 (Feb 4, 2009, Revision 3)
  static const List<String> _managementCriteria = [
    'Gives reasonable course / subject assignments',
    'Earns appreciation and kind attention from the students',
    'Gives orientation about the subject and how the students are evaluated',
    'Gives tests and/or projects which are within the objectives of the course',
    'Shows deep interest and concern in assisting the students',
    'Manifests sympathetic insight into students\' feelings',
    'Checks and records test papers/term papers',
    'Is on time and regular in meeting the class',
    'Apportions fair subject/course assignments',
    'Sustains the attention of the class for the whole period',
  ];

  // Performance criteria — SS Form 2 (Feb 4, 2009, Revision 3)
  static const List<String> _performanceCriteria = [
    'Presents lesson clearly, methodically, and substantially',
    'Motivates the students to learn',
    'Facilitates learning with the application of appropriate educational methods and techniques',
    'Shows mastery of the lesson',
    'Is ready for the class',
    'Inspires students\' self-reliance in their quest for knowledge',
    'Knows when the students have difficulty understanding the lesson and find ways to make it easy',
    'Integrates values into the lesson',
    'Speaks the language of instruction (English or Filipino) clearly and fluently',
    'Delivers thought provoking questions',
  ];

  @override
  void initState() {
    super.initState();
    _fetchSubjectDetails();
  }

  Future<void> _fetchSubjectDetails() async {
    try {
      // 1. Resolve active term
      String? activeTermId = widget.termId;
      if (activeTermId == null || activeTermId.isEmpty) {
        final settings = await _supabase
            .from('system_settings')
            .select('current_term_id')
            .maybeSingle();
        activeTermId = settings?['current_term_id'];
      }

      if (activeTermId == null || activeTermId.isEmpty) {
        debugPrint('[SubjectDetailScreen] No active term ID, aborting.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final subjectCode = widget.subject.code;
      debugPrint('[SubjectDetailScreen] Fetching "$subjectCode" in term "$activeTermId"');

      // 2. Get exact subject IDs for this code+instructor+term via instructor_subjects junction table.
      final subjectRows = await _supabase
          .from('instructor_subjects')
          .select('subject_id')
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId)
          .filter('subject_id', 'in',
              // Only rows whose subject matches the code
              (await _supabase
                      .from('subjects')
                      .select('id')
                      .eq('subject_code', subjectCode))
                  .map<String>((s) => s['id'].toString())
                  .toList());

      final subjectIds = (subjectRows as List).map((s) => s['subject_id'].toString()).toList();

      debugPrint('[SubjectDetailScreen] Subject IDs: $subjectIds');

      if (subjectIds.isEmpty) {
        debugPrint('[SubjectDetailScreen] No subjects found for this code+term.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 3. Fetch pre-computed management_results and performance_results.
      //    These are the preferred source per schema design.
      //    Order by created_at DESC so the most recent (corrected) row comes first.
      final precomputed = await Future.wait([
        _supabase
            .from('management_results')
            .select('subject_id, m1_mean, m2_mean, m3_mean, m4_mean, m5_mean, '
                'm6_mean, m7_mean, m8_mean, m9_mean, m10_mean, '
                'overall_management_mean, total_responses, created_at')
            .filter('subject_id', 'in', subjectIds)
            .eq('instructor_id', widget.userId)
            .eq('term_id', activeTermId)
            .order('created_at', ascending: false),
        _supabase
            .from('performance_results')
            .select('subject_id, p1_mean, p2_mean, p3_mean, p4_mean, p5_mean, '
                'p6_mean, p7_mean, p8_mean, p9_mean, p10_mean, '
                'overall_performance_mean, total_responses, created_at')
            .filter('subject_id', 'in', subjectIds)
            .eq('instructor_id', widget.userId)
            .eq('term_id', activeTermId)
            .order('created_at', ascending: false),
        _supabase
            .from('student_remarks')
            .select('remark, tone, created_at')
            .filter('subject_id', 'in', subjectIds)
            .eq('instructor_id', widget.userId)
            .eq('term_id', activeTermId)
            .order('created_at', ascending: false),
      ]);

      final mgmtRows = precomputed[0] as List;
      final perfRows = precomputed[1] as List;
      final remarkRows = precomputed[2] as List;

      debugPrint('[SubjectDetailScreen] mgmtRows=${mgmtRows.length}, '
          'perfRows=${perfRows.length}, remarks=${remarkRows.length}');

      // 4. Pick the best (most recent) row per subject ID, then aggregate.
      //    "Most recent" = first row since we ORDER BY created_at DESC.
      final Map<String, Map<String, dynamic>> bestMgmt = {};
      for (var row in mgmtRows) {
        final sid = row['subject_id']?.toString();
        if (sid != null && !bestMgmt.containsKey(sid)) {
          bestMgmt[sid] = Map<String, dynamic>.from(row);
        }
      }

      final Map<String, Map<String, dynamic>> bestPerf = {};
      for (var row in perfRows) {
        final sid = row['subject_id']?.toString();
        if (sid != null && !bestPerf.containsKey(sid)) {
          bestPerf[sid] = Map<String, dynamic>.from(row);
        }
      }

      // Aggregate across sections (weighted by total_responses)
      double mWeightedSum = 0, pWeightedSum = 0;
      int mTotal = 0, pTotal = 0;
      final Map<String, double> mCriteriaSum = {};
      final Map<String, double> pCriteriaSum = {};
      final Map<String, int> mCriteriaCount = {};
      final Map<String, int> pCriteriaCount = {};

      for (var id in subjectIds) {
        final mgmt = bestMgmt[id];
        if (mgmt != null) {
          final n = (mgmt['total_responses'] as num?)?.toInt() ?? 0;
          final overall = (mgmt['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
          mWeightedSum += overall * n;
          mTotal += n;
          for (int i = 1; i <= 10; i++) {
            final key = 'm${i}_mean';
            final val = (mgmt[key] as num?)?.toDouble() ?? 0.0;
            mCriteriaSum[key] = (mCriteriaSum[key] ?? 0) + val * n;
            mCriteriaCount[key] = (mCriteriaCount[key] ?? 0) + n;
          }
        }

        final perf = bestPerf[id];
        if (perf != null) {
          final n = (perf['total_responses'] as num?)?.toInt() ?? 0;
          final overall = (perf['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
          pWeightedSum += overall * n;
          pTotal += n;
          for (int i = 1; i <= 10; i++) {
            final key = 'p${i}_mean';
            final val = (perf[key] as num?)?.toDouble() ?? 0.0;
            pCriteriaSum[key] = (pCriteriaSum[key] ?? 0) + val * n;
            pCriteriaCount[key] = (pCriteriaCount[key] ?? 0) + n;
          }
        }
      }

      List<Map<String, dynamic>> means = [];
      bool hasPrecomputed = mTotal > 0 || pTotal > 0;

      if (hasPrecomputed) {
        _totalResponses = mTotal > 0 ? mTotal : pTotal;

        final Map<String, dynamic> mgmtData = {'total_responses': mTotal};
        double mgmtOverallSum = 0;
        for (int i = 1; i <= 10; i++) {
          final key = 'm${i}_mean';
          final n = mCriteriaCount[key] ?? 1;
          final mean = n > 0 ? (mCriteriaSum[key] ?? 0) / n : 0.0;
          mgmtData[key] = mean;
          mgmtOverallSum += mean;
          means.add({'label': 'M$i', 'score': mean, 'category': 'Management'});
        }
        _mgmtScore = mTotal > 0 ? mWeightedSum / mTotal : mgmtOverallSum / 10;
        _mgmtData = mgmtData;

        final Map<String, dynamic> perfData = {'total_responses': pTotal};
        double perfOverallSum = 0;
        for (int i = 1; i <= 10; i++) {
          final key = 'p${i}_mean';
          final n = pCriteriaCount[key] ?? 1;
          final mean = n > 0 ? (pCriteriaSum[key] ?? 0) / n : 0.0;
          perfData[key] = mean;
          perfOverallSum += mean;
          means.add({'label': 'P$i', 'score': mean, 'category': 'Performance'});
        }
        _perfScore = pTotal > 0 ? pWeightedSum / pTotal : perfOverallSum / 10;
        _perfData = perfData;
      } else {
        // Fallback to raw data if no pre-computed results exist
        debugPrint('[SubjectDetailScreen] No pre-computed results, falling back to raw data...');
        final rawRows = await _supabase
            .from('sast_all_raw_data_survey')
            .select('m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10')
            .filter('subject_id', 'in', subjectIds)
            .eq('instructor_ID', widget.userId)
            .eq('term_id', activeTermId);

        if ((rawRows as List).isNotEmpty) {
          final int total = rawRows.length;
          _totalResponses = total;
          final Map<String, dynamic> mgmtData = {'total_responses': total};
          double mgmtSum = 0;
          for (int i = 1; i <= 10; i++) {
            double colSum = 0;
            for (var row in rawRows) {
              final val = row['m$i'];
              colSum += (val is num) ? val.toDouble() : double.tryParse(val?.toString() ?? '0') ?? 0;
            }
            final mean = colSum / total;
            mgmtData['m${i}_mean'] = mean;
            mgmtSum += mean;
            means.add({'label': 'M$i', 'score': mean, 'category': 'Management'});
          }
          _mgmtScore = mgmtSum / 10;
          _mgmtData = mgmtData;

          final Map<String, dynamic> perfData = {'total_responses': total};
          double perfSum = 0;
          for (int i = 1; i <= 10; i++) {
            double colSum = 0;
            for (var row in rawRows) {
              final val = row['p$i'];
              colSum += (val is num) ? val.toDouble() : double.tryParse(val?.toString() ?? '0') ?? 0;
            }
            final mean = colSum / total;
            perfData['p${i}_mean'] = mean;
            perfSum += mean;
            means.add({'label': 'P$i', 'score': mean, 'category': 'Performance'});
          }
          _perfScore = perfSum / 10;
          _perfData = perfData;
        }
      }

      _overallScore = (_mgmtScore + _perfScore) / 2;
      debugPrint('[SubjectDetailScreen] =========================================');
      debugPrint('[SubjectDetailScreen] Subject: $subjectCode | Term: $activeTermId');
      debugPrint('[SubjectDetailScreen] Subject IDs resolved: $subjectIds');
      debugPrint('[SubjectDetailScreen] mgmtRows from management_results: ${mgmtRows.length}');
      debugPrint('[SubjectDetailScreen] perfRows from performance_results: ${perfRows.length}');
      for (var id in subjectIds) {
        final mg = bestMgmt[id];
        final pf = bestPerf[id];
        debugPrint('[SubjectDetailScreen]   subj_id=$id');
        if (mg != null) {
          debugPrint('[SubjectDetailScreen]     mgmt: overall=${mg["overall_management_mean"]} | responses=${mg["total_responses"]} | created_at=${mg["created_at"]}');
        } else {
          debugPrint('[SubjectDetailScreen]     mgmt: NO ROW FOUND');
        }
        if (pf != null) {
          debugPrint('[SubjectDetailScreen]     perf: overall=${pf["overall_performance_mean"]} | responses=${pf["total_responses"]} | created_at=${pf["created_at"]}');
        } else {
          debugPrint('[SubjectDetailScreen]     perf: NO ROW FOUND');
        }
      }
      debugPrint('[SubjectDetailScreen] hasPrecomputed=$hasPrecomputed');
      debugPrint('[SubjectDetailScreen] FINAL: mgmt=$_mgmtScore | perf=$_perfScore | overall=$_overallScore | respondents=$_totalResponses');
      debugPrint('[SubjectDetailScreen] =========================================');

      if (mounted) {
        setState(() {
          _questionMeans = means;
          _subjectRemarks = remarkRows.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[SubjectDetailScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // -- Filtered remarks getter ------------------------------
  List<Map<String, dynamic>> get _filteredRemarks {
    List<Map<String, dynamic>> filtered = List.from(_subjectRemarks);
    if (_selectedFilter != 'All') {
      filtered = filtered.where((r) => (r['tone'] ?? 'Neutral') == _selectedFilter).toList();
    }
    
    filtered.sort((a, b) {
      if (_sortOrder == 'Date (Newest)') {
        final dateA = a['created_at'] != null ? DateTime.parse(a['created_at']) : DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b['created_at'] != null ? DateTime.parse(b['created_at']) : DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      } else if (_sortOrder == 'Date (Oldest)') {
        final dateA = a['created_at'] != null ? DateTime.parse(a['created_at']) : DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b['created_at'] != null ? DateTime.parse(b['created_at']) : DateTime.fromMillisecondsSinceEpoch(0);
        return dateA.compareTo(dateB);
      } else if (_sortOrder == 'Sentiment (Positive First)') {
        final weightA = _sentimentWeight(a['tone'] ?? 'Neutral');
        final weightB = _sentimentWeight(b['tone'] ?? 'Neutral');
        return weightB.compareTo(weightA);
      } else if (_sortOrder == 'Sentiment (Critical First)') {
        final weightA = _sentimentWeight(a['tone'] ?? 'Neutral');
        final weightB = _sentimentWeight(b['tone'] ?? 'Neutral');
        return weightA.compareTo(weightB);
      }
      return 0;
    });

    return filtered;
  }

  int _sentimentWeight(String sentiment) {
    if (sentiment == 'Positive') return 3;
    if (sentiment == 'Neutral') return 2;
    return 1;
  }

  // -- Premium filter row -----------------------------------
  Widget _buildFilterRow() {
    final filters = [
      {'label': 'All',      'icon': Icons.all_inclusive_rounded,           'color': AppColors.primaryText,   'count': _subjectRemarks.length},
      {'label': 'Positive', 'icon': Icons.sentiment_very_satisfied_rounded, 'color': AppColors.success,       'count': _subjectRemarks.where((r) => r['tone'] == 'Positive').length},
      {'label': 'Neutral',  'icon': Icons.sentiment_neutral_rounded,        'color': AppColors.textSecondary, 'count': _subjectRemarks.where((r) => (r['tone'] ?? 'Neutral') == 'Neutral').length},
      {'label': 'Critical', 'icon': Icons.sentiment_dissatisfied_rounded,   'color': AppColors.error,         'count': _subjectRemarks.where((r) => r['tone'] == 'Critical').length},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final label    = f['label']   as String;
          final icon     = f['icon']    as IconData;
          final color    = f['color']   as Color;
          final count    = f['count']   as int;
          final selected = _selectedFilter == label;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: selected ? color : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? color : color.withValues(alpha: 0.3),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                    : [],
              ),
              child: InkWell(
                onTap: () => setState(() => _selectedFilter = label),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: selected ? Colors.white : color),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.25)
                              : color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
        title: Text(widget.subject.code, style: const TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _fetchSubjectDetails,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.subject.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary, overflow: TextOverflow.ellipsis)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('Total Respondents: $_totalResponses', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Summary Cards
                    Row(
                      children: [
                        _buildSummaryCard('Management', _mgmtScore, AppColors.primaryText),
                        const SizedBox(width: 16),
                        _buildSummaryCard('Performance', _perfScore, AppColors.success),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSummaryCard(
                      'Overall Weighted Mean', 
                      _overallScore, 
                      Subject.getScoreColor(_overallScore),
                      isFullWidth: true,
                    ),
                    const SizedBox(height: 32),

                    // Management Table
                    _buildSectionHeader('I. Management Breakdown'),
                    const SizedBox(height: 12),
                    _buildCriteriaTable(_managementCriteria, _mgmtData, 'm', AppColors.primary),
                    const SizedBox(height: 32),

                    // Performance Table
                    _buildSectionHeader('II. Performance Breakdown'),
                    const SizedBox(height: 12),
                    _buildCriteriaTable(_performanceCriteria, _perfData, 'p', AppColors.success),
                    const SizedBox(height: 32),

                    // Question Chart
                    _buildSectionHeader('Per-Question Visualization'),
                    const SizedBox(height: 16),
                    Container(
                      height: 220,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.borderHairline),
                      ),
                      child: _questionMeans.isEmpty 
                        ? const Center(child: Text("No question data available"))
                        : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: _questionMeans.map((q) {
                              double barHeight = (q['score'] / 5.0) * 120;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(q['score'].toStringAsFixed(2), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 14,
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color: q['category'] == 'Management' ? AppColors.primary : AppColors.success,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(q['label'], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ),
                    const SizedBox(height: 32),

                    // Subject-specific remarks
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader('Student Feedback'),
                        Text(
                          '${_filteredRemarks.length} of ${_subjectRemarks.length}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Filter chips
                    _buildFilterRow(),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _sortOrder,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: AppColors.surface,
                      ),
                      icon: const Icon(Icons.sort, color: AppColors.primaryText),
                      items: _sortOptions.map((String option) {
                        return DropdownMenuItem<String>(value: option, child: Text(option, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _sortOrder = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_subjectRemarks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text('No feedback yet for this subject.',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    else if (_filteredRemarks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text('No ${_selectedFilter.toLowerCase()} feedback for this subject.',
                              style: const TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    else
                      ..._filteredRemarks.map((remark) => _buildRemarkCard(remark)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title, 
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
    );
  }

  Widget _buildCriteriaTable(List<String> criteria, Map<String, dynamic>? data, String prefix, Color themeColor) {
    if (data == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderHairline),
        ),
        child: const Center(child: Text("No detailed data available for this section")),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(40),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(50),
            3: FixedColumnWidth(40),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.1)),
              children: [
                _buildTableCell('No.', isHeader: true),
                _buildTableCell('Criteria', isHeader: true),
                _buildTableCell('Mean', isHeader: true),
                _buildTableCell('VD', isHeader: true),
              ],
            ),
            ...criteria.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final mean = (data['$prefix${idx}_mean'] as num?)?.toDouble() ?? 0.0;
              return TableRow(
                children: [
                  _buildTableCell('$idx'),
                  _buildTableCell(entry.value, align: TextAlign.left),
                  _buildTableCell(mean.toStringAsFixed(2), fontWeight: FontWeight.bold),
                  _buildTableCell(Subject.getVDCode(mean), fontWeight: FontWeight.bold, color: _getScoreColor(mean)),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, TextAlign align = TextAlign.center, FontWeight? fontWeight, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: isHeader ? 12 : 11,
          fontWeight: isHeader ? FontWeight.bold : (fontWeight ?? FontWeight.normal),
          color: isHeader ? AppColors.textPrimary : (color ?? AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildRemarkCard(Map<String, dynamic> remark) {
    final tone = remark['tone'] ?? 'Neutral';
    Color toneColor = tone == 'Positive'
        ? AppColors.success
        : tone == 'Critical'
            ? AppColors.error
            : AppColors.textSecondary;
    IconData toneIcon = tone == 'Positive'
        ? Icons.sentiment_very_satisfied_rounded
        : tone == 'Critical'
            ? Icons.sentiment_dissatisfied_rounded
            : Icons.sentiment_neutral_rounded;

    return Card(
      color: AppColors.surface,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: toneColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${remark['remark']}"',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(toneIcon, color: toneColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  tone,
                  style: TextStyle(color: toneColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  remark['created_at'] != null ? DateTime.parse(remark['created_at']).toLocal().toString().split(' ')[0] : 'Unknown',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, double score, Color color, {bool isFullWidth = false}) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Text(score.toStringAsFixed(2), style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          if (isFullWidth)
            Text(
              Subject.getVerbalDescription(score),
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );

    if (isFullWidth) return card;
    return Expanded(child: card);
  }

  Color _getScoreColor(double score) {
    return Subject.getScoreColor(score);
  }
}