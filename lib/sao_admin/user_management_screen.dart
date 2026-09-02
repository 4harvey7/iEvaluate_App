// lib/sao_admin/user_management_screen.dart
// This screen manage all the academic users — professors, dept heads, etc.
// If a person teach in a classroom, they probably here somewhere.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env.dart';
import '../core/services/department_head_guard.dart';
import '../core/services/identity_validator.dart';
import '../widgets/duplicate_warning_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/apple_ui.dart';
import '../widgets/safe_button.dart';

/// The head currently sitting for one department.
///
/// A department gets exactly one (migration 20240130000016), so this screen
/// keeps at most one per department id and uses it to say who is in the way
/// before an OTP is sent or an account is created.
class _SittingHead {
  const _SittingHead({required this.userId, required this.name});

  final String? userId;
  final String name;
}

// The widget shell — just a box that holds the real stuff inside
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _supabase = Supabase.instance.client; // one ring to rule the database
  
  List<Map<String, dynamic>> _allUsers = []; // every academic user fetched from DB
  List<Map<String, dynamic>> _roles = []; // available roles, but only non-SAO ones
  List<Map<String, dynamic>> _allDeptNames = []; // all department names for dropdowns

  /// Which department already has a head, and who it is.
  ///
  /// Built from the rows this screen already fetched -- department_table IS the
  /// list of academic accounts, so naming the sitting head costs no extra
  /// query. Refreshed by every _fetchData, so it follows a promotion made here.
  Map<int, _SittingHead> _headByDept = <int, _SittingHead>{};

  bool _isLoading = true; // spinner flag — true while we waiting for data
  String _searchQuery = ''; // what the admin typed in the search box
  String _selectedRoleFilter = 'All'; // which role filter is selected, default all
  String _selectedDeptFilter = 'All'; // department filter — new
  String _sortBy = 'Newest'; // sort order — newest or oldest first
  final List<String> _sortOptions = ['Newest', 'Oldest', 'A-Z', 'Z-A']; // added a-z sorting

  // called once when screen opens — start loading data right away
  @override
  void initState() {
    super.initState();
    _fetchData(); // go get the users, dili ta wait
  }

  // fetch all users from department_table with their info, roles, and departments
  // this query is long because we need everything in one call — wala choice
  Future<void> _fetchData() async {
    if (!mounted) return; // screen already gone, ayaw proceed
    setState(() => _isLoading = true);
    
    try {
      debugPrint('[USER_MGMT] Fetching academic users from department_table...');
      // the big join query — gets user info, role, and dept all at once
      final usersResponse = await _supabase
          .from('department_table')
          .select('''
            id,
            user_id,
            Department_name_ID,
            roles,
            user_info!user_id (
              first_name,
              last_name,
              university_id,
              account_status,
              email
            ),
            role_data:roles!roles ( Roles ),
            dept_data:department_name!Department_name_ID ( d_name )
          ''');

      // fetch all departments separately for the edit dropdown
      final deptsResponse = await _supabase.from('department_name').select('id, d_name');
      // fetch all roles — we'll filter out SAO roles after
      final rolesResponse = await _supabase.from('roles').select('id, Roles');

      debugPrint('[USER_MGMT] Raw DB Response Count: ${usersResponse.length}');
      for (var u in usersResponse) {
         final ui = u['user_info'];
         debugPrint(' - Found: ${ui != null ? '${ui['first_name']} ${ui['last_name']}' : "MISSING_USER_INFO"} | ID: ${u['user_id']} | Status: ${ui != null ? ui['account_status'] : "N/A"}');
      }

      if (mounted) {
        setState(() {
          _allUsers = List<Map<String, dynamic>>.from(usersResponse);
          _allDeptNames = List<Map<String, dynamic>>.from(deptsResponse);
          _headByDept = _readHeadsByDept(_allUsers);
          // filter roles to only non-SAO ones — this screen is for academic staff only
          _roles = List<Map<String, dynamic>>.from(rolesResponse)
              .where((r) => !r['Roles'].toString().toUpperCase().contains('SAO'))
              .toList();
          _isLoading = false; // done loading, show the list
        });
      }
    } catch (e) {
      debugPrint('[USER_MGMT] Error fetching data: $e');
      if (mounted) {
        setState(() => _isLoading = false); // stop spinner even if it crash
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load user data. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── One department head per department ─────────────────────────────────────
  // The rule is enforced by the trigger department_table_one_head (migration
  // 20240130000016) and re-checked by admin-create-academic and
  // admin-update-role. Everything below is so the admin reads a sentence
  // instead of a rejected write -- and reads it before a verification code is
  // emailed, since promoting someone to head costs an OTP round trip.

  /// Sitting heads keyed by department id, read from the rows already fetched.
  ///
  /// DEAN counts as a head: it routes to the same dashboard as
  /// DEPARTMENT_HEAD, so two of them over one department is the collision the
  /// rule exists to stop. A deleted account is not sitting in the chair.
  Map<int, _SittingHead> _readHeadsByDept(List<Map<String, dynamic>> rows) {
    final Map<int, _SittingHead> heads = <int, _SittingHead>{};
    for (final row in rows) {
      final deptId = row['Department_name_ID'];
      if (deptId is! int) continue;
      if (!isDepartmentHeadRole(row['role_data']?['Roles']?.toString())) continue;

      final ui = row['user_info'];
      if (ui == null) continue;
      if ((ui['account_status'] ?? '').toString().toLowerCase() == 'deleted') {
        continue;
      }

      final name =
          '${ui['first_name'] ?? ''} ${ui['last_name'] ?? ''}'.trim();
      heads[deptId] = _SittingHead(
        userId: row['user_id']?.toString(),
        name: name.isEmpty ? 'Another account' : name,
      );
    }
    return heads;
  }

  /// The head standing in the way of making someone head of [deptId], or null
  /// when the chair is free.
  ///
  /// [excludeUserId] is the account being edited, so the sitting head is never
  /// reported as blocking themselves -- re-saving their own profile, or moving
  /// them to another department, has to stay possible.
  _SittingHead? _headBlocking(Object? deptId, {String? excludeUserId}) {
    if (deptId is! int) return null;
    final head = _headByDept[deptId];
    if (head == null) return null;
    if (excludeUserId != null && head.userId == excludeUserId) return null;
    return head;
  }

  String _deptNameFor(Object? deptId) {
    for (final d in _allDeptNames) {
      if (d['id'] == deptId) return (d['d_name'] ?? '').toString();
    }
    return '';
  }

  /// The sentence shown for a taken chair, wherever it is shown.
  String _headTakenMessage(_SittingHead head, Object? deptId) =>
      DepartmentHeadGuard.conflictMessage(
        headName: head.name,
        departmentName: _deptNameFor(deptId),
      );

  /// Inline warning inside the create / edit dialogs.
  Widget _buildHeadTakenBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.person_off_outlined, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.error, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Department items for the create / edit dialogs.
  ///
  /// When the role being assigned is a head role, departments that already have
  /// one are disabled and labelled with who holds it -- the admin can see the
  /// whole picture without opening each department, and cannot pick one that
  /// would be refused. For every other role all departments stay selectable:
  /// a department with a head still takes instructors.
  List<DropdownMenuItem<int>> _departmentItems({
    required bool forHeadRole,
    String? excludeUserId,
  }) {
    return _allDeptNames.map((d) {
      final id = d['id'] as int;
      final name = (d['d_name'] ?? '').toString();
      final head = forHeadRole
          ? _headBlocking(id, excludeUserId: excludeUserId)
          : null;
      return DropdownMenuItem<int>(
        value: id,
        enabled: head == null,
        child: Text(
          head == null ? name : '$name — head: ${head.name}',
          style: TextStyle(
            color: head == null ? AppColors.textPrimary : AppColors.textTertiary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }).toList();
  }

  /// Modal shown when the admin submits anyway (the department was picked
  /// before the role, or the data went stale under them).
  Future<void> _showHeadTakenDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.person_off_outlined,
            color: AppColors.error, size: 32),
        title: const Text('Department Head Already Assigned',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(message, style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // computed getter that filters and sorts _allUsers based on current search/filter/sort
  // no DB call here — all done in memory, basin maglisod if user count is huge
  List<Map<String, dynamic>> get _filteredUsers {
    List<Map<String, dynamic>> filtered = _allUsers.where((user) {
      final ui = user['user_info'];
      if (ui == null) return false; // wala user info, skip this one
      
      final roleName = user['role_data']?['Roles'] ?? 'Unknown';
      final deptName = user['dept_data']?['d_name'] ?? '';

      // apply role filter
      if (_selectedRoleFilter != 'All' && roleName != _selectedRoleFilter) return false;
      // apply department filter
      if (_selectedDeptFilter != 'All' && deptName != _selectedDeptFilter) return false;
      
      if (_searchQuery.isNotEmpty) {
        // search by full name OR university ID — both are valid ways to find someone
        final fullName = '${ui['first_name']} ${ui['last_name']}'.toLowerCase();
        final uniId = ui['university_id'].toString().toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!fullName.contains(query) && !uniId.contains(query)) return false;
      }
      return true; // this user passed all filters, include them
    }).toList();

    // sort by ID string or Name
    filtered.sort((a, b) {
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

  // toggle a user between approved and disabled — basically enable/disable them
  // wala middle ground, either approved or disabled
  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final ui = user['user_info'];
    final String currentStatus = ui['account_status'];
    // flip the status: if approved then disable, if disabled then approve
    final String newStatus = currentStatus == 'approved' ? 'disabled' : 'approved';
    
    try {
      // call edge function to update the status — importente kaayo this goes through the function
      await _supabase.functions.invoke('admin-accept-user', body: {
        'targetUserId': user['user_id'],
        'status': newStatus,
      });
      _fetchData(); // refresh the list after change
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

  // ── User Details Modal ────────────────────────────────────────
  // shows a bottom sheet with details — different content for dept heads vs instructors
  Future<void> _showUserDetailsModal(Map<String, dynamic> user) async {
    final ui = user['user_info'];
    final userId = user['user_id'];
    final roleName = user['role_data']?['Roles'] ?? '';
    final deptName = user['dept_data']?['d_name'] ?? 'No Dept';
    final fullName = '${ui['first_name']} ${ui['last_name']}';
    final isDeptHead = roleName.toUpperCase().contains('DEPARTMENT'); // check if dept head

    // prepare containers for data we'll fetch below
    List<Map<String, dynamic>> subjects = [];
    Map<String, dynamic>? overallScore;
    Map<String, dynamic>? deptSummary;

    try {
      // get the current active term — everything is scoped to this term
      final settings = await _supabase.from('system_settings').select('current_term_id').limit(1).maybeSingle();
      final termId = settings?['current_term_id'];

      if (isDeptHead) {
        // for dept heads, show summary of all instructors under them
        final deptRow = await _supabase.from('department_table').select('Department_name_ID').eq('user_id', userId).maybeSingle();
        final deptId = deptRow?['Department_name_ID'];
        if (deptId != null && termId != null) {
          // Get all instructors in this department
          final instrRows = await _supabase
              .from('department_table')
              .select('user_id')
              .eq('Department_name_ID', deptId);
          final instrIds = (instrRows as List).map((r) => r['user_id'].toString()).toList();

          if (instrIds.isNotEmpty) {
            // Sum their scores from overall_total_survey — compute dept average
            final rows = await _supabase
                .from('overall_total_survey')
                .select('overall_mean, combined_score_mean, total_responses')
                .eq('term_id', termId)
                .filter('instructor_id', 'in', instrIds);
            int total = 0; double sum = 0;
            for (final r in (rows as List)) {
              total += (r['total_responses'] as int? ?? 0);
              sum += (r['combined_score_mean'] as num?)?.toDouble() ?? (r['overall_mean'] as num?)?.toDouble() ?? 0.0;
            }
            // package the summary into a map
            deptSummary = {
              'instructorCount': instrIds.length,
              'avgScore': (rows).isEmpty ? 0.0 : sum / (rows).length,
              'totalResponses': total,
            };
          }
        }
      }

      // Fetch personal Instructor stats for EVERYONE (both regular Instructors AND Dept Heads)
      if (termId != null) {
        // get subjects assigned to this instructor this term
        final rows = await _supabase
            .from('instructor_subjects')
            .select('subjects(subject_code, subject_name)')
            .eq('instructor_id', userId)
            .eq('term_id', termId);
        subjects = (rows as List).map((r) {
          final s = r['subjects'];
          return Map<String, dynamic>.from(s is List ? s[0] : s ?? {});
        }).toList();
        
        // get their personal overall evaluation score this term
        overallScore = await _supabase.from('overall_total_survey')
            .select('overall_mean, combined_score_mean, management_mean, performance_mean, total_responses')
            .eq('instructor_id', userId).eq('term_id', termId).maybeSingle();
      }
    } catch (e) { debugPrint('UserDetailsModal error: $e'); } // log it and continue

    if (!mounted) return;
    // show the actual bottom sheet
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.75, // takes up 75% of screen height
        decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          // top header with user's name, role, and dept
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
                Text(deptName, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11), overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
          // scrollable content — dept summary (if applicable) AND instructor scores (for everyone)
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (isDeptHead) ...[
                  _buildDeptModal(deptSummary, deptName),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
                // Show instructor details for EVERYONE (Dept Heads are instructors too!)
                _buildInstructorModal(overallScore, subjects),
              ],
            ),
          )),
        ]),
      ),
    );
  }

  // build the dept head modal content — shows dept stats like avg score, count
  Widget _buildDeptModal(Map<String, dynamic>? s, String name) {
    if (s == null) return const Center(child: Text('No department data.', style: TextStyle(color: AppColors.textSecondary)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Department Summary — $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
      const SizedBox(height: 16),
      // three info tiles: average score, instructor count, total responses
      Row(children: [
        Expanded(child: _infoTile('Avg Score', (s['avgScore'] as double).toStringAsFixed(2), AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(child: _infoTile('Instructors', '${s['instructorCount']}', Colors.teal)),
        const SizedBox(width: 10),
        Expanded(child: _infoTile('Responses', '${s['totalResponses']}', AppColors.success)),
      ]),
    ]);
  }

  // build the instructor modal content — shows score breakdown and their subjects
  Widget _buildInstructorModal(Map<String, dynamic>? overall, List<Map<String, dynamic>> subjects) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (overall != null) ...[
        const Text('Score Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        // three scores: overall, management, performance — the holy trinity of evaluation
        Row(children: [
          Expanded(child: _infoTile('Overall', (overall['combined_score_mean'] as num?)?.toStringAsFixed(2) ?? (overall['overall_mean'] as num?)?.toStringAsFixed(2) ?? '-', AppColors.primary)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile('Management', (overall['management_mean'] as num?)?.toStringAsFixed(2) ?? '-', Colors.teal)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile('Performance', (overall['performance_mean'] as num?)?.toStringAsFixed(2) ?? '-', AppColors.success)),
        ]),
        const SizedBox(height: 6),
        // how many students actually submitted evaluations
        Text('${overall['total_responses'] ?? 0} responses this term', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 20),
      ],
      Text('Subjects This Term (${subjects.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
      const SizedBox(height: 12),
      // show subject cards or empty message if none assigned
      if (subjects.isEmpty) const Text('No subjects assigned.', style: TextStyle(color: AppColors.textSecondary))
      else ...subjects.map((s) => Card(
        color: AppColors.surface, margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: const Icon(Icons.menu_book, color: AppColors.primary, size: 20),
          title: Text('${s['subject_code']} — ${s['subject_name']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis),
        ),
      )),
    ]);
  }

  // small colored info tile with a big value and a label below
  // reusable mini card, used all over the modals
  Widget _infoTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis), // the big number
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  // show the dialog to add a brand new academic user — lots of fields, lots of validation

  void _showAddUserDialog() {
    TextEditingController firstController = TextEditingController();
    TextEditingController lastController = TextEditingController();
    TextEditingController emailController = TextEditingController();
    TextEditingController idController = TextEditingController();
    TextEditingController codeController = TextEditingController(); // for the OTP verification step
    int? selectedRoleId = _roles.isNotEmpty ? _roles.first['id'] : null;
    int? selectedDeptId = _allDeptNames.isNotEmpty ? _allDeptNames.first['id'] : null;
    bool needsCode = false; // becomes true when creating a DEPARTMENT_HEAD, extra auth needed
    bool isSaving = false; // disable button while request in flight, ayaw double click

    showDialog(
      context: context,
      barrierDismissible: false, // cannot dismiss by tapping outside, dili ta escape
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Recomputed on every rebuild, so picking a head role or another
          // department updates the disabled items and the warning at once.
          final selectedRole = _roles.firstWhere(
            (r) => r['id'] == selectedRoleId,
            orElse: () => <String, dynamic>{},
          );
          final bool creatingHead =
              isDepartmentHeadRole(selectedRole['Roles']?.toString());
          final _SittingHead? blockingHead =
              creatingHead ? _headBlocking(selectedDeptId) : null;

          return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          // title changes depending on which step we're on
          title: Text(needsCode ? 'Verify Authorization' : 'Add Academic Personnel',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  // step 1: fill in the user details
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 12),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(controller: idController, decoration: const InputDecoration(labelText: 'University ID')),
                  const SizedBox(height: 16),
                  // pick a role from the dropdown — only non-SAO roles shown here
                  DropdownButtonFormField<int>(
                    initialValue: selectedRoleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _roles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val),
                  ),
                  const SizedBox(height: 12),
                  // pick a department — everyone needs a department.
                  // For a head role the departments that already have one are
                  // disabled and labelled with who holds it: a department gets
                  // exactly one head, so those are not choices.
                  DropdownButtonFormField<int>(
                    initialValue: selectedDeptId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: _departmentItems(forHeadRole: creatingHead),
                    onChanged: (val) => setDialogState(() => selectedDeptId = val!),
                  ),
                  if (blockingHead != null)
                    _buildHeadTakenBanner(
                        _headTakenMessage(blockingHead, selectedDeptId)),
                ] else ...[
                  // step 2: verify with OTP code before creating a dept head — extra security
                  const Text('Creating a Department Head requires authorization.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  const Text('Enter the 6-digit code sent to your email:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8), // big spaced code display
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
                // Validate fields first — ayaw submit if empty fields
                final fn = firstController.text.trim();
                final ln = lastController.text.trim();
                final em = emailController.text.trim();
                final id = idController.text.trim();
                if (fn.isEmpty || ln.isEmpty || em.isEmpty || id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all required fields'), backgroundColor: Colors.red));
                  return;
                }
                // Role is checked here, before the network round trip below:
                // every local check should fail fast, and it keeps the
                // BuildContext use ahead of the first await.
                final roleMatches = _roles.where((r) => r['id'] == selectedRoleId).toList();
                if (roleMatches.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid role'), backgroundColor: Colors.red));
                  return;
                }
                final role = roleMatches.first;
                final roleName = role['Roles'];
                // Name / email / ID rules all come from IdentityValidator, so
                // this screen, Personnel Management and the public registration
                // screen accept exactly the same values. They used to disagree.
                final formatError = IdentityValidator.validateFormat(
                  firstName: fn, lastName: ln, email: em, universityId: id,
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
                );
                if (!availability.isAvailable) {
                  if (!context.mounted) return;
                  await showDuplicateWarningDialog(
                    context,
                    message: availability.error!,
                    field: availability.field,
                  );
                  return;
                }

                // One head per department. Checked before the OTP is requested:
                // there is no point emailing a code for an account the database
                // will refuse. admin-create-academic checks again server-side
                // and the trigger is the actual guarantee, so this is the
                // message, not the enforcement.
                if (isDepartmentHeadRole(roleName?.toString())) {
                  final head = _headBlocking(selectedDeptId);
                  if (head != null) {
                    if (!context.mounted) return;
                    await _showHeadTakenDialog(
                        _headTakenMessage(head, selectedDeptId));
                    return;
                  }
                }

                // department head needs extra OTP verification — cannot just create one freely
                if (roleName == 'DEPARTMENT_HEAD' && !needsCode) {
                   final currentUser = _supabase.auth.currentUser;
                   setDialogState(() => isSaving = true);
                   try {
                     // request the server to email a verification code to the admin
                     await _supabase.functions.invoke(
                       'send-admin-code',
                       body: {'email': currentUser?.email},
                       headers: {
                         'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                         'apikey': Env.supabaseAnonKey,
                       },
                     );
                     // switch dialog to code entry step
                     setDialogState(() { needsCode = true; isSaving = false; });
                     scaffoldMessenger.showSnackBar(SnackBar(content: Text('Verification code sent to ${currentUser?.email}')));
                     return;
                   } catch (e) {
                     setDialogState(() => isSaving = false);
                     scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
                     return;
                   }
                }

                // actually create the user — call the edge function with all the data
                setDialogState(() => isSaving = true);
                try {
                  final response = await _supabase.functions.invoke(
                    'admin-create-academic',
                    body: {
                      'firstName': firstController.text.trim(),
                      'lastName': lastController.text.trim(),
                      'email': emailController.text.trim(),
                      'universityId': idController.text.trim(),
                      'roleName': roleName,
                      'deptId': selectedDeptId,
                      'verificationCode': codeController.text.trim(), // OTP if dept head
                    },
                    headers: {
                      'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                      'apikey': Env.supabaseAnonKey,
                    },
                  );

                  if (response.status == 200) {
                    _fetchData(); // refresh list to show the new user
                    if (mounted) navigator.pop();
                    scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Personnel created!'), backgroundColor: AppColors.success));
                  } else {
                    throw response.data['error'] ?? 'Server error'; // throw the server's error message
                  }
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  // The server's duplicate message has to survive to the admin,
                  // so unwrap the exception rather than printing it.
                  final msg = IdentityValidator.describeEdgeFunctionError(
                    e,
                    fallback: 'Could not create the user. Please try again.',
                  );
                  // The chair can be taken between the check above and this
                  // call -- by another admin, or by a registration approved in
                  // the meantime. Same modal either way.
                  final headTaken =
                      DepartmentHeadGuard.describeConflictError(msg);
                  if (headTaken != null) {
                    if (!context.mounted) return;
                    await _showHeadTakenDialog(headTaken);
                  }
                  // A duplicate can still reach us here if two admins submit the
                  // same person at once and the unique index catches the second.
                  else if (isDuplicateMessage(msg)) {
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
              // show spinner when saving, show text otherwise
              child: isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(needsCode ? 'Verify & Create' : 'Create User'),
            ),
          ],
          );
        },
      ),
    );
  }

  // show dialog to edit an existing user's name, role, or department
  // if changing to dept head, OTP verification kicks in again — dili ta skip security
  void _showEditUserDialog(Map<String, dynamic> user) {
    final ui = user['user_info'];
    // pre-fill the fields with existing data
    TextEditingController firstController = TextEditingController(text: ui['first_name']);
    TextEditingController lastController = TextEditingController(text: ui['last_name']);
    TextEditingController codeController = TextEditingController(); // for OTP if upgrading to dept head
    int selectedRoleId = user['roles'];
    int selectedDeptId = user['Department_name_ID'];
    bool needsCode = false; // becomes true if promoting to dept head
    bool isSaving = false;

    // What the record looked like when the dialog opened. Anything still equal
    // to this means there is nothing to save.
    final String originalFirst = (ui['first_name'] ?? '').toString().trim();
    final String originalLast = (ui['last_name'] ?? '').toString().trim();
    final int originalRoleId = selectedRoleId;
    final int originalDeptId = selectedDeptId;

    // Reads the live values, so the button label follows what is typed.
    // Nothing changed -> the button says Back and simply closes: no duplicate
    // check, no edge function call, and no "your account was updated" email to
    // a user whose account was not in fact updated.
    bool hasChanges() =>
        firstController.text.trim() != originalFirst ||
        lastController.text.trim() != originalLast ||
        selectedRoleId != originalRoleId ||
        selectedDeptId != originalDeptId;

    // This account never blocks itself: the sitting head has to be able to save
    // their own profile and to be moved to another department.
    final String? editedUserId = user['user_id']?.toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Recomputed on every rebuild, so the warning and the disabled
          // departments follow whatever is currently chosen in the dialog.
          final selectedRole = _roles.firstWhere(
            (r) => r['id'] == selectedRoleId,
            orElse: () => <String, dynamic>{},
          );
          final bool assigningHead =
              isDepartmentHeadRole(selectedRole['Roles']?.toString());
          final _SittingHead? blockingHead = assigningHead
              ? _headBlocking(selectedDeptId, excludeUserId: editedUserId)
              : null;

          return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(needsCode ? 'Verify Authorization' : 'Edit Academic Profile'), // title changes on step 2
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  // edit form fields — name, role, department.
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedRoleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _roles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val!),
                  ),
                  const SizedBox(height: 12),
                  // Departments that already have a head are disabled while a
                  // head role is selected, and labelled with who holds it.
                  DropdownButtonFormField<int>(
                    initialValue: selectedDeptId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: _departmentItems(
                      forHeadRole: assigningHead,
                      excludeUserId: editedUserId,
                    ),
                    onChanged: (val) => setDialogState(() => selectedDeptId = val!),
                  ),
                  if (blockingHead != null)
                    _buildHeadTakenBanner(
                        _headTakenMessage(blockingHead, selectedDeptId)),
                ] else ...[
                  // OTP step — only shown when upgrading someone to department head
                  const Text('Updating to Department Head requires authorization.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  const Text('Enter the 6-digit code:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                // Nothing edited: behave as a plain Back button.
                if (!hasChanges()) {
                  navigator.pop();
                  return;
                }
                final roleMatches = _roles.where((r) => r['id'] == selectedRoleId).toList();
                if (roleMatches.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid role'), backgroundColor: Colors.red));
                  return;
                }
                final role = roleMatches.first;
                final roleName = role['Roles'];

                // Renaming is the second way a duplicate appears: the account
                // was unique when created, then someone edits the name to match
                // an existing person. Validated here for a fast, clear message;
                // admin-update-role re-checks it server-side, and the unique
                // index is the actual guarantee.
                final newFirst = firstController.text.trim();
                final newLast = lastController.text.trim();
                final formatError = IdentityValidator.validateFormat(
                  firstName: newFirst, lastName: newLast,
                );
                if (formatError != null) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text(formatError), backgroundColor: AppColors.error));
                  return;
                }
                // excludeUserId is this account, so saving without touching the
                // name does not report the person as their own duplicate.
                final availability = await IdentityValidator.checkAvailability(
                  client: _supabase,
                  firstName: newFirst,
                  lastName: newLast,
                  excludeUserId: user['user_id']?.toString(),
                );
                if (!availability.isAvailable) {
                  if (!context.mounted) return;
                  await showDuplicateWarningDialog(
                    context,
                    message: availability.error!,
                    field: availability.field,
                  );
                  return;
                }

                // One head per department, checked before the OTP is requested.
                // Covers both ways this dialog can create a second head:
                // promoting someone in a department that already has one, and
                // moving a sitting head into a department that already has one.
                if (isDepartmentHeadRole(roleName?.toString())) {
                  final head = _headBlocking(selectedDeptId,
                      excludeUserId: editedUserId);
                  if (head != null) {
                    if (!context.mounted) return;
                    await _showHeadTakenDialog(
                        _headTakenMessage(head, selectedDeptId));
                    return;
                  }
                }

                // check if they're being promoted to dept head when they weren't before
                final bool isUpgradingToHead = roleName == 'DEPARTMENT_HEAD' && user['role_data']?['Roles'] != 'DEPARTMENT_HEAD';

                // upgrading to dept head needs OTP first — extra layer of protection
                if (isUpgradingToHead && !needsCode) {
                   final currentUser = _supabase.auth.currentUser;
                   setDialogState(() => isSaving = true);
                   try {
                     // request the OTP code from the server
                     await _supabase.functions.invoke('send-admin-code', body: {'email': currentUser?.email});
                     setDialogState(() { needsCode = true; isSaving = false; });
                     return;
                   } catch (e) {
                     setDialogState(() => isSaving = false);
                     return;
                   }
                }

                // actually update the user — call edge function with new data
                setDialogState(() => isSaving = true);
                try {
                  await _supabase.functions.invoke('admin-update-role', body: {
                    'targetUserId': user['user_id'],
                    'firstName': newFirst,
                    'lastName': newLast,
                    'roleId': selectedRoleId,
                    'roleName': roleName,
                    // Was never sent, which is why the Department dropdown in
                    // this dialog changed nothing. admin-update-role now moves
                    // department_table and the is_primary instructor_departments
                    // row together.
                    'deptId': selectedDeptId,
                    'verificationCode': codeController.text.trim(),
                    'isAcademic': true,
                    'isPromotion': isUpgradingToHead, // true only when actually promoting to Dept Head
                  });
                  _fetchData(); // reload users after update
                  if (mounted) navigator.pop();
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  // describeEdgeFunctionError digs the server's own wording out
                  // of the exception. Without it a duplicate shows up as
                  // "FunctionException(status: 400, details: {error: ...})".
                  final msg = IdentityValidator.describeEdgeFunctionError(
                    e,
                    fallback: 'Update failed. Please try again.',
                  );
                  // Someone else filled the chair between the check above and
                  // this call.
                  final headTaken =
                      DepartmentHeadGuard.describeConflictError(msg);
                  if (headTaken != null) {
                    if (!context.mounted) return;
                    await _showHeadTakenDialog(headTaken);
                  } else if (isDuplicateMessage(msg)) {
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
                  : Text(hasChanges() ? 'Save Changes' : 'Back'),
            ),
          ],
          );
        },
      ),
    );
  }

  // Filter bottom sheet removed in favor of inline dropdowns for better visibility

  // the main build — the whole screen is a list of users with search bar on top
  // Shared decoration for the three filter dropdowns — identical to the fields
  // on Personnel Management. Horizontal padding is a touch tighter than that
  // screen's because three dropdowns share one row here instead of two.
  InputDecoration _filterDecoration() {
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: AppColors.background,
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers; // get filtered+sorted list

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
        title: const Text('User Management', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: AppColors.primary),
            onPressed: _showAddUserDialog,
          ),
          SafeIconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _fetchData,
          ),
        ],
      ),
      // show spinner while loading, show content when done
      body: _isLoading
          ? const AppleLoadingState(label: 'Loading academic users…')
          : Column(
              children: [
                // search + inline dropdowns for filters — same layout as
                // Personnel Management, but with three dropdowns in one row
                AppleSurface(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      AppleSearchField(
                        onChanged: (v) => setState(() => _searchQuery = v), // filter live as you type
                        hintText: 'Search Name or University ID',
                      ),
                      const SizedBox(height: 12),
                      // Department | Role | Sort By — three across
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedDeptFilter,
                              isExpanded: true,
                              decoration: _filterDecoration(),
                              icon: const Icon(Icons.apartment, color: AppColors.primary, size: 18),
                              items: ['All', ..._allDeptNames.map((d) => d['d_name'].toString())].map((String dept) {
                                return DropdownMenuItem<String>(value: dept, child: Text(dept, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis));
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) setState(() => _selectedDeptFilter = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedRoleFilter,
                              isExpanded: true,
                              decoration: _filterDecoration(),
                              icon: const Icon(Icons.filter_list, color: AppColors.primary, size: 18),
                              items: ['All', ..._roles.map((r) => r['Roles'].toString())].map((String role) {
                                return DropdownMenuItem<String>(value: role, child: Text(role, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis));
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
                              decoration: _filterDecoration(),
                              icon: const Icon(Icons.sort, color: AppColors.primary, size: 18),
                              items: _sortOptions.map((String option) {
                                return DropdownMenuItem<String>(value: option, child: Text(option, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis));
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
                    onRefresh: _fetchData, // pull down to refresh
                    color: AppColors.primary,
                    // show empty state or user list depending on results
                    child: users.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              Center(child: Padding(
                                padding: EdgeInsets.all(48),
                                child: Text('No academic users found.'),
                              )),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final ui = user['user_info'];
                              final isActive = ui['account_status'] == 'approved'; // active or disabled

                              return Card(
                                color: AppColors.surface,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  onTap: () => _showUserDetailsModal(user), // tap to see details
                                  leading: CircleAvatar(
                                    // gray background if disabled, colored if active
                                    backgroundColor: isActive ? AppColors.primary.withValues(alpha: 0.1) : AppColors.borderHairline,
                                    child: Text(ui['first_name'][0], style: TextStyle(color: isActive ? AppColors.primary : AppColors.textSecondary)),
                                  ),
                                  // strikethrough name if user is disabled — visual cue
                                  title: Text('${ui['first_name']} ${ui['last_name']}', style: TextStyle(fontWeight: FontWeight.bold, decoration: isActive ? null : TextDecoration.lineThrough), overflow: TextOverflow.ellipsis),
                                  subtitle: Text('${ui['university_id']} • ${user['role_data']?['Roles'] ?? 'N/A'}\n${user['dept_data']?['d_name'] ?? 'No Dept'}', overflow: TextOverflow.ellipsis),
                                  isThreeLine: true,
                                   // three dot menu with edit and enable/disable options
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'edit') _showEditUserDialog(user);
                                      if (val == 'status') _toggleUserStatus(user);
                                    },
                                    itemBuilder: (context) {
                                      return [
                                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Profile')])),
                                        PopupMenuItem(value: 'status', child: Row(children: [Icon(isActive ? Icons.block : Icons.check_circle, size: 18), SizedBox(width: 8), Text(isActive ? 'Disable' : 'Approve')])),
                                      ];
                                    },
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
