// lib/instructor/instructor_dashboard.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart';
import 'past_semesters_screen.dart';
import 'student_feedback_screen.dart';
import 'instructor_settings_screen.dart';
//import 'ai_sentiment_analysis.dark';

class InstructorDashboardScreen extends StatefulWidget {
  const InstructorDashboardScreen({super.key});

  @override
  State<InstructorDashboardScreen> createState() => _InstructorDashboardScreenState();
}

class _InstructorDashboardScreenState extends State<InstructorDashboardScreen> {
  // --- DUMMY INSTRUCTOR DATA ---
  final Map<String, dynamic> _myProfile = {
    'name': 'Kazuto Kirigaya',
    'title': 'Senior Instructor',
    'dept': 'Computer Studies',
    'overallScore': 4.85,
    'totalEvaluations': 142,
    'trend': 'up',
  };

  // 👈 NEW: DUMMY NOTICES FROM THE DEAN
  final List<Map<String, dynamic>> _officialNotices = [
    {
      'title': 'Mandated Action Required',
      'message': 'Please schedule a Curriculum Review Meeting regarding the recent feedback in CS202. - Dr. Yuuki (Dean)',
      'date': 'Oct 24, 2026',
      'type': 'urgent',
    }
  ];

  final List<Map<String, dynamic>> _mySubjects = [
    {'code': 'CS101', 'name': 'Intro to Programming', 'score': 4.90, 'students': 45},
    {'code': 'CS202', 'name': 'Data Structures & Algorithms', 'score': 4.80, 'students': 38},
    {'code': 'IT305', 'name': 'Web Development', 'score': 4.85, 'students': 59},
  ];

  final List<Map<String, dynamic>> _myHistory = [
    {'sem': '1st Sem 25', 'score': 4.20},
    {'sem': '2nd Sem 25', 'score': 4.65},
    {'sem': '1st Sem 26', 'score': 4.85},
  ];

  final List<String> _recentFeedback = [
    "The examples used in class are really helpful for understanding the code.",
    "Pacing is a bit fast during the Data Structures lectures, but very engaging.",
    "Always willing to answer questions after class. Great instructor!",
    "Clear grading rubrics and fair exams."
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('My Dashboard', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        actions: [
          // 👈 UPDATED: Notification Bell now has a red badge if there are notices!
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: AppColors.white),
                onPressed: () {},
              ),
              if (_officialNotices.isNotEmpty)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                  ),
                )
            ],
          ),
        ],
      ),

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
                    backgroundColor: AppColors.royalBlue.withOpacity(0.3),
                    child: Text(_myProfile['name'][0], style: const TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(_myProfile['name'], style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('${_myProfile['title']} • ${_myProfile['dept']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            _buildDrawerItem(context, Icons.dashboard, 'Dashboard', true),
            _buildDrawerItem(context, Icons.history, 'Past Semesters', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PastSemestersScreen()));
            }),
            _buildDrawerItem(context, Icons.forum, 'Student Feedback', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const StudentFeedbackScreen()));
            }),
            _buildDrawerItem(context, Icons.settings, 'Account Settings', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const InstructorSettingsScreen()));
            }),
            const Divider(),
            _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
            }),
          ],
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==========================================
              // 👈 NEW: OFFICIAL NOTICES BANNER
              // ==========================================
              if (_officialNotices.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withOpacity(0.5), width: 1.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_officialNotices[0]['title'], style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(_officialNotices[0]['message'], style: const TextStyle(color: AppColors.darkGray, fontSize: 13, height: 1.4)),
                            const SizedBox(height: 8),
                            Text(_officialNotices[0]['date'], style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: Colors.red),
                        tooltip: 'Acknowledge Receipt',
                        onPressed: () {
                          // In a real app, this would tell the Dean the instructor saw it!
                          setState(() {
                            _officialNotices.clear();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice acknowledged. Dean notified.')));
                        },
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // --- WELCOME CARD ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.deepBlue, AppColors.royalBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.royalBlue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back, ${_myProfile['name'].split(' ')[0]}!', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('Your Performance Overview', style: TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Overall Rating', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('${_myProfile['overallScore']}', style: const TextStyle(color: AppColors.gold, fontSize: 36, fontWeight: FontWeight.bold)),
                                const Text('/5.0', style: TextStyle(color: Colors.white70, fontSize: 16)),
                              ],
                            ),
                          ],
                        ),
                        Container(width: 1, height: 50, color: Colors.white24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Evaluations', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('${_myProfile['totalEvaluations']}', style: const TextStyle(color: AppColors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Container(width: 1, height: 50, color: Colors.white24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Trend', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 8),
                            Icon(
                              _myProfile['trend'] == 'up' ? Icons.trending_up : Icons.trending_flat,
                              color: _myProfile['trend'] == 'up' ? Colors.greenAccent : Colors.orangeAccent,
                              size: 28,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // --- SUBJECT BREAKDOWN ---
              const Text('Current Classes', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Column(
                children: _mySubjects.map((subject) {
                  return Card(
                    color: AppColors.white,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.class_, color: AppColors.royalBlue),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subject['code'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.royalBlue, fontSize: 12)),
                                Text(subject['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray, fontSize: 15), overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text('${subject['students']} evals submitted', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text('${subject['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // --- TWO-COLUMN LAYOUT: HISTORY & FEEDBACK ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Growth', style: TextStyle(color: AppColors.deepBlue, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          height: 180,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: _myHistory.map<Widget>((data) {
                              double barHeight = (data['score'] / 5.0) * 100;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text('${data['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 24,
                                    height: barHeight,
                                    decoration: BoxDecoration(color: AppColors.royalBlue, borderRadius: BorderRadius.circular(4)),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(data['sem'].split(' ')[0], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Recent Feedback', style: TextStyle(color: AppColors.deepBlue, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          height: 180,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                          child: ListView.separated(
                            itemCount: _recentFeedback.length,
                            separatorBuilder: (context, index) => const Divider(height: 16),
                            itemBuilder: (context, index) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.format_quote, color: AppColors.gold, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _recentFeedback[index],
                                      style: const TextStyle(fontSize: 12, color: AppColors.darkGray, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

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