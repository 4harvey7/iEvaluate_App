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
  String _selectedFilter = 'All'; // ← filter state
  List<Map<String, dynamic>> _questionMeans = [];
  List<Map<String, dynamic>> _subjectRemarks = [];
  int _totalResponses = 0;
  
  Map<String, dynamic>? _mgmtData;
  Map<String, dynamic>? _perfData;
  double _mgmtScore = 0.0;
  double _perfScore = 0.0;
  double _overallScore = 0.0;

  static const List<String> _managementCriteria = [
    'gives reasonable course/subject assignments',
    'earns appreciation and kind attention from the students',
    'gives orientation about the subject and how the students are evaluated',
    'gives tests and/or projects which are within the objectives of the course',
    'shows concern in assisting the students',
    'shows sympathetic insight into students\' feelings',
    'checks and records test papers/term papers promptly',
    'is on time and regular in meeting the class',
    'assigns fair subjects/course requirements',
    'sustains the attention of the class for the whole period',
  ];

  static const List<String> _performanceCriteria = [
    'presents lesson clearly, methodically, and substantially',
    'motivates the students to learn',
    'facilitates learning with the application of appropriate educational methods and techniques',
    'shows mastery of the lesson',
    'is prepared for the class',
    'inspires students\' self-reliance in their quest for knowledge',
    'knows when the students have difficulty understanding the lesson and finds ways to make it easy',
    'integrates values into the lesson',
    'speaks the language of instruction (English or Filipino) clearly and fluently',
    'delivers thought provoking questions',
  ];

  @override
  void initState() {
    super.initState();
    _fetchSubjectDetails();
  }

  Future<void> _fetchSubjectDetails() async {
    try {
      // 1. Resolve IDs and Terms
      String? activeTermId = widget.termId;
      if (activeTermId == null || activeTermId.isEmpty) {
        final settings = await _supabase.from('system_settings').select('current_term_id').maybeSingle();
        activeTermId = settings?['current_term_id'];
      }

      if (activeTermId == null || activeTermId.isEmpty) {
        debugPrint('SubjectDetailScreen: No active term ID found, aborting fetch.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Use the pre-resolved IDs from the Subject object if available.
      // These were already filtered to the correct term by SubjectsProvider,
      // so we never risk pulling in cross-term subject IDs.
      List<String> allIds;
      if (widget.subject.allRelatedIds.isNotEmpty) {
        allIds = widget.subject.allRelatedIds.toList();
        debugPrint('[SubjectDetailScreen] Using allRelatedIds from Subject: $allIds');
      } else {
        // Fallback: query subjects table filtered to the active term only
        allIds = widget.subject.id != null ? [widget.subject.id!] : [];
        final relatedSubjects = await _supabase
            .from('subjects')
            .select('id')
            .eq('subject_code', widget.subject.code)
            .eq('instructor_id', widget.userId)
            .eq('term_id', activeTermId);
        if (relatedSubjects is List && relatedSubjects.isNotEmpty) {
          allIds = (relatedSubjects as List).map((s) => s['id'].toString()).toSet().toList();
        }
        debugPrint('[SubjectDetailScreen] Fallback subject IDs from DB: $allIds');
      }

      debugPrint('[SubjectDetailScreen] Effective Subject IDs for query: $allIds');

      // 2. Prepare queries
      final mgmtQuery = _supabase
          .from('management_results')
          .select('*')
          .filter('subject_id', 'in', allIds)
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      final perfQuery = _supabase
          .from('performance_results')
          .select('*')
          .filter('subject_id', 'in', allIds)
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      final remarksQuery = _supabase
          .from('student_remarks')
          .select('remark, tone, created_at')
          .filter('subject_id', 'in', allIds)
          .eq('term_id', activeTermId);

      final responses = await Future.wait([
        mgmtQuery,
        perfQuery,
        remarksQuery.order('created_at', ascending: false),
      ]);

      final mgmtList = (responses[0] as List<dynamic>?) ?? [];
      final perfList = (responses[1] as List<dynamic>?) ?? [];
      final remarks = (responses[2] as List<dynamic>?) ?? [];

      debugPrint('[SubjectDetailScreen] mgmtList.length: ${mgmtList.length}');
      debugPrint('[SubjectDetailScreen] perfList.length: ${perfList.length}');

      // Merge results if multiple IDs exist
      Map<String, dynamic>? mgmt;
      Map<String, dynamic>? perf;

      if (mgmtList.isNotEmpty) {
        mgmt = Map<String, dynamic>.from(mgmtList.first);
        _totalResponses = (mgmt['total_responses'] as int?) ?? 0;
        debugPrint('[SubjectDetailScreen] Initial _totalResponses from mgmt: $_totalResponses');
        // If there are more, we technically should average them, but usually only one has summary data
        // For simplicity, we take the one with the most responses if multiple exist
        for (var m in mgmtList) {
           if ((m['total_responses'] ?? 0) > (mgmt!['total_responses'] ?? 0)) {
             mgmt = Map<String, dynamic>.from(m);
             _totalResponses = m['total_responses'];
           }
        }
      }

      if (perfList.isNotEmpty) {
        perf = Map<String, dynamic>.from(perfList.first);
        if (_totalResponses == 0) _totalResponses = (perf['total_responses'] as int?) ?? 0;
        debugPrint('[SubjectDetailScreen] _totalResponses after perf check: $_totalResponses');
        for (var p in perfList) {
           if ((p['total_responses'] ?? 0) > (perf!['total_responses'] ?? 0)) {
             perf = Map<String, dynamic>.from(p);
             _totalResponses = p['total_responses'];
           }
        }
      }

      // FALLBACK: If summary tables are empty for all linked IDs, calculate from RAW data
      if (mgmt == null && perf == null) {
        debugPrint('Subject summaries empty for term $activeTermId. Calculating from raw data fallback...');
        try {
          var query = _supabase
              .from('raw_GoogleSheet_data_result')
              .select('m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,remark,student_ID')
              .filter('subject_id', 'in', allIds)
              .eq('instructor_ID', widget.userId);

          // Apply term filter if available — critical to show current-term scores only
          if (activeTermId != null && activeTermId.isNotEmpty) {
            query = query.eq('term_id', activeTermId);
          }

          final rawResults = await query;
          
          debugPrint('[SubjectDetailScreen] rawResults.length: ${rawResults.length}');
          
          if (rawResults.isNotEmpty) {
            int total = rawResults.length;
            _totalResponses = total;
            
            // Reconstruct a pseudo-mgmt object
            Map<String, dynamic> fallbackMgmt = {'total_responses': total};
            for (int i = 1; i <= 10; i++) {
              double sum = 0;
              for (var r in rawResults) {
                var val = r['m$i'];
                sum += (val is num) ? val.toDouble() : double.tryParse(val?.toString() ?? '0') ?? 0;
              }
              fallbackMgmt['m${i}_mean'] = sum / total;
              debugPrint('[SubjectDetailScreen] m$i mean: ${fallbackMgmt['m${i}_mean']}');
            }
            mgmt = fallbackMgmt;

            // Reconstruct a pseudo-perf object
            Map<String, dynamic> fallbackPerf = {'total_responses': total};
            for (int i = 1; i <= 10; i++) {
              double sum = 0;
              for (var r in rawResults) {
                var val = r['p$i'];
                sum += (val is num) ? val.toDouble() : double.tryParse(val?.toString() ?? '0') ?? 0;
              }
              fallbackPerf['p${i}_mean'] = sum / total;
              debugPrint('[SubjectDetailScreen] p$i mean: ${fallbackPerf['p${i}_mean']}');
            }
            perf = fallbackPerf;
          }
        } catch (e) {
          debugPrint('Subject raw fallback failed: $e');
        }
      }

      List<Map<String, dynamic>> means = [];
      
      if (mgmt != null) {
        _mgmtData = mgmt;
        _totalResponses = mgmt['total_responses'] ?? 0;
        double mgmtSum = 0;
        for (int i = 1; i <= 10; i++) {
          double score = (mgmt['m${i}_mean'] as num?)?.toDouble() ?? 0.0;
          mgmtSum += score;
          means.add({
            'label': 'M$i',
            'score': score,
            'category': 'Management'
          });
        }
        _mgmtScore = mgmtSum / 10;
      }

      if (perf != null) {
        _perfData = perf;
        if (_totalResponses == 0) _totalResponses = perf['total_responses'] ?? 0;
        double perfSum = 0;
        for (int i = 1; i <= 10; i++) {
          double score = (perf['p${i}_mean'] as num?)?.toDouble() ?? 0.0;
          perfSum += score;
          means.add({
            'label': 'P$i',
            'score': score,
            'category': 'Performance'
          });
        }
        _perfScore = perfSum / 10;
      }
      
      _overallScore = (_mgmtScore + _perfScore) / 2;

      if (mounted) {
        setState(() {
          _questionMeans = means;
          _subjectRemarks = remarks.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching subject details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Filtered remarks getter ──────────────────────────────
  List<Map<String, dynamic>> get _filteredRemarks {
    if (_selectedFilter == 'All') return _subjectRemarks;
    return _subjectRemarks.where((r) => (r['tone'] ?? 'Neutral') == _selectedFilter).toList();
  }

  // ── Premium filter row ───────────────────────────────────
  Widget _buildFilterRow() {
    final filters = [
      {'label': 'All',      'icon': Icons.all_inclusive_rounded,           'color': AppColors.primary,       'count': _subjectRemarks.length},
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
        title: Text(widget.subject.code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
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
                    Text(widget.subject.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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
                        _buildSummaryCard('Management', _mgmtScore, AppColors.primary),
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
                        color: Colors.white, 
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
                                    Text(q['score'].toStringAsFixed(1), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
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
                                    Text(q['label'], style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
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
              final mean = (data['${prefix}${idx}_mean'] as num?)?.toDouble() ?? 0.0;
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
