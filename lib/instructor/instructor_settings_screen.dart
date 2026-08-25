// lib/instructor/instructor_settings_screen.dart
// The account settings page. This is where the instructor can edit their name,
// change password, or do the extreme action of deleting their whole account.
// Proceed with caution. Especially the delete part. Dili pwede undo.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';
import '../widgets/safe_button.dart';
import '../widgets/logout_confirmation_dialog.dart';


// Simple StatefulWidget — needs state because profile data loads after build
class InstructorSettingsScreen extends StatefulWidget {
  const InstructorSettingsScreen({super.key});

  @override
  State<InstructorSettingsScreen> createState() => _InstructorSettingsScreenState();
}

class _InstructorSettingsScreenState extends State<InstructorSettingsScreen> {
  // Supabase client and auth service — our connection to the backend gods
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();

  // --- INTERACTIVE PROFILE STATE ---
  // These hold the current profile values — start empty, filled after load
  String _firstName = '';
  String _lastName = '';
  String _userTitle = 'Instructor'; // default title if fetch fails
  String _userDept = 'Computer Studies'; // default dept — pray it matches actual one
  bool _isLoading = true; // show spinner until data arrives
  bool _pushNotificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile(); // kick off the profile fetch immediately
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _pushNotificationsEnabled = prefs.getBool('instructor_push_notifications') ?? true;
      });
    }
  }

  Future<void> _togglePushNotifications(bool value) async {
    setState(() {
      _pushNotificationsEnabled = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('instructor_push_notifications', value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? 'Push notifications enabled.' : 'Push notifications disabled.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Loads instructor profile from Supabase.
  // Does two queries at once (in parallel) to save time — smart, not lazy.
  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        // No logged-in user? Just stop loading and show whatever we have
        setState(() => _isLoading = false);
        return;
      }

      // Run queries in parallel to save time and reduce main thread waiting
      final results = await Future.wait([
        _supabase
            .from('user_info')
            .select('first_name, last_name')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase
            .from('department_table')
            .select('department_name:Department_name_ID(d_name), roles:roles(Roles)')
            .eq('user_id', user.id)
            .maybeSingle(),
      ]);

      final data = results[0]; // first_name, last_name
      final deptData = results[1]; // department and role

      if (mounted) {
        setState(() {
          if (data != null) {
            _firstName = data['first_name'] ?? '';
            _lastName = data['last_name'] ?? '';
          }
          
          if (deptData != null) {
            final dept = deptData['department_name'];
            _userDept = dept is Map ? dept['d_name'] ?? 'General' : 'General';
            
            final role = deptData['roles'];
            _userTitle = role is Map ? role['Roles'] ?? 'Instructor' : 'Instructor';
          }
          
          _isLoading = false; // done loading, time to show the goods
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      // Even on error, stop the spinner so user is not stuck forever staring at it
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // INTERACTIVE: EDIT PROFILE BOTTOM SHEET
  // ==========================================
  // Shows a bottom sheet where the instructor can edit their first and last name.
  // Has its own save button that hits Supabase and updates state on success.
  void _showEditProfileSheet() {
    final TextEditingController firstController = TextEditingController(text: _firstName);
    final TextEditingController lastController = TextEditingController(text: _lastName);
    bool isSaving = false; // prevent double-tap spam while saving

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // allows sheet to resize when keyboard appears
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                // Push sheet up when keyboard is open so the fields are visible
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
                          // Close button — for when the user change their mind
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning.withOpacity(0.5)),
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
                          // Disable button while saving to avoid double-click disaster
                          onPressed: isSaving ? null : () async {
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            setSheetState(() => isSaving = true);
                            try {
                              // Call auth service to update name in the database
                              final result = await _authService.updateProfile(
                                firstName: firstController.text.trim(),
                                lastName: lastController.text.trim(),
                              );
                              
                              if (result.success) {
                                // Update local state immediately so UI reflects the change
                                setState(() {
                                  _firstName = firstController.text.trim();
                                  _lastName = lastController.text.trim();
                                });
                                if (mounted) navigator.pop();
                                messenger.showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.success));
                              } else {
                                throw Exception(result.error);
                              }
                            } catch (e) {
                              setSheetState(() => isSaving = false);
                              messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                            }
                          },
                          // Show spinner while saving, text when idle
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

  // ==========================================
  // INTERACTIVE: EDIT ACADEMIC INFO
  // ==========================================
  void _showEditAcademicInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Academic Info', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          content: const Text(
            'Your Academic Information (Role and Department) is managed by the system administrator to maintain data integrity.\n\n'
            'If you need to change your department or title, please contact the SAO Admin.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Understood', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // INTERACTIVE: EDIT EMAIL
  // ==========================================
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
                    final result = await _authService.updateEmail(newEmail);
                    
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
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

  // ==========================================
  // INTERACTIVE: DELETE ACCOUNT
  // ==========================================
  // Shows a confirmation dialog before deleting the account.
  // This is the danger zone. No undo. Wala gyud. Think before tapping.
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
            // Cancel button — the safe exit when the user realizes it was a bad idea
            TextButton(child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)), onPressed: () => Navigator.pop(context)),
            SafeElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text("Delete My Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                navigator.pop(); // close dialog first
                final result = await _authService.deleteAccount(); // the point of no return
                if (result.success) {
                  // Account deleted — kick back to login screen, no route history left
                   if (mounted) navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
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
  // Three-step password change: verify current, enter new, confirm new.
  // Must match, must be at least 6 chars, then logs out automatically after success.
  void _showChangePasswordDialog() {
    final TextEditingController currentPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    bool isUpdating = false; // prevent double submit

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Change Password', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInput(label: 'Current Password', controller: currentPasswordController, isPassword: true),
                    const SizedBox(height: 12),
                    _buildInput(label: 'New Password', controller: newPasswordController, isPassword: true),
                    const SizedBox(height: 12),
                    _buildInput(label: 'Confirm Password', controller: confirmPasswordController, isPassword: true),
                  ],
                ),
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
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final rootNavigator = Navigator.of(this.context);
                  final currentPw = currentPasswordController.text.trim();
                  final newPw = newPasswordController.text.trim();
                  final confirmPw = confirmPasswordController.text.trim();

                  // Validation 1: Cannot leave fields empty, ayaw!
                  if (currentPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
                    messenger.showSnackBar(const SnackBar(content: Text('Please fill in all fields.'), backgroundColor: AppColors.error));
                    return;
                  }

                  // Validation 2: New and confirm passwords must match exactly
                  if (newPw != confirmPw) {
                    messenger.showSnackBar(const SnackBar(content: Text('Passwords do not match.'), backgroundColor: AppColors.error));
                    return;
                  }

                  // Validation 3: Password must be at least 6 characters long
                  if (newPw.length < 6) {
                    messenger.showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters.'), backgroundColor: AppColors.error));
                    return;
                  }

                  setDialogState(() => isUpdating = true); // show spinner
                  
                  try {
                    // Step 1: Verify current password by re-signing in — must confirm identity first
                    final email = _supabase.auth.currentUser?.email ?? '';
                    final verifyResp = await _supabase.auth.signInWithPassword(
                        email: email, password: currentPw);
                    if (verifyResp.user == null) {
                      // Wrong current password — balik ka
                      setDialogState(() => isUpdating = false);
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Current password is incorrect.'),
                          backgroundColor: AppColors.error));
                      return;
                    }

                    // Step 2: Update to new password using auth service
                    final result = await _authService.updatePassword(newPw);
                    if (!mounted) return;
                    if (result.success) {
                      navigator.pop(); // close dialog first
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Password updated. Please log in again.'),
                        backgroundColor: AppColors.success,
                      ));
                      // Small delay so the user can see the success message before logout
                      await Future.delayed(const Duration(seconds: 2));
                      await _authService.signOut(); // force re-login for security
                      if (mounted) {
                        rootNavigator.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false, // clear all routes — fresh start
                        );
                      }
                    } else {
                      setDialogState(() => isUpdating = false);
                      messenger.showSnackBar(SnackBar(
                        content: Text(result.error ?? 'Failed to update password.'),
                        backgroundColor: AppColors.error,
                      ));
                    }
                  } catch (e) {
                    setDialogState(() => isUpdating = false);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                    }
                  }
                },
                  // Spinner when updating, text when idle — basin ma confuse user
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

  // Reusable text field widget for forms — handles labels, icons, and password masking
  Widget _buildInput({required String label, IconData? icon, TextEditingController? controller, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword, // hide text if password field, importente for security
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
    // Calculate initials from name — e.g. "Juan dela Cruz" → "JD"
    String initials = "U"; // "U" for Unknown if name not loaded
    if (_firstName.isNotEmpty) {
      initials = _firstName[0];
      if (_lastName.isNotEmpty) {
        initials += _lastName[0]; // combine first letters
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.surface),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Account Settings', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section: Profile — shows avatar, name, title, and edit link
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
                      // Circle avatar with initials — no photo upload yet, bahala na
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        child: Text(initials.toUpperCase(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Full name display
                            Text('$_firstName $_lastName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            // Title and dept on the same line
                            Text('$_userTitle • $_userDept', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            // Tap this to open the edit profile bottom sheet
                            GestureDetector(
                              onTap: _showEditProfileSheet,
                              child: const Text('Edit Personal Details', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _showEditAcademicInfoDialog,
                              child: const Text('Edit Academic Info', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Section: Notifications — manage push notification preferences
              const Text('Notifications', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.notifications_active, color: AppColors.primary),
                  ),
                  title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  subtitle: const Text('Receive evaluation updates and system alerts directly on your device.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: Switch.adaptive(
                    value: _pushNotificationsEnabled,
                    activeTrackColor: AppColors.primary,
                    onChanged: _togglePushNotifications,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Section: Security & Danger Zone — where the brave (and reckless) go
              const Text('Security & Danger Zone', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    // Edit Email tile
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
                    // Change password tile — opens the 3-field password dialog
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
                    // Delete account tile — the red one. Handle with care. Wala undo.
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

              // Big red sign-out button at the bottom — clear and hard to miss
              SizedBox(
                width: double.infinity,
                height: 54,
                child: SafeOutlinedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final confirm = await showLogoutConfirmationDialog(context);
                    if (confirm == true) {
                      if (!mounted) return;
                      showLoggingOutOverlay(context);
                      await Future.delayed(const Duration(milliseconds: 1500)); // Show it for 1.5s
                      await _authService.signOut(); // clear session from Supabase
                      if (mounted) {
                        // Send to login screen, remove all previous routes so user cant go back
                        navigator.pushAndRemoveUntil(
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
                      Text('Sign Out Securely', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Version label — just the prototype badge at the very bottom
              const Center(
                child: Text('iEvaluate Version 1.0.0 (Prototype)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
