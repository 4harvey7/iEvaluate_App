// lib/gatherer/gatherer_drawer.dart
// The side drawer — slides out from the left when user swipe or tap menu icon.
// Has navigation links, badge counts for failed scans and import errors,
// and the logout button at the bottom. Importente kaayo this drawer.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../core/navigation/role_switch_screen.dart';
import '../core/navigation/role_nav_config.dart';

// the drawer widget — StatefulWidget because it loads badge counts on open
class GathererDrawer extends StatefulWidget {
  final int currentIndex; // which tab is currently active (to highlight in drawer)
  final Function(int) onMenuTap; // callback to switch tabs from the drawer
  final VoidCallback? onImportTap; // callback to open import screen

  /// Pass the already-loaded name and role from the parent screen
  /// so the drawer shows instantly without re-fetching from Supabase.
  /// If we fetch again here, user see "..." every time they open drawer. Bad UX.
  final String userName;
  final String userRole;
  final UserRole? originalRole; // Support role switching

  const GathererDrawer({
    super.key,
    required this.currentIndex,
    required this.onMenuTap,
    this.onImportTap,
    this.userName = '', // default empty, parent should always pass this
    this.userRole = 'Data Gatherer',
    this.originalRole,
  });

  @override
  State<GathererDrawer> createState() => _GathererDrawerState();
}

// the state — loads badge counts for failed scans and import errors
class _GathererDrawerState extends State<GathererDrawer> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService(); // for logout functionality

  // badge counts — shown as little orange numbers on menu items
  int _importErrorCount = 0; // import errors pending review

  // load badge counts when drawer first opens
  @override
  void initState() {
    super.initState();
    _loadImportErrorCount(); // how many import errors need attention
  }

  // get count of pending import errors from the import_errors table
  // shown as badge on the Import Errors menu item
  Future<void> _loadImportErrorCount() async {
    try {
      final response = await _supabase
          .from('import_errors')
          .select('id')
          .eq('status', 'pending');
      if (mounted) setState(() => _importErrorCount = (response as List).length);
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
        overflow: TextOverflow.ellipsis,
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: AppColors.heroGradient),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.textInvertedFaint,
                  child: Text(
                    initials.toUpperCase(),
                    style: const TextStyle(color: AppColors.surface, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  style: const TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.userRole,
                  style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ── Navigation Items ─────────────────────────────────────────
          
          // Google Sheet / Form Import
          _buildDrawerItem(context, Icons.note_add_rounded, 'Google Sheet / Form Import', widget.currentIndex == 6, onTap: () {
            Navigator.pop(context);
            if (widget.onImportTap != null) widget.onImportTap!();
          }),

          // Import Errors — index 4
          _buildDrawerItem(
            context,
            Icons.error_outline,
            'Import Errors',
            widget.currentIndex == 4,
            badge: _importErrorCount,
            onTap: () {
              Navigator.pop(context);
              widget.onMenuTap(4);
            },
          ),
          
          // Settings — index 5
          _buildDrawerItem(context, Icons.settings, 'Settings', widget.currentIndex == 5, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(5);
          }),

          const Divider(), // visual separator before logout

          // ── Role Switcher Return ─────────────────────────────────────────
          if (widget.originalRole != null)
            ListTile(
              leading: const Icon(Icons.keyboard_return_rounded, color: AppColors.primary),
              title: const Text(
                'Return to SAO Admin',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(context); // Close drawer
                // Push the transition screen over the current UI
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => RoleSwitchScreen(
                      targetRoleName: 'SAO Admin',
                      targetIcon: Icons.admin_panel_settings_rounded,
                      onComplete: (switchCtx) {
                        // Safely pop twice: transition screen AND Gatherer Screen
                        int count = 0;
                        Navigator.of(switchCtx).popUntil((_) => count++ >= 2);
                      },
                    ),
                    transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
                  ),
                );
              },
            ),

          if (widget.originalRole != null)
            const Divider(),

          // Log Out — red because it ends the session
          _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
            final confirm = await showLogoutConfirmationDialog(context);
            if (confirm == true) {
              if (!context.mounted) return;
              showLoggingOutOverlay(context);
              await Future.delayed(const Duration(milliseconds: 1500)); // Show it for 1.5s
              await _authService.signOut(); // sign out from supabase
              if (context.mounted) {
                // remove all routes and go to login — user cannot go back
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false, // remove everything from stack
                );
              }
            }
          }),
        ],
      ),
    );
  }
}
