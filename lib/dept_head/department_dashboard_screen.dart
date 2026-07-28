// lib/dept_head/department_dashboard_screen.dart
// This is the BIG BOSS screen. The dept head open this and feel very important.
// Shows scores, alerts, word clouds — basically everything the dean need to not panic.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart'; // For logging out — ayaw forget this, or user stuck forever
import '../core/services/system_settings_service.dart';
import '../core/services/evaluation_service.dart';
import '../core/services/auth_service.dart';
import 'faculty_roster_screen.dart';
import 'subject_analytics_screen.dart';
import 'intervention_reports_screen.dart';
import 'dept_head_settings_screen.dart';

// The main widget for the department dashboard. Very importente kaayo.
// It is stateful because data changes and we need to rebuild the UI — dili pwede static.
class DepartmentDashboardScreen extends StatefulWidget {
  final String userId;
  const DepartmentDashboardScreen({super.key, required this.userId});

  @override
  State<DepartmentDashboardScreen> createState() => _DepartmentDashboardScreenState();
}

class _DepartmentDashboardScreenState extends State<DepartmentDashboardScreen> {
  // Services — the workers behind the scene. pray lang they don't throw exception.
  final _settingsService = SystemSettingsService();
  final _evaluationService = EvaluationService();
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;

  // These start with '...' because we don't have data yet. Patience, friend.
  String _currentSemester = '...';
  String _currentYear = '...';
  String _deanName = '...';

  // Stream subscription for settings — listens for changes like a worried parent
  StreamSubscription<SystemSettings>? _settingsSubscription;

  // --- DYNAMIC DATA ---
  // All the important numbers the boss want to see. wala choice, we fetch them all.
  Map<String, dynamic> _deptInfo = {
    'college': '',
    'dean': '',
    'overallScore': 0.0,
    'totalEvals': '0',
    'completionRate': 0.0,
    'facultyCount': 0,
  };

  // Alerts are the problems we hope to never see but always plan for — bahala na
  List<ActionAlert> _dynamicAlerts = [];
  // Word cloud — the AI version of "what students actually think"
  List<Map<String, dynamic>> _wordCloudData = [];
  // The current term ID — basin naa pa previous term, we make sure its the right one
  String _currentTermId = '';

  // Called once when the screen is born into this world
  @override
  void initState() {
    super.initState();
    _subscribeToSettings(); // Start listening for semester changes
    _loadInitialData(); // Fetch all the data — go go go
  }

  // Called when screen is destroyed — cancel subscription or memory will leak like old pipe
  @override
  void dispose() {
    _settingsSubscription?.cancel(); // Stop listening, we leaving
    super.dispose();
  }

  // Subscribe to live settings stream — so if admin changes the term, this screen knows immediately
  // No need to refresh manually. importente kaayo this part.
  void _subscribeToSettings() {
    _settingsSubscription = _settingsService.streamSettings().listen((settings) {
      if (mounted) {
        final newTermId = settings.termId ?? '';
        // Only reload data if the term actually changed — dili ta waste API calls
        final termChanged = newTermId.isNotEmpty && newTermId != _currentTermId;
        setState(() {
          _currentSemester = settings.semester;
          _currentYear = settings.academicYear;
          if (termChanged) _currentTermId = newTermId;
        });
        if (termChanged) _loadInitialData(); // New term detected — fetch fresh data
      }
    });
  }

  // The big data loader — fetches everything the dashboard need in one go.
  // If something fail, it catch the error and show empty state. dili ta crash.
  Future<void> _loadInitialData() async {
    try {
      // Get the dept summary — overall score, completion rate, etc.
      final summary = await _evaluationService.getDepartmentSummary(widget.userId);
      // Use dept average as threshold: show instructors below the dept mean
      // If no average yet, default to 3.0 so alerts still work — smart move
      final deptAvg = summary.averageScore > 0 ? summary.averageScore : 3.0;
      final alerts = await _evaluationService.getDepartmentAlerts(widget.userId, threshold: deptAvg);
      // Word cloud — student comments turned into fancy colored words
      final wordCloud = await _evaluationService.getDeptWordCloud(widget.userId);
      
      // Fetch User Info — we need the dean name so the drawer don't say "..."
      final user = await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', widget.userId)
          .maybeSingle();

      // Fetch Department Info — which college this dean belong to
      final deptData = await _supabase
          .from('department_table')
          .select('department_name!Department_name_ID(d_name)')
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          // Combine first and last name — simple but we need to do it
          if (user != null) {
            _deanName = '${user['first_name']} ${user['last_name']}';
          }
          
          // Default to 'Department' if no dept data found — better than showing null
          String deptName = 'Department';
          if (deptData != null && deptData['department_name'] != null) {
            deptName = deptData['department_name']['d_name'];
          }

          // Fill the deptInfo map with all the numbers — this feeds the UI cards
          _deptInfo = {
            'college': deptName,
            'dean': _deanName,
            // Show dash if score is zero — no data is better than showing fake 0
            'overallScore': summary.averageScore > 0
                ? summary.averageScore.toStringAsFixed(2)
                : '—',
            'totalEvals': summary.totalEvaluations.toString(),
            'completionRate': summary.completionRate,
            'facultyCount': summary.facultyCount,
          };
          _dynamicAlerts = alerts; // Store alerts for the dashboard and notification bell
          _wordCloudData = wordCloud; // Store word cloud data for the AI section
        });
      }
    } catch (e) {
      // If anything fails, just print it and show empty state — wala choice
      debugPrint('Error loading initial data: $e');
      if (mounted) setState(() {});
    }
  }

  // --- UI Icons and Colors for Alerts ---
  // Decide which icon to show base on alert type — critical get the scary warning icon
  IconData _getAlertIcon(String type) {
    if (type == 'critical') return Icons.warning_amber_rounded; // This one look serious
    return Icons.analytics; // Default — less scary but still notable
  }

  // Decide the color for alerts — red for critical, orange for just "pay attenshun"
  Color _getAlertColor(String type) {
    if (type == 'critical') return AppColors.error; // RED ALERT. not good.
    return AppColors.warning; // Yellow — proceed with caution
  }

  // Word cloud colours — cycle through these based on word index
  // We have 5 colors, repeat if more than 5 words. bahala na, looks nice anyway.
  static const List<Color> _cloudColors = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    AppColors.textPrimary,
    AppColors.primaryDeep,
  ];

  // The main build method — builds the entire screen UI.
  // Its long but thats because there is a LOT of info to show. dili ta complain.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Department Overview', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold, fontSize: 18)),
            // Shows current semester and year — so dean know which term they looking at
            Text('$_currentSemester, $_currentYear', style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12), overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // Notification bell — shows a red badge if there are alerts to worry about
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined, color: AppColors.primary),
                // Only show red dot if there are actual alerts — dili ta false alarm
                if (_dynamicAlerts.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: AppColors.error, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '${_dynamicAlerts.length}', // How many problems waiting
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              // Tapping bell just show a snackbar — no separate page, pray lang
              if (_dynamicAlerts.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No active alerts.')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      '${_dynamicAlerts.length} active alert(s). Check the dashboard below.'),
                ));
              }
            },
          ),
        ],
      ),

      // ==========================================
      // DEPARTMENT HEAD NAVIGATION DRAWER
      // The side menu — where the dean go to navigate. importente to keep tidy.
      // ==========================================
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Drawer header shows the dean's name and college — look professional
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.textPrimary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Avatar shows first letter of dean's name — fancy but simple
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    child: Text(_deanName.isNotEmpty ? _deanName[0] : '?', style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(_deanName, style: const TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  Text('Dean • ${_deptInfo['college']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Current page — marked as selected so it look highlighted
            _buildDrawerItem(context, Icons.dashboard, 'Department Overview', true, onTap: () {
              Navigator.pop(context); // Just close the drawer, we already here
            }),
            // Go to faculty roster — see all the instructors
            _buildDrawerItem(context, Icons.people, 'Faculty Roster', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => FacultyRosterScreen(userId: widget.userId)),
              );
            }),
            // Go to subject analytics — see how each subject performing
            _buildDrawerItem(context, Icons.library_books, 'Subject Analytics', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SubjectAnalyticsScreen(userId: widget.userId)),
              );
            }),
            // Go to intervention reports — the "problems" list
            _buildDrawerItem(context, Icons.gavel, 'Intervention Reports', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => InterventionReportsScreen(userId: widget.userId)),
              );
            }),
            // Go to settings — where user change their info or password
            _buildDrawerItem(context, Icons.settings, 'Account Settings', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DeptHeadSettingsScreen()),
              );
            }),
            const Divider(),
            // Log out — sign out and go back to login. No coming back without logging in again.
            _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
              await _authService.signOut(); // Bye bye session
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false, // Remove ALL previous routes — no going back
                );
              }
            }),
          ],
        ),
      ),

      // ==========================================
      // MAIN CONTENT
      // The scrollable body — everything below the appbar
      // ==========================================
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInitialData, // Pull down to reload — the classic trick
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(), // Always scrollable so refresh work even if content is short
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Big title — "Executive Dashboard" sounds fancy, dean will like
                const Text('Executive Dashboard', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                // Shows the college name — so we know whose dashboard this is
                Text(
                  _deptInfo['college'] ?? 'Department',
                  style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),

                // --- TOP SUMMARY CARD ---
                // The hero card — shows overall score, faculty count, and completion rate
                // Looks nice with gradient background. importente kaayo first impression.
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: AppColors.heroGradient),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Department Average', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                    // The big number — the overall dept score. Hopefully not low.
                    Text(
                      '${_deptInfo['overallScore']}',
                      style: const TextStyle(color: AppColors.primary, fontSize: 40, fontWeight: FontWeight.bold),
                    ),
                                    const Text('/5.0', style: TextStyle(color: Colors.white70, fontSize: 16)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Thin divider between score and faculty count — visual separator
                          Container(width: 1, height: 60, color: Colors.white24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Active Faculty', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                const SizedBox(height: 4),
                                // Total count of instructors in the dept — just a number, but importente
                                Text('${_deptInfo['facultyCount']}', style: const TextStyle(color: AppColors.surface, fontSize: 32, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Progress bar section — shows how many students already submitted evals
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Evaluation Completion Progress', style: TextStyle(color: Colors.white, fontSize: 12)),
                              // Show percentage — e.g. "72%" completion. Ayaw let it be 0%.
                              Text('${(_deptInfo['completionRate'] * 100).toInt()}%', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // The actual progress bar — fills based on completion rate
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _deptInfo['completionRate'], // 0.0 to 1.0
                              backgroundColor: Colors.white24,
                              color: AppColors.primary,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Shows total evaluations submitted — dean love seeing this number go up
                          Text('${_deptInfo['totalEvals']} forms processed this semester', style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // --- ACTION REQUIRED ALERTS ---
                // This section shows which instructors need attention — basin naa problema below
                const Row(
                  children: [
                    Icon(Icons.assignment_late, color: AppColors.textPrimary),
                    SizedBox(width: 8),
                    Text('Action Required', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                // If no alerts — show green "all good" message. Rare but nice.
                if (_dynamicAlerts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.success),
                        SizedBox(width: 12),
                        Text('No critical issues detected.', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  // Got alerts — show them all as tappable cards
                  Column(
                    children: _dynamicAlerts.map((alert) {
                      final color = _getAlertColor(alert.type); // Red or orange base on severity
                      return Card(
                        color: AppColors.surface,
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: color.withValues(alpha: 0.3), width: 1), // Colored border hint
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: Icon(_getAlertIcon(alert.type), color: color),
                          ),
                          title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(alert.desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4), overflow: TextOverflow.ellipsis),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                          onTap: () {
                            // Navigate base on what kind of alert it is
                            if (alert.instructorId != null) {
                              // Instructor problem — go to intervention reports
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => InterventionReportsScreen(userId: widget.userId),
                              ));
                            } else if (alert.subjectCode != null) {
                              // Subject problem — go to subject analytics
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => SubjectAnalyticsScreen(userId: widget.userId),
                              ));
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),

                // --- DEPARTMENT AI WORD CLOUD ---
                // Shows common words from student feedback — AI-processed, looks fancy
                // murag a real word cloud but we just use Wrap widget. smart shortcut.
                const Text('Department Voice (AI Analysis)', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Aggregated themes from all student comments across the college.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  child: _wordCloudData.isEmpty
                  // No word data yet — show placeholder message
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No feedback data yet for this term.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ),
                    )
                  // Got words — render them with size based on frequency count
                  : Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16.0,
                    runSpacing: 12.0,
                    children: List.generate(_wordCloudData.length, (i) {
                      final wordData = _wordCloudData[i];
                      final count = (wordData['total_count'] as num?)?.toInt() ?? 1;
                      // Scale font: min 12, max 36 based on count — more frequent = bigger word
                      final maxCount = (_wordCloudData.first['total_count'] as num?)?.toInt() ?? 1;
                      final fontSize = 12.0 + (count / maxCount) * 24.0; // Simple linear scale
                      final color = _cloudColors[i % _cloudColors.length]; // Cycle through colors
                      return Text(
                        wordData['word'],
                        style: TextStyle(
                          fontSize: fontSize,
                          // Bold if word appears in top 50% of frequency — stand out more
                          fontWeight: count > (maxCount * 0.5) ? FontWeight.bold : FontWeight.w500,
                          color: color,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widget for Drawer ---
  // Builds each row item in the navigation drawer — keeps code clean, dili ta repeat
  // isLogout flag turns the text red so user know its the danger button
  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected, {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary)),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // Bold if current page
        ),
        overflow: TextOverflow.ellipsis,
      ),
      selected: isSelected,
      // If no onTap given, default to showing "coming soon" — wala choice for unimplemented items
      onTap: onTap ?? () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$title coming soon!")));
      },
    );
  }
}