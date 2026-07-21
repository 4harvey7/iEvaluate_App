// lib/admin/sao_admin_settings.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';

class SaoAdminSettings extends StatefulWidget {
  const SaoAdminSettings({super.key});

  @override
  State<SaoAdminSettings> createState() => _SaoAdminSettingsState();
}

class _SaoAdminSettingsState extends State<SaoAdminSettings> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();

  // --- INTERACTIVE PROFILE STATE ---
  String _firstName = '';
  String _lastName = '';
  String _userTitle = 'System Administrator';
  String _userOffice = 'Student Affairs Office';
  bool _isLoading = true;

  // --- ADMIN SYSTEM STATE ---
  final TextEditingController _yearSearchController = TextEditingController();
  String _selectedSemester = '2nd Semester';
  String _selectedYear = '2025-2026';
  bool _isUpdatingSettings = false;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadUserProfile(),
        _loadSystemSettings(),
      ]);
    } catch (e) {
      debugPrint('Error refreshing settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSystemSettings() async {
    try {
      // Query with join to the normalized academic_terms table
      final data = await _supabase
          .from('system_settings')
          .select('*, academic_terms(semester, academic_year)')
          .limit(1)
          .maybeSingle();

      if (data != null && mounted) {
        final term = data['academic_terms'];
        setState(() {
          _selectedSemester = term != null ? term['semester'] : '1st Semester';
          _selectedYear = term != null ? term['academic_year'] : '2025-2026';
        });
      }
    } catch (e) {
      debugPrint('Error loading system settings: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Parallelize profile and role fetching with maybeSingle() for safety
      final results = await Future.wait([
        _supabase.from('user_info').select('first_name, last_name').eq('id', user.id).maybeSingle(),
        _supabase.from('Sao_users').select('roles(Roles)').eq('user_id', user.id).maybeSingle(),
      ]);

      if (mounted) {
        final userInfo = results[0];
        final saoData = results[1];
        setState(() {
          if (userInfo != null) {
            _firstName = userInfo['first_name'] ?? '';
            _lastName = userInfo['last_name'] ?? '';
          }
          if (saoData != null && saoData['roles'] != null) {
            _userTitle = (saoData['roles'] as Map)['Roles'] ?? 'SAO Staff';
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  // ==========================================
  // INTERACTIVE: EDIT PROFILE BOTTOM SHEET
  // ==========================================
  void _showEditProfileSheet() {
    final TextEditingController firstController = TextEditingController(text: _firstName);
    final TextEditingController lastController = TextEditingController(text: _lastName);
    final TextEditingController codeController = TextEditingController();
    
    // Original role data to detect changes
    final String originalRole = _userTitle;
    String tempSelectedRole = _userTitle;
    bool needsOTP = false;
    bool isSaving = false;

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
                          Text(needsOTP ? 'Verify Role Change' : 'Edit Admin Profile', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (!needsOTP) ...[
                        _buildInput(label: 'First Name', controller: firstController, icon: Icons.person),
                        const SizedBox(height: 16),
                        _buildInput(label: 'Last Name', controller: lastController, icon: Icons.person_outline),
                        const SizedBox(height: 16),
                        
                        DropdownButtonFormField<String>(
                          value: tempSelectedRole,
                          decoration: InputDecoration(
                            labelText: 'System Role',
                            prefixIcon: const Icon(Icons.shield, color: AppColors.primary),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          items: ['SAO_ADMIN', 'SAO_STAFF'].map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
                          onChanged: (val) => setSheetState(() => tempSelectedRole = val!),
                        ),
                      ] else ...[
                        const Text('Changing your administrative role requires identity verification.', textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        const Text('Enter the 6-digit code sent to your email:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, letterSpacing: 8),
                          decoration: const InputDecoration(hintText: '000000'),
                        ),
                      ],

                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: isSaving ? null : () async {
                            final bool roleChanged = tempSelectedRole != originalRole;
                            
                            if (roleChanged && !needsOTP) {
                              setSheetState(() => isSaving = true);
                              try {
                                await _supabase.functions.invoke('send-admin-code', body: {'email': _supabase.auth.currentUser?.email});
                                setSheetState(() {
                                  needsOTP = true;
                                  isSaving = false;
                                });
                                return;
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                                return;
                              }
                            }

                            setSheetState(() => isSaving = true);
                            try {
                              if (roleChanged) {
                                // Fetch role ID for the new role
                                final roleData = await _supabase.from('roles').select('id').eq('Roles', tempSelectedRole).single();
                                
                                await _supabase.functions.invoke('admin-update-role', body: {
                                  'targetUserId': _supabase.auth.currentUser?.id,
                                  'firstName': firstController.text.trim(),
                                  'lastName': lastController.text.trim(),
                                  'roleId': roleData['id'],
                                  'roleName': tempSelectedRole,
                                  'verificationCode': codeController.text.trim(),
                                  'isAcademic': false
                                });
                                
                                // Role changed successfully, log out
                                if (mounted) {
                                  Navigator.pop(context);
                                  await _authService.signOut();
                                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated. Please log in again.'), backgroundColor: AppColors.success));
                                }
                              } else {
                                // Simple profile update
                                await _authService.updateProfile(
                                  firstName: firstController.text.trim(),
                                  lastName: lastController.text.trim(),
                                );
                                setState(() {
                                  _firstName = firstController.text.trim();
                                  _lastName = lastController.text.trim();
                                });
                                if (mounted) Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.success));
                              }
                            } catch (e) {
                              setSheetState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                            }
                          },
                          child: isSaving 
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(needsOTP ? 'Verify & Update' : 'Save Changes', style: const TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
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
    final TextEditingController currentPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Change Password', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInput(label: 'Current Password', controller: currentPasswordController, isPassword: true),
                  const SizedBox(height: 12),
                  _buildInput(label: 'New Password', controller: newPasswordController, isPassword: true),
                  const SizedBox(height: 12),
                  _buildInput(label: 'Confirm Password', controller: confirmPasswordController, isPassword: true),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isUpdating ? null : () async {
                    final currentPw = currentPasswordController.text.trim();
                    final newPw = newPasswordController.text.trim();
                    final confirmPw = confirmPasswordController.text.trim();

                    if (currentPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all fields.'), backgroundColor: AppColors.error));
                      return;
                    }

                    if (newPw != confirmPw) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match.'), backgroundColor: AppColors.error));
                      return;
                    }

                    if (newPw.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters.'), backgroundColor: AppColors.error));
                      return;
                    }

                    setDialogState(() => isUpdating = true);

                    try {
                      // Step 1: Verify current password by re-signing in
                      final email = _supabase.auth.currentUser?.email ?? '';
                      final verifyResp = await _supabase.auth.signInWithPassword(
                        email: email, password: currentPw);
                      if (verifyResp.user == null) {
                        setDialogState(() => isUpdating = false);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current password is incorrect.'), backgroundColor: AppColors.error));
                        return;
                      }

                      // Step 2: Update to new password
                      final result = await _authService.updatePassword(newPw);
                      
                      if (mounted) {
                        if (result.success) {
                          Navigator.pop(context); // Close dialog
                          
                          // Force sign-out and re-authentication for security
                          await _authService.signOut();
                          
                          if (mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                              (route) => false,
                            );
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password updated. Please log in with your new password.'),
                                backgroundColor: AppColors.success,
                                duration: Duration(seconds: 5),
                              ),
                            );
                          }
                        } else {
                          setDialogState(() => isUpdating = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result.error ?? 'Failed to update password.'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      setDialogState(() => isUpdating = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                    }
                  },
                  child: isUpdating 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : const Text('Update', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // ==========================================
  // INTERACTIVE: DELETE ACCOUNT
  // ==========================================
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error),
              SizedBox(width: 8),
              Text("Delete Account?"),
            ],
          ),
          content: const Text("This action is permanent and cannot be undone. All your profile data will be removed from the system."),
          actions: [
            TextButton(child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)), onPressed: () => Navigator.pop(context)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text("Delete My Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () async {
                Navigator.pop(context);
                final result = await _authService.deleteAccount();
                if (result.success) {
                   if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                } else {
                   if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result.error}'), backgroundColor: AppColors.error));
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _updateSystemSettings(String semester, String year) async {
    setState(() => _isUpdatingSettings = true);
    try {
      // 1. Ensure the term exists in the normalized 'academic_terms' table
      final termData = await _supabase
          .from('academic_terms')
          .upsert({
            'semester': semester,
            'academic_year': year,
          }, onConflict: 'semester, academic_year')
          .select('id')
          .single();

      final termId = termData['id'];

      // 2. Update the singleton system settings
      await _supabase.from('system_settings').upsert({
        'id': 1,
        'auto_sync': false, // Explicitly false as we are now manual
        'current_term_id': termId,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 3. Trigger notifications to all SAO Admins
      try {
        await _supabase.functions.invoke('update-system-settings', body: {
          'semester': semester,
          'academicYear': year,
          'updatedBy': '$_firstName $_lastName',
        });
      } catch (funcError) {
        debugPrint('Edge Function not found or offline: $funcError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('System configuration updated and admins notified.'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      debugPrint('Error updating system settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingSettings = false);
    }
  }

  Widget _buildInput({required String label, IconData? icon, TextEditingController? controller, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primary) : null,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically generate initials based on the user's name
    String initials = "AD";
    if (_firstName.isNotEmpty) {
      initials = _firstName[0];
      if (_lastName.isNotEmpty) {
        initials += _lastName[0];
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('System Settings', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: AppColors.primary,
                  minHeight: 1,
                ),
              )
            : null,
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
              const Text('Administrator Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
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
                        backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                        child: Text(initials.toUpperCase(), style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_firstName $_lastName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text('$_userTitle • $_userOffice', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
              // 2. ACADEMIC TERM MANAGEMENT (Updated with Automation)
              // ==========================================
              const Text('Academic Term Management', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    // The Dropdowns
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Active Semester', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              DropdownButton<String>(
                                value: _selectedSemester,
                                underline: const SizedBox(),
                                items: <String>['1st Semester', '2nd Semester', 'Summer'].map((String value) {
                                  return DropdownMenuItem<String>(value: value, child: Text(value));
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() => _selectedSemester = newValue!);
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Academic Year', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  Text('Search or choose below', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                ],
                              ),
                              SizedBox(
                                width: 120,
                                height: 40,
                                child: TextField(
                                  controller: _yearSearchController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. 1990',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    filled: true,
                                    fillColor: AppColors.background,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              DropdownButton<String>(
                                value: _selectedYear,
                                underline: const SizedBox(),
                                items: () {
                                  List<String> years = [];
                                  String query = _yearSearchController.text.trim();
                                  
                                  if (query.isEmpty) {
                                    // Default future-proof list (2024 to +10 years)
                                    years = List.generate(
                                      (DateTime.now().year + 10) - 2024,
                                      (index) => '${2024 + index}-${2025 + index}'
                                    );
                                  } else {
                                    // Generate based on search
                                    int? year = int.tryParse(query);
                                    if (year != null) {
                                      if (query.length == 4) {
                                        // Exact year search: show this year and next few
                                        for (int i = 0; i < 5; i++) {
                                          years.add('${year + i}-${year + i + 1}');
                                        }
                                      } else if (query.length < 4) {
                                        // Partial search (e.g. "199")
                                        int start = year * (query.length == 3 ? 10 : (query.length == 2 ? 100 : 1000));
                                        int count = query.length == 3 ? 10 : 20; // limit suggestions
                                        for (int i = 0; i < count; i++) {
                                          years.add('${start + i}-${start + i + 1}');
                                        }
                                      }
                                    }
                                  }
                                  
                                  // CRITICAL: Always include the current selected year to prevent crash
                                  if (!years.contains(_selectedYear)) {
                                    years.insert(0, _selectedYear);
                                  }
                                  
                                  return years.toSet().toList(); // Unique items
                                }().map((String value) {
                                  return DropdownMenuItem<String>(value: value, child: Text(value));
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() => _selectedYear = newValue!);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isUpdatingSettings ? null : () async {
                            // Confirmation dialog before applying changes
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                                    SizedBox(width: 8),
                                    Text('Confirm Term Change'),
                                  ],
                                ),
                                content: Text(
                                  'Are you sure you want to change the active term to\n"$_selectedSemester $_selectedYear"?\n\nThis will affect all dashboards, reports, and analytics across the entire app.',
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.textPrimary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Yes, Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              _updateSystemSettings(_selectedSemester, _selectedYear);
                            }
                          },
                          icon: _isUpdatingSettings
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.sync_problem, color: Colors.white),
                          label: const Text('Update System Configuration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              const SizedBox(height: 32),

              // ==========================================
              // 4. SECURITY & DANGER ZONE
              // ==========================================
              const Text('Security & Administration', style: TextStyle(color: AppColors.error, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.lock, color: AppColors.primary)),
                      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: _showChangePasswordDialog,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_forever, color: AppColors.error)),
                      title: const Text('Delete My Account', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.error),
                      onTap: _showDeleteAccountDialog,
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
                  onPressed: () async {
                    await _authService.signOut();
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                    }
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

  // --- Helper: clean toggle switches (reserved for future use) ---
  // _buildSwitchTile removed — not currently used in settings UI
}
