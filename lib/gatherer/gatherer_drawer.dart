// lib/gatherer/gatherer_drawer.dart
// The side drawer — slides out from the left when user swipe or tap menu icon.
// Has navigation links, badge counts for failed scans and import errors,
// and the logout button at the bottom. Importente kaayo this drawer.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';
import 'failed_scans_screen.dart';
import '../sao_admin/import_errors_screen.dart';

// the drawer widget — StatefulWidget because it loads badge counts on open
class GathererDrawer extends StatefulWidget {
  final int currentIndex; // which tab is currently active (to highlight in drawer)
  final Function(int) onMenuTap; // callback to switch tabs from the drawer
  /// Pass the already-loaded name and role from the parent screen
  /// so the drawer shows instantly without re-fetching from Supabase.
  /// If we fetch again here, user see "..." every time they open drawer. Bad UX.
  final String userName;
  final String userRole;

  const GathererDrawer({
    super.key,
    required this.currentIndex,
    required this.onMenuTap,
    this.userName = '', // default empty, parent should always pass this
    this.userRole = 'Data Gatherer',
  });

  @override
  State<GathererDrawer> createState() => _GathererDrawerState();
}

// the state — loads badge counts for failed scans and import errors
class _GathererDrawerState extends State<GathererDrawer> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService(); // for logout functionality

  // badge counts — shown as little orange numbers on menu items
  int _failedCount = 0; // failed scans pending correction
  int _importErrorCount = 0; // import errors pending review

  // load badge counts when drawer first opens
  @override
  void initState() {
    super.initState();
    _loadFailedCount(); // how many failed scans need attention
    _loadImportErrorCount(); // how many import errors need attention
  }

  // get count of failed scans for this user — shown as badge on Data Validation item
  Future<void> _loadFailedCount() async {
    final count = await FailedScansScreen.getPendingCount(
        _supabase.auth.currentUser?.id ?? ''); // use empty string if no user (safe fallback)
    if (mounted) setState(() => _failedCount = count);
  }

  // get count of pending import errors from the import_errors table
  // shown as badge on the Import Errors menu item
  Future<void> _loadImportErrorCount() async {
    try {
      final res = await _supabase
          .from('import_errors')
          .select('id')
          .eq('status', 'pending'); // only pending ones, not resolved
      if (mounted) {
        setState(() => _importErrorCount = (res as List).length);
      }
    } catch (_) {} // silently fail — if this fail, badge just shows 0. bahala na.
  }


  // build a single drawer menu item — list tile with icon, title, selected highlight, optional badge
  // isLogout = true makes it red, because logout is a destructive-ish action
  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected,
      {bool isLogout = false, VoidCallback? onTap, int badge = 0}) {
    final color = isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      ),
      // show badge only if count > 0 — orange pill with white number
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning, // orange badge — something needs attention
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            )
          : null, // no badge when count is 0
      selected: isSelected,
      onTap: onTap,
    );
  }

  // build the full drawer — header with user info + navigation items + logout
  @override
  Widget build(BuildContext context) {
    // Use parent-provided name; fall back to '...' only if truly not yet loaded
    final displayName = widget.userName.isNotEmpty ? widget.userName : '...';
    // extract initials from the display name — e.g. "John Doe" -> "JD"
    final initials = widget.userName.isNotEmpty
        ? widget.userName.trim().split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join()
        : '?'; // fallback to '?' if name not loaded yet

    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header — same style as instructor/dept head ──────────────
          // dark header with avatar, name, and role
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end, // push content to bottom of header
              children: [
                // circle avatar with initials — no photo, just letters
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                  child: Text(
                    initials.toUpperCase(), // uppercase initials always
                    style: const TextStyle(color: AppColors.surface, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                // full display name
                Text(
                  displayName,
                  style: const TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                // role below name — smaller and dimmer
                Text(
                  widget.userRole,
                  style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12),
                ),
              ],
            ),
          ),

          // ── Navigation Items ─────────────────────────────────────────
          // Dashboard — index 0 — the home screen with stats and buttons
          _buildDrawerItem(context, Icons.dashboard, 'Dashboard', widget.currentIndex == 0, onTap: () {
            Navigator.pop(context); // close drawer first
            widget.onMenuTap(0); // then switch tab
          }),
          // Scanner — index 1 — camera view for scanning forms
          _buildDrawerItem(context, Icons.camera_alt, 'Scanner', widget.currentIndex == 1, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(1);
          }),
          // Data Validation — index 2 — has badge for failed scans count
          _buildDrawerItem(
            context,
            Icons.fact_check,
            'Data Validation',
            widget.currentIndex == 2,
            badge: _failedCount, // show count of failed scans needing correction
            onTap: () {
              Navigator.pop(context);
              widget.onMenuTap(2);
            },
          ),

          // Import Errors — not a tab, navigates to separate screen
          // has badge for import error count
          _buildDrawerItem(
            context,
            Icons.error_outline,
            'Import Errors',
            false, // never shown as "selected" since it a separate screen
            badge: _importErrorCount,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImportErrorsScreen()),
              ).then((_) => _loadImportErrorCount()); // refresh badge on return
            },
          ),
          // Sync Queue — index 3 — shows local upload queue status
          _buildDrawerItem(context, Icons.cloud_upload, 'Sync Queue', widget.currentIndex == 3, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(3);
          }),
          // Settings — index 4 — profile, haptic, password, logout
          _buildDrawerItem(context, Icons.settings, 'Settings', widget.currentIndex == 4, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(4);
          }),

          const Divider(), // visual separator before logout
          // Log Out — red because it ends the session
          _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
            await _authService.signOut(); // sign out from supabase
            if (context.mounted) {
              // remove all routes and go to login — user cannot go back
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false, // remove everything from stack
              );
            }
          }),
        ],
      ),
    );
  }
}