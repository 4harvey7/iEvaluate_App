// lib/dept_head/department_dashboard_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart'; // For logging out
import 'faculty_roster_screen.dart';
import 'subject_analytics_screen.dart';
import 'intervention_reports_screen.dart';
import 'dept_head_settings_screen.dart';

class DepartmentDashboardScreen extends StatefulWidget {
  const DepartmentDashboardScreen({super.key});

  @override
  State<DepartmentDashboardScreen> createState() => _DepartmentDashboardScreenState();
}

class _DepartmentDashboardScreenState extends State<DepartmentDashboardScreen> {
  // --- DUMMY DEPARTMENT DATA ---
  final Map<String, dynamic> _deptInfo = {
    'college': 'College of Computer Studies',
    'dean': 'Dr. Asuna Yuuki',
    'overallScore': 4.62,
    'totalEvals': '3,420',
    'completionRate': 0.88, // 88%
    'facultyCount': 42,
  };

  // --- DUMMY ALERTS (Interventions) ---
  final List<Map<String, dynamic>> _actionAlerts = [
    {
      'type': 'critical',
      'title': 'Low Performance Flag',
      'desc': 'Instructor Klein dropped below 3.0 average this semester.',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.red,
    },
    {
      'type': 'warning',
      'title': 'Subject Anomaly',
      'desc': 'CS202 (Data Structures) shows 40% negative sentiment across all sections.',
      'icon': Icons.analytics,
      'color': Colors.orange,
    },
  ];

  // --- DUMMY DEPT WORD CLOUD ---
  final List<Map<String, dynamic>> _deptWordCloud = [
    {'word': 'Innovative', 'weight': 28.0, 'color': Colors.green},
    {'word': 'Outdated Labs', 'weight': 22.0, 'color': Colors.orange},
    {'word': 'Excellent Faculty', 'weight': 26.0, 'color': Colors.green},
    {'word': 'Fast-paced', 'weight': 18.0, 'color': AppColors.royalBlue},
    {'word': 'Coding', 'weight': 32.0, 'color': AppColors.deepBlue},
    {'word': 'Heavy Workload', 'weight': 20.0, 'color': Colors.redAccent},
    {'word': 'Helpful', 'weight': 24.0, 'color': Colors.green},
    {'word': 'Theory-heavy', 'weight': 16.0, 'color': Colors.orange},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Department Overview', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active, color: AppColors.gold),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have 2 new alerts.')));
            },
          ),
        ],
      ),

      // ==========================================
      // DEPARTMENT HEAD NAVIGATION DRAWER
      // ==========================================
      drawer: Drawer(
        backgroundColor: AppColors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.deepBlue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.gold.withOpacity(0.2),
                    child: const Text('AY', style: TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(_deptInfo['dean'], style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('Dean • Computer Studies', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            _buildDrawerItem(context, Icons.dashboard, 'Department Overview', true),
            _buildDrawerItem(context, Icons.people, 'Faculty Roster', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FacultyRosterScreen()),
              );
            }),
            _buildDrawerItem(context, Icons.library_books, 'Subject Analytics', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SubjectAnalyticsScreen()),
              );
            }),
            _buildDrawerItem(context, Icons.gavel, 'Intervention Reports', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InterventionReportsScreen()),
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
            _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
              );
            }),
          ],
        ),
      ),

      // ==========================================
      // MAIN CONTENT
      // ==========================================
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Executive Dashboard', style: TextStyle(color: AppColors.darkGray, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_deptInfo['college'], style: const TextStyle(color: AppColors.royalBlue, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),

              // --- TOP SUMMARY CARD ---
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.deepBlue, AppColors.royalBlue]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.royalBlue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
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
                                  Text('${_deptInfo['overallScore']}', style: const TextStyle(color: AppColors.gold, fontSize: 40, fontWeight: FontWeight.bold)),
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
                              Text('${_deptInfo['facultyCount']}', style: const TextStyle(color: AppColors.white, fontSize: 32, fontWeight: FontWeight.bold)),
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
                            Text('${(_deptInfo['completionRate'] * 100).toInt()}%', style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _deptInfo['completionRate'],
                            backgroundColor: Colors.white24,
                            color: AppColors.gold,
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
                  Icon(Icons.assignment_late, color: AppColors.deepBlue),
                  SizedBox(width: 8),
                  Text('Action Required', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: _actionAlerts.map((alert) {
                  return Card(
                    color: AppColors.white,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: alert['color'].withOpacity(0.3), width: 1),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: alert['color'].withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(alert['icon'], color: alert['color']),
                      ),
                      title: Text(alert['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(alert['desc'], style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening detailed report for ${alert['title']}...')));
                      },
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // --- DEPARTMENT AI WORD CLOUD ---
              const Text('Department Voice (AI Analysis)', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Aggregated themes from all student comments across the college.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16.0,
                  runSpacing: 12.0,
                  children: _deptWordCloud.map((wordData) {
                    return Text(
                      wordData['word'],
                      style: TextStyle(
                        fontSize: wordData['weight'],
                        fontWeight: FontWeight.bold,
                        color: wordData['color'],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widget for Drawer ---
  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected, {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.red : (isSelected ? AppColors.royalBlue : AppColors.darkGray)),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? Colors.red : (isSelected ? AppColors.royalBlue : AppColors.darkGray),
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