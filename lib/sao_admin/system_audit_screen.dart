// lib/sao_admin/system_audit_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class SystemAuditScreen extends StatefulWidget {
  const SystemAuditScreen({super.key});

  @override
  State<SystemAuditScreen> createState() => _SystemAuditScreenState();
}

class _SystemAuditScreenState extends State<SystemAuditScreen> {
  // --- 1. DATA GATHERER PRODUCTIVITY ---
  final List<Map<String, dynamic>> _gathererProductivity = [
    {'name': 'John (Terminal 1)', 'scanned': 450, 'target': 500, 'color': AppColors.royalBlue},
    {'name': 'Maria (Terminal 2)', 'scanned': 320, 'target': 500, 'color': AppColors.gold},
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
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('System Audit & Health', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live System Metrics',
                style: TextStyle(color: AppColors.darkGray, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Real-time tracking for AI processing, staff productivity, and device synchronization.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),

              // ==========================================
              // 2. AI PROCESSING & ERROR METRICS
              // ==========================================
              const Text('AI Processing Accuracy', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
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
                                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('Perfect Extraction', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('85%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                              Text('Processed perfectly', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 80, color: Colors.grey.shade300),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.warning, color: Colors.orange, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('Manual Validated', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('15%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                              Text('Messy handwriting', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
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
                          Expanded(flex: 85, child: Container(height: 12, color: Colors.green)),
                          Expanded(flex: 15, child: Container(height: 12, color: Colors.orange)),
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
              const Text('Data Gatherer Productivity', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._gathererProductivity.map((staff) {
                double progress = staff['scanned'] / staff['target'];
                return Card(
                  color: AppColors.white,
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
                                  Expanded(child: Text(staff['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray, fontSize: 15), overflow: TextOverflow.ellipsis)),
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
                            backgroundColor: AppColors.lightGray,
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
              const Text('Data Gatherer Sync Status', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._gathererSyncStatus.map((gatherer) {
                return Card(
                  color: AppColors.white,
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: gatherer['isOnline'] ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Icon(
                      gatherer['isOnline'] ? Icons.cloud_done : Icons.cloud_off,
                      color: gatherer['isOnline'] ? Colors.green : Colors.orange,
                      size: 32,
                    ),
                    title: Text(gatherer['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                    subtitle: Text(
                      gatherer['isOnline'] ? 'Fully Synced to Server' : '${gatherer['pending']} forms waiting',
                      style: TextStyle(color: gatherer['isOnline'] ? Colors.grey : Colors.orange.shade800, fontWeight: gatherer['isOnline'] ? FontWeight.normal : FontWeight.bold),
                    ),
                    trailing: gatherer['isOnline']
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : IconButton(
                      icon: const Icon(Icons.sync, color: Colors.orange),
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
              const Text('Campus Evaluation Progress', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
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
                              Expanded(child: Text(college['college'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              Text(college['percentage'], style: TextStyle(fontWeight: FontWeight.bold, color: college['progress'] == 1.0 ? Colors.green : AppColors.royalBlue)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: college['progress'],
                              backgroundColor: AppColors.lightGray,
                              color: college['progress'] == 1.0 ? Colors.green : AppColors.royalBlue,
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