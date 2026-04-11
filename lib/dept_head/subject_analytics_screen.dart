// lib/dept_head/subject_analytics_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class SubjectAnalyticsScreen extends StatefulWidget {
  const SubjectAnalyticsScreen({super.key});

  @override
  State<SubjectAnalyticsScreen> createState() => _SubjectAnalyticsScreenState();
}

class _SubjectAnalyticsScreenState extends State<SubjectAnalyticsScreen> {
  // --- DUMMY SUBJECT ANALYTICS DATA ---
  final List<Map<String, dynamic>> _subjectAnalytics = [
    {
      'code': 'CS101',
      'name': 'Intro to Programming',
      'avgScore': 4.82,
      'deptAvg': 4.62,
      'difficulty': 'Moderate',
      'sentiment': 'Highly Positive',
      'trend': 'stable',
      'sections': 8,
    },
    {
      'code': 'CS202',
      'name': 'Data Structures & Algorithms',
      'avgScore': 3.15, // 👈 Flagged: Significantly lower than dept average
      'deptAvg': 4.62,
      'difficulty': 'High',
      'sentiment': 'Critical',
      'trend': 'down',
      'sections': 5,
    },
    {
      'code': 'IT305',
      'name': 'Web Development',
      'avgScore': 4.70,
      'deptAvg': 4.62,
      'difficulty': 'Moderate',
      'sentiment': 'Positive',
      'trend': 'up',
      'sections': 4,
    },
    {
      'code': 'GE101',
      'name': 'Ethics in Tech',
      'avgScore': 4.45,
      'deptAvg': 4.62,
      'difficulty': 'Low',
      'sentiment': 'Neutral',
      'trend': 'same',
      'sections': 12,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Subject Analytics', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Curriculum Health', style: TextStyle(color: AppColors.darkGray, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Identifying subjects that may require curriculum review or additional teaching resources.', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 24),

              // ==========================================
              // SUBJECT PERFORMANCE LIST
              // ==========================================
              Column(
                children: _subjectAnalytics.map((subject) {
                  double score = subject['avgScore'];
                  double deptAvg = subject['deptAvg'];
                  // Logic: If subject is > 0.5 points below dept average, it's an anomaly
                  bool isAnomaly = (deptAvg - score) > 0.5;

                  return Card(
                    color: AppColors.white,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isAnomaly ? Colors.orange.withOpacity(0.5) : Colors.transparent, width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Code and Name
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.royalBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text(subject['code'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.royalBlue, fontSize: 12)),
                              ),
                              if (isAnomaly)
                                const Row(
                                  children: [
                                    Icon(Icons.auto_graph, color: Colors.orange, size: 16),
                                    SizedBox(width: 4),
                                    Text('System Anomaly', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(subject['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.darkGray)),
                          const SizedBox(height: 20),

                          // Metrics Row
                          Row(
                            children: [
                              _buildMiniStat('Avg Score', '${subject['avgScore']}', isAnomaly ? Colors.orange : AppColors.deepBlue),
                              _buildMiniStat('Difficulty', subject['difficulty'], AppColors.royalBlue),
                              _buildMiniStat('Sentiment', subject['sentiment'], subject['sentiment'] == 'Critical' ? Colors.red : Colors.green),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Comparative Progress Bar
                          const Text('Score vs. Department Average', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Stack(
                            children: [
                              // Department Average Marker (Background)
                              Container(
                                height: 12,
                                width: double.infinity,
                                decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(6)),
                              ),
                              // Subject Score Bar
                              FractionallySizedBox(
                                widthFactor: (subject['avgScore'] / 5.0),
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: isAnomaly ? Colors.orange : AppColors.royalBlue,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              // Visual indicator for where the Dept Avg is
                              Positioned(
                                left: (MediaQuery.of(context).size.width - 88) * (subject['deptAvg'] / 5.0),
                                child: Container(width: 2, height: 12, color: AppColors.darkGray),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('0.0', style: TextStyle(color: Colors.grey, fontSize: 10)),
                              Text('Dept Avg: ${subject['deptAvg']}', style: const TextStyle(color: AppColors.darkGray, fontSize: 10, fontWeight: FontWeight.bold)),
                              const Text('5.0', style: TextStyle(color: Colors.grey, fontSize: 10)),
                            ],
                          ),

                          if (isAnomaly) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                              child: const Text(
                                "AI Note: Multiple instructors teaching this course have reported low scores. This suggests a Curricular Difficulty rather than poor teaching.",
                                style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ]
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

  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}