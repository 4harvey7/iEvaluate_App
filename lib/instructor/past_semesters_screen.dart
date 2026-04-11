// lib/instructor/past_semesters_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class PastSemestersScreen extends StatefulWidget {
  const PastSemestersScreen({super.key});

  @override
  State<PastSemestersScreen> createState() => _PastSemestersScreenState();
}

class _PastSemestersScreenState extends State<PastSemestersScreen> {
  // --- DUMMY HISTORICAL DATA ---
  // Notice the growth over time: 4.20 -> 4.65 -> 4.85
  final List<Map<String, dynamic>> _historicalData = [
    {
      'semester': '1st Semester 2026',
      'overallScore': 4.85,
      'evaluations': 142,
      'trend': 'up',
      'subjects': [
        {'code': 'CS101', 'name': 'Intro to Programming', 'score': 4.90},
        {'code': 'CS202', 'name': 'Data Structures & Algorithms', 'score': 4.80},
        {'code': 'IT305', 'name': 'Web Development', 'score': 4.85},
      ]
    },
    {
      'semester': '2nd Semester 2025',
      'overallScore': 4.65,
      'evaluations': 130,
      'trend': 'up',
      'subjects': [
        {'code': 'CS101', 'name': 'Intro to Programming', 'score': 4.70},
        {'code': 'IT201', 'name': 'Database Systems', 'score': 4.60},
      ]
    },
    {
      'semester': '1st Semester 2025',
      'overallScore': 4.20,
      'evaluations': 125,
      'trend': 'baseline', // First recorded semester
      'subjects': [
        {'code': 'CS101', 'name': 'Intro to Programming', 'score': 4.30},
        {'code': 'IT105', 'name': 'Networking Basics', 'score': 4.10},
      ]
    },
  ];

  @override
  Widget build(BuildContext context) {
    // Reversing the list just for the chart so it reads left-to-right (Oldest to Newest)
    final List<Map<String, dynamic>> chartData = _historicalData.reversed.toList();

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Past Semesters', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: AppColors.gold),
            tooltip: 'Download Complete History',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating Full History PDF...')));
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
              // HEADER
              // ==========================================
              const Text('Historical Growth', style: TextStyle(color: AppColors.darkGray, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Track your evaluation scores and student feedback across all your previous academic terms.', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 24),

              // ==========================================
              // TREND CHART CARD
              // ==========================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Performance Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.deepBlue)),
                    const SizedBox(height: 24),

                    // Custom Bar Chart
                    SizedBox(
                      height: 200, // 👈 FIX: Increased height from 160 to 200 to prevent vertical overflow
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: chartData.map((data) {
                          // Max height is 120px for a score of 5.0
                          double barHeight = (data['overallScore'] / 5.0) * 120;
                          // Highlight the most recent semester in Gold, others in Blue
                          bool isLatest = data == chartData.last;

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${data['overallScore']}', style: TextStyle(fontWeight: FontWeight.bold, color: isLatest ? AppColors.gold : AppColors.darkGray)),
                              const SizedBox(height: 8),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.easeOut,
                                width: 40,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isLatest ? AppColors.gold : AppColors.royalBlue.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: isLatest ? [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                data['semester'].replaceAll('Semester ', 'Sem\n'), // Formats "1st Sem\n2026"
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // SEMESTER BREAKDOWN LIST
              // ==========================================
              const Text('Detailed Breakdown', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              Column(
                children: _historicalData.map((term) {
                  final List subjects = term['subjects'];
                  final bool isLatest = term == _historicalData.first;

                  return Card(
                    color: AppColors.white,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: isLatest ? const BorderSide(color: AppColors.gold, width: 2) : BorderSide.none,
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.history_edu, color: AppColors.royalBlue),
                        ),
                        title: Text(term['semester'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray, fontSize: 16)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('${term['evaluations']} Total Evaluations', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (term['trend'] == 'up')
                              const Icon(Icons.trending_up, color: Colors.green, size: 20)
                            else if (term['trend'] == 'down')
                              const Icon(Icons.trending_down, color: Colors.red, size: 20)
                            else
                              const Icon(Icons.remove, color: Colors.grey, size: 20),

                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: AppColors.deepBlue, borderRadius: BorderRadius.circular(20)),
                              child: Text('${term['overallScore']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.white, fontSize: 14)),
                            ),
                          ],
                        ),

                        // Expanded Content: The individual subjects taught that term
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.lightGray.withOpacity(0.5),
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                            ),
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
                            child: Column(
                              children: subjects.map<Widget>((subject) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 50,
                                        child: Text(subject['code'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.royalBlue, fontSize: 12)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(subject['name'], style: const TextStyle(color: AppColors.darkGray, fontSize: 13), overflow: TextOverflow.ellipsis),
                                      ),
                                      Text('${subject['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
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
}