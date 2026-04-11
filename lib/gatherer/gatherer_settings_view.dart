// lib/gatherer/gatherer_settings_view.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart';

class GathererSettingsView extends StatefulWidget {
  const GathererSettingsView({super.key});

  @override
  State<GathererSettingsView> createState() => _GathererSettingsViewState();
}

class _GathererSettingsViewState extends State<GathererSettingsView> {
  bool _autoFlash = false;
  bool _hapticFeedback = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Matches the "Profile" section header style
            const Text('Profile', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // Matches the unified Profile Card
            Card(
              color: AppColors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.royalBlue.withOpacity(0.1),
                        child: const Icon(Icons.document_scanner, color: AppColors.deepBlue, size: 28)
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Terminal 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.darkGray)),
                          SizedBox(height: 4),
                          Text('Data Gatherer Unit', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Matches the unified Settings list style
            const Text('Scanner Preferences', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              color: AppColors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'Auto-Flash',
                    subtitle: 'Turn on flashlight in dark rooms.',
                    icon: Icons.flash_on,
                    value: _autoFlash,
                    onChanged: (val) => setState(() => _autoFlash = val),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSwitchTile(
                    title: 'Haptic Feedback',
                    subtitle: 'Vibrate phone on successful scan.',
                    icon: Icons.vibration,
                    value: _hapticFeedback,
                    onChanged: (val) => setState(() => _hapticFeedback = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Matches the unified Logout button style
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                  );
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('End Shift & Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Unified Switch Tile Helper
  Widget _buildSwitchTile({required String title, required String subtitle, required IconData icon, required bool value, required Function(bool) onChanged}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.royalBlue),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.white,
        activeTrackColor: Colors.green,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.grey.shade300,
      ),
    );
  }
}