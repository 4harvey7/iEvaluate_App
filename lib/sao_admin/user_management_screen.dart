// lib/sao_admin/user_management_screen.dart
// This screen manage all the academic users — professors, dept heads, etc.
// If a person teach in a classroom, they probably here somewhere.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/apple_ui.dart';
import '../widgets/safe_button.dart';

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
              email,
              employment_status
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

  // ── Assign Second Department (for Non-Resident instructors) ──────────────
  // SAO Admin can link a Non-Resident instructor to a second department.
  // Each dept head of that second dept will then see the instructor in their roster.
  Future<void> _showAssignSecondDeptDialog(Map<String, dynamic> user) async {
    final userId = user['user_id'];
    final ui = user['user_info'];
    final fullName = '${ui['first_name']} ${ui['last_name']}';
    int? selectedDeptId;
    bool isSaving = false;

    // Fetch current secondary departments for this instructor
    List<Map<String, dynamic>> currentSecondaryDepts = [];
    try {
      final rows = await _supabase
          .from('instructor_departments')
          .select('department_id, is_primary, department_name:department_id(d_name)')
          .eq('instructor_id', userId)
          .eq('is_primary', false);
      currentSecondaryDepts = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('[USER_MGMT] Error fetching secondary depts: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Assign Second Department\n$fullName',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show existing secondary depts
                if (currentSecondaryDepts.isNotEmpty) ...[
                  const Text('Current secondary departments:',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  ...currentSecondaryDepts.map((d) {
                    final deptNameData = d['department_name'];
                    final dName = deptNameData is List
                        ? (deptNameData.isNotEmpty ? deptNameData[0]['d_name'] : 'Unknown')
                        : deptNameData?['d_name'] ?? 'Unknown';
                    final deptId = d['department_id'];
                    return Row(
                      children: [
                        const Icon(Icons.apartment, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(dName.toString(),
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                        // Remove button
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red, size: 18),
                          tooltip: 'Remove this secondary dept',
                          onPressed: () async {
                            // Capture context references before async gap
                            final nav = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await _supabase
                                  .from('instructor_departments')
                                  .delete()
                                  .eq('instructor_id', userId)
                                  .eq('department_id', deptId)
                                  .eq('is_primary', false);
                              nav.pop();
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Secondary department removed.'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                              _showAssignSecondDeptDialog(user);
                            } catch (e) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Error removing dept: $e'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                        ),

                      ],
                    );
                  }),
                  const Divider(height: 24),
                ],
                const Text('Add a new secondary department:',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: selectedDeptId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Select Department'),
                  items: _allDeptNames
                      .map((d) => DropdownMenuItem<int>(
                            value: d['id'],
                            child: Text(d['d_name']),
                          ))
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedDeptId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            StatefulBuilder(
              builder: (context, setButtonState) => ElevatedButton(
                onPressed: isSaving || selectedDeptId == null
                    ? null
                    : () async {
                        setButtonState(() => isSaving = true);
                        // Captured before the await — this context belongs to
                        // the StatefulBuilder and is popped below.
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await _supabase.from('instructor_departments').insert({
                            'instructor_id': userId,
                            'department_id': selectedDeptId,
                            'is_primary': false, // secondary dept
                          });
                          if (mounted) {
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Second department assigned successfully.'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          setButtonState(() => isSaving = false);
                          // Catch duplicate assignment — friendly message instead of raw DB error
                          final errStr = e.toString();
                          final isDuplicate = errStr.contains('unique') ||
                              errStr.contains('duplicate') ||
                              errStr.contains('23505');
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(isDuplicate
                                    ? 'This instructor is already assigned to that department.'
                                    : 'Error assigning department. Please try again.'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Assign', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
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
        builder: (context, setDialogState) => AlertDialog(
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
                  // pick a department — everyone needs a department
                  DropdownButtonFormField<int>(
                    initialValue: selectedDeptId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: _allDeptNames.map((d) => DropdownMenuItem<int>(value: d['id'], child: Text(d['d_name']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedDeptId = val!),
                  ),
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
                // basic email format check — murag real email ba
                if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(em)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email address'), backgroundColor: Colors.red));
                  return;
                }
                // university ID must have at least 4 characters — reasonable requirement
                if (id.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('University ID must be at least 4 characters'), backgroundColor: Colors.red));
                  return;
                }
                final roleMatches = _roles.where((r) => r['id'] == selectedRoleId).toList();
                if (roleMatches.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid role'), backgroundColor: Colors.red));
                  return;
                }
                final role = roleMatches.first;
                final roleName = role['Roles'];

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
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error));
                }
              },
              // show spinner when saving, show text otherwise
              child: isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(needsCode ? 'Verify & Create' : 'Create User'),
            ),
          ],
        ),
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(needsCode ? 'Verify Authorization' : 'Edit Academic Profile'), // title changes on step 2
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  // edit form fields — name, role, department
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedRoleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _roles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selectedDeptId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: _allDeptNames.map((d) => DropdownMenuItem<int>(value: d['id'], child: Text(d['d_name']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedDeptId = val!),
                  ),
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
                final roleMatches = _roles.where((r) => r['id'] == selectedRoleId).toList();
                if (roleMatches.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid role'), backgroundColor: Colors.red));
                  return;
                }
                final role = roleMatches.first;
                final roleName = role['Roles'];
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
                    'firstName': firstController.text.trim(),
                    'lastName': lastController.text.trim(),
                    'roleId': selectedRoleId,
                    'roleName': roleName,
                    'verificationCode': codeController.text.trim(),
                    'isAcademic': true,
                    'isPromotion': isUpgradingToHead, // true only when actually promoting to Dept Head
                  });
                  _fetchData(); // reload users after update
                  if (mounted) navigator.pop();
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.error));
                }
              },
              child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Changes'),
            ),
          ],
        ),
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
                                   // three dot menu with edit, enable/disable, and second dept options
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'edit') _showEditUserDialog(user);
                                      if (val == 'status') _toggleUserStatus(user);
                                      if (val == 'second_dept') _showAssignSecondDeptDialog(user);
                                    },
                                    itemBuilder: (context) {
                                      final empStatus = user['user_info']?['employment_status']?.toString() ?? '';
                                      final isNonResident = empStatus.toLowerCase().contains('part') ||
                                          empStatus.toLowerCase().contains('non');
                                      return [
                                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Profile')])),
                                        PopupMenuItem(value: 'status', child: Row(children: [Icon(isActive ? Icons.block : Icons.check_circle, size: 18), SizedBox(width: 8), Text(isActive ? 'Disable' : 'Approve')])),
                                        if (isNonResident)
                                          const PopupMenuItem(value: 'second_dept', child: Row(children: [Icon(Icons.apartment, size: 18, color: Colors.teal), SizedBox(width: 8), Text('Assign Second Dept', style: TextStyle(color: Colors.teal))])),
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
