// lib/gatherer/gatherer_dashboard_view.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class GathererDashboardView extends StatelessWidget {
  final int scanned;
  final int target;
  final int queueCount;
  final VoidCallback onStartScan; // 👈 Added to trigger the scanner tab!

  const GathererDashboardView({
    super.key,
    required this.scanned,
    required this.target,
    required this.queueCount,
    required this.onStartScan,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // 1. WELCOME & STATUS CARD
            // ==========================================
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Welcome, Rodz Harvey', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.deepBlue),
                      const SizedBox(width: 4),
                      Text('Terminal 2 • Data Gatherer', style: TextStyle(fontSize: 12, color: AppColors.deepBlue.withValues(alpha: 0.7))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('System Status: ', style: TextStyle(fontSize: 12, color: AppColors.deepBlue.withValues(alpha: 0.7))),
                      const Text('Online', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const CircleAvatar(radius: 5, backgroundColor: Colors.green),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ==========================================
            // 2. MASSIVE SCAN ACTION BUTTON
            // ==========================================
            SizedBox(
              width: double.infinity,
              height: 120,
              child: ElevatedButton(
                onPressed: onStartScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold, // High visibility action color
                  foregroundColor: AppColors.deepBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 5,
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, size: 40),
                    SizedBox(height: 8),
                    Text('START NEW DATA ENTRY', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ==========================================
            // 3. STATS GRID ROW
            // ==========================================
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: AppColors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ENTRIES TODAY:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.deepBlue.withValues(alpha: 0.7))),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('$scanned', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.royalBlue)),
                              Text(' / $target', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    color: AppColors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PENDING SYNCS:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.deepBlue.withValues(alpha: 0.7))),
                          const SizedBox(height: 8),
                          Text('$queueCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}