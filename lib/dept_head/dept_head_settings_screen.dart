// lib/dept_head/dept_head_settings_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart';

class DeptHeadSettingsScreen extends StatefulWidget {
  const DeptHeadSettingsScreen({super.key});

  @override
  State<DeptHeadSettingsScreen> createState() => _DeptHeadSettingsScreenState();
}

class _DeptHeadSettingsScreenState extends State<DeptHeadSettingsScreen> {
  // --- EXECUTIVE NOTIFICATION STATE ---
  bool _lowPerformanceAlerts = true;  // Alert when instructor drops below 3.0
  bool _negativeSentimentAlerts = true; // Alert when AI detects angry comments
  bool _weeklyDepartmentDigest = true;

  // --- INTERACTIVE PROFILE STATE ---
  String _userName = 'Dr. Asuna Yuuki';
  String _userTitle = 'Dean';
  String _userCollege = 'College of Computer Studies';

  // List of available colleges for the dropdown
  final List<String> _colleges = [
    'College of Computer Studies',
    'College of Engineering',
    'College of Education',
    'College of Arts and Sciences',
    'College of Business',
    'College of Agriculture'
  ];

  // ==========================================
  // INTERACTIVE: EDIT PROFILE BOTTOM SHEET
  // ==========================================
  void _showEditProfileSheet() {
    final TextEditingController nameController = TextEditingController(text: _userName);
    final TextEditingController titleController = TextEditingController(text: _userTitle);

    String tempSelectedCollege = _userCollege;
    if (!_colleges.contains(tempSelectedCollege)) {
      tempSelectedCollege = _colleges.first;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.lightGray,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Edit Executive Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInput(label: 'Full Name', controller: nameController, icon: Icons.person),
                      const SizedBox(height: 16),
                      _buildInput(label: 'Job Title', controller: titleController, icon: Icons.work),
                      const SizedBox(height: 16),

                      // College Dropdown
                      DropdownButtonFormField<String>(
                        value: tempSelectedCollege,
                        decoration: InputDecoration(
                          labelText: 'College / Department',
                          prefixIcon: const Icon(Icons.account_balance, color: AppColors.royalBlue),
                          filled: true,
                          fillColor: AppColors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.royalBlue, width: 2)),
                        ),
                        items: _colleges.map((String college) {
                          return DropdownMenuItem<String>(
                            value: college,
                            child: Text(college, style: const TextStyle(color: AppColors.darkGray)),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) setSheetState(() => tempSelectedCollege = newValue);
                        },
                      ),

                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            setState(() {
                              _userName = nameController.text;
                              _userTitle = titleController.text;
                              _userCollege = tempSelectedCollege;
                            });
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green));
                          },
                          child: const Text('Save Changes', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
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
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Change Password', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
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
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed securely.'), backgroundColor: Colors.green));
              },
              child: const Text('Update', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInput({required String label, IconData? icon, TextEditingController? controller, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.royalBlue) : null,
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.royalBlue, width: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get the initials for the avatar (e.g., "Dr. Asuna Yuuki" -> "AY")
    String initials = "U";
    List<String> nameParts = _userName.replaceAll('Dr. ', '').split(' ');
    if (nameParts.isNotEmpty) {
      initials = nameParts[0][0];
      if (nameParts.length > 1) {
        initials += nameParts[1][0];
      }
    }

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Account Settings', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
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
              const Text('Executive Profile', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
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
                        backgroundColor: AppColors.gold.withOpacity(0.2),
                        child: Text(initials.toUpperCase(), style: const TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.darkGray)),
                            const SizedBox(height: 4),
                            Text('$_userTitle • $_userCollege', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _showEditProfileSheet,
                              child: const Text('Edit Personal Info', style: TextStyle(color: AppColors.royalBlue, fontWeight: FontWeight.bold, fontSize: 13)),
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
              // 2. MANAGEMENT ALERT PREFERENCES
              // ==========================================
              const Text('Management Alerts', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildSwitchTile(
                      title: 'Low Performance Alerts',
                      subtitle: 'Notify me immediately if an instructor drops below a 3.0 average.',
                      icon: Icons.trending_down,
                      value: _lowPerformanceAlerts,
                      onChanged: (val) => setState(() => _lowPerformanceAlerts = val),
                      iconColor: Colors.red,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitchTile(
                      title: 'AI Sentiment Flags',
                      subtitle: 'Alert me to highly negative student feedback regarding any faculty.',
                      icon: Icons.warning_amber_rounded,
                      value: _negativeSentimentAlerts,
                      onChanged: (val) => setState(() => _negativeSentimentAlerts = val),
                      iconColor: Colors.orange,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitchTile(
                      title: 'Weekly Department Digest',
                      subtitle: 'Receive a comprehensive summary of all department evaluations.',
                      icon: Icons.analytics,
                      value: _weeklyDepartmentDigest,
                      onChanged: (val) => setState(() => _weeklyDepartmentDigest = val),
                      iconColor: AppColors.royalBlue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 3. SECURITY
              // ==========================================
              const Text('Security', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.lock, color: AppColors.royalBlue),
                      ),
                      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      onTap: _showChangePasswordDialog,
                    ),
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
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('Sign Out Securely', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              const Center(
                child: Text('iEvaluate Version 1.0.0 (Prototype)', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
    required Color iconColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: iconColor),
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