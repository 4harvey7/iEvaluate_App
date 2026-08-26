// lib/sao_admin/performance_analysis_screen.dart
// The screen where admin can see how instructors perform — like a report card, but fancier.
// Has charts, term selector, department averages, and a leaderboard. Very prestige.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/evaluation_service.dart';
import '../core/services/pdf/pdf_service.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/safe_button.dart';
import '../widgets/apple_ui.dart';

// outer widget shell, nothing fancy yet
class PerformanceAnalysisScreen extends StatefulWidget {
  const PerformanceAnalysisScreen({super.key});

  @override
  State<PerformanceAnalysisScreen> createState() => _PerformanceAnalysisScreenState();
}

class _PerformanceAnalysisScreenState extends State<PerformanceAnalysisScreen> {
  final _evaluationService = EvaluationService(); // service that knows how to crunch eval numbers
  final _pdfService = PdfService(); // service that generates the PDF report for download
  final _supabase = Supabase.instance.client; // the database connection
  
  // Term selector — each entry: {id, label}
  // list of all academic terms for the dropdown
  List<Map<String, String>> _terms = [];
  String? _selectedTermId;   // actual UUID used for queries
  String _selectedLabel = 'Loading...'; // human-readable term label shown in UI
  bool _isInitialLoading = true; // true on first load, shows full-screen spinner
  bool _isRefreshing = false; // true when switching terms, shows spinner in dropdown

  // overview stats shown at the top of the dashboard
  Map<String, dynamic> _overviewStats = {
    'overall': '0.0', // university-wide average score
    'totalEvals': '0', // total evaluation responses this term
    'completion': '0%', // how many subjects have been evaluated
  };


  List<InstructorPerformance> _topInstructors = []; // ranked list of instructors by score

  // called once when screen opens — load everything
  @override
  void initState() {
    super.initState();
    _loadAllData(); // pray lang it loads fast
  }

  // loads terms first, then fetches analytics — order matters here
  Future<void> _loadAllData({bool isRefresh = false}) async {
    if (!isRefresh) {
      setState(() => _isInitialLoading = true);
    }
    await _loadTerms(); // fetch available terms from DB
    await _fetchRealAnalytics(); // fetch actual performance data for selected term
    if (!isRefresh && mounted) {
      setState(() => _isInitialLoading = false); // done, hide spinner
    }
  }

  /// Loads all academic terms from Supabase and selects the active one
  /// If the active term is not found in the list, falls back to the first term
  Future<void> _loadTerms() async {
    try {
      // Get active term from system_settings — this is the current semester
      final settings = await _supabase
          .from('system_settings')
          .select('current_term_id')
          .limit(1)
          .maybeSingle();
      final activeTermId = settings?['current_term_id'] as String?;

      // Fetch all terms sorted logically: newest academic year first, then semester
      final rows = await _supabase
          .from('academic_terms')
          .select('id, semester, academic_year')
          .order('academic_year', ascending: false)
          .order('semester', ascending: false);

      if (mounted) {
        setState(() {
          // convert raw rows into id+label maps for the dropdown
          _terms = (rows as List).map((r) {
            final isCurrent = r['id'] == activeTermId;
            return {
              'id': r['id'] as String,
              'label': '${r['semester']} ${r['academic_year']}${isCurrent ? ' (Current)' : ''}',
            };
          }).toList();

          // Select active term, or first if not found
          // basin wala active term set, so fallback to first available
          if (_terms.isNotEmpty) {
            final active = _terms.firstWhere(
              (t) => t['id'] == activeTermId,
              orElse: () => _terms.first, // fallback to first term in list
            );
            _selectedTermId = active['id'];
            _selectedLabel = active['label']!;
          }
        });
      }
    } catch (e) {
      debugPrint('loadTerms error: $e'); // log and move on, bahala na
    }
  }

  /// Called when the user picks a different term from the dropdown
  /// Re-fetches analytics for the newly selected term — dili ta keep old data
  Future<void> _onTermChanged(String termId) async {
    final label = _terms.firstWhere((t) => t['id'] == termId)['label']!;
    setState(() {
      _selectedTermId = termId; // update the selected term UUID
      _selectedLabel = label; // update the display label
      _isRefreshing = true; // show spinner in the dropdown while loading
    });
    await _fetchRealAnalytics(); // reload analytics for new term
    if (mounted) setState(() => _isRefreshing = false); // done refreshing
  }

  // fetch all analytics data from the evaluation service for the current term
  // this calls multiple service methods and stitches together the results
  Future<void> _fetchRealAnalytics() async {
    try {
      // these fetch in parallel inside the service
      final globalStats = await _evaluationService.getGlobalStats(termId: _selectedTermId);
      final topInstructors = await _evaluationService.getTopInstructors(termId: _selectedTermId);

      if (mounted) {
        setState(() {
          // getGlobalStats() returns {avgScore, totalInstructors, totalResponses}
          _overviewStats = {
            'overall': (globalStats['avgScore'] as double? ?? 0.0).toStringAsFixed(2), // round to 2 decimals
            'totalEvals': '${globalStats['totalResponses'] ?? 0}', // total survey responses
          };
          _topInstructors = topInstructors; // sorted list of instructor performances
        });
      }
    } catch (e) {
      debugPrint('Error fetching performance analytics: $e'); // log it, dili crash the screen
    }
  }

  // ==========================================
  // VIEW ALL INSTRUCTORS BOTTOM SHEET
  // shows a searchable list of all instructors with their scores
  // ==========================================
  void _showAllInstructors() {
    final searchController = TextEditingController();
    List<InstructorPerformance> filtered = List.from(_topInstructors); // start with all

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // DraggableScrollableSheet — can be pulled up or down by the user
          return DraggableScrollableSheet(
            initialChildSize: 0.85, // starts at 85% of screen height
            minChildSize: 0.5, // can be dragged down to 50%
            maxChildSize: 0.95, // can be stretched to 95%
            expand: false,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                // Handle bar at top — visual hint that you can drag this thing
                Container(width: 40, height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(color: AppColors.borderHairline, borderRadius: BorderRadius.circular(2))),
                // Header row with title and close button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.leaderboard, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('All Instructors (${filtered.length})', // shows count including search results
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                // Search bar — filter instructors by name or department
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: TextField(
                    controller: searchController,
                    onChanged: (q) => setSheetState(() {
                      // filter locally, no new DB call needed
                      filtered = _topInstructors.where((i) =>
                          i.name.toLowerCase().contains(q.toLowerCase()) ||
                          i.department.toLowerCase().contains(q.toLowerCase())).toList();
                    }),
                    decoration: InputDecoration(
                      hintText: 'Search by name or department...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // List of instructors — each card shows name, dept, and score
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final inst = filtered[i];
                      final score = inst.overallScore;
                      // color based on score: green=great, yellow=okay, red=low, gray=no data
                      final color = score >= 4.0 ? AppColors.success : score >= 3.0 ? AppColors.warning : score > 0 ? AppColors.error : AppColors.textTertiary;
                      return Card(
                        color: AppColors.surface,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          onTap: () {
                            Navigator.pop(ctx); // close this sheet first
                            _showInstructorDetailsSheet(inst); // then show details for this instructor
                          },
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Text(inst.name.isNotEmpty ? inst.name[0] : '?',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(inst.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis),
                          subtitle: Text(inst.department, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                          trailing: Text(
                            score > 0 ? score.toStringAsFixed(2) : '—', // show score or dash if no data
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // INSTRUCTOR DETAILS POP-UP (WITH ZOOMABLE CHART)
  // shows historical score chart and current term subject breakdown
  // ==========================================
  Future<void> _showInstructorDetailsSheet(InstructorPerformance instructor) async {
    // Fetch detailed info on demand — ayaw fetch this for all instructors at once
    final history = await _evaluationService.getInstructorHistory(instructor.id); // past term scores
    final subjects = await _evaluationService.getInstructorSubjects(instructor.id); // current term subjects

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        double chartScale = 1.0; // current zoom level of the bar chart

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85, // takes 85% of screen
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sticky Header — name, dept, and close button
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          child: Text(instructor.name[0], style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 24)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(instructor.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                              Text(instructor.department, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(context), // close the sheet
                        )
                      ],
                    ),
                  ),

                  // Scrollable Content — the chart and subject breakdown below
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text('Historical Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              ),
                              // zoom controls for the bar chart
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.zoom_out, color: AppColors.primary),
                                    onPressed: () {
                                      // don't zoom out past 60% or the bars become invisible
                                      if (chartScale > 0.6) setSheetState(() => chartScale -= 0.2);
                                    },
                                  ),
                                  Text('${(chartScale * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // current zoom %
                                  IconButton(
                                    icon: const Icon(Icons.zoom_in, color: AppColors.primary),
                                    onPressed: () {
                                      // max zoom is 250%, don't let them go nuts
                                      if (chartScale < 2.5) setSheetState(() => chartScale += 0.2);
                                    },
                                  ),
                                ],
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          // the bar chart container — scrollable horizontally if many terms
                          Container(
                            height: 220,
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                            child: history.isEmpty 
                              ? const Center(child: Text("No historical data available", style: TextStyle(color: AppColors.textSecondary)))
                              : SingleChildScrollView(
                                scrollDirection: Axis.horizontal, // horizontal scroll if many bars
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 80),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    crossAxisAlignment: CrossAxisAlignment.end, // bars grow from bottom
                                    children: history.map<Widget>((data) {
                                      double barHeight = (data['score'] / 5.0) * 120; // scale bar to max 120px height
                                      double barWidth = 40 * chartScale; // bar width scales with zoom

                                      return Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12.0 * chartScale),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('${data['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // score label on top of bar
                                            const SizedBox(height: 8),
                                            Container(
                                              width: barWidth,
                                              height: barHeight, // height proportional to score
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius: BorderRadius.circular(6), // rounded tops look nice
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(data['sem'], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)), // semester label below bar
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                          ),
                          const SizedBox(height: 32),
                          // subject breakdown for the current term
                          const Text('Current Semester Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 16),
                          // show each subject with its score — or empty message if none
                          subjects.isEmpty
                            ? const Text("No subjects found for this term", style: TextStyle(color: AppColors.textSecondary))
                            : Column(
                                children: subjects.map<Widget>((subject) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text(subject['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)), // subject name
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                                          child: Text('${subject['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)), // score badge
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  // the main build — full-screen spinner on first load, dashboard after
  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      // initial load spinner — shows while terms and analytics are being fetched
      return const Scaffold(body: AppleLoadingState(label: 'Preparing performance analysis…'));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Performance Analysis', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          SafeIconButton(
            icon: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
            tooltip: 'Export Report',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saving PDF to Downloads...')));
              await _pdfService.generatePerformanceReport(
                title: 'University Performance Report - $_selectedLabel',
                overviewStats: _overviewStats,
                topInstructors: _topInstructors,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadAllData(isRefresh: true), // pull down to reload everything smoothly
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // header area with term selector dropdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ApplePageHeader(
                      eyebrow: 'Institutional Analytics',
                      title: 'Performance',
                      subtitle: 'Compare evaluation outcomes across terms and instructors.',
                    ),
                    if (_terms.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // the term dropdown — pick any semester to view its data
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.borderHairline),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedTermId,
                            isExpanded: true,
                            // show spinner in dropdown while data loads, else arrow icon
                            icon: _isRefreshing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                : const Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                            items: _terms.map((t) => DropdownMenuItem<String>(
                              value: t['id'],
                              child: Text(t['label']!, overflow: TextOverflow.ellipsis),
                            )).toList(),
                            // disabled while refreshing so admin no double-change
                            onChanged: _isRefreshing ? null : (val) { if (val != null) _onTermChanged(val); },
                          ),
                        ),
                      ),
                    ] else
                      Text(_selectedLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis), // fallback if no terms loaded
                  ],
                ),
                const SizedBox(height: 24),
                // two stat cards: university average and total evaluations
                Row(
                  children: [
                    Expanded(child: _buildStatCard('University Avg', '${_overviewStats['overall']}/5', Icons.star, AppColors.primary)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStatCard('Total Evals', '${_overviewStats['totalEvals'] ?? 0}', Icons.library_books, AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 32),

                // instructor leaderboard section header with "View All" button
                AppleSectionHeader(
                  title: 'Instructor Leaderboard',
                  subtitle: 'Highest overall scores for the selected term.',
                  action: TextButton(
                      onPressed: () => _showAllInstructors(), // open the full list
                      child: const Text('View All'),
                    ),
                ),
                const SizedBox(height: 8),
                // the actual leaderboard cards — top instructors by score
                Column(
                  children: _topInstructors.isEmpty
                    ? [const AppleEmptyState(
                        icon: Icons.leaderboard_outlined,
                        title: 'No instructor results',
                        message: 'Evaluation results will appear when this term has responses.',
                      )]
                    : _topInstructors.map((instructor) {
                        return Card(
                          color: AppColors.surface,
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showInstructorDetailsSheet(instructor), // tap for details
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text(instructor.name[0], style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(instructor.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                              subtitle: Text('${instructor.subjectCount} Subject(s) • ${instructor.department}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    // trending up arrow if improving, flat arrow if not
                                    instructor.trend == 'up' ? Icons.trending_up : Icons.trending_flat,
                                    color: instructor.trend == 'up' ? AppColors.success : AppColors.warning,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${instructor.overallScore}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)), // the score number
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

  // a small colored stat card with icon, big value, and label
  // reused for 'University Avg' and 'Total Evals' cards at the top
  Widget _buildStatCard(String title, String value, IconData icon, Color iconColor) {
    return AppleMetricCard(
      label: title,
      value: value,
      icon: icon,
      color: iconColor,
    );
  }
}
