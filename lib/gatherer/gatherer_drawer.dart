// lib/gatherer/gatherer_drawer.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';
import 'failed_scans_screen.dart';

class GathererDrawer extends StatefulWidget {
  final int currentIndex;
  final Function(int) onMenuTap;
  /// Pass the already-loaded name and role from the parent screen
  /// so the drawer shows instantly without re-fetching from Supabase.
  final String userName;
  final String userRole;

  const GathererDrawer({
    super.key,
    required this.currentIndex,
    required this.onMenuTap,
    this.userName = '',
    this.userRole = 'Data Gatherer',
  });

  @override
  State<GathererDrawer> createState() => _GathererDrawerState();
}

class _GathererDrawerState extends State<GathererDrawer> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();

  int _failedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFailedCount();
  }

  Future<void> _loadFailedCount() async {
    final count = await FailedScansScreen.getPendingCount(
        _supabase.auth.currentUser?.id ?? '');
    if (mounted) setState(() => _failedCount = count);
  }


  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected,
      {bool isLogout = false, VoidCallback? onTap, int badge = 0}) {
    final color = isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      ),
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning,
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
          : null,
      selected: isSelected,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use parent-provided name; fall back to '...' only if truly not yet loaded
    final displayName = widget.userName.isNotEmpty ? widget.userName : '...';
    final initials = widget.userName.isNotEmpty
        ? widget.userName.trim().split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join()
        : '?';

    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header — same style as instructor/dept head ──────────────
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                  child: Text(
                    initials.toUpperCase(),
                    style: const TextStyle(color: AppColors.surface, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  style: const TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.userRole,
                  style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12),
                ),
              ],
            ),
          ),

          // ── Navigation Items ─────────────────────────────────────────
          _buildDrawerItem(context, Icons.dashboard, 'Dashboard', widget.currentIndex == 0, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(0);
          }),
          _buildDrawerItem(context, Icons.camera_alt, 'Scanner', widget.currentIndex == 1, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(1);
          }),
          _buildDrawerItem(
            context,
            Icons.fact_check,
            'Data Validation',
            widget.currentIndex == 2,
            badge: _failedCount,
            onTap: () {
              Navigator.pop(context);
              widget.onMenuTap(2);
            },
          ),

          _buildDrawerItem(context, Icons.cloud_upload, 'Sync Queue', widget.currentIndex == 3, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(3);
          }),
          _buildDrawerItem(context, Icons.settings, 'Settings', widget.currentIndex == 4, onTap: () {
            Navigator.pop(context);
            widget.onMenuTap(4);
          }),

          const Divider(),
          _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
            await _authService.signOut();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          }),
        ],
      ),
    );
  }
}