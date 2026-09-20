// lib/gatherer/gatherer_dashboard_view.dart
// The welcome screen for data gatherers.
// Shows who you are, how many you scanned today, and the big START SCAN button.
// Also shows n8n status — is the automation server alive or naa bay problema?
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/apple_ui.dart';

// pure StatelessWidget — all data is passed in from parent, no own state
// parent (DataGathererScreen) manages the state, we just display what we receive
class GathererDashboardView extends StatelessWidget {
  final String userName; // logged-in user full name
  final String userRole; // Data Gatherer, Admin, etc.
  final String currentTerm; // e.g. "1st Semester, 2025-2026"
  final int scanned; // how many scanned today — from supabase
  final int target; // daily target (500) — hard-coded in parent, pray lang maabot
  final int queueCount; // total items in local sync queue
  final int pendingCount; // how many still not uploaded
  final int successCount; // how many successfully uploaded this session
  final int overallSurveyCount; // total surveys for the current term
  final bool n8nOnline; // is the automation server alive
  final bool checkingN8n; // true while pinging n8n
  final VoidCallback onCheckN8n; // tap to re-ping n8n
  final VoidCallback onStartScan; // goes to scanner tab
  final VoidCallback onImportData; // opens Google Sheet import screen

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

  // build the entire dashboard scroll content
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            ApplePageHeader(
              eyebrow: userRole,
              title: 'Welcome, $userName',
              subtitle: currentTerm,
            ),
            const SizedBox(height: 22),

            // ==========================================
            // 1. WELCOME & STATUS CARD
            // Shows user name, current term, role, and n8n status
            // ==========================================
            AppleSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // greet the user by name — personalised touch
                  const AppleSectionHeader(title: 'Connection'),
                  const SizedBox(height: 10),
                  // Current term — shows semester and academic year
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(currentTerm, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Role display — badge icon with the user role text
                  Row(
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(userRole, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // N8N System Status (live check)
                  // tap this to re-ping n8n — if offline, uploads will fail
                  GestureDetector(
                    onTap: checkingN8n ? null : onCheckN8n, // disable tap while already checking
                    child: Row(
                      children: [
                        Text('System Status: ',
                            style: TextStyle(fontSize: 12, color: AppColors.textPrimary.withValues(alpha: 0.7))),
                        if (checkingN8n)
                          // tiny spinner while checking — murag kasagaran sa life
                          const SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                          )
                        else ...[
                          // show "Online" or "Offline" text with matching color
                          Text(
                            n8nOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 12,
                              color: n8nOnline ? AppColors.success : AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // small dot indicator — green or red
                          CircleAvatar(
                              radius: 5,
                              backgroundColor: n8nOnline ? AppColors.success : AppColors.error),
                          const SizedBox(width: 8),
                          // hint to user that they can tap to refresh status
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
            // The biggest, most important button on this screen
            // Tap it to go to the camera scanner tab — this the main job
            // ==========================================
            ApplePressable(
              onTap: onStartScan,
              semanticLabel: 'Start scanning forms',
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.heroGradient),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x2E0066CC), blurRadius: 20, offset: Offset(0, 8)),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, size: 40, color: AppColors.textInverted),
                    SizedBox(height: 8),
                    Text('Start Scan', style: TextStyle(color: AppColors.textInverted, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ==========================================
            // GOOGLE SHEET IMPORT BUTTON
            // Alternative to scanning — import from a Google Sheet link
            // Useful when forms are already digitized, dili na need scan
            // ==========================================
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: onImportData, // navigate to Google Sheet import screen
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('IMPORT FROM GOOGLE SHEETS', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 2), // outlined style
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0, // no shadow — flat look
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // 3. SUPABASE CONNECTION STATS — 4 Cards
            // Shows numbers pulled from actual database — not just local estimates
            // ==========================================
            const AppleSectionHeader(
              title: 'Shift Activity',
              subtitle: 'Live database and local queue totals.',
            ),
            const SizedBox(height: 10),

            // Row 1: Entries Today + Pending
            // "Entries Today" = how many forms actually made it to supabase today
            // "Pending" = how many are queued but not uploaded yet
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
                  color: AppColors.warning, // orange = caution, needs upload
                  icon: Icons.hourglass_empty_rounded,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Row 2: Success + Overall
            // "Success" = how many uploaded this session (may reset on reload)
            // "Overall Surveys" = total count for the whole current term
            Row(
              children: [
                _buildStatCard(
                  label: 'SUCCESS',
                  value: '$successCount',
                  sub: 'synced this session',
                  color: AppColors.success, // green = good
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

            const SizedBox(height: 40), // bottom breathing room so nothing cut off
          ],
        ),
      ),
    );
  }

  // builds a single stat card widget — shown in 2x2 grid below the buttons
  // each card has an icon, label, big number value, and subtitle
  Widget _buildStatCard({
    required String label,
    required String value,
    required String sub,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: AppleMetricCard(
        label: label,
        value: value,
        detail: sub,
        color: color,
        icon: icon,
      ),
    );
  }
}
