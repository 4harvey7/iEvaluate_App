import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'models/subject.dart';
import '../widgets/apple_ui.dart';
import '../core/services/term_aware_state.dart';
import '../core/utils/sast_rating.dart';
import '../core/services/eval_results_service.dart';
import '../widgets/eval_report_widgets.dart';

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

class _SubjectDetailScreenState extends State<SubjectDetailScreen>
    with TermAwareState<SubjectDetailScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  // New 15-item report (SET / SUP). When set, it replaces the old-form view.
  EvalReport? _evalReport;
  // Stored means for this subject. Null = nobody answered (shown as "—").
  double? _mgmtScore;
  double? _perfScore;
  double? _overallScore;
  int _totalResponses = 0;
  // Set when a legacy entry (no subject id) matched several class records and
  // only the most recent one could be shown.
  String? _sourceNote;
  List<Map<String, dynamic>> _questionMeans = [];
  List<Map<String, dynamic>> _subjectRemarks = [];
  Map<String, dynamic>? _mgmtData;
  Map<String, dynamic>? _perfData;
  // Whether each breakdown table is expanded. Both start open so nothing looks
  // missing; the arrow in each section header collapses them.
  bool _mgmtExpanded = true;
  bool _perfExpanded = true;

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

  // Reload when the SAO office switches the active term, instead of
  // showing the previous term's figures until this screen is rebuilt.
  @override
  void onTermChanged() {
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

      // New-form term: this subject has eval_results rows, use the new view.
      final ownSubjectId = widget.subject.id;
      final evalReport = await EvalResultsService.load(
        instructorId: widget.userId,
        termId: activeTermId,
        subjectId: (ownSubjectId != null && ownSubjectId.isNotEmpty) ? ownSubjectId : null,
      );
      if (evalReport != null && evalReport.student != null) {
        // The toned remarks are keyed by instructor + term + subject (student_remarks), not by form.
        List<Map<String, dynamic>> toned = const [];
        if (ownSubjectId != null && ownSubjectId.isNotEmpty) {
          try {
            final rows = await _supabase
                .from('student_remarks')
                .select('remark, tone, created_at')
                .eq('subject_id', ownSubjectId)
                .eq('instructor_id', widget.userId)
                .eq('term_id', activeTermId)
                .order('created_at', ascending: false);
            toned = (rows as List).cast<Map<String, dynamic>>();
          } catch (e) {
            debugPrint('[SubjectDetailScreen] student_remarks not loaded: $e');
          }
        }
        if (mounted) setState(() { _evalReport = evalReport; _subjectRemarks = toned; _isLoading = false; });
        return;
      }
      if (mounted && _evalReport != null) setState(() => _evalReport = null);

      final subjectCode = widget.subject.code;
      debugPrint('[SubjectDetailScreen] Fetching "$subjectCode" in term "$activeTermId"');

      // 2. Which subject row to show.
      //    The card that opened this screen is ONE subject row (SubjectsProvider
      //    builds one card per subject id), so its id is used directly and the
      //    screen shows that row's stored results as-is. Results are never
      //    averaged across rows in Dart: that is what produced numbers a
      //    teacher could not reproduce from the report.
      //    Only an entry without an id (older cache) falls back to the code.
      List<String> subjectIds;
      final ownId = widget.subject.id;
      if (ownId != null && ownId.isNotEmpty) {
        subjectIds = [ownId];
      } else {
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
        subjectIds = (subjectRows as List).map((s) => s['subject_id'].toString()).toList();
      }

      debugPrint('[SubjectDetailScreen] Subject IDs: $subjectIds');

      if (subjectIds.isEmpty) {
        debugPrint('[SubjectDetailScreen] No subjects found for this code+term.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 3. Fetch the stored management_results / performance_results rows.
      //    select('*') on purpose: the m*_count / p*_count columns only exist
      //    once migration 013 is applied, and naming a missing column would
      //    make PostgREST reject the whole request. Missing counts are simply
      //    not shown.
      //    Order by created_at DESC so the most recent (corrected) row comes first.
      final precomputed = await Future.wait([
        _supabase
            .from('management_results')
            .select('*')
            .filter('subject_id', 'in', subjectIds)
            .eq('instructor_id', widget.userId)
            .eq('term_id', activeTermId)
            .order('created_at', ascending: false),
        _supabase
            .from('performance_results')
            .select('*')
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

      // 4. Pick the subject row to display: the most recent row (first, since
      //    ordered DESC). With an id there is only one subject. A legacy
      //    code-only entry that matches several class records shows the most
      //    recent one and says so, instead of blending them.
      String? shownId;
      if (mgmtRows.isNotEmpty) {
        shownId = mgmtRows.first['subject_id']?.toString();
      } else if (perfRows.isNotEmpty) {
        shownId = perfRows.first['subject_id']?.toString();
      }

      Map<String, dynamic>? mgmt;
      for (final row in mgmtRows) {
        if (row['subject_id']?.toString() == shownId) {
          mgmt = Map<String, dynamic>.from(row);
          break;
        }
      }
      Map<String, dynamic>? perf;
      for (final row in perfRows) {
        if (row['subject_id']?.toString() == shownId) {
          perf = Map<String, dynamic>.from(row);
          break;
        }
      }

      final rowsWithResults = <String>{
        for (final r in mgmtRows) r['subject_id']?.toString() ?? '',
        for (final r in perfRows) r['subject_id']?.toString() ?? '',
      }..remove('');

      // 5. Display the stored values as-is.
      //    Management = overall_management_mean (itself the average of the
      //    M1-M10 means shown below), Performance likewise, and Overall =
      //    ROUND((Management + Performance) / 2, 2) -- the same rule the
      //    backend uses for overall_total_survey. No per-subject combined value
      //    is stored, so this one line is the only arithmetic on this screen.
      final List<Map<String, dynamic>> means = [];
      final mgmtTotal = SastRating.parseInt(mgmt?['total_responses']);
      final perfTotal = SastRating.parseInt(perf?['total_responses']);
      if (mgmt != null) {
        for (int i = 1; i <= 10; i++) {
          means.add({'label': 'M$i', 'score': SastRating.parse(mgmt['m${i}_mean']), 'category': 'Management'});
        }
      }
      if (perf != null) {
        for (int i = 1; i <= 10; i++) {
          means.add({'label': 'P$i', 'score': SastRating.parse(perf['p${i}_mean']), 'category': 'Performance'});
        }
      }
      final mScore = SastRating.parse(mgmt?['overall_management_mean']);
      final pScore = SastRating.parse(perf?['overall_performance_mean']);

      debugPrint('[SubjectDetailScreen] Subject: $subjectCode | Term: $activeTermId | shown=$shownId');
      debugPrint('[SubjectDetailScreen] mgmt=$mScore (n=$mgmtTotal) | perf=$pScore (n=$perfTotal)');

      if (mounted) {
        setState(() {
          _mgmtScore = mScore;
          _perfScore = pScore;
          _overallScore = SastRating.combine(mScore, pScore);
          // Forms that answered at least one question in either category.
          _totalResponses = [mgmtTotal ?? 0, perfTotal ?? 0].reduce((a, b) => a > b ? a : b);
          _mgmtData = mgmt;
          _perfData = perf;
          _sourceNote = rowsWithResults.length > 1
              ? 'Showing the most recent of ${rowsWithResults.length} class records for $subjectCode.'
              : null;
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
        final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      } else if (_sortOrder == 'Date (Oldest)') {
        final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
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
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(widget.subject.code, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis)),
      ),
      body: _isLoading
          ? const AppleLoadingState(label: 'Loading subject analysis…')
          : RefreshIndicator(
              onRefresh: _fetchSubjectDetails,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ApplePageHeader(
                      eyebrow: widget.subject.code,
                      title: widget.subject.name,
                      subtitle: '${_evalReport?.student?.respondents ?? _totalResponses} total respondents',
                    ),
                    if (_sourceNote != null) ...[
                      const SizedBox(height: 6),
                      Text(_sourceNote!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 24),

                    if (_evalReport != null)
                      EvalReportView(report: _evalReport!)
                    else if (_mgmtData == null && _perfData == null) ...[
                      const AppleEmptyState(
                        icon: Icons.assessment_outlined,
                        title: 'No evaluation results yet',
                        message: 'Scores for this subject will appear here once its evaluation forms have been processed.',
                      ),
                      const SizedBox(height: 32),
                    ] else ...[

                    // Summary Cards — all three side by side.
                    // IntrinsicHeight so the boxes share one height even though
                    // the Overall card carries an extra description line.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'Management',
                              _mgmtScore,
                              AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildSummaryCard(
                              'Performance',
                              _perfScore,
                              AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildSummaryCard(
                              'Overall Weighted Mean',
                              _overallScore,
                              Subject.getScoreColor(_overallScore),
                              showDescription: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Management Table — collapsible
                    _buildCollapsibleSection(
                      title: 'I. Management Breakdown',
                      expanded: _mgmtExpanded,
                      onToggle: () =>
                          setState(() => _mgmtExpanded = !_mgmtExpanded),
                      child: _buildCriteriaTable(
                        _managementCriteria,
                        _mgmtData,
                        'm',
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Performance Table — collapsible
                    _buildCollapsibleSection(
                      title: 'II. Performance Breakdown',
                      expanded: _perfExpanded,
                      onToggle: () =>
                          setState(() => _perfExpanded = !_perfExpanded),
                      child: _buildCriteriaTable(
                        _performanceCriteria,
                        _perfData,
                        'p',
                        AppColors.success,
                      ),
                    ),
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
                              // Null = nobody answered this question: no bar, "—" label.
                              final double? qScore = q['score'] as double?;
                              final double barHeight = qScore == null ? 0 : (qScore / 5.0).clamp(0.0, 1.0) * 120;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(SastRating.format(qScore), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
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
                    ],

                    // Subject-specific remarks.
                    // The count goes in AppleSectionHeader's own `action` slot.
                    // It must NOT be wrapped in an outer Row: AppleSectionHeader
                    // is itself a Row containing an Expanded, so a Row parent
                    // hands it unbounded width, layout throws every frame and
                    // the render object never leaves NEEDS-LAYOUT — which pins
                    // the UI thread and shows up as an Android ANR.
                    AppleSectionHeader(
                      title: 'Student Feedback',
                      action: Text(
                        '${_filteredRemarks.length} of ${_subjectRemarks.length}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Filter chips
                    _buildFilterRow(),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _sortOrder,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: AppColors.surface,
                      ),
                      icon: const Icon(Icons.sort, color: AppColors.primary),
                      items: _sortOptions.map((String option) {
                        return DropdownMenuItem<String>(value: option, child: Text(option, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _sortOrder = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_subjectRemarks.isEmpty)
                      const AppleEmptyState(
                        icon: Icons.forum_outlined,
                        title: 'No feedback yet',
                        message: 'Student comments for this subject will appear here.',
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
    return AppleSectionHeader(title: title);
  }

  /// A section header with a show/hide arrow, and its content underneath.
  /// Tapping anywhere on the header row toggles it.
  Widget _buildCollapsibleSection({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            // The arrow goes in AppleSectionHeader's own `action` slot â€” it must
            // not be put in an outer Row, see the note at the Student Feedback
            // header below.
            child: AppleSectionHeader(
              title: title,
              action: AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.expand_more_rounded,
                  color: AppColors.textSecondary,
                  semanticLabel: expanded ? 'Hide $title' : 'Show $title',
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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
            2: FixedColumnWidth(64),
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
              // Stored mean; null (nobody answered) shows as "—", not 0.00.
              final mean = SastRating.parse(data['$prefix${idx}_mean']);
              // "(2 of 3 answered)" -- omitted for rows written before the
              // *_count columns existed.
              final answered = SastRating.answeredLabel(
                SastRating.parseInt(data['$prefix${idx}_count']),
                SastRating.parseInt(data['total_responses']),
              );
              return TableRow(
                children: [
                  _buildTableCell('$idx'),
                  _buildTableCell(entry.value, align: TextAlign.left),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(
                      children: [
                        Text(
                          SastRating.format(mean),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        if (answered != null)
                          Text(
                            answered,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
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
                  DateTime.tryParse(remark['created_at']?.toString() ?? '')?.toLocal().toString().split(' ')[0] ?? 'Unknown',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Returns a bare card. Callers wrap it in Expanded themselves â€” a helper
  /// that returns an Expanded hides a layout requirement from the call site,
  /// which is the class of bug that used to freeze this screen.
  Widget _buildSummaryCard(
    String title,
    double? score,
    Color color, {
    bool showDescription = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            SastRating.format(score),
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (showDescription) ...[
            const SizedBox(height: 2),
            Text(
              Subject.getVerbalDescription(score),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getScoreColor(double? score) {
    return Subject.getScoreColor(score);
  }
}
