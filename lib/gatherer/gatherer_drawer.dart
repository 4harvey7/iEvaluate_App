// lib/gatherer/gatherer_drawer.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart';
// Note: We deleted the import for data_validation_screen.dart here because the main screen handles it now!

class GathererDrawer extends StatelessWidget {
  final int currentIndex;
  final Function(int) onMenuTap;

  const GathererDrawer({
    super.key,
    required this.currentIndex,
    required this.onMenuTap
  });

  // The helper function lives inside here now!
  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected, {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.red : (isSelected ? AppColors.royalBlue : AppColors.darkGray)),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? Colors.red : (isSelected ? AppColors.royalBlue : AppColors.darkGray),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: AppColors.deepBlue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(radius: 28, backgroundColor: AppColors.white, child: Icon(Icons.document_scanner, color: AppColors.deepBlue, size: 28)),
                SizedBox(height: 12),
                Text('Terminal 2', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Data Gatherer Unit', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),

          // Index 0
          _buildDrawerItem(context, Icons.dashboard, 'Dashboard', currentIndex == 0, onTap: () {
            Navigator.pop(context);
            onMenuTap(0);
          }),

          // Index 1
          _buildDrawerItem(context, Icons.camera_alt, 'Scanner', currentIndex == 1, onTap: () {
            Navigator.pop(context);
            onMenuTap(1);
          }),

          // Index 2 (Now perfectly synced with the main screen list!)
          _buildDrawerItem(context, Icons.fact_check, 'Data Validation', currentIndex == 2, onTap: () {
            Navigator.pop(context);
            onMenuTap(2);
          }),

          // Index 3 (Shifted down)
          _buildDrawerItem(context, Icons.cloud_upload, 'Sync Queue', currentIndex == 3, onTap: () {
            Navigator.pop(context);
            onMenuTap(3);
          }),

          // Index 4 (Shifted down)
          _buildDrawerItem(context, Icons.settings, 'Settings', currentIndex == 4, onTap: () {
            Navigator.pop(context);
            onMenuTap(4);
          }),

          const Divider(),
          _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
          }),
        ],
      ),
    );
  }
}