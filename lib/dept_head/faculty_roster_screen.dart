// lib/dept_head/faculty_roster_screen.dart
// The list of all instructors in the department — who they are, how they scoring.
// Dean can search, sort, and tap to see more. importente screen, treat with respect.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';
import 'intervention_reports_screen.dart';
import 'instructor_detail_page.dart';

// Faculty roster widget — shows all instructors in this dept
// Stateful because we fetch data and let user search/sort
class FacultyRosterScreen extends StatefulWidget {
  final String userId; // The dept head's user ID — used to find their department
  const FacultyRosterScreen({super.key, required this.userId});

  @override
  State<FacultyRosterScreen> createState() => _FacultyRosterScreenState();
}

class _FacultyRosterScreenState extends State<FacultyRosterScreen> {
  final _supabase = Supabase.instance.client;
  
  static final Map<String, List<Map<String, dynamic>>> _rosterCache = {};
  static final Map<String, String> _termIdCache = {};
  
  bool _isLoading = true; // Start loading immediately on open
  List<Map<String, dynamic>> _facultyList = []; // All faculty from the dept
  String _currentTermId = ''; // Current academic term — we only show scores for this term

  // Kick off data fetch as soon as screen loads
  @override
  void initState() {
    super.initState();
    _fetchFacultyData(); // Go get the roster data
  }

  // The main data fetching function — this does a lot of work so buckle up.
  // Fetches: current term, previous term, dept info, all instructors + their scores.
  // If any step fail, we stop and show empty state. dili ta crash.
  Future<void> _fetchFacultyData() async {
    String activeTermId = _termIdCache['current'] ?? '';
    if (activeTermId.isEmpty) {
      final settings = await _supabase.from('system_settings').select('current_term_id').maybeSingle();
      activeTermId = settings?['current_term_id'] ?? '';
      _termIdCache['current'] = activeTermId;
    }
    _currentTermId = activeTermId;

    if (_rosterCache.containsKey(activeTermId)) {
      if (mounted) {
        setState(() {
          _facultyList = _rosterCache[activeTermId]!;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = true);
    }
    
    try {
      if (_currentTermId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // 2b. Fetch all terms ordered by creation date so we can find the previous term
      // We need previous term to calculate score trend — up, down, or flat
      final allTerms = await _supabase
          .from('academic_terms')
          .select('id, created_at')
          .order('created_at', ascending: true);

      // Find the index of the current term and the ID of the one before it
      final termIds = (allTerms as List).map((t) => t['id'] as String).toList();
      final currentTermIndex = termIds.indexOf(_currentTermId);
      // If current term is first in list, there is no previous — previousTermId will be null
      final previousTermId = currentTermIndex > 0 ? termIds[currentTermIndex - 1] : null;

      // 2. Get Department of current user (Dean) — prefer passed userId
      // Fallback to auth.currentUser if userId is empty for some reason
      final deanId = widget.userId.isNotEmpty
          ? widget.userId
          : (_supabase.auth.currentUser?.id ?? '');
      if (deanId.isEmpty) return; // No user ID = no dept = wala data

      // Fetch the dept info using the dean's user ID
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID, department_name:Department_name_ID(d_name)')
          .eq('user_id', deanId)
          .maybeSingle();
      
      final deptId = deptData?['Department_name_ID']; // The department UUID
      final deptName = deptData?['department_name']?['d_name'] ?? 'Unknown Department';

      // Debug prints — helpful during development, won't hurt in production
      debugPrint('--- [DEBUG] Roster Fetch ---');
      debugPrint('User ID: $deanId');
      debugPrint('Department ID: $deptId');
      debugPrint('Department Name: $deptName');

      // If dean has no department assigned — something is wrong in the database
      if (deptId == null) {
        debugPrint('Warning: Current user has no department assigned in department_table');
        setState(() => _isLoading = false);
        return;
      }

      // 3. Fetch all instructors in this department (excluding the dept head themselves)
      // We join with overall_total_survey to get their scores — the important numbers
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
              combined_score_mean,
              management_mean,
              performance_mean,
              total_responses,
              term_id
            )
          ''')
          .eq('department_table.Department_name_ID', deptId)
          .neq('id', deanId); // Exclude dean from their own roster — they not faculty
      
      debugPrint('Raw Faculty Data Count: ${facultyData.length}');

      if (mounted) {
        debugPrint('Fetched ${facultyData.length} faculty rows for Dept ID: $deptId');
        
        final fetchedList = (facultyData as List).map<Map<String, dynamic>>((f) {
            // Handle department_table which might be a List or a Map — supabase surprise
            final deptList = f['department_table'];
            final deptItem = deptList is List
                ? (deptList.isNotEmpty ? deptList[0] : null)
                : deptList;
            final roleInfo = deptItem?['roles'];

            // Safely extract the survey data list
            final surveyData = f['overall_total_survey'];
            final List<dynamic>? surveyList = surveyData is List ? surveyData : null;

            // Find survey data for the active term
            final survey = surveyList != null
                ? surveyList.firstWhere(
                    (s) => s['term_id'] == activeTermId,
                    orElse: () => null)
                : null;

            // Find previous term survey for trend comparison — so we can show arrow
            final prevSurvey = (surveyList != null && previousTermId != null)
                ? surveyList.firstWhere(
                    (s) => s['term_id'] == previousTermId,
                    orElse: () => null)
                : null;

            // Calculate trend: up/down/flat based on 0.1-point threshold
            // Anything less than 0.1 difference is considered flat — not significant
            final currentScore = (survey?['combined_score_mean'] as num?)?.toDouble() ?? (survey?['overall_mean'] as num?)?.toDouble() ?? 0.0;
            final prevScore = (prevSurvey?['combined_score_mean'] as num?)?.toDouble() ?? (prevSurvey?['overall_mean'] as num?)?.toDouble() ?? 0.0;
            String trend;
            if (prevSurvey == null || prevScore == 0.0) {
              trend = 'flat'; // No previous data to compare — we dont guess
            } else if (currentScore - prevScore > 0.1) {
              trend = 'up'; // Score improved by more than 0.1 — good news
            } else if (prevScore - currentScore > 0.1) {
              trend = 'down'; // Score dropped by more than 0.1 — dean should notice
            } else {
              trend = 'flat'; // Basically unchanged — status quo
            }

            // Return the clean faculty map — all the info the UI cards need
            return {
              'id': f['id'],
              'name': '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'.trim(),
              'title': roleInfo?['Roles'] ?? 'Instructor', // Default to Instructor if role missing
              'department': deptName,
              'score': (survey?['combined_score_mean'] as num?)?.toDouble() ?? (survey?['overall_mean'] as num?)?.toDouble() ?? 0.0,
              'mgmt_score': (survey?['management_mean'] as num?)?.toDouble() ?? 0.0,
              'perf_score': (survey?['performance_mean'] as num?)?.toDouble() ?? 0.0,
              'evals': survey?['total_responses'] ?? 0,
              'trend': trend, // 'up', 'down', or 'flat'
            };
          }).toList();
          
          setState(() {
            _rosterCache[activeTermId] = fetchedList;
            _facultyList = fetchedList;
            _isLoading = false; // Done loading — show the list now
          });
      }
    } catch (e) {
      debugPrint('Error fetching faculty roster: $e');
      if (mounted) setState(() => _isLoading = false); // Show empty state on error
    }
  }

  // Search query — user types here to filter by name. Empty = show all.
  String _searchQuery = '';
  // Sort option — default to highest score first (dean want to see stars on top)
  String _sortBy = 'Score (Highest to Lowest)';

  // Computed getter — filters and sorts the faculty list based on current search + sort
  // Called every time UI rebuilds — no caching needed here, list is not that big
  List<Map<String, dynamic>> get _filteredAndSortedFaculty {
    // Filter by search query — case insensitive name match
    List<Map<String, dynamic>> filtered = _facultyList.where((faculty) {
      return faculty['name'].toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Apply the selected sort order — user can pick from dropdown
    if (_sortBy == 'Score (Highest to Lowest)') {
      filtered.sort((a, b) => b['score'].compareTo(a['score'])); // Best to worst
    } else if (_sortBy == 'Score (Lowest to Highest)') {
      filtered.sort((a, b) => a['score'].compareTo(b['score'])); // Worst to best — intervention mode
    } else if (_sortBy == 'Name (A-Z)') {
      filtered.sort((a, b) => a['name'].compareTo(b['name'])); // Alphabetical — old school
    }
    return filtered;
  }

  // Navigate to the full instructor detail page when a card is tapped
  // Passes instructor map + dept head ID + current term — everything the detail page needs
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
  // These are small widgets used inside the bottom sheet modal for instructor quick-view

  // Top section of the modal — avatar + name + close button
  // ignore: unused_element
  Widget _buildModalHeader(Map<String, dynamic> instructor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Row(
        children: [
          // Circle avatar with first letter of instructor's name
          CircleAvatar(radius: 30, backgroundColor: AppColors.primary.withValues(alpha: 0.1), child: Text(instructor['name'].isNotEmpty ? instructor['name'][0] : '?', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 24))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(instructor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
            Text(instructor['title'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), overflow: TextOverflow.ellipsis),
          ])),
          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  // Two stat chips: overall score and total evaluations count side by side
  // ignore: unused_element
  Widget _buildQuickStats(Map<String, dynamic> instructor) {
    return Row(
      children: [
        // Score chip — red if below 3.0 (bad), dark if okay
        Expanded(child: _statCard('Overall Score', '${instructor['score']}', instructor['score'] >= 3.0 ? AppColors.textPrimary : AppColors.error)),
        const SizedBox(width: 16),
        // Total evaluations — just a count, always in dark color
        Expanded(child: _statCard('Total Evals', '${instructor['evals']}', AppColors.textPrimary)),
      ],
    );
  }

  // A single stat card box — label on top, big number below
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

  // Sentiment breakdown legend — positive/neutral/negative percentages in a row
  // ignore: unused_element
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

  // Single legend dot + label item — used inside sentiment legend row
  Widget _legendItem(String label, String perc, Color color) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), // Color dot
      const SizedBox(width: 4),
      Text('$label: ', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      Text(perc, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
    ]);
  }

  // Card shown when instructor score is below threshold — alerts dean + links to reports
  // This card is RED and has a "Draft Intervention Report" button. Serious business.
  // ignore: unused_element
  Widget _buildInterventionCard(Map<String, dynamic> instructor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Warning header row
        const Row(children: [Icon(Icons.warning, color: AppColors.error), SizedBox(width: 8), Text('Intervention Required', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error))]),
        const SizedBox(height: 16),
        // Button — close this modal and go to intervention reports screen
        SizedBox(
          width: double.infinity, 
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), 
            onPressed: () {
              Navigator.pop(context); // Close Modal first
              Navigator.push(context, MaterialPageRoute(builder: (_) => InterventionReportsScreen(userId: widget.userId)));
            }, 
            child: const Text('Draft Intervention Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ),
      ]),
    );
  }

  // Empty state widget — shown when no faculty found or search returns nothing
  // If search is active, show a "Clear Search" button so user can reset
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Soft icon in a primary-tint circle — friendly empty state
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
            child: const Icon(Icons.people_outline, size: 40, color: AppColors.primaryText),
          ),
          const SizedBox(height: 18),
          Text(
            // Different message depending on whether they searched or not
            _searchQuery.isEmpty ? 'No instructors found in your department.' : 'No instructors match "$_searchQuery"',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Pull to refresh or adjust your search.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          // Only show clear button if a search is active — no point showing it if search is empty
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _searchQuery = ''), // Reset search query
              child: const Text('Clear Search', style: TextStyle(color: AppColors.primaryText)),
            ),
        ],
      ),
    );
  }

  // The main build — search bar on top, sorted list below
  @override
  Widget build(BuildContext context) {
    // Get filtered + sorted list from computed getter
    final roster = _filteredAndSortedFaculty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: AppColors.textInverted,
        iconTheme: const IconThemeData(color: AppColors.textInverted),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E1608), AppColors.textPrimary],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Faculty Roster', style: TextStyle(color: AppColors.textInverted, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
          children: [
            // ==========================================
            // SEARCH & SORT HEADER
            // Fixed at top — not scrollable with the list
            // ==========================================
            Entrance(
              index: 0,
              child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search input — tonal, borderless, focus ring in primary
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Search instructor name...',
                      hintStyle: const TextStyle(color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Count label — shows how many instructors match the current filter
                      Expanded(
                        child: Text(
                          '${roster.length} Instructors Found'.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Sort dropdown — three options for ordering the list
                      Flexible(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _sortBy,
                          icon: const Icon(
                            Icons.sort,
                            color: AppColors.primaryText,
                            size: 18,
                          ),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          underline: const SizedBox(), // Remove default underline — looks cleaner
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
                              setState(() => _sortBy = newValue!), // Apply selected sort
                        ),
                      ),
                    ],
                  )
                ],
              ),
              ),
            ),

            // ==========================================
            // ROSTER LIST
            // Scrollable list of instructor cards — tap any to see full detail
            // ==========================================
            Expanded(
              child: roster.isEmpty 
                ? _buildEmptyState() // No results — show friendly empty state
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: roster.length,
                itemBuilder: (context, index) {
                  final faculty = roster[index];
                  // Flag low performers with a red border — so dean know who to worry about
                  bool isLowPerformer = faculty['score'] < 3.0;

                  return Entrance(
                    index: index.clamp(0, 8).toInt(),
                    child: Pressable(
                      child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showInstructorDetails(faculty), // Go to full detail view
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Row(
                          children: [
                            // Rank pill — shows position in sorted list
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isLowPerformer ? AppColors.error.withValues(alpha: 0.10) : AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '#${index + 1}', // Rank number — #1 is best in current sort
                                style: TextStyle(fontWeight: FontWeight.w700, color: isLowPerformer ? AppColors.error : AppColors.primaryText, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Profile Avatar — primary-tint circle with first letter
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.primaryTint,
                              child: Text(faculty['name'].isNotEmpty ? faculty['name'][0] : '?', style: const TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 14),

                            // Name & Title — the who and what of this person
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(faculty['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(faculty['title'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),

                            // Score & Trend — the actual numbers dean care about most
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    // Trend icon — up arrow, down arrow, or flat line
                                    Icon(
                                      faculty['trend'] == 'up' ? Icons.trending_up : (faculty['trend'] == 'down' ? Icons.trending_down : Icons.trending_flat),
                                      color: faculty['trend'] == 'up' ? AppColors.success : (faculty['trend'] == 'down' ? AppColors.error : AppColors.warning),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    // The score number — big and colored based on pass/fail threshold
                                    Text(
                                      '${faculty['score']}',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isLowPerformer ? AppColors.error : AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                // Small eval count below the score — context for the number
                                Text('${faculty['evals']} evals', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
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