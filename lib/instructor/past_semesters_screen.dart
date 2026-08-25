// Screen for viewing all past semesters with evaluation scores.
// Basically the "history tab" — where you see how far you've come, or how far you fell.
// Pull-to-refresh works, bar chart is tappable, murag interactive siya. importente.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import 'models/subject.dart';
import 'subject_detail_screen.dart';
import 'detailed_report_screen.dart';
import 'widgets/subject_card.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';

// StatefulWidget because we fetch data from Supabase and manage selected term state
class PastSemestersScreen extends StatefulWidget {
  final String userId;
  const PastSemestersScreen({super.key, required this.userId});

  @override
  State<PastSemestersScreen> createState() => _PastSemestersScreenState();
}

class _PastSemestersScreenState extends State<PastSemestersScreen> {
  final _supabase = Supabase.instance.client;

  // General loading flag — true while fetching term history
  bool _isLoading = true;
  // Separate flag for when we're loading a specific term's subjects — so the rest of UI stays visible
  bool _isTermLoading = false;
  // All historical term data — list of maps with scores and term info
  List<Map<String, dynamic>> _historicalData = [];
  // The currently selected term ID in the dropdown — drives which subjects show below
  String? _selectedTermId;
  // The subjects taught in the selected term
  List<Map<String, dynamic>> _selectedTermSubjects = [];
  
  @override
  void initState() {
    super.initState();
    _fetchHistory(); // start fetching all historical terms right away
  }

  // Fetches all terms where this instructor has evaluation summaries.
  // Also determines which term to show by default (current term or the latest one).
  Future<void> _fetchHistory() async {
    try {
      if (mounted) setState(() => _isLoading = true);

      // Fetch all terms where this instructor has an overall summary
      // Run both queries in parallel — current term ID and history data
      final responses = await Future.wait<dynamic>([
        _supabase.from('system_settings').select('current_term_id').maybeSingle(),
        _supabase.from('overall_total_survey').select('*, academic_terms(*)').eq('instructor_id', widget.userId),
      ]);

      final currentTermId = responses[0]?['current_term_id'];
      final summaries = responses[1] as List;

      // Use a map to deduplicate by term ID — one entry per term
      Map<String, Map<String, dynamic>> termsMap = {};

      for (var item in summaries) {
        final tid = item['term_id'];
        if (tid == null) continue; // skip rows with no term ID, bahala na
        final termData = item['academic_terms'];
        
        termsMap[tid] = {
          'termId': tid,
          'semester': termData != null 
              ? '${termData['semester']} ${termData['academic_year']}'
              : 'Unknown Term', // fallback if academic_terms join is null
          'created_at': termData?['created_at'] ?? item['created_at'] ?? '',
          'overallScore': (item['combined_score_mean'] as num?)?.toDouble() ?? (item['overall_mean'] as num?)?.toDouble() ?? 0.0,
          'managementScore': (item['management_mean'] as num?)?.toDouble() ?? 0.0,
          'performanceScore': (item['performance_mean'] as num?)?.toDouble() ?? 0.0,
          'evaluations': (item['total_responses'] as int?) ?? 0,
        };
      }

      List<Map<String, dynamic>> processedData = termsMap.values.toList();
      // Sort chronologically: oldest academic year first, then 1st → 2nd → Summer within year
      processedData.sort((a, b) {
        final semOrder = {'1st': 0, '2nd': 1, 'Sum': 2, 'Summer': 2};
        final aSem = a['semester']?.toString() ?? '';
        final bSem = b['semester']?.toString() ?? '';
        // Extract start year from academic_year e.g. "2025-2026" → 2025
        int aYear = 0, bYear = 0;
        int aSemIdx = 99, bSemIdx = 99;
        final aParts = aSem.split(' ');
        final bParts = bSem.split(' ');
        if (aParts.length >= 3) {
          aYear = int.tryParse(aParts.last.split('-').first) ?? 0;
          aSemIdx = semOrder[aParts[0]] ?? 99;
        }
        if (bParts.length >= 3) {
          bYear = int.tryParse(bParts.last.split('-').first) ?? 0;
          bSemIdx = semOrder[bParts[0]] ?? 99;
        }
        if (aYear != bYear) return aYear.compareTo(bYear);
        return aSemIdx.compareTo(bSemIdx);
      });

      if (mounted) {
        setState(() {
          _historicalData = processedData;
          
          if (_selectedTermId == null) {
            // Try to default to current term if it's in history, else last historical term
            if (processedData.any((t) => t['termId'] == currentTermId)) {
              _selectedTermId = currentTermId; // current term is in history, select it
            } else if (processedData.isNotEmpty) {
              _selectedTermId = processedData.last['termId']; // just pick the latest one
            }
          }
          _isLoading = false;
        });

        // Load subjects for the auto-selected term
        if (_selectedTermId != null) {
          _loadSelectedTermData(_selectedTermId!);
        }
      }
    } catch (e) {
      debugPrint('Error fetching history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Loads subjects for a specific selected term.
  // This is the complex one — junction tables, weighted aggregation, and fallback to raw data.
  // Pray lang everything is in the precomputed tables. Wala choice if not.
  Future<void> _loadSelectedTermData(String termId) async {
    try {
      if (mounted) setState(() => _isTermLoading = true);

      debugPrint('[PastSemesters] =========================================');
      debugPrint('[PastSemesters] LOAD TERM: ${widget.userId} | term=$termId');
      // 1. Get subjects for this instructor+term via instructor_subjects junction table.
      final subjectsList = await _supabase
          .from('instructor_subjects')
          .select('subject_id, subjects(id, subject_code, subject_name, department_id)')
          .eq('instructor_id', widget.userId)
          .eq('term_id', termId);

      if ((subjectsList as List).isEmpty) {
        // No subjects linked to this instructor for this term — empty result
        if (mounted) setState(() { _selectedTermSubjects = []; _isTermLoading = false; });
        return;
      }

      // Build lookup maps: subject_id → subject metadata, and subject_code → list of IDs
      // Multiple IDs per code because same subject can have multiple sections
      final Map<String, Map<String, dynamic>> subjectById = {};
      final Map<String, List<String>> codeToIds = {};
      for (var row in subjectsList) {
        final subjectData = row['subjects'];
        if (subjectData == null) continue;
        final s = Map<String, dynamic>.from(
          subjectData is List ? subjectData[0] : subjectData,
        );
        final id = s['id']?.toString();
        final code = s['subject_code']?.toString();
        if (id == null || code == null) continue;
        subjectById.putIfAbsent(id, () => s);
        codeToIds.putIfAbsent(code, () => []).add(id); // group sections by subject code
      }

      final validSubjectIds = subjectById.keys.toList();

      // 2. Fetch pre-computed results for ONLY the valid subject IDs.
      //    Order by created_at DESC so the most recent (corrected) row comes first.
      final results = await Future.wait([
        _supabase
            .from('management_results')
            .select('subject_id, overall_management_mean, total_responses, created_at')
            .eq('instructor_id', widget.userId)
            .eq('term_id', termId)
            .filter('subject_id', 'in', validSubjectIds)
            .order('created_at', ascending: false), // newest row = most accurate
        _supabase
            .from('performance_results')
            .select('subject_id, overall_performance_mean, total_responses, created_at')
            .eq('instructor_id', widget.userId)
            .eq('term_id', termId)
            .filter('subject_id', 'in', validSubjectIds)
            .order('created_at', ascending: false),
      ]);

      final mgmtRows = results[0] as List;
      final perfRows = results[1] as List;

      // Best (most recent) row per subject_id — only keep the first occurrence since sorted DESC
      final Map<String, Map<String, dynamic>> bestMgmt = {};
      for (var row in mgmtRows) {
        final sid = row['subject_id']?.toString();
        if (sid != null && !bestMgmt.containsKey(sid)) {
          bestMgmt[sid] = Map<String, dynamic>.from(row); // first = most recent
        }
      }
      final Map<String, Map<String, dynamic>> bestPerf = {};
      for (var row in perfRows) {
        final sid = row['subject_id']?.toString();
        if (sid != null && !bestPerf.containsKey(sid)) {
          bestPerf[sid] = Map<String, dynamic>.from(row);
        }
      }

      // 3. Build subject list — one entry per unique subject_code.
      //    Aggregate across sections (weighted by total_responses).
      // This ensures that if a subject has 2 sections, we combine them properly.
      List<Map<String, dynamic>> processed = [];

      for (var entry in codeToIds.entries) {
        final code = entry.key;
        final ids = entry.value;
        final meta = subjectById[ids.first]!; // use first section's metadata for display

        // Weighted sum for management — weight each section by its number of responses
        double mWeightedSum = 0, pWeightedSum = 0;
        int mTotal = 0, pTotal = 0;

        for (var id in ids) {
          final mgmt = bestMgmt[id];
          if (mgmt != null) {
            final n = (mgmt['total_responses'] as num?)?.toInt() ?? 0;
            final mean = (mgmt['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
            mWeightedSum += mean * n; // weighted contribution
            mTotal += n;
          }
          final perf = bestPerf[id];
          if (perf != null) {
            final n = (perf['total_responses'] as num?)?.toInt() ?? 0;
            final mean = (perf['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
            pWeightedSum += mean * n;
            pTotal += n;
          }
        }

        // Final weighted average for this subject code
        double mMean = mTotal > 0 ? mWeightedSum / mTotal : 0.0;
        double pMean = pTotal > 0 ? pWeightedSum / pTotal : 0.0;

        // Fallback to raw data if no pre-computed results — bahala na last resort
        if (mMean == 0.0 && pMean == 0.0) {
          debugPrint('[PastSemesters] No precomputed data for $code in $termId, using raw...');
          final rawData = await _supabase
              .from('sast_all_raw_data_survey')
              .select('m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10')
              .filter('subject_id', 'in', ids)
              .eq('instructor_ID', widget.userId)
              .eq('term_id', termId);

          if ((rawData as List).isNotEmpty) {
            double mSum = 0, pSum = 0;
            // Sum all 10 management and 10 performance columns across all rows
            for (var row in rawData) {
              for (int i = 1; i <= 10; i++) {
                mSum += (row['m$i'] as num?)?.toDouble() ?? 0.0;
                pSum += (row['p$i'] as num?)?.toDouble() ?? 0.0;
              }
            }
            // Divide by (total rows * 10 questions) to get mean per question
            mMean = mSum / (rawData.length * 10);
            pMean = pSum / (rawData.length * 10);
          }
        }

        // Debug logs — very verbose, but helpful when things go wrong
        debugPrint('[PastSemesters] ─────────────────────────────────');
        debugPrint('[PastSemesters] Subject: $code | Term: $termId');
        debugPrint('[PastSemesters]   Subject IDs (this term): $ids');
        for (var id in ids) {
          final mg = bestMgmt[id];
          final pf = bestPerf[id];
          debugPrint('[PastSemesters]   subj_id=$id');
          if (mg != null) {
            debugPrint('[PastSemesters]     mgmt: overall=${mg["overall_management_mean"]} | responses=${mg["total_responses"]} | created=${mg["created_at"]}');
          } else {
            debugPrint('[PastSemesters]     mgmt: NO ROW FOUND');
          }
          if (pf != null) {
            debugPrint('[PastSemesters]     perf: overall=${pf["overall_performance_mean"]} | responses=${pf["total_responses"]} | created=${pf["created_at"]}');
          } else {
            debugPrint('[PastSemesters]     perf: NO ROW FOUND');
          }
        }
        debugPrint('[PastSemesters]   FINAL → mgmt=$mMean | perf=$pMean');

        // Add the processed subject to our result list
        processed.add({
          ...meta,
          'management_mean': mMean,
          'performance_mean': pMean,
        });
      }

      // Sort subjects alphabetically by code for consistent ordering
      processed.sort((a, b) => (a['subject_code'] ?? '').compareTo(b['subject_code'] ?? ''));

      if (mounted) {
        setState(() {
          _selectedTermSubjects = processed;
          _isTermLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[PastSemesters] Error loading term data: $e');
      if (mounted) setState(() => _isTermLoading = false);
    }
  }

  // Getter for the currently selected term's summary data.
  // Looks up the selected term ID in the history list — returns null if not found.
  Map<String, dynamic>? get _selectedTermData {
    if (_selectedTermId == null || _historicalData.isEmpty) return null;
    final matches = _historicalData.where((t) => t['termId'] == _selectedTermId);
    // If no exact match, return the last one as fallback — bahala na
    return matches.isNotEmpty ? matches.first : _historicalData.last;
  }

  @override
  Widget build(BuildContext context) {
    final termData = _selectedTermData;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: AppColors.textInverted,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E1608), AppColors.textPrimary],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textInverted),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textInverted),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Past Terms',
            style: TextStyle(
                color: AppColors.textInverted,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textInverted),
            tooltip: 'Refresh',
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : RefreshIndicator(
        onRefresh: _fetchHistory, // pull-to-refresh also re-fetches history
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // needed for pull-to-refresh even on short content
          padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page title and subtitle
            const Text('Historical Growth',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.1,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('Track your evaluation scores across previous academic terms.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 24),

            // Interactive bar chart showing all historical term scores
            Entrance(child: _buildTrendGraph()),

            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Term Filter'.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.textSecondary)),
                // Show "Full Term Report" button only when a term with data is selected
                if (termData != null && termData.isNotEmpty)
                  Pressable(
                    child: TextButton.icon(
                    onPressed: () {
                      // Get instructor name from user metadata — not ideal but wala pa better source here
                      final name = _supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'Instructor';
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailedReportScreen(
                        userId: widget.userId,
                        instructorName: name,
                        department: 'Faculty', // hardcoded for now — not great but acceptable
                        termId: _selectedTermId,
                        // Parse semester and academic year from combined string
                        term: termData['semester']?.toString().split(' ')[0] ?? '',
                        academicYear: termData['semester']?.toString().contains(' ') == true ? termData['semester']?.toString().split(' ').sublist(1).join(' ') ?? '' : '',
                        managementScore: (termData['managementScore'] as num?)?.toDouble() ?? 0.0,
                        performanceScore: (termData['performanceScore'] as num?)?.toDouble() ?? 0.0,
                        overallScore: (termData['overallScore'] as num?)?.toDouble() ?? 0.0,
                        totalEvaluations: (termData['evaluations'] as int?) ?? 0,
                      )));
                    },
                    icon: const Icon(Icons.description, size: 16),
                    label: const Text('Full Term Report',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      backgroundColor: AppColors.primaryTint,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100)),
                    ),
                  ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Dropdown to select which term to view subjects for
            if (_historicalData.isNotEmpty)
              Entrance(
                index: 1,
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTermId,
                    isExpanded: true,
                    hint: const Text('Select Term'),
                    // Show terms newest first in dropdown — reversed list
                    items: _historicalData.reversed.map((t) {
                      return DropdownMenuItem(
                        value: t['termId'] as String,
                        child: Text(t['semester']),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedTermId = val); // update selected term
                        _loadSelectedTermData(val); // and load its subjects
                      }
                    },
                  ),
                ),
              ),
              )
            else
              // No history at all — maybe the instructor is brand new
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryTint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history_rounded,
                            color: AppColors.primaryText, size: 26),
                      ),
                      const SizedBox(height: 12),
                      const Text('No historical data found.',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subjects Taught'.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.textSecondary)),
                // Show count of subjects for selected term when not loading
                if (!_isTermLoading)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('${_selectedTermSubjects.length} Subjects',
                        style: const TextStyle(
                            color: AppColors.primaryText,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Either show loading, empty message, or list of subject cards
            if (_isTermLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppColors.primary)))
            else if (_selectedTermSubjects.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryTint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.menu_book_rounded,
                            color: AppColors.primaryText, size: 26),
                      ),
                      const SizedBox(height: 12),
                      const Text('No subjects found for this term.',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ],
                  ),
                ),
              )
            else
              // Map each subject data into a Subject model and render a SubjectCard
              ..._selectedTermSubjects.asMap().entries.map((entry) {
                final s = entry.value;
                final subjectObj = Subject.fromJson({
                  ...s,
                  'management_mean': s['management_mean'],
                  'performance_mean': s['performance_mean'],
                  // Use fallback date if created_at is missing — dili null ang date pls
                  'created_at': s['created_at'] ?? termData?['created_at'] ?? DateTime.now().toIso8601String(),
                });
                return Entrance(
                  index: entry.key.clamp(0, 8),
                  child: SubjectCard(
                  subject: subjectObj,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectDetailScreen(subject: subjectObj, userId: widget.userId, termId: _selectedTermId!))),
                ),
                );
              }),
          ],
        ),
      ),
      ),
    );
  }

  // Builds the dark gradient bar chart showing performance trend across all terms.
  // Each bar is tappable — clicking it selects that term and loads its subjects.
  Widget _buildTrendGraph() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1608), AppColors.textPrimary],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // soft orange glow, upper right — echoes the login hero
            Positioned(
              top: -70,
              right: -50,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.30),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Performance Trend',
                      style: TextStyle(
                          color: AppColors.textInverted,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 180,
                    child: _historicalData.isEmpty
                        // No data at all — cannot draw bars, show placeholder text
                        ? const Center(child: Text('No data available', style: TextStyle(color: AppColors.textInvertedDim)))
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: _historicalData.map((data) {
                              double score = (data['overallScore'] as num?)?.toDouble() ?? 0.0;
                              // Bar height proportional to score out of 5 — max 120px
                              double h = (score / 5.0) * 120;
                              bool isSel = data['termId'] == _selectedTermId; // highlight selected term
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Score label above the bar
                                  Text(score.toStringAsFixed(2), style: TextStyle(color: isSel ? AppColors.primary : AppColors.textInvertedDim, fontSize: 11, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  // Tappable bar — clicking selects this term
                                  Pressable(
                                    child: GestureDetector(
                                    onTap: () {
                                      setState(() => _selectedTermId = data['termId']);
                                      _loadSelectedTermData(data['termId']); // load this term's subjects
                                    },
                                    child: Container(
                                      width: 30,
                                      height: h.clamp(5, 120), // minimum height 5px so it's always visible
                                      decoration: BoxDecoration(
                                        gradient: isSel
                                            ? const LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [AppColors.primary, AppColors.primaryDeep],
                                              )
                                            : null,
                                        color: isSel ? null : AppColors.textInvertedFaint, // highlight selected
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: isSel
                                            ? [
                                                BoxShadow(
                                                  color: AppColors.primary.withValues(alpha: 0.4),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                  ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Short label below bar: "1st\n25-26" so different years are distinguishable
                                  SizedBox(
                                    width: 40,
                                    child: Builder(builder: (_) {
                                      final full = data['semester']?.toString() ?? '';
                                      // full = "1st Semester 2025-2026"
                                      final parts = full.split(' ');
                                      final ordinal = parts.isNotEmpty ? parts[0] : full; // "1st"
                                      // academic_year is the last token e.g. "2025-2026" → shorten to "25-26"
                                      String yearShort = '';
                                      if (parts.length >= 3) {
                                        final ay = parts.last; // "2025-2026"
                                        final ayParts = ay.split('-');
                                        if (ayParts.length == 2) {
                                          yearShort = '${ayParts[0].length >= 2 ? ayParts[0].substring(ayParts[0].length - 2) : ayParts[0]}-'
                                              '${ayParts[1].length >= 2 ? ayParts[1].substring(ayParts[1].length - 2) : ayParts[1]}';
                                        } else {
                                          yearShort = ay;
                                        }
                                      }
                                      final label = yearShort.isNotEmpty ? '$ordinal\n$yearShort' : ordinal;
                                      return Text(
                                        label,
                                        style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 11),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      );
                                    }),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
