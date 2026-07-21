import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/evaluation_service.dart';
import '../core/services/pdf/pdf_service.dart';
import '../theme/app_colors.dart';

class PerformanceAnalysisScreen extends StatefulWidget {
  const PerformanceAnalysisScreen({super.key});

  @override
  State<PerformanceAnalysisScreen> createState() => _PerformanceAnalysisScreenState();
}

class _PerformanceAnalysisScreenState extends State<PerformanceAnalysisScreen> {
  final _evaluationService = EvaluationService();
  final _pdfService = PdfService();
  final _supabase = Supabase.instance.client;
  
  // Term selector — each entry: {id, label}
  List<Map<String, String>> _terms = [];
  String? _selectedTermId;   // actual UUID used for queries
  String _selectedLabel = 'Loading...';
  bool _isInitialLoading = true;
  bool _isRefreshing = false;

  Map<String, dynamic> _overviewStats = {
    'overall': '0.0',
    'totalEvals': '0',
    'completion': '0%',
  };

  List<Map<String, dynamic>> _departmentAverages = [];
  List<InstructorPerformance> _topInstructors = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isInitialLoading = true);
    await _loadTerms();
    await _fetchRealAnalytics();
    if (mounted) setState(() => _isInitialLoading = false);
  }

  /// Loads all academic terms from Supabase and selects the active one
  Future<void> _loadTerms() async {
    try {
      // Get active term from system_settings
      final settings = await _supabase
          .from('system_settings')
          .select('current_term_id')
          .limit(1)
          .maybeSingle();
      final activeTermId = settings?['current_term_id'] as String?;

      // Fetch all terms sorted newest first
      final rows = await _supabase
          .from('academic_terms')
          .select('id, semester, academic_year')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _terms = (rows as List).map((r) => {
            'id': r['id'] as String,
            'label': '${r['semester']} ${r['academic_year']}',
          }).toList();

          // Select active term, or first if not found
          if (_terms.isNotEmpty) {
            final active = _terms.firstWhere(
              (t) => t['id'] == activeTermId,
              orElse: () => _terms.first,
            );
            _selectedTermId = active['id'];
            _selectedLabel = active['label']!;
          }
        });
      }
    } catch (e) {
      debugPrint('loadTerms error: $e');
    }
  }

  /// Called when the user picks a different term from the dropdown
  Future<void> _onTermChanged(String termId) async {
    final label = _terms.firstWhere((t) => t['id'] == termId)['label']!;
    setState(() {
      _selectedTermId = termId;
      _selectedLabel = label;
      _isRefreshing = true;
    });
    await _fetchRealAnalytics();
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _fetchRealAnalytics() async {
    try {
      final globalStats = await _evaluationService.getGlobalStats(termId: _selectedTermId);
      final deptAverages = await _evaluationService.getDepartmentAverages(termId: _selectedTermId);
      final topInstructors = await _evaluationService.getTopInstructors(termId: _selectedTermId);

      if (mounted) {
        setState(() {
          // getGlobalStats() returns {avgScore, totalInstructors, totalResponses}
          _overviewStats = {
            'overall': (globalStats['avgScore'] as double? ?? 0.0).toStringAsFixed(2),
            'totalEvals': '${globalStats['totalResponses'] ?? 0}',
            'completion': 'N/A',
          };
          _departmentAverages = deptAverages.map((d) => {
            'dept': d['dept'],
            'score': d['score'],
            'color': d['score'] >= 4.0 ? AppColors.primary : AppColors.warning,
          }).toList();
          _topInstructors = topInstructors;
        });
      }
    } catch (e) {
      debugPrint('Error fetching performance analytics: $e');
    }
  }

  // ==========================================
  // VIEW ALL INSTRUCTORS BOTTOM SHEET
  // ==========================================
  void _showAllInstructors() {
    final searchController = TextEditingController();
    List<InstructorPerformance> filtered = List.from(_topInstructors);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                // Handle
                Container(width: 40, height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(color: AppColors.borderHairline, borderRadius: BorderRadius.circular(2))),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.leaderboard, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text('All Instructors (${filtered.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.textPrimary)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: TextField(
                    controller: searchController,
                    onChanged: (q) => setSheetState(() {
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
                // List
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final inst = filtered[i];
                      final score = inst.overallScore;
                      final color = score >= 4.0 ? AppColors.success : score >= 3.0 ? AppColors.warning : score > 0 ? AppColors.error : AppColors.textTertiary;
                      return Card(
                        color: AppColors.surface,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          onTap: () {
                            Navigator.pop(ctx);
                            _showInstructorDetailsSheet(inst);
                          },
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Text(inst.name.isNotEmpty ? inst.name[0] : '?',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(inst.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(inst.department, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          trailing: Text(
                            score > 0 ? score.toStringAsFixed(2) : '—',
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
  // ==========================================
  Future<void> _showInstructorDetailsSheet(InstructorPerformance instructor) async {
    // Fetch detailed info on demand
    final history = await _evaluationService.getInstructorHistory(instructor.id);
    final subjects = await _evaluationService.getInstructorSubjects(instructor.id);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        double chartScale = 1.0;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sticky Header
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
                              Text(instructor.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.textPrimary)),
                              Text(instructor.department, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                  ),

                  // Scrollable Content
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
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.zoom_out, color: AppColors.primary),
                                    onPressed: () {
                                      if (chartScale > 0.6) setSheetState(() => chartScale -= 0.2);
                                    },
                                  ),
                                  Text('${(chartScale * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  IconButton(
                                    icon: const Icon(Icons.zoom_in, color: AppColors.primary),
                                    onPressed: () {
                                      if (chartScale < 2.5) setSheetState(() => chartScale += 0.2);
                                    },
                                  ),
                                ],
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 220,
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                            child: history.isEmpty 
                              ? const Center(child: Text("No historical data available", style: TextStyle(color: AppColors.textSecondary)))
                              : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 80),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: history.map<Widget>((data) {
                                      double barHeight = (data['score'] / 5.0) * 120;
                                      double barWidth = 40 * chartScale;

                                      return Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12.0 * chartScale),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('${data['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                            const SizedBox(height: 8),
                                            Container(
                                              width: barWidth,
                                              height: barHeight,
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(data['sem'], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                          ),
                          const SizedBox(height: 32),
                          const Text('Current Semester Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 16),
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
                                        Expanded(child: Text(subject['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                                          child: Text('${subject['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
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

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Performance Analysis', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
            tooltip: 'Export Report',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF Report...')));
              await _pdfService.generatePerformanceReport(
                title: 'University Performance Report - $_selectedLabel',
                overviewStats: _overviewStats,
                departmentAverages: _departmentAverages,
                topInstructors: _topInstructors,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAllData,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dashboard', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                    if (_terms.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.borderHairline),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedTermId,
                            icon: _isRefreshing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                : const Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                            items: _terms.map((t) => DropdownMenuItem<String>(
                              value: t['id'],
                              child: Text(t['label']!, overflow: TextOverflow.ellipsis),
                            )).toList(),
                            onChanged: _isRefreshing ? null : (val) { if (val != null) _onTermChanged(val); },
                          ),
                        ),
                      )
                    else
                      Text(_selectedLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _buildStatCard('University Avg', '${_overviewStats['overall']}/5', Icons.star, AppColors.primary)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStatCard('Total Evals', '${_overviewStats['totalEvals'] ?? 0}', Icons.library_books, AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: AppColors.heroGradient),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Data Extraction Rate', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          SizedBox(height: 4),
                          Text('System performing optimally', style: TextStyle(color: AppColors.surface, fontSize: 12)),
                        ],
                      ),
                      Text(_overviewStats['completion'] ?? 'N/A', style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text('Department Averages', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10)]),
                  child: _departmentAverages.isEmpty 
                    ? const Center(child: Text("No department data found"))
                    : Column(
                        children: _departmentAverages.map((dept) {
                          double percentage = (dept['score'] / 5.0);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        dept['dept'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('${dept['score']}', style: TextStyle(fontWeight: FontWeight.bold, color: dept['color'])),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Stack(
                                  children: [
                                    Container(height: 8, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4))),
                                    FractionallySizedBox(
                                      widthFactor: percentage,
                                      child: Container(height: 8, decoration: BoxDecoration(color: dept['color'], borderRadius: BorderRadius.circular(4))),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Instructor Leaderboard', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () => _showAllInstructors(),
                      child: const Text('View All', style: TextStyle(color: AppColors.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  children: _topInstructors.isEmpty
                    ? [const Center(child: Text("No instructors found"))]
                    : _topInstructors.map((instructor) {
                        return Card(
                          color: AppColors.surface,
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showInstructorDetailsSheet(instructor),
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
                                    instructor.trend == 'up' ? Icons.trending_up : Icons.trending_flat,
                                    color: instructor.trend == 'up' ? AppColors.success : AppColors.warning,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${instructor.overallScore}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
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

  Widget _buildStatCard(String title, String value, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
