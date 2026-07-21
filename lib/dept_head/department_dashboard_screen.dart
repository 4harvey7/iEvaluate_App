// lib/dept_head/department_dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart'; // For logging out
import '../core/services/system_settings_service.dart';
import '../core/services/evaluation_service.dart';
import '../core/services/auth_service.dart';
import 'faculty_roster_screen.dart';
import 'subject_analytics_screen.dart';
import 'intervention_reports_screen.dart';
import 'dept_head_settings_screen.dart';

class DepartmentDashboardScreen extends StatefulWidget {
  final String userId;
  const DepartmentDashboardScreen({super.key, required this.userId});

  @override
  State<DepartmentDashboardScreen> createState() => _DepartmentDashboardScreenState();
}

class _DepartmentDashboardScreenState extends State<DepartmentDashboardScreen> {
  final _settingsService = SystemSettingsService();
  final _evaluationService = EvaluationService();
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;
  
  String _currentSemester = '...';
  String _currentYear = '...';
  String _deanName = '...';

  StreamSubscription<SystemSettings>? _settingsSubscription;

  // --- DYNAMIC DATA ---
  Map<String, dynamic> _deptInfo = {
    'college': '',
    'dean': '',
    'overallScore': 0.0,
    'totalEvals': '0',
    'completionRate': 0.0,
    'facultyCount': 0,
  };

  List<ActionAlert> _dynamicAlerts = [];
  List<Map<String, dynamic>> _wordCloudData = [];
  String _currentTermId = '';

  @override
  void initState() {
    super.initState();
    _subscribeToSettings();
    _loadInitialData();
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToSettings() {
    _settingsSubscription = _settingsService.streamSettings().listen((settings) {
      if (mounted) {
        final newTermId = settings.termId ?? '';
        final termChanged = newTermId.isNotEmpty && newTermId != _currentTermId;
        setState(() {
          _currentSemester = settings.semester;
          _currentYear = settings.academicYear;
          if (termChanged) _currentTermId = newTermId;
        });
        if (termChanged) _loadInitialData();
      }
    });
  }

  Future<void> _loadInitialData() async {
    try {
      final summary = await _evaluationService.getDepartmentSummary(widget.userId);
      // Use dept average as threshold: show instructors below the dept mean
      final deptAvg = summary.averageScore > 0 ? summary.averageScore : 3.0;
      final alerts = await _evaluationService.getDepartmentAlerts(widget.userId, threshold: deptAvg);
      final wordCloud = await _evaluationService.getDeptWordCloud(widget.userId);
      
      // Fetch User Info
      final user = await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', widget.userId)
          .maybeSingle();

      // Fetch Department Info
      final deptData = await _supabase
          .from('department_table')
          .select('department_name!Department_name_ID(d_name)')
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (user != null) {
            _deanName = '${user['first_name']} ${user['last_name']}';
          }
          
          String deptName = 'Department';
          if (deptData != null && deptData['department_name'] != null) {
            deptName = deptData['department_name']['d_name'];
          }

          _deptInfo = {
            'college': deptName,
            'dean': _deanName,
            'overallScore': summary.averageScore > 0
                ? summary.averageScore.toStringAsFixed(2)
                : '—',
            'totalEvals': summary.totalEvaluations.toString(),
            'completionRate': summary.completionRate,
            'facultyCount': summary.facultyCount,
          };
          _dynamicAlerts = alerts;
          _wordCloudData = wordCloud;
        });
      }
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (mounted) setState(() {});
    }
  }

  // --- UI Icons and Colors for Alerts ---
  IconData _getAlertIcon(String type) {
    if (type == 'critical') return Icons.warning_amber_rounded;
    return Icons.analytics;
  }

  Color _getAlertColor(String type) {
    if (type == 'critical') return AppColors.error;
    return AppColors.warning;
  }

  // Word cloud colours — cycle through these based on word index
  static const List<Color> _cloudColors = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    AppColors.textPrimary,
    AppColors.primaryDeep,
  ];

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
            Text('$_currentSemester, $_currentYear', style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined, color: AppColors.primary),
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
                        '${_dynamicAlerts.length}',
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
      // ==========================================
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.textPrimary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    child: Text(_deanName.isNotEmpty ? _deanName[0] : '?', style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(_deanName, style: const TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Dean • ${_deptInfo['college']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            _buildDrawerItem(context, Icons.dashboard, 'Department Overview', true, onTap: () {
              Navigator.pop(context);
            }),
            _buildDrawerItem(context, Icons.people, 'Faculty Roster', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => FacultyRosterScreen(userId: widget.userId)),
              );
            }),
            _buildDrawerItem(context, Icons.library_books, 'Subject Analytics', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SubjectAnalyticsScreen(userId: widget.userId)),
              );
            }),
            _buildDrawerItem(context, Icons.gavel, 'Intervention Reports', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => InterventionReportsScreen(userId: widget.userId)),
              );
            }),
            _buildDrawerItem(context, Icons.settings, 'Account Settings', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DeptHeadSettingsScreen()),
              );
            }),
            const Divider(),
            _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
              await _authService.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                );
              }
            }),
          ],
        ),
      ),

      // ==========================================
      // MAIN CONTENT
      // ==========================================
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInitialData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Executive Dashboard', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  _deptInfo['college'] ?? 'Department',
                  style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // --- TOP SUMMARY CARD ---
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
                          Container(width: 1, height: 60, color: Colors.white24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Active Faculty', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('${_deptInfo['facultyCount']}', style: const TextStyle(color: AppColors.surface, fontSize: 32, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Evaluation Completion Progress', style: TextStyle(color: Colors.white, fontSize: 12)),
                              Text('${(_deptInfo['completionRate'] * 100).toInt()}%', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _deptInfo['completionRate'],
                              backgroundColor: Colors.white24,
                              color: AppColors.primary,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('${_deptInfo['totalEvals']} forms processed this semester', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // --- ACTION REQUIRED ALERTS ---
                const Row(
                  children: [
                    Icon(Icons.assignment_late, color: AppColors.textPrimary),
                    SizedBox(width: 8),
                    Text('Action Required', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
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
                  Column(
                    children: _dynamicAlerts.map((alert) {
                      final color = _getAlertColor(alert.type);
                      return Card(
                        color: AppColors.surface,
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: Icon(_getAlertIcon(alert.type), color: color),
                          ),
                          title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(alert.desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                          onTap: () {
                            if (alert.instructorId != null) {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => InterventionReportsScreen(userId: widget.userId),
                              ));
                            } else if (alert.subjectCode != null) {
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
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No feedback data yet for this term.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ),
                    )
                  : Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16.0,
                    runSpacing: 12.0,
                    children: List.generate(_wordCloudData.length, (i) {
                      final wordData = _wordCloudData[i];
                      final count = (wordData['total_count'] as num?)?.toInt() ?? 1;
                      // Scale font: min 12, max 36 based on count
                      final maxCount = (_wordCloudData.first['total_count'] as num?)?.toInt() ?? 1;
                      final fontSize = 12.0 + (count / maxCount) * 24.0;
                      final color = _cloudColors[i % _cloudColors.length];
                      return Text(
                        wordData['word'],
                        style: TextStyle(
                          fontSize: fontSize,
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
  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected, {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary)),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: onTap ?? () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$title coming soon!")));
      },
    );
  }
}