// lib/gatherer/gatherer_dashboard_view.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GathererDashboardView extends StatelessWidget {
  final String userName;
  final String userRole;
  final String currentTerm;
  final int scanned;
  final int target;
  final int queueCount;
  final int pendingCount;
  final int successCount;
  final int overallSurveyCount;
  final bool n8nOnline;
  final bool checkingN8n;
  final VoidCallback onCheckN8n;
  final VoidCallback onStartScan;
  final VoidCallback onImportData;

  const GathererDashboardView({
    super.key,
    required this.userName,
    required this.userRole,
    required this.currentTerm,
    required this.scanned,
    required this.target,
    required this.queueCount,
    required this.pendingCount,
    required this.successCount,
    required this.overallSurveyCount,
    required this.n8nOnline,
    required this.checkingN8n,
    required this.onCheckN8n,
    required this.onStartScan,
    required this.onImportData,
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
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome, $userName',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  // Current term
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(currentTerm, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Role display
                  Row(
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(userRole, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // N8N System Status (live check)
                  GestureDetector(
                    onTap: checkingN8n ? null : onCheckN8n,
                    child: Row(
                      children: [
                        Text('System Status: ',
                            style: TextStyle(fontSize: 12, color: AppColors.textPrimary.withValues(alpha: 0.7))),
                        if (checkingN8n)
                          const SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                          )
                        else ...[
                          Text(
                            n8nOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 12,
                              color: n8nOnline ? AppColors.success : AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          CircleAvatar(
                              radius: 5,
                              backgroundColor: n8nOnline ? AppColors.success : AppColors.error),
                          const SizedBox(width: 8),
                          Text('(tap to refresh)',
                              style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.6))),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // 2. SCAN BUTTON
            // ==========================================
            SizedBox(
              width: double.infinity,
              height: 120,
              child: ElevatedButton(
                onPressed: onStartScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 5,
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, size: 40),
                    SizedBox(height: 8),
                    Text('START SCAN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ==========================================
            // 🔗 GOOGLE SHEET IMPORT BUTTON
            // ==========================================
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: onImportData,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('IMPORT FROM GOOGLE SHEETS', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // 3. SUPABASE CONNECTION STATS — 4 Cards
            // ==========================================
            const Text('Supabase Connection',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 10),

            // Row 1: Entries Today + Pending
            Row(
              children: [
                _buildStatCard(
                  label: 'ENTRIES TODAY',
                  value: '$scanned',
                  sub: 'submitted today',
                  color: AppColors.primary,
                  icon: Icons.today_rounded,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  label: 'PENDING',
                  value: '$pendingCount',
                  sub: 'not yet synced',
                  color: AppColors.warning,
                  icon: Icons.hourglass_empty_rounded,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Row 2: Success + Overall
            Row(
              children: [
                _buildStatCard(
                  label: 'SUCCESS',
                  value: '$successCount',
                  sub: 'synced this session',
                  color: AppColors.success,
                  icon: Icons.cloud_done_rounded,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  label: 'OVERALL SURVEYS',
                  value: '$overallSurveyCount',
                  sub: 'gathered this term',
                  color: AppColors.textPrimary,
                  icon: Icons.bar_chart_rounded,
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String sub,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.8))),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}