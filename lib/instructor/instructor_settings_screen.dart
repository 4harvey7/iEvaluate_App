// lib/instructor/instructor_settings_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart';

class InstructorSettingsScreen extends StatefulWidget {
  const InstructorSettingsScreen({super.key});

  @override
  State<InstructorSettingsScreen> createState() => _InstructorSettingsScreenState();
}

class _InstructorSettingsScreenState extends State<InstructorSettingsScreen> {
  // --- DUMMY SETTINGS STATE ---
  bool _emailNotifications = true;
  bool _pushNotifications = false;

  // REMOVED: Biometric state variable

  // --- INTERACTIVE PROFILE STATE ---
  String _userName = 'Kazuto Kirigaya';
  String _userTitle = 'Senior Instructor';
  String _userDept = 'Computer Studies'; // Updated default to match dropdown

  // List of available departments for the dropdown
  final List<String> _departments = [
    'Computer Studies',
    'Engineering',
    'Education',
    'Arts and Sciences',
    'Business',
    'Agriculture'
  ];

  // ==========================================
  // INTERACTIVE: EDIT PROFILE BOTTOM SHEET
  // ==========================================
  void _showEditProfileSheet() {
    final TextEditingController nameController = TextEditingController(text: _userName);
    final TextEditingController titleController = TextEditingController(text: _userTitle);

    // Local variable to hold the dropdown selection before saving
    String tempSelectedDept = _userDept;

    // Ensure the current department is actually in the list to prevent dropdown errors
    if (!_departments.contains(tempSelectedDept)) {
      tempSelectedDept = _departments.first;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // StatefulBuilder allows the dropdown to update its value inside the bottom sheet
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInput(label: 'Full Name', controller: nameController, icon: Icons.person),
                      const SizedBox(height: 16),
                      _buildInput(label: 'Job Title', controller: titleController, icon: Icons.work),
                      const SizedBox(height: 16),

                      // 👈 UPDATED: Department is now a Dropdown!
                      DropdownButtonFormField<String>(
                        value: tempSelectedDept,
                        decoration: InputDecoration(
                          labelText: 'Department',
                          prefixIcon: const Icon(Icons.business, color: AppColors.primary),
                          filled: true,
                          fillColor: AppColors.surface, // Changed to white for better contrast
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                        ),
                        items: _departments.map((String dept) {
                          return DropdownMenuItem<String>(
                            value: dept,
                            child: Text(dept, style: const TextStyle(color: AppColors.textPrimary)),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setSheetState(() => tempSelectedDept = newValue);
                          }
                        },
                      ),

                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            // Update the UI state with the new typed values and selected dropdown
                            setState(() {
                              _userName = nameController.text;
                              _userTitle = titleController.text;
                              _userDept = tempSelectedDept;
                            });
                            Navigator.pop(context); // Close sheet
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.success));
                          },
                          child: const Text('Save Changes', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
        );
      },
    );
  }

  // ==========================================
  // INTERACTIVE: CHANGE PASSWORD DIALOG
  // ==========================================
  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Change Password', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInput(label: 'Current Password', isPassword: true),
              const SizedBox(height: 12),
              _buildInput(label: 'New Password', isPassword: true),
              const SizedBox(height: 12),
              _buildInput(label: 'Confirm Password', isPassword: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed securely.'), backgroundColor: AppColors.success));
              },
              child: const Text('Update', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // Helper Widget for Text Inputs inside Dialogs
  Widget _buildInput({required String label, IconData? icon, TextEditingController? controller, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primary) : null,
        filled: true,
        fillColor: AppColors.surface, // Changed to white for better contrast
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Account Settings', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==========================================
              // 1. PROFILE SECTION
              // ==========================================
              const Text('Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: Text(_userName.isNotEmpty ? _userName[0] : 'U', style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text('$_userTitle • $_userDept', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _showEditProfileSheet,
                              child: const Text('Edit Personal Info', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 2. NOTIFICATION PREFERENCES
              // ==========================================
              const Text('Notifications', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildSwitchTile(
                      title: 'Email Alerts',
                      subtitle: 'Get emailed when a new evaluation is processed.',
                      icon: Icons.email,
                      value: _emailNotifications,
                      onChanged: (val) => setState(() => _emailNotifications = val),
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitchTile(
                      title: 'Push Notifications',
                      subtitle: 'Receive alerts directly on your device.',
                      icon: Icons.notifications_active,
                      value: _pushNotifications,
                      onChanged: (val) => setState(() => _pushNotifications = val),
                    ),

                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 3. SECURITY & LOGIN
              // ==========================================
              const Text('Security', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.lock, color: AppColors.primary),
                      ),
                      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: _showChangePasswordDialog,
                    ),
                    // 👈 UPDATED: Biometric login has been fully removed from here.
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 4. LOG OUT BUTTON
              // ==========================================
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
                  icon: const Icon(Icons.logout, color: AppColors.error),
                  label: const Text('Sign Out Securely', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              const Center(
                child: Text('iEvaluate Version 1.0.0 (Prototype)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widget to generate clean toggle switches ---
  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.surface,
        activeTrackColor: AppColors.success,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: AppColors.borderHairline,
      ),
    );
  }
}