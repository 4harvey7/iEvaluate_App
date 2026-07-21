// lib/dept_head/faculty_roster_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'intervention_reports_screen.dart';
import 'instructor_detail_page.dart';

class FacultyRosterScreen extends StatefulWidget {
  final String userId;
  const FacultyRosterScreen({super.key, required this.userId});

  @override
  State<FacultyRosterScreen> createState() => _FacultyRosterScreenState();
}

class _FacultyRosterScreenState extends State<FacultyRosterScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _facultyList = [];
  String _currentTermId = '';

  @override
  void initState() {
    super.initState();
    _fetchFacultyData();
  }

  Future<void> _fetchFacultyData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Get current term
      final settings = await _supabase.from('system_settings').select('current_term_id').maybeSingle();
      _currentTermId = settings?['current_term_id'] ?? '';

      if (_currentTermId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // 2. Get Department of current user (Dean) — prefer passed userId
      final deanId = widget.userId.isNotEmpty
          ? widget.userId
          : (_supabase.auth.currentUser?.id ?? '');
      if (deanId.isEmpty) return;

      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID, department_name:Department_name_ID(d_name)')
          .eq('user_id', deanId)
          .maybeSingle();
      
      final deptId = deptData?['Department_name_ID'];
      final deptName = deptData?['department_name']?['d_name'] ?? 'Unknown Department';

      debugPrint('--- [DEBUG] Roster Fetch ---');
      debugPrint('User ID: $deanId');
      debugPrint('Department ID: $deptId');
      debugPrint('Department Name: $deptName');

      if (deptId == null) {
        debugPrint('Warning: Current user has no department assigned in department_table');
        setState(() => _isLoading = false);
        return;
      }

      // 3. Fetch all instructors in this department
      final facultyData = await _supabase
          .from('user_info')
          .select('''
            id,
            first_name,
            last_name,
            department_table!inner (
              roles:roles (Roles),
              Department_name_ID
            ),
            overall_total_survey (
              overall_mean,
              management_mean,
              performance_mean,
              total_responses,
              term_id
            )
          ''')
          .eq('department_table.Department_name_ID', deptId);
      
      debugPrint('Raw Faculty Data Count: ${facultyData.length}');

      if (mounted) {
        debugPrint('Fetched ${facultyData.length} faculty rows for Dept ID: $deptId');
        setState(() {
          _facultyList = (facultyData as List).map((f) {
            // Handle department_table which might be a List or a Map
            final deptRaw = f['department_table'];
            Map<String, dynamic>? deptMap;
            if (deptRaw is List && deptRaw.isNotEmpty) {
              deptMap = deptRaw[0];
            } else if (deptRaw is Map<String, dynamic>) {
              deptMap = deptRaw;
            }

            final roleInfo = deptMap?['roles'];
            
            // Find the survey for the CURRENT term only
            final surveyList = f['overall_total_survey'] as List?;
            final survey = (surveyList != null) 
                ? surveyList.firstWhere(
                    (s) => s['term_id'] == _currentTermId, 
                    orElse: () => null
                  )
                : null;

            return {
              'id': f['id'],
              'name': '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'.trim(),
              'title': roleInfo?['Roles'] ?? 'Instructor',
              'department': deptName,
              'score': (survey?['overall_mean'] as num?)?.toDouble() ?? 0.0,
              'mgmt_score': (survey?['management_mean'] as num?)?.toDouble() ?? 0.0,
              'perf_score': (survey?['performance_mean'] as num?)?.toDouble() ?? 0.0,
              'evals': survey?['total_responses'] ?? 0,
              'trend': 'flat', // Simplified for now
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching faculty roster: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _searchQuery = '';
  String _sortBy = 'Score (Highest to Lowest)';

  List<Map<String, dynamic>> get _filteredAndSortedFaculty {
    List<Map<String, dynamic>> filtered = _facultyList.where((faculty) {
      return faculty['name'].toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (_sortBy == 'Score (Highest to Lowest)') {
      filtered.sort((a, b) => b['score'].compareTo(a['score']));
    } else if (_sortBy == 'Score (Lowest to Highest)') {
      filtered.sort((a, b) => a['score'].compareTo(b['score']));
    } else if (_sortBy == 'Name (A-Z)') {
      filtered.sort((a, b) => a['name'].compareTo(b['name']));
    }
    return filtered;
  }

  void _showInstructorDetails(Map<String, dynamic> instructor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InstructorDetailPage(
          instructor: instructor,
          deptHeadUserId: widget.userId,
          currentTermId: _currentTermId,
        ),
      ),
    );
  }

  // --- Helper UI Builders to keep code clean ---

  Widget _buildModalHeader(Map<String, dynamic> instructor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Row(
        children: [
          CircleAvatar(radius: 30, backgroundColor: AppColors.primary.withValues(alpha: 0.1), child: Text(instructor['name'].isNotEmpty ? instructor['name'][0] : '?', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 24))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(instructor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.textPrimary)),
            Text(instructor['title'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  Widget _buildQuickStats(Map<String, dynamic> instructor) {
    return Row(
      children: [
        Expanded(child: _statCard('Overall Score', '${instructor['score']}', instructor['score'] >= 3.0 ? AppColors.textPrimary : AppColors.error)),
        const SizedBox(width: 16),
        Expanded(child: _statCard('Total Evals', '${instructor['evals']}', AppColors.textPrimary)),
      ],
    );
  }

  Widget _statCard(String label, String val, Color valColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: valColor)),
      ]),
    );
  }

  Widget _buildSentimentLegend(Map<String, dynamic> sent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _legendItem('Positive', '${((sent['pos'] ?? 0.0) * 100).toInt()}%', AppColors.success),
        _legendItem('Neutral', '${((sent['neu'] ?? 0.0) * 100).toInt()}%', AppColors.warning),
        _legendItem('Negative', '${((sent['neg'] ?? 0.0) * 100).toInt()}%', AppColors.error),
      ],
    );
  }

  Widget _legendItem(String label, String perc, Color color) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label: ', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      Text(perc, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
    ]);
  }

  Widget _buildInterventionCard(Map<String, dynamic> instructor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.warning, color: AppColors.error), SizedBox(width: 8), Text('Intervention Required', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error))]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, 
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), 
            onPressed: () {
              Navigator.pop(context); // Close Modal
              Navigator.push(context, MaterialPageRoute(builder: (_) => InterventionReportsScreen(userId: widget.userId)));
            }, 
            child: const Text('Draft Intervention Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppColors.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No instructors found in your department.' : 'No instructors match "$_searchQuery"',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _searchQuery = ''),
              child: const Text('Clear Search', style: TextStyle(color: AppColors.primary)),
            ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }
    final roster = _filteredAndSortedFaculty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Faculty Roster', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),

      ),
      body: SafeArea(
        child: Column(
          children: [
            // ==========================================
            // SEARCH & SORT HEADER
            // ==========================================
            Container(
              padding: const EdgeInsets.all(24.0),
              color: AppColors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search instructor name...',
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${roster.length} Instructors Found',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(width: 8),

                      Flexible(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _sortBy,
                          icon: const Icon(
                            Icons.sort,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          underline: const SizedBox(),
                          items: [
                            'Score (Highest to Lowest)',
                            'Score (Lowest to Highest)',
                            'Name (A-Z)'
                          ].map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (newValue) =>
                              setState(() => _sortBy = newValue!),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            // ==========================================
            // ROSTER LIST
            // ==========================================
            Expanded(
              child: roster.isEmpty 
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: roster.length,
                itemBuilder: (context, index) {
                  final faculty = roster[index];
                  // Flag low performers with a red border
                  bool isLowPerformer = faculty['score'] < 3.0;

                  return Card(
                    color: AppColors.surface,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isLowPerformer ? AppColors.error.withValues(alpha: 0.5) : Colors.transparent, width: 2),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showInstructorDetails(faculty),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            // Rank / Status Indicator
                            SizedBox(
                              width: 30,
                              child: Text(
                                '#${index + 1}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: isLowPerformer ? AppColors.error : AppColors.textTertiary, fontSize: 16),
                              ),
                            ),

                            // Profile Avatar
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                              child: Text(faculty['name'].isNotEmpty ? faculty['name'][0] : '?', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 16),

                            // Name & Title
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(faculty['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(faculty['title'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),

                            // Score & Trend
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      faculty['trend'] == 'up' ? Icons.trending_up : (faculty['trend'] == 'down' ? Icons.trending_down : Icons.trending_flat),
                                      color: faculty['trend'] == 'up' ? AppColors.success : (faculty['trend'] == 'down' ? AppColors.error : AppColors.warning),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${faculty['score']}',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isLowPerformer ? AppColors.error : AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${faculty['evals']} evals', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
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
}