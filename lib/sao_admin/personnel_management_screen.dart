// lib/sao_admin/personnel_management_screen.dart
// This screen manages the SAO staff — the people running the evaluation system.
// Different from user_management (academics), this is for the SAO office folks.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env.dart';
import '../core/services/auth_service.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/safe_button.dart';
import '../widgets/apple_ui.dart';

// the outer shell widget — just a box, nothing special yet
class PersonnelManagementScreen extends StatefulWidget {
  const PersonnelManagementScreen({super.key});

  @override
  State<PersonnelManagementScreen> createState() => _PersonnelManagementScreenState();
}

class _PersonnelManagementScreenState extends State<PersonnelManagementScreen> {
  final _supabase = Supabase.instance.client; // database connection, treat with respect
  final _authService = AuthService(); // handles auth stuff like password reset
  
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
    final String currentStatus = ui['account_status'];
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  // ── Personnel Details Modal ───────────────────────────────────
  // shows bottom sheet with details — admins see profile info, staff see scan stats
  Future<void> _showPersonnelDetailsModal(Map<String, dynamic> person) async {
    final ui = person['user_info'];
    final userId = person['user_id'];
    final roleName = person['role_data']?['Roles'] ?? '';
    final fullName = '${ui['first_name']} ${ui['last_name']}';
    final isAdmin = roleName.toUpperCase().contains('ADMIN'); // admins get different view

    // scan statistics — now relevant for ALL SAO personnel since Admins can act as Gatherers
    int totalScans = 0, todayScans = 0, termScans = 0;
    String lastUpload = '';

    try {
      final settings = await _supabase.from('system_settings').select('current_term_id').limit(1).maybeSingle();
      final termId = settings?['current_term_id'];
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String(); // midnight UTC

      // All-time scans by this user — from the beginning of time
      final all = await _supabase
          .from('sast_all_raw_data_survey')
          .select('created_at')
          .eq('sao_staff_id', userId);
      totalScans = (all as List).length;

      // This term's scans — scoped to current active term
      var termQ = _supabase
          .from('sast_all_raw_data_survey')
          .select('created_at')
          .eq('sao_staff_id', userId);
      if (termId != null) termQ = termQ.eq('term_id', termId); // apply term filter
      final termRows = await termQ;
      termScans = (termRows as List).length;
      // today's scans = anything uploaded since midnight today
      todayScans = termRows.where((r) => (r['created_at'] as String? ?? '').compareTo(startOfDay) >= 0).length;

      if (all.isNotEmpty) {
        // find the most recent upload timestamp
        final sorted = all.map((r) => r['created_at'] as String).toList()..sort((a, b) => b.compareTo(a));
        lastUpload = sorted.first; // most recent = first after descending sort
      }
    } catch (e) { debugPrint('PersonnelModal error: $e'); }

    if (!mounted) return;
    // show the modal with different content based on whether person is admin or staff
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.65, // 65% of screen height
        decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          // header with name, role, and email
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Row(children: [
              CircleAvatar(radius: 26, backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                  child: Text((ui['first_name'] as String)[0], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                Text(roleName, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12), overflow: TextOverflow.ellipsis),
                Text(ui['email'] ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11), overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
          // body: admin sees profile and stats, staff sees just their scan stats
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (isAdmin) _buildAdminProfile(ui), // show profile details for admins
                if (isAdmin) const SizedBox(height: 24),
                _buildGathererStats(totalScans, termScans, todayScans, lastUpload), // show scan stats for EVERYONE now
              ],
            ),
          )),
        ]),
      ),
    );
  }

  // builds a simple profile view for SAO admin accounts
  // admins just need to see their ID, email, and status — no scan stats
  Widget _buildAdminProfile(Map<String, dynamic> ui) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Account Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
      const SizedBox(height: 16),
      _profileRow(Icons.badge_outlined, 'University ID', ui['university_id']?.toString() ?? '-'),
      _profileRow(Icons.email_outlined, 'Email', ui['email'] ?? '-'),
      _profileRow(Icons.check_circle_outline, 'Status', ui['account_status'] ?? '-'),
    ]);
  }

  // builds scan statistics for SAO staff — today, this term, and all-time counts
  // also shows how long ago their last upload was
  Widget _buildGathererStats(int total, int term, int today, String lastUpload) {
    String lastStr = 'No uploads yet'; // default if they haven't uploaded anything
    if (lastUpload.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastUpload).toLocal(); // convert from UTC to local time
        final diff = DateTime.now().difference(dt);
        // human-readable time ago: minutes, hours, or days
        if (diff.inMinutes < 60) lastStr = '${diff.inMinutes}m ago';
        else if (diff.inHours < 24) lastStr = '${diff.inHours}h ago';
        else lastStr = '${diff.inDays}d ago';
      } catch (_) {} // if parsing fails, just keep 'No uploads yet'
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Scan Statistics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
      const SizedBox(height: 16),
      // three boxes: today, this term, all time — in order of recency
      Row(children: [
        Expanded(child: _statBox('Today', '$today', AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(child: _statBox('This Term', '$term', Colors.teal)),
        const SizedBox(width: 10),
        Expanded(child: _statBox('All Time', '$total', AppColors.success)),
      ]),
      const SizedBox(height: 16),
      // last upload time — useful to see if staff been active recently
      _profileRow(Icons.cloud_upload_outlined, 'Last Upload', lastStr),
    ]);
  }

  // a single row in the profile view — icon, label, and value side by side
  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 18), // colored icon on left
        const SizedBox(width: 12),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)), // bold label
        Expanded(child: Text(value, style: const TextStyle(color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)), // value text
      ]),
    );
  }

  // a colored box with a big number and a label underneath it
  // used for scan count stats — today, term, all-time
  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis), // big number
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis), // label below
      ]),
    );
  }

  // dialog to edit an existing SAO personnel — name and role changes
  // if promoting to SAO_ADMIN, needs OTP verification — dili basta basta mag-promote
  void _showEditPersonnelDialog(Map<String, dynamic> person) {
    final ui = person['user_info'];
    // pre-fill with current values
    TextEditingController firstController = TextEditingController(text: ui['first_name']);
    TextEditingController lastController = TextEditingController(text: ui['last_name']);
    TextEditingController codeController = TextEditingController(); // OTP input for admin promotion
    int selectedRoleId = person['role_id'];
    bool needsCode = false; // becomes true if promoting to SAO_ADMIN
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false, // cannot dismiss by tapping outside
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(needsCode ? 'Verify Authorization' : 'Edit Personnel Profile', 
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  // step 1: edit form
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 16),
                  // role dropdown — only SAO roles shown here
                  DropdownButtonFormField<int>(
                    value: selectedRoleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _saoRoles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val!),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            SafeElevatedButton(
              onPressed: () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final selectedRole = _saoRoles.firstWhere((r) => r['id'] == selectedRoleId);
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
                     setDialogState(() => isSaving = false);
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

                  // 2. Call the Edge Function to verify the code and update the role
                  final response = await _supabase.functions.invoke(
                    'admin-update-role',
                    body: {
                      'targetUserId': targetUserId,
                      'firstName': firstController.text.trim(),
                      'lastName': lastController.text.trim(),
                      'roleId': selectedRoleId,
                      'roleName': roleName,
                      'isAcademic': false, // this is SAO staff, not academic
                      'verificationCode': codeController.text.trim(), // Server verifies this!
                    },
                    headers: {
                      'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                      'apikey': Env.supabaseAnonKey,
                    },
                  );

                  if (response.status == 200) {
                    _fetchData(); // reload the list to show changes
                    if (mounted) navigator.pop();
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('Personnel updated successfully!'), backgroundColor: AppColors.success)
                    );
                  } else {
                    // server returned an error, extract and throw the message
                    final errorMsg = response.data is Map ? (response.data['error'] ?? 'Server error') : 'Server error';
                    throw errorMsg;
                  }
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.error)
                  );
                }
              },
              // show spinner or button label depending on save state
              child: isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(needsCode ? 'Verify & Save' : 'Save Changes'),
            ),
          ],
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                  TextField(controller: idController, decoration: const InputDecoration(labelText: 'University ID')),
                  const SizedBox(height: 16),
                  // role dropdown — only SAO roles (SAO_ADMIN, SAO_STAFF etc.)
                  DropdownButtonFormField<String>(
                    value: selectedRoleName,
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                if (selectedRoleName == null) return; // no role selected, ayaw proceed
                // Validate required fields — all four must be filled
                final fn = firstController.text.trim();
                final ln = lastController.text.trim();
                final em = emailController.text.trim();
                final id = idController.text.trim();
                if (fn.isEmpty || ln.isEmpty || em.isEmpty || id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all required fields'), backgroundColor: Colors.red));
                  return;
                }
                // validate email format — looks murag real email
                if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(em)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email address'), backgroundColor: Colors.red));
                  return;
                }
                // university ID must have at least 4 chars — reasonable minimum
                if (id.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('University ID must be at least 4 characters'), backgroundColor: Colors.red));
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
                     setDialogState(() { needsCode = true; isSaving = false; }); // switch to OTP step
                     scaffoldMessenger.showSnackBar(SnackBar(content: Text('Verification code sent to ${currentUser?.email}')));
                     return;
                   } catch (e) {
                     setDialogState(() => isSaving = false);
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
                    if (mounted) navigator.pop();
                    scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Personnel created!'), backgroundColor: AppColors.success));
                  } else {
                    throw response.data['error'] ?? 'Server error'; // server said no
                  }
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error));
                }
              },
              child: isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(needsCode ? 'Verify & Create' : 'Create User'),
            ),
          ],
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
                              value: _selectedRoleFilter,
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
                              value: _sortBy,
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
                                  child: Text(ui['first_name'][0], style: TextStyle(color: isActive ? AppColors.primary : AppColors.textSecondary)),
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
                                    if (val == 'status') _toggleStatus(person); // enable/disable
                                    if (val == 'reset') {
                                      // send password reset email — useful when staff forget password
                                      _authService.sendPasswordResetEmail(ui['email']);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset email sent.')));
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Profile')])),
                                    PopupMenuItem(value: 'status', child: Row(children: [Icon(isActive ? Icons.block : Icons.check_circle, size: 18), SizedBox(width: 8), Text(isActive ? 'Disable' : 'Enable')])),
                                    const PopupMenuItem(value: 'reset', child: Row(children: [Icon(Icons.lock_reset, size: 18), SizedBox(width: 8), Text('Reset Password')])),
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
