// lib/gatherer/gatherer_settings_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';
import '../widgets/safe_button.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../widgets/apple_ui.dart';

class GathererSettingsView extends StatefulWidget {
  const GathererSettingsView({super.key});

  @override
  State<GathererSettingsView> createState() => _GathererSettingsViewState();
}

class _GathererSettingsViewState extends State<GathererSettingsView> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();

  bool _hapticFeedback = true;
  static const _hapticPrefKey = 'gatherer_haptic_feedback';

  // --- INTERACTIVE PROFILE STATE ---
  String _firstName = '';
  String _lastName = '';
  String _userTitle = 'Data Gatherer';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadHapticPref();
  }

  Future<void> _loadHapticPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _hapticFeedback = prefs.getBool(_hapticPrefKey) ?? true);
  }

  Future<void> _setHaptic(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticPrefKey, val);
    if (val) HapticFeedback.mediumImpact();
    if (mounted) setState(() => _hapticFeedback = val);
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', user.id)
          .maybeSingle();

      final saoData = await _supabase
          .from('Sao_users')
          .select('roles:roles(Roles)')
          .eq('user_id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (data != null) {
            _firstName = data['first_name'] ?? '';
            _lastName = data['last_name'] ?? '';
          }
          
          if (saoData != null) {
            final role = saoData['roles'];
            _userTitle = role is Map ? role['Roles'] ?? 'Data Gatherer' : 'Data Gatherer';
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditProfileSheet() {
    final TextEditingController firstController = TextEditingController(text: _firstName);
    final TextEditingController lastController = TextEditingController(text: _lastName);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Please ensure your name exactly matches your official school records. This name is used for scanner validation and official workflow reports. Change it wisely.',
                                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInput(label: 'First Name', controller: firstController, icon: Icons.person),
                      const SizedBox(height: 16),
                      _buildInput(label: 'Last Name', controller: lastController, icon: Icons.person_outline),
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
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            setSheetState(() => isSaving = true);
                            try {
                              final result = await _authService.updateProfile(
                                firstName: firstController.text.trim(),
                                lastName: lastController.text.trim(),
                              );
                              
                              if (result.success && mounted) {
                                setState(() {
                                  _firstName = firstController.text.trim();
                                  _lastName = lastController.text.trim();
                                });
                                navigator.pop();
                                messenger.showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.success));
                              } else {
                                throw Exception(result.error);
                              }
                            } catch (e) {
                              setSheetState(() => isSaving = false);
                              if (mounted) {
                                messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                              }
                            }
                          },
                          child: isSaving 
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Save Changes', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
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

  void _showEditEmailDialog() {
    final TextEditingController emailController = TextEditingController(text: _supabase.auth.currentUser?.email ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Edit Email', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter your new email address. You will receive a confirmation link.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'New Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  onPressed: isSaving ? null : () async {
                    final newEmail = emailController.text.trim();
                    if (newEmail.isEmpty || !newEmail.contains('@')) return;

                    setDialogState(() => isSaving = true);
                    // Captured before the await — the dialog context is gone after pop.
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final result = await _authService.updateEmail(newEmail);
                    
                    if (mounted) {
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(result.success ? 'Email updated! Check your inbox for confirmation.' : result.error!),
                          backgroundColor: result.success ? AppColors.success : AppColors.error,
                        ),
                      );
                    }
                  },
                  child: isSaving 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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
            SafeElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text("Delete My Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final rootNavigator = Navigator.of(this.context);
                final messenger = ScaffoldMessenger.of(context);
                navigator.pop();
                final result = await _authService.deleteAccount();
                if (result.success) {
                   if (mounted) rootNavigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                } else {
                   if (mounted) messenger.showSnackBar(SnackBar(content: Text('Error: ${result.error}'), backgroundColor: AppColors.error));
                }
              },
            ),
          ],
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
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    final rootNavigator = Navigator.of(this.context);
                    final newPw = newPasswordController.text.trim();
                    final confirmPw = confirmPasswordController.text.trim();

                    if (newPw.isEmpty || confirmPw.isEmpty) {
                      messenger.showSnackBar(const SnackBar(content: Text('Please fill in all fields.'), backgroundColor: AppColors.error));
                      return;
                    }

                    if (newPw != confirmPw) {
                      messenger.showSnackBar(const SnackBar(content: Text('Passwords do not match.'), backgroundColor: AppColors.error));
                      return;
                    }

                    if (newPw.length < 6) {
                      messenger.showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters.'), backgroundColor: AppColors.error));
                      return;
                    }

                    setDialogState(() => isUpdating = true);
                    
                    try {
                      final result = await _authService.updatePassword(newPw);
                      
                      if (mounted) {
                        if (result.success) {
                          navigator.pop();
                          messenger.showSnackBar(const SnackBar(
                            content: Text('Password updated successfully. Please log in again.'), 
                            backgroundColor: AppColors.success
                          ));
                          
                          // Auto sign out for security
                          await Future.delayed(const Duration(seconds: 2));
                          await _authService.signOut();
                          if (mounted) {
                            rootNavigator.pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const LoginScreen()), 
                              (route) => false
                            );
                          }
                        } else {
                          setDialogState(() => isUpdating = false);
                          messenger.showSnackBar(SnackBar(content: Text(result.error ?? 'Failed to update password.'), backgroundColor: AppColors.error));
                        }
                      }
                    } catch (e) {
                      setDialogState(() => isUpdating = false);
                      if (mounted) {
                        messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                      }
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
    String initials = "U";
    if (_firstName.isNotEmpty) {
      initials = _firstName[0];
      if (_lastName.isNotEmpty) {
        initials += _lastName[0];
      }
    }

    if (_isLoading) {
      return const AppleLoadingState(label: 'Loading gatherer settings…');
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ApplePageHeader(
              eyebrow: 'Data Gatherer',
              title: 'Settings',
              subtitle: 'Profile, scanner feedback, and account security.',
            ),
            const SizedBox(height: 30),
            const AppleSectionHeader(title: 'Profile'),
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
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        child: Text(initials.toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold))
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$_firstName $_lastName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text(_userTitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _showEditProfileSheet,
                            child: const Text('Edit Personal Details', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            const AppleSectionHeader(title: 'Scanner Preferences'),
            const SizedBox(height: 12),
            Card(
              color: AppColors.surface,
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: _buildSwitchTile(
                title: 'Haptic Feedback',
                subtitle: 'Vibrate phone on successful scan.',
                icon: Icons.vibration,
                value: _hapticFeedback,
                onChanged: _setHaptic,
              ),
            ),
            const SizedBox(height: 32),

            const AppleSectionHeader(
              title: 'Security',
              subtitle: 'Email, password, and account controls.',
            ),
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
                      child: const Icon(Icons.email_outlined, color: AppColors.primary),
                    ),
                    title: const Text('Edit Email', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                    onTap: _showEditEmailDialog,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.lock, color: AppColors.primary),
                    ),
                    title: const Text('Edit Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                    onTap: _showChangePasswordDialog,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.delete_forever, color: AppColors.error),
                    ),
                    title: const Text('Delete My Account', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.error),
                    onTap: _showDeleteAccountDialog,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 54,
                child: SafeOutlinedButton(
                  onPressed: () async {
                    final rootNavigator = Navigator.of(context);
                    final confirm = await showLogoutConfirmationDialog(context);
                    if (confirm == true) {
                      if (!context.mounted) return;
                      showLoggingOutOverlay(context);
                      await Future.delayed(const Duration(milliseconds: 1500)); // Show it for 1.5s
                      await _authService.signOut();
                      if (mounted) {
                        rootNavigator.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                              (route) => false,
                        );
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('End Shift & Log Out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
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
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.surface,
        activeTrackColor: AppColors.success,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: AppColors.borderHairline,
      ),
    );
  }
}
