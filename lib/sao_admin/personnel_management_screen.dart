// lib/sao_admin/personnel_management_screen.dart
// This screen manages the SAO staff — the people running the evaluation system.
// Different from user_management (academics), this is for the SAO office folks.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env.dart';
import '../core/services/identity_validator.dart';
import '../widgets/duplicate_warning_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/safe_button.dart';
import '../widgets/apple_ui.dart';
import '../widgets/controller_disposer.dart';

// the outer shell widget — just a box, nothing special yet
class PersonnelManagementScreen extends StatefulWidget {
  const PersonnelManagementScreen({super.key});

  @override
  State<PersonnelManagementScreen> createState() => _PersonnelManagementScreenState();
}

class _PersonnelManagementScreenState extends State<PersonnelManagementScreen> {
  final _supabase = Supabase.instance.client; // database connection, treat with respect
  
  List<Map<String, dynamic>> _allPersonnel = []; // all SAO staff fetched from DB
  List<Map<String, dynamic>> _saoRoles = []; // only SAO roles (filtered from all roles)
  bool _isLoading = true; // spinner flag
  
  String _searchQuery = ''; // search text
  String _selectedRoleFilter = 'All'; // which role to filter by
  String _sortBy = 'Newest'; // sort direction
  final List<String> _sortOptions = ['Newest', 'Oldest', 'A-Z', 'Z-A']; // added sort options

  // called once on screen open — start fetching data right away
  @override
  void initState() {
    super.initState();
    _fetchData(); // fetch everything, dili ta wait for button click
  }

  // fetch all SAO personnel and their roles from the database
  // 1. fetches from Sao_users table (not department_table — that's for academics)
  // 2. also fetches all roles and filters to SAO ones only
  Future<void> _fetchData() async {
    if (!mounted) return; // screen gone already? ayaw proceed
    setState(() => _isLoading = true);
    
    try {
      final currentUser = _supabase.auth.currentUser;
      debugPrint('[PERSONNEL_MGMT] Logged in as: ${currentUser?.email} (ID: ${currentUser?.id})');

      // 1. Fetch Users from Sao_users (SAO Admin/Staff)
      // includes user info and role data via joins
      final personnelResponse = await _supabase
          .from('Sao_users')
          .select('''
            id,
            user_id,
            role_id,
            user_info!user_id (
              first_name,
              last_name,
              university_id,
              account_status,
              email
            ),
            role_data:roles!role_id ( Roles )
          ''');

      // 2. Fetch Roles (Filtered to SAO roles)
      // we fetch all roles then filter in-memory to only keep SAO ones
      final rolesResponse = await _supabase.from('roles').select('id, Roles');

      if (mounted) {
        setState(() {
          _allPersonnel = List<Map<String, dynamic>>.from(personnelResponse);
          // only keep roles that start with 'SAO' — dili ta include academic roles here
          _saoRoles = List<Map<String, dynamic>>.from(rolesResponse)
              .where((r) => r['Roles'].toString().toUpperCase().startsWith('SAO'))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[PERSONNEL_MGMT] Fetch Error: $e');
      if (mounted) {
        setState(() => _isLoading = false); // stop spinner even on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // computed getter — filters and sorts personnel based on current search/filter/sort
  // disabled accounts always float to the top — admin can see who needs attention
  List<Map<String, dynamic>> get _filteredPersonnel {
    List<Map<String, dynamic>> filtered = _allPersonnel.where((person) {
      final ui = person['user_info'];
      if (ui == null) return false; // no user info? skip this ghost

      final roleName = person['role_data']?['Roles'] ?? 'Unknown';
      
      // apply role filter if not set to 'All'
      if (_selectedRoleFilter != 'All' && roleName != _selectedRoleFilter) return false;
      
      if (_searchQuery.isNotEmpty) {
        // match by full name or university ID — both are acceptable ways to find someone
        final fullName = '${ui['first_name']} ${ui['last_name']}'.toLowerCase();
        final uniId = ui['university_id'].toString().toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!fullName.contains(query) && !uniId.contains(query)) return false;
      }
      return true; // passed all checks, include in results
    }).toList();

    // sort with a twist: disabled users always come first — admin should see them prominently
    filtered.sort((a, b) {
      final uiA = a['user_info'];
      final uiB = b['user_info'];
      if (uiA == null || uiB == null) return 0; // null safety, ayaw crash
      
      final isActiveA = uiA['account_status'] == 'approved';
      final isActiveB = uiB['account_status'] == 'approved';

      // 1. Blocked/Disabled users first — float them to the top so admin notice
      if (isActiveA != isActiveB) {
        return isActiveA ? 1 : -1; // disabled (-1) comes before active (1)
      }

      // 2. then sort by ID within same status group
      if (_sortBy == 'Newest') {
        return b['id'].toString().compareTo(a['id'].toString());
      } else if (_sortBy == 'Oldest') {
        return a['id'].toString().compareTo(b['id'].toString());
      } else if (_sortBy == 'A-Z') {
        final nameA = '${a['user_info']['first_name']} ${a['user_info']['last_name']}'.toLowerCase();
        final nameB = '${b['user_info']['first_name']} ${b['user_info']['last_name']}'.toLowerCase();
        return nameA.compareTo(nameB);
      } else if (_sortBy == 'Z-A') {
        final nameA = '${a['user_info']['first_name']} ${a['user_info']['last_name']}'.toLowerCase();
        final nameB = '${b['user_info']['first_name']} ${b['user_info']['last_name']}'.toLowerCase();
        return nameB.compareTo(nameA);
      }
      return 0;
    });

    return filtered;
  }

  // toggle personnel between approved and disabled status
  // basically the on/off switch for SAO staff accounts
  Future<void> _toggleStatus(Map<String, dynamic> person) async {
    final ui = person['user_info'];
    // account_status is nullable in user_info; a String cast on null threw.
    final String currentStatus = (ui['account_status'] ?? '').toString();
    // flip it: approved becomes disabled, disabled becomes approved
    final String newStatus = currentStatus == 'approved' ? 'disabled' : 'approved';
    
    try {
      // call the edge function — importente kaayo dili ta update directly
      await _supabase.functions.invoke('admin-accept-user', body: {
        'targetUserId': person['user_id'],
        'status': newStatus,
      });
      
      _fetchData(); // refresh the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account $newStatus successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
      }
    }
  }

  // ── Personnel Details Modal ───────────────────────────────────
  // Read-only bottom sheet showing staff details and scan stats
  Future<void> _showPersonnelDetailsModal(Map<String, dynamic> person) async {
    final ui = person['user_info'];
    final userId = person['user_id'];
    final roleName = person['role_data']?['Roles'] ?? '';
    final fullName = '${ui['first_name']} ${ui['last_name']}';
    final email = ui['email'] ?? 'Not provided';
    final universityId = ui['university_id']?.toString() ?? 'Not provided';
    final accountStatus = ui['account_status'] ?? 'unknown';
    final isActive = accountStatus == 'approved';

    // fetch scan stats
    int totalScans = 0, todayScans = 0, termScans = 0;
    String lastUpload = '';

    try {
      final settings = await _supabase.from('system_settings').select('current_term_id').limit(1).maybeSingle();
      final termId = settings?['current_term_id'];
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();

      // Server-side exact counts (a plain select is capped at 1000 rows).
      PostgrestFilterBuilder<PostgrestList> termQ() {
        var q = _supabase.from('sast_all_raw_data_survey').select('id').eq('sao_staff_id', userId);
        if (termId != null) q = q.eq('term_id', termId);
        return q;
      }

      final results = await Future.wait<dynamic>([
        _supabase
            .from('sast_all_raw_data_survey')
            .select('id')
            .eq('sao_staff_id', userId)
            .count(CountOption.exact),
        termQ().count(CountOption.exact),
        termQ().gte('created_at', startOfDay).count(CountOption.exact),
        _supabase
            .from('sast_all_raw_data_survey')
            .select('created_at')
            .eq('sao_staff_id', userId)
            .order('created_at', ascending: false)
            .limit(1),
      ]);
      totalScans = (results[0] as PostgrestResponse).count;
      termScans = (results[1] as PostgrestResponse).count;
      todayScans = (results[2] as PostgrestResponse).count;

      final latest = results[3] as List;
      if (latest.isNotEmpty) {
        lastUpload = latest.first['created_at'] as String;
      }
    } catch (e) { debugPrint('PersonnelModal error: $e'); }

    if (!mounted) return;

    // format last upload as human-readable
    String lastUploadStr = 'No uploads yet';
    if (lastUpload.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastUpload).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          lastUploadStr = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          lastUploadStr = '${diff.inHours}h ago';
        } else {
          lastUploadStr = '${diff.inDays}d ago';
        }
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.70,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Dark Header ───────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.35),
                    child: Text(
                      fullName.isNotEmpty ? fullName[0] : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName,
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(roleName,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        // Active / Disabled badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.green.withValues(alpha: 0.25)
                                : Colors.red.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isActive ? '● Active' : '● ${accountStatus.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── White Body ────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Account Details
                    Text('Account Details', style: AppTextStyles.titleSmall),
                    const SizedBox(height: 16),
                    _detailRow(Icons.badge_outlined,      'Staff ID',        universityId),
                    _detailRow(Icons.email_outlined,       'Email Address',   email),
                    _detailRow(Icons.check_circle_outline, 'Account Status',  isActive ? 'Approved' : accountStatus),

                    const SizedBox(height: 24),

                    // Scan Statistics
                    Text('Scan Statistics', style: AppTextStyles.titleSmall),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: _statBox('Today',     '$todayScans', AppColors.primary)),
                      const SizedBox(width: 10),
                      Expanded(child: _statBox('This Term', '$termScans',  Colors.teal)),
                      const SizedBox(width: 10),
                      Expanded(child: _statBox('All Time',  '$totalScans', AppColors.success)),
                    ]),
                    const SizedBox(height: 16),
                    _detailRow(Icons.cloud_upload_outlined, 'Last Upload', lastUploadStr),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // single detail row: icon + label above + value below
  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 3),
                Text(value,
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // colored stat box with big number and label
  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.titleLarge.copyWith(color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }


  // dialog to edit an existing SAO personnel — name, login email and role changes
  // if promoting to SAO_ADMIN, needs OTP verification — dili basta basta mag-promote
  void _showEditPersonnelDialog(Map<String, dynamic> person) {
    final ui = person['user_info'];
    // pre-fill with current values
    final firstController = TextEditingController(text: ui['first_name']);
    final lastController = TextEditingController(text: ui['last_name']);
    final emailController = TextEditingController(text: (ui['email'] ?? '').toString());
    final codeController = TextEditingController(); // OTP input for admin promotion
    // Sao_users.role_id is nullable; assigning null to an int threw on open.
    int? selectedRoleId = person['role_id'] as int?;
    bool needsCode = false; // becomes true if promoting to SAO_ADMIN
    bool isSaving = false;

    // What the record looked like when the dialog opened. Still equal to this
    // means there is nothing to save.
    final String originalFirst = (ui['first_name'] ?? '').toString().trim();
    final String originalLast = (ui['last_name'] ?? '').toString().trim();
    final String originalEmail = IdentityValidator.cleanEmail(ui['email']?.toString());
    final int? originalRoleId = selectedRoleId;

    // The signed-in admin's own login email is changed from Settings, which
    // sends a confirmation link. admin-update-role refuses it here as well.
    final bool isSelf = person['user_id']?.toString() == _supabase.auth.currentUser?.id;

    bool emailChanged() =>
        IdentityValidator.cleanEmail(emailController.text) != originalEmail;

    // Reads the live values so the button label follows what is typed. Nothing
    // changed -> the button says Back and just closes: no duplicate check, no
    // edge function call, and no "your account was updated" email to someone
    // whose account was not in fact updated.
    bool hasChanges() =>
        firstController.text.trim() != originalFirst ||
        lastController.text.trim() != originalLast ||
        emailChanged() ||
        selectedRoleId != originalRoleId;

    showDialog(
      context: context,
      barrierDismissible: false, // cannot dismiss by tapping outside
      // Controllers are disposed after the exit animation, not on pop (see ControllerDisposer).
      builder: (context) => ControllerDisposer(
        controllers: [firstController, lastController, emailController, codeController],
        child: StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          // System back must not close the dialog mid-save.
          canPop: !isSaving,
          child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(needsCode ? 'Verify Authorization' : 'Edit Personnel Profile', 
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  // step 1: edit form.
                  // onChanged rebuilds the dialog so the action button can flip
                  // between Back and Save Changes as the admin types.
                  TextField(
                    controller: firstController,
                    decoration: const InputDecoration(labelText: 'First Name'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lastController,
                    decoration: const InputDecoration(labelText: 'Last Name'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  // login email — also what login-by-Staff-ID resolves to
                  TextField(
                    controller: emailController,
                    enabled: !isSelf && !isSaving,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      helperText: isSelf
                          ? 'Change your own email from Settings.'
                          : (emailChanged() ? 'This becomes their login email.' : null),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  // role dropdown — only SAO roles shown here
                  DropdownButtonFormField<int>(
                    // A value missing from items trips the Dropdown assertion.
                    initialValue: _saoRoles.any((r) => r['id'] == selectedRoleId) ? selectedRoleId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _saoRoles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val),
                  ),
                ] else ...[
                  // step 2: enter OTP — required when upgrading to SAO_ADMIN
                  const Text('Upgrading a user to Admin requires authorization.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  const Text('Enter the 6-digit code sent to your email:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8), // big spaced digits
                    decoration: const InputDecoration(hintText: '000000'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            // Disabled while saving: closing mid-save would let the later
            // navigator.pop() close this screen instead of the dialog.
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            SafeElevatedButton(
              onPressed: isSaving ? null : () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                // Nothing edited: behave as a plain Back button.
                if (!hasChanges()) {
                  navigator.pop();
                  return;
                }
                // orElse: the account's current role may not be an SAO role,
                // and firstWhere without it threw a StateError here.
                final selectedRole = _saoRoles.firstWhere(
                  (r) => r['id'] == selectedRoleId,
                  orElse: () => <String, dynamic>{},
                );
                if (selectedRole.isEmpty) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Please select a valid role'), backgroundColor: AppColors.error),
                  );
                  return;
                }

                // Email is checked before any OTP is requested, so a typo does
                // not cost the admin a verification code.
                final bool changingEmail = emailChanged();
                final String newEmail = IdentityValidator.cleanEmail(emailController.text);
                if (changingEmail && !needsCode) {
                  final emailError = IdentityValidator.validateEmail(newEmail);
                  if (emailError != null) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text(emailError), backgroundColor: AppColors.error),
                    );
                    return;
                  }
                  setDialogState(() => isSaving = true);
                  final emailCheck = await IdentityValidator.checkAvailability(
                    client: _supabase,
                    email: newEmail,
                    excludeUserId: person['user_id']?.toString(),
                  );
                  if (!context.mounted) return;
                  setDialogState(() => isSaving = false);
                  if (!emailCheck.isAvailable) {
                    await showDuplicateWarningDialog(
                      context,
                      message: emailCheck.error!,
                      field: emailCheck.field,
                    );
                    return;
                  }
                }
                // check if this is a promotion from non-admin to admin
                final bool isUpgradingToAdmin = selectedRole['Roles'] == 'SAO_ADMIN' && 
                    person['role_data']?['Roles'] != 'SAO_ADMIN';

                // promoting to SAO_ADMIN requires OTP — extra security layer, importente kaayo
                if (isUpgradingToAdmin && !needsCode) {
                   final currentUser = _supabase.auth.currentUser;
                   
                   setDialogState(() => isSaving = true);
                   try {
                     // 1. Request the code from the server (Server generates and emails it)
                     await _supabase.functions.invoke(
                       'send-admin-code',
                       body: {
                         'email': currentUser?.email,
                         // We no longer send the code from here! server decides that
                       },
                       headers: {
                         'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                         'apikey': Env.supabaseAnonKey,
                       },
                     );
                     if (!context.mounted) return;

                     // switch dialog to OTP input step
                     setDialogState(() {
                       needsCode = true;
                       isSaving = false;
                     });
                     
                     scaffoldMessenger.showSnackBar(
                       SnackBar(content: Text('Verification code sent to ${currentUser?.email}'))
                     );
                     return; // stop here and wait for user to enter the code
                   } catch (e) {
                     if (context.mounted) setDialogState(() => isSaving = false);
                     scaffoldMessenger.showSnackBar(
                       SnackBar(content: Text('Failed to send verification: $e'), backgroundColor: Colors.red)
                     );
                     return;
                   }
                }

                // if not upgrading to admin, or OTP already entered — proceed with update
                try {
                  setDialogState(() => isSaving = true);
                  
                  final targetUserId = person['user_id'];
                  final roleName = selectedRole['Roles'];

                  // Renaming is the second way a duplicate appears: the account
                  // was unique when created, then someone edits the name to
                  // match an existing person. Validated here for a fast, clear
                  // message; admin-update-role re-checks it server-side, and the
                  // unique index is the actual guarantee.
                  final newFirst = firstController.text.trim();
                  final newLast = lastController.text.trim();
                  final formatError = IdentityValidator.validateFormat(
                    firstName: newFirst, lastName: newLast,
                  );
                  if (formatError != null) {
                    setDialogState(() => isSaving = false);
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text(formatError), backgroundColor: AppColors.error),
                    );
                    return;
                  }
                  // excludeUserId is this account, so saving without touching
                  // the name does not report the person as their own duplicate.
                  final availability = await IdentityValidator.checkAvailability(
                    client: _supabase,
                    firstName: newFirst,
                    lastName: newLast,
                    excludeUserId: targetUserId?.toString(),
                  );
                  if (!context.mounted) return;
                  if (!availability.isAvailable) {
                    setDialogState(() => isSaving = false);
                    await showDuplicateWarningDialog(
                      context,
                      message: availability.error!,
                      field: availability.field,
                    );
                    return;
                  }

                  // 2. Call the Edge Function to verify the code and update the role
                  final response = await _supabase.functions.invoke(
                    'admin-update-role',
                    body: {
                      'targetUserId': targetUserId,
                      'firstName': newFirst,
                      'lastName': newLast,
                      // Sent only when it changed; absent means "leave it".
                      if (changingEmail) 'email': newEmail,
                      'roleId': selectedRoleId,
                      'roleName': roleName,
                      'isAcademic': false,
                      'isPromotion': isUpgradingToAdmin, // true only when promoting to SAO_ADMIN
                      'verificationCode': codeController.text.trim(),
                    },
                    headers: {
                      'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                      'apikey': Env.supabaseAnonKey,
                    },
                  );

                  if (response.status == 200) {
                    _fetchData(); // reload the list to show changes
                    if (context.mounted) navigator.pop();
                    // A deployment of admin-update-role that predates email
                    // editing ignores the field and still answers 200.
                    final emailSkipped = changingEmail &&
                        !(response.data is Map && response.data['emailUpdated'] == true);
                    scaffoldMessenger.showSnackBar(emailSkipped
                        ? const SnackBar(
                            content: Text('Personnel updated, but the email was NOT changed. '
                                'The server function needs to be updated -- contact the system administrator.'),
                            backgroundColor: AppColors.error,
                            duration: Duration(seconds: 8),
                          )
                        : const SnackBar(content: Text('Personnel updated successfully!'), backgroundColor: AppColors.success));
                  } else {
                    // server returned an error, extract and throw the message
                    final errorMsg = response.data is Map ? (response.data['error'] ?? 'Server error') : 'Server error';
                    throw errorMsg;
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  setDialogState(() => isSaving = false);
                  // describeEdgeFunctionError digs the server's own wording out
                  // of the exception. Without it a duplicate shows up as
                  // "FunctionException(status: 400, details: {error: ...})".
                  final msg = IdentityValidator.describeEdgeFunctionError(
                    e,
                    fallback: 'Update failed. Please try again.',
                  );
                  if (isDuplicateMessage(msg)) {
                    if (!context.mounted) return;
                    await showDuplicateWarningDialog(context, message: msg);
                  } else {
                    scaffoldMessenger.showSnackBar(SnackBar(
                      content: Text(msg),
                      backgroundColor: AppColors.error,
                      duration: const Duration(seconds: 6),
                    ));
                  }
                }
              },
              // show spinner or button label depending on save state
              child: isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(needsCode
                    ? 'Verify & Save'
                    : (hasChanges() ? 'Save Changes' : 'Back')),
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }

  // dialog to create a brand new SAO personnel from scratch
  // creating SAO_ADMIN requires OTP — wala choice, it's a rule
  void _showAddPersonnelDialog() {
    TextEditingController firstController = TextEditingController();
    TextEditingController lastController = TextEditingController();
    TextEditingController emailController = TextEditingController();
    TextEditingController idController = TextEditingController();
    TextEditingController codeController = TextEditingController(); // OTP if creating admin
    String? selectedRoleName = _saoRoles.isNotEmpty ? _saoRoles.first['Roles'] : null; // default to first role
    bool needsCode = false; // triggered when creating SAO_ADMIN
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      // Controllers are disposed after the exit animation, not on pop (see ControllerDisposer).
      builder: (context) => ControllerDisposer(
        controllers: [firstController, lastController, emailController, idController, codeController],
        child: StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          // System back must not close the dialog mid-save.
          canPop: !isSaving,
          child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(needsCode ? 'Verify Authorization' : 'Add SAO Personnel',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  // step 1: fill in new person's details
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 12),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(controller: idController, decoration: const InputDecoration(labelText: 'Staff ID')),
                  const SizedBox(height: 16),
                  // role dropdown — only SAO roles (SAO_ADMIN, SAO_STAFF etc.)
                  DropdownButtonFormField<String>(
                    initialValue: selectedRoleName,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _saoRoles.map((r) => DropdownMenuItem<String>(value: r['Roles'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleName = val),
                  ),
                ] else ...[
                  // step 2: OTP verification for creating admin accounts
                  const Text('Creating an Admin requires authorization.', textAlign: TextAlign.center),
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
              ],
            ),
          ),
          actions: [
            // Disabled while saving: closing mid-save would let the later
            // navigator.pop() close this screen instead of the dialog.
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                if (selectedRoleName == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a role first'), backgroundColor: Colors.red),
                  );
                  return;
                }
                // Validate required fields — all four must be filled
                final fn = firstController.text.trim();
                final ln = lastController.text.trim();
                final em = emailController.text.trim();
                final id = idController.text.trim();
                if (fn.isEmpty || ln.isEmpty || em.isEmpty || id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all required fields'), backgroundColor: Colors.red));
                  return;
                }
                // Name / email / ID rules all come from IdentityValidator, so
                // this screen, User Management and the public registration
                // screen accept exactly the same values. They used to disagree.
                final formatError = IdentityValidator.validateFormat(
                  firstName: fn, lastName: ln, email: em, universityId: id,
                  idLabel: IdentityValidator.staffIdLabel,
                );
                if (formatError != null) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text(formatError), backgroundColor: AppColors.error));
                  return;
                }
                // Is this person already in the system? Checked here so the
                // admin gets a clear message before an OTP is sent and before
                // any account is created. The unique indexes in the database
                // are what actually guarantee it; this is the friendly warning.
                final availability = await IdentityValidator.checkAvailability(
                  client: _supabase,
                  firstName: fn, lastName: ln, email: em, universityId: id,
                  idLabel: IdentityValidator.staffIdLabel,
                );
                // The dialog may have been cancelled during the check.
                if (!context.mounted) return;
                if (!availability.isAvailable) {
                  await showDuplicateWarningDialog(
                    context,
                    message: availability.error!,
                    field: availability.field,
                  );
                  return;
                }

                // creating SAO_ADMIN requires OTP first — trigger the email
                if (!needsCode && selectedRoleName == 'SAO_ADMIN') {
                   final currentUser = _supabase.auth.currentUser;
                   setDialogState(() => isSaving = true);
                   try {
                     // request server to send OTP to the current admin's email
                     await _supabase.functions.invoke(
                       'send-admin-code',
                       body: {'email': currentUser?.email},
                       headers: {
                         'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                         'apikey': Env.supabaseAnonKey,
                       },
                     );
                     if (!context.mounted) return;
                     setDialogState(() { needsCode = true; isSaving = false; }); // switch to OTP step
                     scaffoldMessenger.showSnackBar(SnackBar(content: Text('Verification code sent to ${currentUser?.email}')));
                     return;
                   } catch (e) {
                     if (context.mounted) setDialogState(() => isSaving = false);
                     scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
                     return;
                   }
                }

                // actually create the user — call the edge function
                setDialogState(() => isSaving = true);
                try {
                  final response = await _supabase.functions.invoke(
                    'admin-create-user',
                    body: {
                      'firstName': firstController.text.trim(),
                      'lastName': lastController.text.trim(),
                      'email': emailController.text.trim(),
                      'universityId': idController.text.trim(),
                      'roleName': selectedRoleName!,
                      'address': 'SAO Office', // default address for all SAO staff
                      'verificationCode': codeController.text.trim(), // OTP if admin
                    },
                    headers: {
                      'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                      'apikey': Env.supabaseAnonKey,
                    },
                  );

                  if (response.status == 200 || response.status == 201) {
                    _fetchData(); // refresh list
                    // The dialog's own context, not this State's: popping after
                    // the dialog is gone would pop the route underneath it.
                    if (context.mounted) navigator.pop();
                    scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Personnel created!'), backgroundColor: AppColors.success));
                  } else {
                    throw response.data['error'] ?? 'Server error'; // server said no
                  }
                } catch (e) {
                  if (context.mounted) setDialogState(() => isSaving = false);
                  // The server's duplicate message has to survive to the admin,
                  // so unwrap the exception rather than printing it.
                  final msg = IdentityValidator.describeEdgeFunctionError(
                    e,
                    fallback: 'Could not create the personnel. Please try again.',
                  );
                  // A duplicate can still land here if two admins submit the
                  // same person at once and the unique index catches the second.
                  if (isDuplicateMessage(msg)) {
                    if (!context.mounted) return;
                    await showDuplicateWarningDialog(context, message: msg);
                  } else {
                    scaffoldMessenger.showSnackBar(SnackBar(
                      content: Text(msg),
                      backgroundColor: AppColors.error,
                      duration: const Duration(seconds: 6),
                    ));
                  }
                }
              },
              child: isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(needsCode ? 'Verify & Create' : 'Create User'),
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }

  // Filter bottom sheet removed in favor of inline dropdowns

  // the main build method — the whole screen with appbar, search, and list
  @override
  Widget build(BuildContext context) {
    final personnel = _filteredPersonnel; // apply filter+sort before rendering

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
        title: const Text('Personnel Management', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: AppColors.primary),
            onPressed: _showAddPersonnelDialog,
          ),
          SafeIconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _fetchData,
          ),
        ],
      ),
      // spinner while loading, column layout when done
      body: _isLoading 
          ? const AppleLoadingState(label: 'Loading SAO personnel…')
          : Column(
              children: [
                // search + inline dropdowns for filters
                AppleSurface(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      AppleSearchField(
                        onChanged: (v) => setState(() => _searchQuery = v), // filter live as you type
                        hintText: 'Search name or university ID',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedRoleFilter,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: AppColors.background,
                              ),
                              icon: const Icon(Icons.filter_list, color: AppColors.primary),
                              items: ['All', ..._saoRoles.map((r) => r['Roles'].toString())].map((String role) {
                                return DropdownMenuItem<String>(value: role, child: Text(role, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis));
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) setState(() => _selectedRoleFilter = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _sortBy,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: AppColors.background,
                              ),
                              icon: const Icon(Icons.sort, color: AppColors.primary),
                              items: _sortOptions.map((String option) {
                                return DropdownMenuItem<String>(value: option, child: Text(option, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis));
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) setState(() => _sortBy = value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchData,
                    color: AppColors.primary,
                    // show empty message or the actual list
                    child: personnel.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(16),
                                child: AppleEmptyState(
                                  icon: Icons.badge_outlined,
                                  title: 'No SAO personnel',
                                  message: 'Try changing the search or role filter.',
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: personnel.length,
                          itemBuilder: (context, index) {
                            final person = personnel[index];
                            final ui = person['user_info'];
                            final isActive = ui['account_status'] == 'approved'; // is this person enabled?
                            final isTargetAdmin = person['role_data']?['Roles'] == 'SAO_ADMIN'; // admins have shield icon, cannot edit by others

                            return Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                onTap: () => _showPersonnelDetailsModal(person), // tap to see details
                                leading: CircleAvatar(
                                  // gray if disabled, colored if active
                                  backgroundColor: isActive ? AppColors.primary.withValues(alpha: 0.1) : AppColors.borderHairline,
                                  // first_name is nullable and may be empty; [0] threw in build.
                                  child: Text((ui['first_name'] ?? '').toString().isNotEmpty ? ui['first_name'].toString()[0] : '?', style: TextStyle(color: isActive ? AppColors.primary : AppColors.textSecondary)),
                                ),
                                // strikethrough if disabled — visual cue that account is off
                                title: Text('${ui['first_name']} ${ui['last_name']}', style: TextStyle(fontWeight: FontWeight.bold, decoration: isActive ? null : TextDecoration.lineThrough), overflow: TextOverflow.ellipsis),
                                subtitle: Text('${ui['university_id']} • ${person['role_data']?['Roles'] ?? 'N/A'}', overflow: TextOverflow.ellipsis),
                                // admins get a shield icon — cannot be edited by others, dili pwede
                                trailing: isTargetAdmin 
                                  ? const Icon(Icons.shield, color: AppColors.textSecondary, size: 20) // Admins cannot be edited by other admins
                                  : PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == 'edit') _showEditPersonnelDialog(person);
                                    if (val == 'status') _toggleStatus(person);
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Profile')])),
                                    PopupMenuItem(value: 'status', child: Row(children: [Icon(isActive ? Icons.block : Icons.check_circle, size: 18), SizedBox(width: 8), Text(isActive ? 'Disable' : 'Enable')])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ),
                ),
              ],
            ),
    );
  }
}
