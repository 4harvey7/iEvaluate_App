// lib/dept_head/dept_head_settings_screen.dart
// Settings screen for the dept head — where they change name, password, and other stuff.
// Also where they can delete their account if they feeling dramatic. ayaw.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';
import '../widgets/safe_button.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../widgets/apple_ui.dart';
import '../widgets/deactivate_account_dialog.dart';


// The settings widget — stateful because we load and change user info here
class DeptHeadSettingsScreen extends StatefulWidget {
  const DeptHeadSettingsScreen({super.key});

  @override
  State<DeptHeadSettingsScreen> createState() => _DeptHeadSettingsScreenState();
}

class _DeptHeadSettingsScreenState extends State<DeptHeadSettingsScreen> {
  // Supabase and auth — the backbone of this whole operation
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();

  // --- EXECUTIVE NOTIFICATION STATE ---
  // These toggles control which alerts the dean receive — all ON by default
  // because missing a problem is worse than getting too many notifs
  bool _lowPerformanceAlerts = true;  // Alert when instructor drops below 3.0
  bool _negativeSentimentAlerts = true; // Alert when AI detects angry comments
  bool _weeklyDepartmentDigest = true; // Weekly summary — good for busy dean

  // --- INTERACTIVE PROFILE STATE ---
  // These hold the user's actual name and role — loaded from database
  String _firstName = '';
  String _lastName = '';
  String _userTitle = 'Dean'; // Default title — hope they really are a Dean
  String _userCollege = 'College'; // Default college — will be replaced by real data
  bool _isLoading = true; // Show spinner while fetching profile

  // Called on screen load — kick off the profile fetch immediately
  @override
  void initState() {
    super.initState();
    _loadUserProfile(); // Go get the user data from Supabase
  }

  // Fetches the user profile from database — name, role, department
  // If user is null (no session), just stop loading. dili ta panic.
  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        // No logged in user — unusual, but handle it gracefully
        setState(() => _isLoading = false);
        return;
      }

      // Fetch first and last name and alert prefs from user_info table
      final data = await _supabase
          .from('user_info')
          .select('first_name, last_name, alert_performance, alert_sentiment, alert_digest')
          .eq('id', user.id)
          .maybeSingle();

      // Fetch dept name and role title — both importente for the profile card
      final deptData = await _supabase
          .from('department_table')
          .select('department_name:Department_name_ID(d_name), roles:roles(Roles)')
          .eq('user_id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          // Apply name data if it came back non-null
          if (data != null) {
            _firstName = data['first_name'] ?? 'Dean';
            _lastName = data['last_name'] ?? '';
            // Load alert settings (default to true if null in DB)
            _lowPerformanceAlerts = data['alert_performance'] ?? true;
            _negativeSentimentAlerts = data['alert_sentiment'] ?? true;
            _weeklyDepartmentDigest = data['alert_digest'] ?? true;
          }
          
          if (deptData != null) {
            // dept and role might come as Map or String — handle both like a pro
            final dept = deptData['department_name'];
            _userCollege = dept is Map ? dept['d_name'] ?? 'General' : 'General';
            
            final role = deptData['roles'];
            _userTitle = role is Map ? role['Roles'] ?? 'Dept Head' : 'Dept Head';
          }
          
          _isLoading = false; // Done loading — show the actual UI now
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false); // Even if error, stop the spinner
    }
  }

  // ==========================================
  // INTERACTIVE: EDIT PROFILE BOTTOM SHEET
  // A bottom sheet pops up so user can edit their name.
  // Only first and last name — no changing role or dept here.
  // ==========================================
  void _showEditProfileSheet() {
    // Pre-fill inputs with current name — dili ta make user type from scratch
    final TextEditingController firstController = TextEditingController(text: _firstName);
    final TextEditingController lastController = TextEditingController(text: _lastName);
    bool isSaving = false; // Prevent double submit
    bool isSheetOpen = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allow sheet to grow when keyboard appears
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
                child: SingleChildScrollView(
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
                            const Text('Edit Executive Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            // X button to dismiss without saving — disabled while saving
                            IconButton(
                              icon: const Icon(Icons.close, color: AppColors.textSecondary),
                              onPressed: isSaving ? null : () {
                                if (isSheetOpen && sheetContext.mounted) {
                                  isSheetOpen = false;
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                            ),
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
                        // Form fields — simple first and last name
                        _buildInput(label: 'First Name', controller: firstController, icon: Icons.person),
                        const SizedBox(height: 16),
                        _buildInput(label: 'Last Name', controller: lastController, icon: Icons.person_outline),
                        const SizedBox(height: 24),

                        // Save button — disabled while saving
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.textPrimary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSaving ? null : () async {
                              final newFirst = firstController.text.trim();
                              final newLast = lastController.text.trim();
                              final messenger = ScaffoldMessenger.of(this.context);

                              if (newFirst.isEmpty || newLast.isEmpty) {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Please fill in both first and last name.'), backgroundColor: AppColors.error),
                                );
                                return;
                              }

                              FocusScope.of(context).unfocus();
                              if (isSheetOpen && sheetContext.mounted) {
                                setSheetState(() => isSaving = true);
                              }

                              try {
                                // Update profile via auth service
                                final result = await _authService.updateProfile(
                                  firstName: newFirst,
                                  lastName: newLast,
                                );
                                
                                if (result.success) {
                                  // Update local state so UI updates immediately
                                  if (mounted) {
                                    setState(() {
                                      _firstName = newFirst;
                                      _lastName = newLast;
                                    });
                                  }
                                  if (isSheetOpen && sheetContext.mounted) {
                                    isSheetOpen = false;
                                    Navigator.of(sheetContext).pop();
                                  }
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.success),
                                  );
                                } else {
                                  throw Exception(result.error ?? 'Failed to update profile.');
                                }
                              } catch (e) {
                                // Reset saving state so user can retry
                                if (isSheetOpen && sheetContext.mounted) {
                                  setSheetState(() => isSaving = false);
                                }
                                final cleanError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Error: $cleanError'), backgroundColor: AppColors.error),
                                );
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
                ),
              );
            }
        );
      },
    ).whenComplete(() {
      isSheetOpen = false;
      firstController.dispose();
      lastController.dispose();
    });
  }

  // ==========================================
  // INTERACTIVE: EDIT EMAIL
  // ==========================================
  void _showEditEmailDialog() {
    final TextEditingController emailController = TextEditingController(text: _supabase.auth.currentUser?.email ?? '');
    bool isSaving = false;
    bool isDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Edit Email', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              content: SingleChildScrollView(
                child: Column(
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
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () {
                    if (isDialogOpen && dialogContext.mounted) {
                      isDialogOpen = false;
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  onPressed: isSaving ? null : () async {
                    final newEmail = emailController.text.trim();
                    final messenger = ScaffoldMessenger.of(this.context);

                    if (newEmail.isEmpty || !newEmail.contains('@')) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Please enter a valid email address.'), backgroundColor: AppColors.error),
                      );
                      return;
                    }

                    final currentEmail = _supabase.auth.currentUser?.email ?? '';
                    if (newEmail.toLowerCase() == currentEmail.toLowerCase()) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('This is already your current email address.'), backgroundColor: AppColors.error),
                      );
                      return;
                    }

                    FocusScope.of(context).unfocus();
                    if (isDialogOpen && dialogContext.mounted) {
                      setDialogState(() => isSaving = true);
                    }

                    try {
                      final result = await _authService.updateEmail(newEmail);
                      
                      if (result.success) {
                        if (isDialogOpen && dialogContext.mounted) {
                          isDialogOpen = false;
                          Navigator.of(dialogContext).pop();
                        }
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Email updated! Check your inbox for confirmation.'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } else {
                        if (isDialogOpen && dialogContext.mounted) {
                          setDialogState(() => isSaving = false);
                        }
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(result.error ?? 'Failed to update email.'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    } catch (e) {
                      if (isDialogOpen && dialogContext.mounted) {
                        setDialogState(() => isSaving = false);
                      }
                      final cleanError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Error: $cleanError'),
                          backgroundColor: AppColors.error,
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
    ).whenComplete(() {
      isDialogOpen = false;
      emailController.dispose();
    });
  }

  // ==========================================
  // INTERACTIVE: DELETE ACCOUNT
  // The nuclear option — shown as a confirmation dialog first.
  // Very permanent. very scary. importente to warn the user good.
  // ==========================================
  // Deactivation lives in showDeactivateAccountDialog: warning, emailed code,
  // then the blocking "Deactivating account…" overlay. All this screen still
  // decides is where the user lands afterwards.
  Future<void> _showDeleteAccountDialog() async {
    // Captured before the await -- after deactivation the session is gone and
    // this State may be on its way out.
    final navigator = Navigator.of(context);
    final deactivated = await showDeactivateAccountDialog(context);
    if (!mounted || deactivated != true) return;
    // No route history left to go back to.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ==========================================
  // INTERACTIVE: CHANGE PASSWORD DIALOG
  // Three fields — current, new, confirm.
  // After success, auto sign out for security. bahala na, security first.
  // ==========================================
  void _showChangePasswordDialog() {
    // Three separate controllers for three fields — dili ta reuse
    final TextEditingController currentPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    bool isUpdating = false; // Prevent double submit while waiting
    bool isDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
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
                    // Current password — for verification (Supabase uses session, but good practice)
                    _buildInput(label: 'Current Password', controller: currentPasswordController, isPassword: true),
                    const SizedBox(height: 12),
                    // New password — must be at least 6 chars
                    _buildInput(label: 'New Password', controller: newPasswordController, isPassword: true),
                    const SizedBox(height: 12),
                    // Confirm — must match new password or we reject
                    _buildInput(label: 'Confirm Password', controller: confirmPasswordController, isPassword: true),
                  ],
                ),
              ),
              actions: [
                // Cancel — no changes made
                TextButton(
                  onPressed: isUpdating ? null : () {
                    if (isDialogOpen && dialogContext.mounted) {
                      isDialogOpen = false;
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  // Disabled while request is in flight — ayaw double tap
                  onPressed: isUpdating ? null : () async {
                    final messenger = ScaffoldMessenger.of(this.context);
                    final rootNavigator = Navigator.of(this.context);
                    final currentPw = currentPasswordController.text.trim();
                    final newPw = newPasswordController.text.trim();
                    final confirmPw = confirmPasswordController.text.trim();

                    // Validate all fields — dili ta allow empty password change
                    if (currentPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
                      messenger.showSnackBar(const SnackBar(content: Text('Please fill in all fields.'), backgroundColor: AppColors.error));
                      return;
                    }

                    // Passwords must match — otherwise user made typo and we need to catch it
                    if (newPw != confirmPw) {
                      messenger.showSnackBar(const SnackBar(content: Text('Passwords do not match.'), backgroundColor: AppColors.error));
                      return;
                    }

                    // Minimum length check — 6 chars is the floor, anything less is too risky
                    if (newPw.length < 6) {
                      messenger.showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters.'), backgroundColor: AppColors.error));
                      return;
                    }

                    FocusScope.of(context).unfocus();
                    if (isDialogOpen && dialogContext.mounted) {
                      setDialogState(() => isUpdating = true); // Show spinner, disable button
                    }
                    
                    try {
                      // Attempt to re-authenticate or just update if session is fresh
                      // Supabase allows password update if there's a valid session.
                      final email = _supabase.auth.currentUser?.email ?? '';
                      final verifyResp = await _supabase.auth.signInWithPassword(
                          email: email, password: currentPw);
                      if (verifyResp.user == null) {
                        if (isDialogOpen && dialogContext.mounted) {
                          setDialogState(() => isUpdating = false);
                        }
                        messenger.showSnackBar(const SnackBar(
                            content: Text('Current password is incorrect.'),
                            backgroundColor: AppColors.error));
                        return;
                      }

                      final result = await _authService.updatePassword(newPw);
                      
                      if (result.success) {
                        if (isDialogOpen && dialogContext.mounted) {
                          isDialogOpen = false;
                          Navigator.of(dialogContext).pop(); // Close dialog
                        }
                        messenger.showSnackBar(const SnackBar(
                          content: Text('Password updated successfully. Please log in again for security.'), 
                          backgroundColor: AppColors.success
                        ));
                        // Auto sign out for security after password change
                        // Wait 2 seconds so user can read the success message first
                        await Future.delayed(const Duration(seconds: 2));
                        await _authService.signOut(); // Sign out — new password require new login
                        if (mounted) {
                          rootNavigator.pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const LoginScreen()), 
                            (route) => false // Remove all previous routes
                          );
                        }
                      } else {
                        if (isDialogOpen && dialogContext.mounted) {
                          setDialogState(() => isUpdating = false); // Re-enable button
                        }
                        messenger.showSnackBar(SnackBar(content: Text(result.error ?? 'Failed to update password.'), backgroundColor: AppColors.error));
                      }
                    } catch (e) {
                      if (isDialogOpen && dialogContext.mounted) {
                        setDialogState(() => isUpdating = false); // Re-enable on error
                      }
                      final cleanError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
                      messenger.showSnackBar(SnackBar(content: Text('Error: $cleanError'), backgroundColor: AppColors.error));
                    }
                  },
                  // Show spinner or "Update" text based on loading state
                  child: isUpdating 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : const Text('Update', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    ).whenComplete(() {
      isDialogOpen = false;
      currentPasswordController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    });
  }

  // Reusable text input builder — keeps form fields consistent throughout the screen
  // isPassword flag hides the text so nobody can shoulder-surf the password
  Widget _buildInput({required String label, IconData? icon, TextEditingController? controller, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword, // Hide chars if this is a password field
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primary) : null,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        // Blue border on focus — so user know which field is active
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
    );
  }

  // Update alert setting in Supabase
  Future<void> _updateAlertSetting(String column, bool value) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase.from('user_info').update({column: value}).eq('id', user.id);
    } catch (e) {
      debugPrint('Failed to update $column: $e');
    }
  }

  // Main build — the whole settings screen layout
  // Shows profile card, notification toggles, security section, and logout button
  @override
  Widget build(BuildContext context) {
    // Generate initials from first + last name — e.g. "Juan Dela Cruz" → "JD"
    String initials = "U"; // Default if name empty
    if (_firstName.isNotEmpty) {
      initials = _firstName[0]; // First letter of first name
      if (_lastName.isNotEmpty) {
        initials += _lastName[0]; // Plus first letter of last name
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Executive Settings', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading 
        ? const AppleLoadingState(label: 'Loading executive settings…')
        : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ApplePageHeader(
                eyebrow: 'Department Leadership',
                title: 'Executive Settings',
                subtitle: 'Profile, intelligence alerts, and account security.',
              ),
              const SizedBox(height: 30),
              // Profile section header
              const AppleSectionHeader(title: 'Executive Profile'),
              const SizedBox(height: 12),
              // Profile card — shows avatar, name, title, and edit link
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Circle avatar with initials — quick visual identifier
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
                            // Full name display — hopefully correct after the data loads
                            Text('$_firstName $_lastName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            // Title and college — e.g. "Dean • College of Engineering"
                            Text('$_userTitle • $_userCollege', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            const SizedBox(height: 8),
                            // Tap to open the edit bottom sheet — importente this is clickable
                            GestureDetector(
                              onTap: _showEditProfileSheet,
                              child: const Text('Edit Personal Details', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Notification toggles section — dean can turn things on/off
              const AppleSectionHeader(
                title: 'Executive Intelligence',
                subtitle: 'Choose which department signals should notify you.',
              ),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    // Toggle: alert when instructor rating drops below 3.0
                    _buildSwitchTile(
                      title: 'Performance Alerts',
                      subtitle: 'Alert when instructor rating drops below 3.0.',
                      icon: Icons.trending_down,
                      value: _lowPerformanceAlerts,
                      onChanged: (val) {
                        setState(() => _lowPerformanceAlerts = val);
                        _updateAlertSetting('alert_performance', val);
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    // Toggle: alert when students leave very negative comments
                    _buildSwitchTile(
                      title: 'Sentiment Analysis',
                      subtitle: 'Alert on detected negative student feedback.',
                      icon: Icons.psychology,
                      value: _negativeSentimentAlerts,
                      onChanged: (val) {
                        setState(() => _negativeSentimentAlerts = val);
                        _updateAlertSetting('alert_sentiment', val);
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    // Toggle: get a weekly email digest — for the dean who love summary
                    _buildSwitchTile(
                      title: 'Weekly Digest',
                      subtitle: 'Receive a summary of department activity.',
                      icon: Icons.summarize,
                      value: _weeklyDepartmentDigest,
                      onChanged: (val) {
                        setState(() => _weeklyDepartmentDigest = val);
                        _updateAlertSetting('alert_digest', val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Security section — change password or nuke the account
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
                    // Edit Email row
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
                    // Change password row — tap to open the dialog
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.lock, color: AppColors.primary),
                      ),
                      title: const Text('Edit Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: _showChangePasswordDialog, // Pop the change password dialog
                    ),
                    const Divider(height: 1, indent: 56),
                    // Delete account — the big red button. use with extreme caution.
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.delete_forever, color: AppColors.error),
                      ),
                      title: const Text('Deactivate My Account', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.error),
                      onTap: _showDeleteAccountDialog, // Opens confirmation dialog first
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Logout button — big, red, full width. Hard to miss.
              SizedBox(
                width: double.infinity,
                height: 54,
                child: SafeOutlinedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final confirm = await showLogoutConfirmationDialog(context);
                    if (confirm == true) {
                      if (!context.mounted) return;
                      showLoggingOutOverlay(context);
                      await Future.delayed(const Duration(milliseconds: 1500)); // Show it for 1.5s
                      await _authService.signOut(); // End the session in Supabase
                      if (mounted) {
                        navigator.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false, // Wipe all routes — no going back without login
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

              // Version number at the bottom — for the QA people and curious users
              const Center(
                child: Text('iEvaluate Version 1.0.0 (Prototype)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Reusable toggle tile for notifications — icon, title, subtitle, and a switch
  // All three notification settings use this same builder — keeps it DRY
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
        child: Icon(icon, color: AppColors.primary), // Icon hint for the toggle's purpose
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      // The actual switch — green when on, gray when off
      trailing: Switch(
        value: value,
        onChanged: onChanged, // Calls setState in parent to reflect change
        activeThumbColor: AppColors.surface,
        activeTrackColor: AppColors.success, // Green track when enabled
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: AppColors.borderHairline, // Gray when disabled
      ),
    );
  }
}
