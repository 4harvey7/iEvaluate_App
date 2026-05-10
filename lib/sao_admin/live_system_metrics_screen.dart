// lib/sao_admin/live_system_metrics_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LiveSystemMetricsScreen extends StatefulWidget {
  const LiveSystemMetricsScreen({super.key});

  @override
  State<LiveSystemMetricsScreen> createState() => _LiveSystemMetricsScreenState();
}

class _LiveSystemMetricsScreenState extends State<LiveSystemMetricsScreen> {
  // --- 1. DATA GATHERER PRODUCTIVITY ---
  final List<Map<String, dynamic>> _gathererProductivity = [
    {'name': 'John (Terminal 1)', 'scanned': 450, 'target': 500, 'color': AppColors.primary},
    {'name': 'Maria (Terminal 2)', 'scanned': 320, 'target': 500, 'color': AppColors.primary},
  ];

  // --- 3. DATA GATHERER SYNC STATUS (Updated) ---
  final List<Map<String, dynamic>> _gathererSyncStatus = [
    {'name': 'John (Terminal 1)', 'status': 'Fully Synced', 'pending': 0, 'isOnline': true},
    {'name': 'Maria (Terminal 2)', 'status': 'Cached Locally', 'pending': 50, 'isOnline': false},
  ];

  // --- 4. OVERALL EVALUATION PROGRESS ---
  final List<Map<String, dynamic>> _collegeProgress = [
    {'college': 'College of Technology', 'progress': 1.0, 'percentage': '100%'},
    {'college': 'College of Education', 'progress': 0.4, 'percentage': '40%'},
    {'college': 'College of Engineering', 'progress': 0.75, 'percentage': '75%'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // 👈 Reverted to hardcoded color
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Live System Metrics', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Real-time tracking for AI processing, staff productivity, and device synchronization.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),

              // ==========================================
              // 2. AI PROCESSING & ERROR METRICS
              // ==========================================
              const Text('AI Processing Accuracy', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface, // 👈 Reverted to hardcoded color
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.check_circle, color: AppColors.success, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('Perfect Extraction', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('85%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              Text('Processed perfectly', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 80, color: AppColors.borderHairline),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.warning, color: AppColors.warning, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('Manual Validated', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('15%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              Text('Messy handwriting', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Expanded(flex: 85, child: Container(height: 12, color: AppColors.success)),
                          Expanded(flex: 15, child: Container(height: 12, color: AppColors.warning)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 1. DATA GATHERER PRODUCTIVITY (AUDIT LOGS)
              // ==========================================
              const Text('Data Gatherer Productivity', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._gathererProductivity.map((staff) {
                double progress = staff['scanned'] / staff['target'];
                return Card(
                  color: AppColors.surface, // 👈 Reverted to hardcoded color
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: staff['color'].withOpacity(0.1),
                                    child: Icon(Icons.person, color: staff['color'], size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(staff['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 15), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${staff['scanned']} forms', style: TextStyle(color: staff['color'], fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: AppColors.background,
                            color: staff['color'],
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),

              // ==========================================
              // 3. DATA GATHERER SYNC STATUS (UPDATED)
              // ==========================================
              const Text('Data Gatherer Sync Status', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._gathererSyncStatus.map((gatherer) {
                return Card(
                  color: AppColors.surface, // 👈 Reverted to hardcoded color
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: gatherer['isOnline'] ? AppColors.success.withOpacity(0.3) : AppColors.warning.withOpacity(0.3))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Icon(
                      gatherer['isOnline'] ? Icons.cloud_done : Icons.cloud_off,
                      color: gatherer['isOnline'] ? AppColors.success : AppColors.warning,
                      size: 32,
                    ),
                    title: Text(gatherer['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    subtitle: Text(
                      gatherer['isOnline'] ? 'Fully Synced to Server' : '${gatherer['pending']} forms waiting',
                      style: TextStyle(color: gatherer['isOnline'] ? AppColors.textSecondary : AppColors.warning, fontWeight: gatherer['isOnline'] ? FontWeight.normal : FontWeight.bold),
                    ),
                    trailing: gatherer['isOnline']
                        ? const Icon(Icons.check_circle, color: AppColors.success)
                        : IconButton(
                      icon: const Icon(Icons.sync, color: AppColors.warning),
                      tooltip: 'Force Sync',
                      onPressed: () {},
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),

              // ==========================================
              // 4. OVERALL EVALUATION PROGRESS
              // ==========================================
              const Text('Campus Evaluation Progress', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface, // 👈 Reverted to hardcoded color
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: _collegeProgress.map((college) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(college['college'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              Text(college['percentage'], style: TextStyle(fontWeight: FontWeight.bold, color: college['progress'] == 1.0 ? AppColors.success : AppColors.primary)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: college['progress'],
                              backgroundColor: AppColors.background,
                              color: college['progress'] == 1.0 ? AppColors.success : AppColors.primary,
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}