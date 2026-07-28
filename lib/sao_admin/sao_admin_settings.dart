// lib/admin/sao_admin_settings.dart
// This is the settings screen for the SAO Admin. Importente kaayo ni sya.
// If you break this, good luck explaining to the boss.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../login_screen.dart';
import '../core/services/auth_service.dart';
import '../widgets/safe_button.dart';

class SaoAdminSettings extends StatefulWidget {
  const SaoAdminSettings({super.key});

  @override
  State<SaoAdminSettings> createState() => _SaoAdminSettingsState();
}

class _SaoAdminSettingsState extends State<SaoAdminSettings> {
  // supabase client — wala choice, always needed
  final _supabase = Supabase.instance.client;
  // auth service — the one doing all the dirty work
  final _authService = AuthService();

  // --- INTERACTIVE PROFILE STATE ---
  // these hold the admin's name. if empty, something went wrong, pray lang
  String _firstName = '';
  String _lastName = '';
  String _userTitle = 'System Administrator'; // default title, fancy sounding
  String _userOffice = 'Student Affairs Office'; // their kingdom
  bool _isLoading = true; // screen spinning like our lives

  // --- ADMIN SYSTEM STATE ---
  // the text field for typing a year because dropdown alone isnt enough apparently
  final TextEditingController _yearSearchController = TextEditingController();
  String _selectedSemester = '2nd Semester'; // default semester, change if needed
  String _selectedYear = '2025-2026'; // default year, the future is now
  bool _isUpdatingSettings = false; // true when saving, dili ta mag-double click ha

  @override
  void initState() {
    super.initState();
    // call refresh right away — no waiting around like a lazy student
    _refreshData();
  }

  // loads everything at once — profile AND settings, para efficient
  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      // run both fetches at same time, because serial is for slow people
      await Future.wait([
        _loadUserProfile(),
        _loadSystemSettings(),
      ]);
    } catch (e) {
      // something blew up, log it and move on, bahala na
      debugPrint('Error refreshing settings: $e');
    } finally {
      // stop spinning whether it worked or not
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // fetches the current active semester and year from supabase
  // does a fancy join to academic_terms table because data is normalized now
  Future<void> _loadSystemSettings() async {
    try {
      // Query with join to the normalized academic_terms table
      // one row to rule them all — limit(1) because there should only be one system
      final data = await _supabase
          .from('system_settings')
          .select('*, academic_terms(semester, academic_year)')
          .limit(1)
          .maybeSingle();

      if (data != null && mounted) {
        final term = data['academic_terms']; // the nested join result
        setState(() {
          // if term is null, fall back to defaults — dili pwede mag-crash
          _selectedSemester = term != null ? term['semester'] : '1st Semester';
          _selectedYear = term != null ? term['academic_year'] : '2025-2026';
        });
      }
    } catch (e) {
      debugPrint('Error loading system settings: $e');
    }
  }

  // loads the admin's profile — name and role — from two tables at once
  // because fetching one by one is too old school
  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return; // not logged in? how did you even get here

      // Parallelize profile and role fetching with maybeSingle() for safety
      // maybeSingle() so it dont crash if no row found — wise decision
      final results = await Future.wait([
        _supabase.from('user_info').select('first_name, last_name').eq('id', user.id).maybeSingle(),
        _supabase.from('Sao_users').select('roles(Roles)').eq('user_id', user.id).maybeSingle(),
      ]);

      if (mounted) {
        final userInfo = results[0]; // the name data
        final saoData = results[1]; // the role data
        setState(() {
          if (userInfo != null) {
            _firstName = userInfo['first_name'] ?? ''; // first name or empty string
            _lastName = userInfo['last_name'] ?? '';   // last name or empty string
          }
          if (saoData != null && saoData['roles'] != null) {
            // drill into the nested roles map to get the actual role string
            _userTitle = (saoData['roles'] as Map)['Roles'] ?? 'SAO Staff';
          }
        });
      }
    } catch (e) {
      // something wrong, log and survive
      debugPrint('Error loading profile: $e');
    }
  }

  // ==========================================
  // INTERACTIVE: EDIT PROFILE BOTTOM SHEET
  // pops up from the bottom so user can change their name and role
  // if changing role, an OTP verification is required — security muna
  // ==========================================
  void _showEditProfileSheet() {
    // create fresh controllers with existing data pre-filled
    final TextEditingController firstController = TextEditingController(text: _firstName);
    final TextEditingController lastController = TextEditingController(text: _lastName);
    final TextEditingController codeController = TextEditingController(); // for OTP code

    // Original role data to detect changes — needed to know if OTP step is needed
    final String originalRole = _userTitle;
    String tempSelectedRole = _userTitle; // tracks what the dropdown shows
    bool needsOTP = false; // flip this to true when role changed and needs verification
    bool isSaving = false; // prevent double-tapping the save button

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // allows sheet to grow when keyboard shows
      backgroundColor: Colors.transparent, // let the container handle bg color
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return Padding(
                // pushes the sheet up when keyboard appears — importente kaayo ni
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
                          // title changes depending on if we're in OTP step or not
                          Text(needsOTP ? 'Verify Role Change' : 'Edit Admin Profile', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (!needsOTP) ...[
                        // regular form fields — name and role
                        _buildInput(label: 'First Name', controller: firstController, icon: Icons.person),
                        const SizedBox(height: 16),
                        _buildInput(label: 'Last Name', controller: lastController, icon: Icons.person_outline),
                        const SizedBox(height: 16),

                        // dropdown to change the admin's system role
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
                        // OTP verification step — shown only when role changed
                        const Text('Changing your administrative role requires identity verification.', textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        const Text('Enter the 6-digit code sent to your email:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        // big number input for the 6-digit OTP code
                        TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, letterSpacing: 8), // spaced out like the number pad
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
                            final bool roleChanged = tempSelectedRole != originalRole; // did the role actually change

                            if (roleChanged && !needsOTP) {
                              // role changed but no OTP yet — send the code first
                              setSheetState(() => isSaving = true);
                              try {
                                // fire the edge function to email the code
                                await _supabase.functions.invoke('send-admin-code', body: {'email': _supabase.auth.currentUser?.email});
                                setSheetState(() {
                                  needsOTP = true; // switch to OTP input mode
                                  isSaving = false;
                                });
                                return;
                              } catch (e) {
                                // edge function failed, dili ta makapadayon
                                setSheetState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                                return;
                              }
                            }

                            setSheetState(() => isSaving = true);
                            try {
                              if (roleChanged) {
                                // Fetch role ID for the new role — need the id, not just the name
                                final roleData = await _supabase.from('roles').select('id').eq('Roles', tempSelectedRole).single();

                                // call the edge function to actually change the role in DB
                                await _supabase.functions.invoke('admin-update-role', body: {
                                  'targetUserId': _supabase.auth.currentUser?.id,
                                  'firstName': firstController.text.trim(),
                                  'lastName': lastController.text.trim(),
                                  'roleId': roleData['id'],
                                  'roleName': tempSelectedRole,
                                  'verificationCode': codeController.text.trim(), // the OTP code
                                  'isAcademic': false
                                });

                                // Role changed successfully — must log out for new permissions to take effect
                                if (mounted) {
                                  Navigator.pop(context);
                                  await _authService.signOut(); // bye bye session
                                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated. Please log in again.'), backgroundColor: AppColors.success));
                                }
                              } else {
                                // Simple profile update — just name, no drama
                                await _authService.updateProfile(
                                  firstName: firstController.text.trim(),
                                  lastName: lastController.text.trim(),
                                );
                                // update local state so UI reflects new name immediately
                                setState(() {
                                  _firstName = firstController.text.trim();
                                  _lastName = lastController.text.trim();
                                });
                                if (mounted) Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.success));
                              }
                            } catch (e) {
                              // something went wrong during save, stop the spinner and tell user
                              setSheetState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                            }
                          },
                          // show spinner while saving, otherwise show appropriate label
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
  // asks for current password to verify identity first — ayaw skip ni
  // then updates to the new one and kicks the user back to login
  // ==========================================
  void _showChangePasswordDialog() {
    final TextEditingController currentPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    bool isUpdating = false; // prevent pressing update twice

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
                  // current password — we verify this before proceeding, dili ta basta basta
                  _buildInput(label: 'Current Password', controller: currentPasswordController, isPassword: true),
                  const SizedBox(height: 12),
                  _buildInput(label: 'New Password', controller: newPasswordController, isPassword: true),
                  const SizedBox(height: 12),
                  _buildInput(label: 'Confirm Password', controller: confirmPasswordController, isPassword: true),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(context), // cancel while not loading
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

                    // basic validation — all fields must have something, no laziness allowed
                    if (currentPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all fields.'), backgroundColor: AppColors.error));
                      return;
                    }

                    // passwords must match — typos are the enemy
                    if (newPw != confirmPw) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match.'), backgroundColor: AppColors.error));
                      return;
                    }

                    // minimum length check — basin mag-use ug "123" ang admin
                    if (newPw.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters.'), backgroundColor: AppColors.error));
                      return;
                    }

                    setDialogState(() => isUpdating = true); // start the spinner

                    try {
                      // Step 1: Verify current password by re-signing in
                      // we re-authenticate to confirm identity — murag double check sa guard
                      final email = _supabase.auth.currentUser?.email ?? '';
                      final verifyResp = await _supabase.auth.signInWithPassword(
                        email: email, password: currentPw);
                      if (verifyResp.user == null) {
                        // wrong current password — dili ta makaproceed
                        setDialogState(() => isUpdating = false);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current password is incorrect.'), backgroundColor: AppColors.error));
                        return;
                      }

                      // Step 2: Update to new password — current one was correct so go ahead
                      final result = await _authService.updatePassword(newPw);

                      if (mounted) {
                        if (result.success) {
                          Navigator.pop(context); // Close dialog — mission accomplished

                          // Force sign-out and re-authentication for security
                          // new password means new session, pray lang they remember it
                          await _authService.signOut();

                          if (mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                              (route) => false, // nuke the entire navigation stack
                            );

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password updated. Please log in with your new password.'),
                                backgroundColor: AppColors.success,
                                duration: Duration(seconds: 5), // show it longer — importente ni
                              ),
                            );
                          }
                        } else {
                          // authService returned failure — show the error message
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
                      // unexpected crash — stop spinner and show what happened
                      setDialogState(() => isUpdating = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                    }
                  },
                  // show tiny spinner inside button while updating
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
  // the nuclear option — ayaw diri kung dili sure
  // shows a warning dialog first because consequences are permanent
  // ==========================================
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          // warning icon + title to scare the user a little before they proceed
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error), // red warning — serious kaayo ni
              SizedBox(width: 8),
              Text("Delete Account?"),
            ],
          ),
          // very clear disclaimer — they can't say we didn't warn them
          content: const Text("This action is permanent and cannot be undone. All your profile data will be removed from the system."),
          actions: [
            // cancel — the sensible choice
            TextButton(child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)), onPressed: () => Navigator.pop(context)),
            SafeElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text("Delete My Account", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () async {
                Navigator.pop(context); // close the confirmation dialog
                final result = await _authService.deleteAccount(); // actually delete
                if (result.success) {
                   // account gone — redirect to login, wala nay account to go back to
                   if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                } else {
                   // deletion failed — at least show why
                   if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result.error}'), backgroundColor: AppColors.error));
                }
              },
            ),
          ],
        );
      },
    );
  }

  // saves the chosen semester and academic year to the database
  // also triggers notifications to all SAO Admins via an edge function
  // this is the big button — dili i-click if dili sure
  void _updateSystemSettings(String semester, String year) async {
    setState(() => _isUpdatingSettings = true); // lock the button
    try {
      // 1. Ensure the term exists in the normalized 'academic_terms' table
      // upsert = insert if new, update if already there — murag magic
      final termData = await _supabase
          .from('academic_terms')
          .upsert({
            'semester': semester,
            'academic_year': year,
          }, onConflict: 'semester, academic_year') // prevent duplicate rows
          .select('id')
          .single();

      final termId = termData['id']; // grab the ID of the term we just upserted

      // 2. Update the singleton system settings — id=1 is the one and only row
      await _supabase.from('system_settings').upsert({
        'id': 1,
        'auto_sync': false, // Explicitly false as we are now manual — human in control
        'current_term_id': termId, // point to the term we just saved
        'updated_at': DateTime.now().toIso8601String(), // timestamp the change
      });

      // 3. Trigger notifications to all SAO Admins via edge function
      // wrapped in try-catch because if edge function offline, settings still saved
      try {
        await _supabase.functions.invoke('update-system-settings', body: {
          'semester': semester,
          'academicYear': year,
          'updatedBy': '$_firstName $_lastName', // blame tracker — who changed this
        });
      } catch (funcError) {
        // edge function might not exist or be offline — dili ta mag-crash for this
        debugPrint('Edge Function not found or offline: $funcError');
      }

      // success — show green snackbar to calm everyone down
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('System configuration updated and admins notified.'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      // something actually broke — red snackbar of shame
      debugPrint('Error updating system settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      // always unlock the button whether success or failure — wala choice
      if (mounted) setState(() => _isUpdatingSettings = false);
    }
  }

  // reusable text field builder — saves us from writing the same InputDecoration 20 times
  // supports optional icon and password mode (dots instead of letters)
  Widget _buildInput({required String label, IconData? icon, TextEditingController? controller, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword, // hide text if it's a password — privacy muna
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primary) : null, // icon optional
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
    // defaults to "AD" if name is somehow empty — "AD" for Admin, clever
    String initials = "AD";
    if (_firstName.isNotEmpty) {
      initials = _firstName[0]; // take first letter of first name
      if (_lastName.isNotEmpty) {
        initials += _lastName[0]; // append first letter of last name
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('System Settings', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        // show a thin progress bar at the bottom of appbar while loading
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(1), // barely visible — subtle loading indicator
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
              // shows the admin's name, title and a link to edit
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
                      // circle avatar showing the initials — no profile picture, this is not facebook
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
                            // full name of the logged-in admin
                            Text('$_firstName $_lastName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            // title and office in smaller text below the name
                            Text('$_userTitle • $_userOffice', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            const SizedBox(height: 8),
                            // tap this to open the edit profile bottom sheet
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
              // lets admin pick which semester and year is currently active
              // affects ALL dashboards, reports, and analytics — no pressure
              // ==========================================
              const Text('Academic Term Management', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    // The Dropdowns — for semester and academic year selection
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Active Semester', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              // dropdown with 3 choices: 1st, 2nd, Summer
                              DropdownButton<String>(
                                value: _selectedSemester,
                                underline: const SizedBox(), // no ugly underline
                                items: <String>['1st Semester', '2nd Semester', 'Summer'].map((String value) {
                                  return DropdownMenuItem<String>(value: value, child: Text(value));
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() => _selectedSemester = newValue!); // update state when selected
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
                                  // hint text explaining the search field below
                                  Text('Search or choose below', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                ],
                              ),
                              // small text field to type a year and filter the dropdown
                              SizedBox(
                                width: 120,
                                height: 40,
                                child: TextField(
                                  controller: _yearSearchController,
                                  keyboardType: TextInputType.number, // numbers only, not poetry
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. 1990', // hint — dili actual year limit
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    filled: true,
                                    fillColor: AppColors.background,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => setState(() {}), // rebuild on each keystroke to filter dropdown
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // smart year dropdown — generates years dynamically based on search input
                              DropdownButton<String>(
                                value: _selectedYear,
                                underline: const SizedBox(),
                                items: () {
                                  List<String> years = [];
                                  String query = _yearSearchController.text.trim();

                                  if (query.isEmpty) {
                                    // Default future-proof list (2024 to +10 years)
                                    // generate years from 2024 to 10 years from now — future proof
                                    years = List.generate(
                                      (DateTime.now().year + 10) - 2024,
                                      (index) => '${2024 + index}-${2025 + index}'
                                    );
                                  } else {
                                    // Generate based on search — user typed something
                                    int? year = int.tryParse(query);
                                    if (year != null) {
                                      if (query.length == 4) {
                                        // Exact year search: show this year and next few
                                        for (int i = 0; i < 5; i++) {
                                          years.add('${year + i}-${year + i + 1}');
                                        }
                                      } else if (query.length < 4) {
                                        // Partial search (e.g. "199") — user still typing
                                        int start = year * (query.length == 3 ? 10 : (query.length == 2 ? 100 : 1000));
                                        int count = query.length == 3 ? 10 : 20; // limit suggestions
                                        for (int i = 0; i < count; i++) {
                                          years.add('${start + i}-${start + i + 1}');
                                        }
                                      }
                                    }
                                  }

                                  // CRITICAL: Always include the current selected year to prevent crash
                                  // if we don't do this, Flutter throws a fit — ayaw kang tanggal ani
                                  if (!years.contains(_selectedYear)) {
                                    years.insert(0, _selectedYear);
                                  }

                                  return years.toSet().toList(); // Unique items — no duplicates allowed
                                }().map((String value) {
                                  return DropdownMenuItem<String>(value: value, child: Text(value));
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() => _selectedYear = newValue!); // user picked a year
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
                            // Confirmation dialog before applying changes — dili ta mag-yolo
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: AppColors.warning), // yellow warning — serious but not critical
                                    SizedBox(width: 8),
                                    Flexible(child: Text('Confirm Term Change')),
                                  ],
                                ),
                                // warn user this change is global — affects everyone, bahala na
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
                                    onPressed: () => Navigator.pop(context, true), // confirmed — go ahead
                                    child: const Text('Yes, Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              // user confirmed — now actually update the settings
                              _updateSystemSettings(_selectedSemester, _selectedYear);
                            }
                          },
                          // spinner or icon depending on update status
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
              // red title because it means business — change password or nuke account
              // ==========================================
              const Text('Security & Administration', style: TextStyle(color: AppColors.error, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surface,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    // change password option — recommended to do regularly, dili kag bato
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.lock, color: AppColors.primary)),
                      title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: _showChangePasswordDialog, // opens the password change dialog
                    ),
                    const Divider(height: 1, indent: 56),
                    // delete account — the point of no return, red because danger
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_forever, color: AppColors.error)),
                      title: const Text('Delete My Account', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.error),
                      onTap: _showDeleteAccountDialog, // opens the "are you sure" dialog
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // 5. LOG OUT BUTTON
              // the exit door — signs out and kicks user to login screen
              // ==========================================
              SizedBox(
                width: double.infinity,
                height: 54,
                child: SafeOutlinedButton(
                  onPressed: () async {
                    await _authService.signOut(); // terminate the session
                    if (mounted) {
                      // send user back to login, remove all routes — no going back
                      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error, width: 2), // red border — logout is serious
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, color: AppColors.error), // red logout icon
                      SizedBox(width: 8),
                      Text('Sign Out Securely', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // version label at the bottom — at least we know what prototype we on
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
  // TODO: maybe bring it back someday, or maybe not, bahala na
}
