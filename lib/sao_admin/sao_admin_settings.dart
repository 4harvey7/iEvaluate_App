// lib/admin/sao_admin_settings.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart';

class SaoAdminSettings extends StatefulWidget {
  const SaoAdminSettings({super.key});

  @override
  State<SaoAdminSettings> createState() => _SaoAdminSettingsState();
}

class _SaoAdminSettingsState extends State<SaoAdminSettings> {
  // --- INTERACTIVE PROFILE STATE ---
  String _userName = 'Rodz Harvey D. Licayan';
  String _userTitle = 'System Administrator';
  String _userOffice = 'Student Affairs Office';

  final List<String> _offices = [
    'Student Affairs Office',
    'IT Department',
    'Registrar',
    'Dean\'s Office',
  ];

  // --- ADMIN SYSTEM STATE ---
  bool _autoUpdateTerm = true; // Automatically syncs semester/year
  String _selectedSemester = '2nd Semester';
  String _selectedYear = '2025-2026';
  bool _strictOcrValidation = true;  // Flags forms with <85% confidence
  bool _autoArchiveReports = false;  // Hides intervention reports once cleared

  @override
  void initState() {
    super.initState();
    // Run the automated date check as soon as the screen loads!
    if (_autoUpdateTerm) {
      _calculateCurrentTerm();
    }
  }

  // ==========================================
  // AUTOMATION LOGIC: ACADEMIC CALENDAR MATH
  // ==========================================
  void _calculateCurrentTerm() {
    DateTime now = DateTime.now();
    int month = now.month;
    int year = now.year;

    setState(() {
      // Academic Year Logic (Assuming academic year starts in August)
      if (month < 8) {
        _selectedYear = '${year - 1}-$year'; // E.g., Jan 2026 belongs to 2025-2026
      } else {
        _selectedYear = '$year-${year + 1}'; // E.g., Sept 2026 belongs to 2026-2027
      }

      // Semester Logic
      if (month >= 8 && month <= 12) {
        _selectedSemester = '1st Semester';
      } else if (month >= 1 && month <= 5) {
        _selectedSemester = '2nd Semester';
      } else {
        _selectedSemester = 'Summer';
      }
    });
  }

  // ==========================================
  // INTERACTIVE: EDIT PROFILE BOTTOM SHEET
  // ==========================================
  void _showEditProfileSheet() {
    final TextEditingController nameController = TextEditingController(text: _userName);
    final TextEditingController titleController = TextEditingController(text: _userTitle);

    String tempSelectedOffice = _userOffice;
    if (!_offices.contains(tempSelectedOffice)) {
      tempSelectedOffice = _offices.first;
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
                          const Text('Edit Admin Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInput(label: 'Full Name', controller: nameController, icon: Icons.person),
                      const SizedBox(height: 16),
                      _buildInput(label: 'System Role', controller: titleController, icon: Icons.shield),
                      const SizedBox(height: 16),

                      // Office Dropdown
                      DropdownButtonFormField<String>(
                        value: tempSelectedOffice,
                        decoration: InputDecoration(
                          labelText: 'Assigned Office',
                          prefixIcon: const Icon(Icons.account_balance, color: AppColors.royalBlue),
                          filled: true,
                          fillColor: AppColors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.royalBlue, width: 2)),
                        ),
                        items: _offices.map((String office) {
                          return DropdownMenuItem<String>(
                            value: office,
                            child: Text(office, style: const TextStyle(color: AppColors.darkGray)),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) setSheetState(() => tempSelectedOffice = newValue);
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
                              _userOffice = tempSelectedOffice;
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

  // ==========================================
  // INTERACTIVE: SYSTEM WIPE DIALOG
  // ==========================================
  void _showResetSystemDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text("Reset Semester Data?"),
            ],
          ),
          content: const Text("This will archive all current evaluations and prep the database for a new semester. This cannot be undone."),
          actions: [
            TextButton(child: const Text("Cancel", style: TextStyle(color: Colors.grey)), onPressed: () => Navigator.pop(context)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text("Reset Data", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database Reset Successfully.'), backgroundColor: Colors.red));
              },
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
    // Dynamically generate initials based on the user's name
    String initials = "AD";
    List<String> nameParts = _userName.replaceAll('Dr. ', '').split(' ');
    if (nameParts.isNotEmpty) {
      initials = nameParts[0][0];
      if (nameParts.length > 1) {
        initials += nameParts[nameParts.length - 1][0]; // Grabs first and last initial
      }
    }

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('System Settings', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
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
              const Text('Administrator Profile', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
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
                            Text('$_userTitle • $_userOffice', style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
              // 2. ACADEMIC TERM MANAGEMENT (Updated with Automation)
              // ==========================================
              const Text('Academic Term Management', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    // The Auto-Sync Master Switch
                    // The Auto-Sync Master Switch
                    _buildSwitchTile(
                      title: 'Auto-Sync with System Clock',
                      subtitle: 'Automatically update semester based on the current date.',
                      icon: Icons.sync, // <--- CHANGED TO THIS
                      value: _autoUpdateTerm,
                      onChanged: (val) {
                        setState(() {
                          _autoUpdateTerm = val;
                          if (_autoUpdateTerm) _calculateCurrentTerm();
                        });
                      },
                      iconColor: Colors.green,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),

                    // The Dropdowns (Disabled if Auto-Sync is ON)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Opacity(
                        opacity: _autoUpdateTerm ? 0.5 : 1.0, // Dims them out when locked
                        child: IgnorePointer(
                          ignoring: _autoUpdateTerm, // Prevents clicking when locked
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Active Semester', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                                  DropdownButton<String>(
                                    value: _selectedSemester,
                                    underline: const SizedBox(),
                                    items: <String>['1st Semester', '2nd Semester', 'Summer'].map((String value) {
                                      return DropdownMenuItem<String>(value: value, child: Text(value));
                                    }).toList(),
                                    onChanged: (newValue) => setState(() => _selectedSemester = newValue!),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Academic Year', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                                  DropdownButton<String>(
                                    value: _selectedYear,
                                    underline: const SizedBox(),
                                    items: <String>['2024-2025', '2025-2026', '2026-2027', '2027-2028'].map((String value) {
                                      return DropdownMenuItem<String>(value: value, child: Text(value));
                                    }).toList(),
                                    onChanged: (newValue) => setState(() => _selectedYear = newValue!),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 3. AI & FORM SETTINGS
              // ==========================================
              const Text('Evaluation Parameters', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildSwitchTile(
                      title: 'Strict OCR Validation',
                      subtitle: 'Flag forms with < 85% confidence to Data Gatherers.',
                      icon: Icons.psychology,
                      value: _strictOcrValidation,
                      onChanged: (val) => setState(() => _strictOcrValidation = val),
                      iconColor: AppColors.royalBlue,
                    ),
                    const Divider(height: 1, indent: 56),
                    _buildSwitchTile(
                      title: 'Auto-Archive Reports',
                      subtitle: 'Hide intervention reports once resolved by the Dean.',
                      icon: Icons.inventory_2,
                      value: _autoArchiveReports,
                      onChanged: (val) => setState(() => _autoArchiveReports = val),
                      iconColor: Colors.orange,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 4. SECURITY & DANGER ZONE
              // ==========================================
              const Text('Security & Administration', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.lock, color: AppColors.royalBlue)),
                      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      onTap: _showChangePasswordDialog,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_forever, color: Colors.red)),
                      title: const Text('Reset Semester Data', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                      onTap: _showResetSystemDialog, // Triggers the Danger Zone alert
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 5. LOG OUT BUTTON
              // ==========================================
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
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