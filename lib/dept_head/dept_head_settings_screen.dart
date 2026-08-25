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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allow sheet to grow when keyboard appears
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                // Shift content above keyboard — wala choice or the fields get covered
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle — signals this is a sheet
                      Center(
                        child: Container(width: 44, height: 5, decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(100))),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Edit Executive Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary)),
                          // X button to dismiss without saving — ayaw forget this
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Please ensure your name exactly matches your official school records. This name is used for scanner validation and official workflow reports. Change it wisely.',
                                style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // First name input field
                      _buildInput(label: 'First Name', controller: firstController, icon: Icons.person),
                      const SizedBox(height: 16),
                      // Last name input field
                      _buildInput(label: 'Last Name', controller: lastController, icon: Icons.person_outline),
                      const SizedBox(height: 24),
                      // Save button — gradient CTA with warm glow
                      Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDeep]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          // Disabled while save is in progress — dili ta allow double tap
                          onPressed: isSaving ? null : () async {
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            final navigator = Navigator.of(context);
                            setSheetState(() => isSaving = true); // Show loading state
                            try {
                              // Call auth service to update name in Supabase
                              final result = await _authService.updateProfile(
                                firstName: firstController.text.trim(),
                                lastName: lastController.text.trim(),
                              );
                              
                              if (!mounted) return;
                              if (result.success) {
                                // Update local state so UI reflects the new name immediately
                                setState(() {
                                  _firstName = firstController.text.trim();
                                  _lastName = lastController.text.trim();
                                });
                                navigator.pop(); // Close the sheet
                                scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.success));
                              } else {
                                throw Exception(result.error); // Something went wrong
                              }
                            } catch (e) {
                              if (!mounted) return;
                              setSheetState(() => isSaving = false); // Re-enable button
                              scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                            }
                          },
                          // Show spinner while saving, text when idle
                          child: isSaving 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                            : const Text('Save Changes', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
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
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Edit Email', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter your new email address. You will receive a confirmation link.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'New Email',
                      labelStyle: const TextStyle(color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primaryText),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
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
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
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
  // The nuclear option — shown as a confirmation dialog first.
  // Very permanent. very scary. importente to warn the user good.
  // ==========================================
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error), // Scary red icon
              SizedBox(width: 8),
              Text("Delete Account?", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textPrimary)),
            ],
          ),
          // Clear warning — no vague language. User must understand what they doing.
          content: const Text("This action is permanent and cannot be undone. All your profile data will be removed from the system.", style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
          actions: [
            // Cancel — the safe choice. ayaw delete if not sure.
            TextButton(child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)), onPressed: () => Navigator.pop(context)),
            // Delete button — red, bold, and final. wala choice after this.
            SafeElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Delete My Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              onPressed: () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                navigator.pop(); // Close dialog first
                final result = await _authService.deleteAccount(); // Send the delete request
                if (!mounted) return;
                if (result.success) {
                   // Account deleted — send them back to login screen. wala choice now.
                   navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                } else {
                   scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: ${result.error}'), backgroundColor: AppColors.error));
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
  // Three fields — current, new, confirm.
  // After success, auto sign out for security. bahala na, security first.
  // ==========================================
  void _showChangePasswordDialog() {
    // Three separate controllers for three fields — dili ta reuse
    final TextEditingController currentPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    bool isUpdating = false; // Prevent double submit while waiting

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Change Password', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              content: Column(
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
              actions: [
                // Cancel — no changes made
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  // Disabled while request is in flight — ayaw double tap
                  onPressed: isUpdating ? null : () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    final newPw = newPasswordController.text.trim();
                    final confirmPw = confirmPasswordController.text.trim();

                    // Validate all fields — dili ta allow empty password change
                    if (newPw.isEmpty || confirmPw.isEmpty) {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Please fill in all fields.'), backgroundColor: AppColors.error));
                      return;
                    }

                    // Passwords must match — otherwise user made typo and we need to catch it
                    if (newPw != confirmPw) {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Passwords do not match.'), backgroundColor: AppColors.error));
                      return;
                    }

                    // Minimum length check — 6 chars is the floor, anything less is too risky
                    if (newPw.length < 6) {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters.'), backgroundColor: AppColors.error));
                      return;
                    }

                    setDialogState(() => isUpdating = true); // Show spinner, disable button
                    
                    try {
                      // Attempt to re-authenticate or just update if session is fresh
                      // Supabase allows password update if there's a valid session.
                      final result = await _authService.updatePassword(newPw);
                      
                      if (!mounted) return;
                      if (result.success) {
                        navigator.pop(); // Close dialog
                        scaffoldMessenger.showSnackBar(const SnackBar(
                          content: Text('Password updated successfully. Please log in again for security.'), 
                          backgroundColor: AppColors.success
                        ));
                        // Auto sign out for security after password change
                        // Wait 2 seconds so user can read the success message first
                        await Future.delayed(const Duration(seconds: 2));
                        await _authService.signOut(); // Sign out — new password require new login
                        if (!mounted) return;
                        navigator.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()), 
                          (route) => false // Remove all previous routes
                        );
                      } else {
                        setDialogState(() => isUpdating = false); // Re-enable button
                        scaffoldMessenger.showSnackBar(SnackBar(content: Text(result.error ?? 'Failed to update password.'), backgroundColor: AppColors.error));
                      }
                    } catch (e) {
                      if (!mounted) return;
                      setDialogState(() => isUpdating = false); // Re-enable on error
                      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                    }
                  },
                  // Show spinner or "Update" text based on loading state
                  child: isUpdating 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : const Text('Update', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // Reusable text input builder — keeps form fields consistent throughout the screen
  // isPassword flag hides the text so nobody can shoulder-surf the password
  Widget _buildInput({required String label, IconData? icon, TextEditingController? controller, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword, // Hide chars if this is a password field
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primaryText) : null,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        // Orange border on focus — so user know which field is active
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
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
        elevation: 0,
        foregroundColor: AppColors.textInverted,
        iconTheme: const IconThemeData(color: AppColors.textInverted),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E1608), AppColors.textPrimary],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Executive Settings', style: TextStyle(color: AppColors.textInverted, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) 
        : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile section header
              const Text('Executive Profile', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              // Profile card — espresso hero with a warm orange glow accent
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E1608), AppColors.textPrimary],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      // Soft orange radial glow, upper right — matches the dashboard hero
                      Positioned(
                        top: -60,
                        right: -40,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.30),
                                AppColors.primary.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            // Circle avatar with initials — quick visual identifier
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.18),
                              child: Text(initials.toUpperCase(), style: const TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Full name display — hopefully correct after the data loads
                                  Text('$_firstName $_lastName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: -0.3, color: AppColors.textInverted), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  // Title and college — e.g. "Dean • College of Engineering"
                                  Text('$_userTitle • $_userCollege', style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 10),
                                  // Tap to open the edit bottom sheet — importente this is clickable
                                  GestureDetector(
                                    onTap: _showEditProfileSheet,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: const Text('Edit Personal Details', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Notification toggles section — dean can turn things on/off
              const Text('Executive Intelligence', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
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
                    const Divider(height: 1, indent: 64, color: AppColors.borderHairline),
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
                    const Divider(height: 1, indent: 64, color: AppColors.borderHairline),
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
              const SizedBox(height: 28),

              // Security section — change password or nuke the account
              const Text('Security & Danger Zone', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  children: [
                    // Edit Email row
                    ListTile(
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.email_outlined, color: AppColors.primaryText),
                      ),
                      title: const Text('Edit Email', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: _showEditEmailDialog,
                    ),
                    const Divider(height: 1, indent: 64, color: AppColors.borderHairline),
                    // Change password row — tap to open the dialog
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.lock, color: AppColors.primaryText),
                      ),
                      title: const Text('Edit Password', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: _showChangePasswordDialog, // Pop the change password dialog
                    ),
                    const Divider(height: 1, indent: 64, color: AppColors.borderHairline),
                    // Delete account — the big red button. use with extreme caution.
                    ListTile(
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.delete_forever, color: AppColors.error),
                      ),
                      title: const Text('Delete My Account', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.error),
                      onTap: _showDeleteAccountDialog, // Opens confirmation dialog first
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Logout button — full-width destructive CTA with red gradient + glow
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.error, Color(0xFF9A3412)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: AppColors.error.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: SafeOutlinedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final confirm = await showLogoutConfirmationDialog(context);
                    if (confirm == true) {
                      if (!mounted) return;
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
                    foregroundColor: Colors.white,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Sign Out Securely', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppColors.primaryText), // Icon hint for the toggle's purpose
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      // The actual switch — green when on, gray when off
      trailing: Switch(
        value: value,
        onChanged: onChanged, // Calls setState in parent to reflect change
        activeThumbColor: AppColors.surface,
        activeTrackColor: AppColors.success, // Green track when enabled
        inactiveThumbColor: AppColors.surface,
        inactiveTrackColor: AppColors.borderHairline, // Gray when disabled
      ),
    );
  }
}
