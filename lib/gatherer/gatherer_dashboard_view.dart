// lib/gatherer/gatherer_dashboard_view.dart
// The welcome screen for data gatherers.
// Shows who you are, how many you scanned today, and the big START SCAN button.
// Also shows n8n status — is the automation server alive or naa bay problema?
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';

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
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ==========================================
          // 1. ESPRESSO HERO HEADER
          // Gradient block with warm glow — shows user name, term, role,
          // and the live n8n status pill
          // ==========================================
          Entrance(
            index: 0,
            child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E1608), AppColors.textPrimary],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Stack(
              children: [
                // soft orange glow, upper right — login's signature accent
                Positioned(
                  top: -70,
                  right: -50,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.35),
                          AppColors.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // greet the user by name — personalised touch
                      const Text(
                        'Welcome,',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textInvertedDim,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textInverted,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // Current term — shows semester and academic year
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 13, color: AppColors.textInvertedDim),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(currentTerm,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textInvertedDim),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 14),
                          // Role display — badge icon with the user role text
                          const Icon(Icons.badge_outlined,
                              size: 14, color: AppColors.textInvertedDim),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(userRole,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textInvertedDim),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // N8N System Status (live check)
                      // tap this to re-ping n8n — if offline, uploads will fail
                      GestureDetector(
                        onTap: checkingN8n ? null : onCheckN8n, // disable tap while already checking
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.textInvertedFaint,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('System Status: ',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textInvertedDim)),
                              if (checkingN8n)
                                // tiny spinner while checking — murag kasagaran sa life
                                const SizedBox(
                                  width: 10, height: 10,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.primary),
                                )
                              else ...[
                                // small dot indicator — green or red
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: n8nOnline
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFFCA5A5),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // show "Online" or "Offline" text with matching color
                                Text(
                                  n8nOnline ? 'Online' : 'Offline',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: n8nOnline
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFFCA5A5),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // hint to user that they can tap to refresh status
                                const Text('(tap to refresh)',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textInvertedDim)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ==========================================
                // 2. SCAN BUTTON
                // The biggest, most important button on this screen
                // Tap it to go to the camera scanner tab — this the main job
                // ==========================================
                Entrance(
                  index: 1,
                  child: Pressable(
                  child: Container(
                  width: double.infinity,
                  height: 120, // big button, hard to miss
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDeep],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: onStartScan, // jump to scanner tab
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 40),
                        SizedBox(height: 8),
                        Text('START SCAN',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0)),
                      ],
                    ),
                  ),
                ),
                ),
                ),

                const SizedBox(height: 14),

                // ==========================================
                // GOOGLE SHEET IMPORT BUTTON
                // Alternative to scanning — import from a Google Sheet link
                // Useful when forms are already digitized, dili na need scan
                // ==========================================
                Entrance(
                  index: 2,
                  child: Pressable(
                  child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: onImportData, // navigate to Google Sheet import screen
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('IMPORT FROM GOOGLE SHEETS',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: AppColors.primaryText,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0, // no shadow on the button itself — container carries it
                    ),
                  ),
                ),
                ),
                ),

                const SizedBox(height: 28),

                // ==========================================
                // 3. SUPABASE CONNECTION STATS — 4 Cards
                // Shows numbers pulled from actual database — not just local estimates
                // ==========================================
                const Text('Supabase Connection',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                const SizedBox(height: 12),

                // Row 1: Entries Today + Pending
                // "Entries Today" = how many forms actually made it to supabase today
                // "Pending" = how many are queued but not uploaded yet
                Entrance(
                  index: 3,
                  child: Row(
                  children: [
                    _buildStatCard(
                      label: 'ENTRIES TODAY',
                      value: '$scanned',
                      sub: 'submitted today',
                      color: AppColors.primaryText,
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
                ),

                const SizedBox(height: 12),

                // Row 2: Success + Overall
                // "Success" = how many uploaded this session (may reset on reload)
                // "Overall Surveys" = total count for the whole current term
                Entrance(
                  index: 4,
                  child: Row(
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
                ),

                const SizedBox(height: 40), // bottom breathing room so nothing cut off
              ],
            ),
          ),
        ],
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
    return Expanded( // both cards share equal width in the row
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // icon in soft tinted circle — matches the card accent color
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis, // dont overflow on small screens
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(value,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: color)), // big number
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)), // subtitle below number
          ],
        ),
      ),
    );
  }
}
