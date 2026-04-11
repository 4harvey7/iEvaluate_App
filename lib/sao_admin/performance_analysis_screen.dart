// lib/sao_admin/performance_analysis_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class PerformanceAnalysisScreen extends StatefulWidget {
  const PerformanceAnalysisScreen({super.key});

  @override
  State<PerformanceAnalysisScreen> createState() => _PerformanceAnalysisScreenState();
}

class _PerformanceAnalysisScreenState extends State<PerformanceAnalysisScreen> {
  String _selectedSemester = '1st Semester 2026';
  final List<String> _semesters = ['1st Semester 2026', '2nd Semester 2025', '1st Semester 2025'];

  // --- DUMMY ANALYTICS DATA ---
  final Map<String, String> _overviewStats = {
    'overall': '4.68',
    'totalEvals': '1,248',
    'completion': '94%',
  };

  final List<Map<String, dynamic>> _departmentAverages = [
    {'dept': 'Computer Studies', 'score': 4.82, 'color': AppColors.royalBlue},
    {'dept': 'Engineering', 'score': 4.65, 'color': AppColors.gold},
    {'dept': 'Education', 'score': 4.51, 'color': Colors.green},
    {'dept': 'Arts and Sciences', 'score': 4.30, 'color': Colors.orange},
    {'dept': 'Business', 'score': 4.15, 'color': Colors.purple},
  ];

  final List<Map<String, dynamic>> _topInstructors = [
    {
      'name': 'Kirito (Kazuto Kirigaya)',
      'dept': 'Computer Studies',
      'overallScore': 4.85,
      'trend': 'up',
      'subjects': [
        {'name': 'CS101 - Intro to Programming', 'score': 4.90},
        {'name': 'CS202 - Data Structures', 'score': 4.80},
      ],
      'history': [
        {'sem': '1st Sem 25', 'score': 4.20},
        {'sem': '2nd Sem 25', 'score': 4.65},
        {'sem': '1st Sem 26', 'score': 4.85},
      ]
    },
    {
      'name': 'Asuna Yuuki',
      'dept': 'Arts and Sciences',
      'overallScore': 4.88,
      'trend': 'up',
      'subjects': [
        {'name': 'ENG201 - Advanced Physics', 'score': 4.88},
      ],
      'history': [
        {'sem': '1st Sem 25', 'score': 4.70},
        {'sem': '2nd Sem 25', 'score': 4.80},
        {'sem': '1st Sem 26', 'score': 4.88},
      ]
    },
    {
      'name': 'Klein (Ryotaro Tsuboi)',
      'dept': 'Engineering',
      'overallScore': 4.45,
      'trend': 'same',
      'subjects': [
        {'name': 'GE101 - Ethics', 'score': 4.20},
        {'name': 'ENG105 - Thermodynamics', 'score': 4.60},
        {'name': 'ENG106 - Fluid Dynamics', 'score': 4.55},
      ],
      'history': [
        {'sem': '1st Sem 25', 'score': 4.45},
        {'sem': '2nd Sem 25', 'score': 4.40},
        {'sem': '1st Sem 26', 'score': 4.45},
      ]
    },
  ];

  // ==========================================
  // INSTRUCTOR DETAILS POP-UP (WITH ZOOMABLE CHART)
  // ==========================================
  void _showInstructorDetailsSheet(Map<String, dynamic> instructor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {

        double chartScale = 1.0;

        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              final List subjects = instructor['subjects'];
              final List history = instructor['history'];

              return Container(
                height: MediaQuery.of(context).size.height * 0.85,
                decoration: const BoxDecoration(
                  color: AppColors.lightGray,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sticky Header
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.royalBlue.withOpacity(0.1),
                            child: Text(instructor['name'][0], style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold, fontSize: 24)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(instructor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.darkGray)),
                                Text(instructor['dept'], style: const TextStyle(color: Colors.grey, fontSize: 14)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
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
                            // --- HISTORICAL CHART SECTION WITH ZOOM CONTROLS ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // 👈 FIX 1: Wrapped in Expanded to prevent horizontal overflow
                                const Expanded(
                                  child: Text('Historical Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
                                ),

                                // Zoom Controls
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.zoom_out, color: AppColors.royalBlue),
                                      onPressed: () {
                                        if (chartScale > 0.6) setSheetState(() => chartScale -= 0.2);
                                      },
                                    ),
                                    Text('${(chartScale * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                                    IconButton(
                                      icon: const Icon(Icons.zoom_in, color: AppColors.royalBlue),
                                      onPressed: () {
                                        if (chartScale < 2.5) setSheetState(() => chartScale += 0.2);
                                      },
                                    ),
                                  ],
                                )
                              ],
                            ),
                            const SizedBox(height: 8),

                            // 👈 FIX 2: Fixed height for chart area to prevent vertical 0.4px overflow
                            Container(
                              height: 220, // Safe height limit
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal, // Swipe left/right if zoomed in!
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 80),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: history.map<Widget>((data) {

                                      // 👈 FIX 3: Height is constant, only Width and Padding scale for zooming!
                                      double barHeight = (data['score'] / 5.0) * 120; // Max height is 120
                                      double barWidth = 40 * chartScale;

                                      return Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12.0 * chartScale),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min, // Hugs the contents tightly
                                          children: [
                                            Text('${data['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                                            const SizedBox(height: 8),
                                            Container(
                                              width: barWidth,
                                              height: barHeight,
                                              decoration: BoxDecoration(
                                                color: AppColors.royalBlue,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(data['sem'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 32),

                            // --- CURRENT SUBJECT BREAKDOWN ---
                            const Text('Current Semester Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
                            const SizedBox(height: 16),
                            Column(
                              children: subjects.map<Widget>((subject) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(subject['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray))),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                                        child: Text('${subject['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
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
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Performance Analysis', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: AppColors.gold),
            tooltip: 'Export Report',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF Report...')));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==========================================
              // HEADER & FILTER
              // ==========================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dashboard', style: TextStyle(color: AppColors.darkGray, fontSize: 24, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSemester,
                        icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.royalBlue),
                        style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold, fontSize: 14),
                        items: _semesters.map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value));
                        }).toList(),
                        onChanged: (newValue) => setState(() => _selectedSemester = newValue!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ==========================================
              // OVERVIEW CARDS
              // ==========================================
              Row(
                children: [
                  Expanded(child: _buildStatCard('University Avg', '${_overviewStats['overall']}/5', Icons.star, AppColors.gold)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Total Evals', _overviewStats['totalEvals']!, Icons.library_books, AppColors.royalBlue)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.deepBlue, AppColors.royalBlue]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.royalBlue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Data Extraction Rate', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('System performing optimally', style: TextStyle(color: AppColors.white, fontSize: 12)),
                      ],
                    ),
                    Text(_overviewStats['completion']!, style: const TextStyle(color: AppColors.gold, fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // DEPARTMENT PERFORMANCE CHART
              // ==========================================
              const Text('Department Averages', style: TextStyle(color: AppColors.darkGray, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                child: Column(
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
                              Text(dept['dept'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                              Text('${dept['score']}', style: TextStyle(fontWeight: FontWeight.bold, color: dept['color'])),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Stack(
                            children: [
                              Container(height: 8, decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(4))),
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

              // ==========================================
              // TOP INSTRUCTORS LEADERBOARD
              // ==========================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Instructor Leaderboard', style: TextStyle(color: AppColors.darkGray, fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton(onPressed: () {}, child: const Text('View All', style: TextStyle(color: AppColors.royalBlue))),
                ],
              ),
              const SizedBox(height: 8),

              Column(
                children: _topInstructors.map((instructor) {
                  final List subjects = instructor['subjects'];

                  return Card(
                    color: AppColors.white,
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showInstructorDetailsSheet(instructor),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.royalBlue.withOpacity(0.1),
                          child: Text(instructor['name'][0], style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(instructor['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                        subtitle: Text('${subjects.length} Subject(s) • ${instructor['dept']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              instructor['trend'] == 'up' ? Icons.trending_up : Icons.trending_flat,
                              color: instructor['trend'] == 'up' ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text('${instructor['overallScore']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.deepBlue)),
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
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: AppColors.darkGray, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}