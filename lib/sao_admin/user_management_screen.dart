// lib/sao_admin/user_management_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env.dart';
import '../theme/app_colors.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _roles = []; 
  List<Map<String, dynamic>> _allDeptNames = []; 
  
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRoleFilter = 'All';
  String _sortBy = 'Newest';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      debugPrint('[USER_MGMT] Fetching academic users from department_table...');
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

      final deptsResponse = await _supabase.from('department_name').select('id, d_name');
      final rolesResponse = await _supabase.from('roles').select('id, Roles');

      debugPrint('[USER_MGMT] Raw DB Response Count: ${usersResponse.length}');
      for (var u in usersResponse) {
         final ui = u['user_info'];
         debugPrint(' - Found: ${ui != null ? (ui['first_name'] + " " + ui['last_name']) : "MISSING_USER_INFO"} | ID: ${u['user_id']} | Status: ${ui != null ? ui['account_status'] : "N/A"}');
      }

      if (mounted) {
        setState(() {
          _allUsers = List<Map<String, dynamic>>.from(usersResponse);
          _allDeptNames = List<Map<String, dynamic>>.from(deptsResponse);
          _roles = List<Map<String, dynamic>>.from(rolesResponse)
              .where((r) => !r['Roles'].toString().toUpperCase().contains('SAO'))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[USER_MGMT] Error fetching data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    List<Map<String, dynamic>> filtered = _allUsers.where((user) {
      final ui = user['user_info'];
      if (ui == null) return false;
      
      final roleName = user['role_data']?['Roles'] ?? 'Unknown';
      if (_selectedRoleFilter != 'All' && roleName != _selectedRoleFilter) return false;
      
      if (_searchQuery.isNotEmpty) {
        final fullName = '${ui['first_name']} ${ui['last_name']}'.toLowerCase();
        final uniId = ui['university_id'].toString().toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!fullName.contains(query) && !uniId.contains(query)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sortBy == 'Newest') {
        return b['id'].toString().compareTo(a['id'].toString());
      } else {
        return a['id'].toString().compareTo(b['id'].toString());
      }
    });

    return filtered;
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final ui = user['user_info'];
    final String currentStatus = ui['account_status'];
    final String newStatus = currentStatus == 'approved' ? 'disabled' : 'approved';
    
    try {
      await _supabase.functions.invoke('admin-accept-user', body: {
        'targetUserId': user['user_id'],
        'status': newStatus,
      });
      _fetchData();
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

  // ── User Details Modal ────────────────────────────────────────
  Future<void> _showUserDetailsModal(Map<String, dynamic> user) async {
    final ui = user['user_info'];
    final userId = user['user_id'];
    final roleName = user['role_data']?['Roles'] ?? '';
    final deptName = user['dept_data']?['d_name'] ?? 'No Dept';
    final fullName = '${ui['first_name']} ${ui['last_name']}';
    final isDeptHead = roleName.toUpperCase().contains('DEPARTMENT');

    List<Map<String, dynamic>> subjects = [];
    Map<String, dynamic>? overallScore;
    Map<String, dynamic>? deptSummary;

    try {
      final settings = await _supabase.from('system_settings').select('current_term_id').limit(1).maybeSingle();
      final termId = settings?['current_term_id'];

      if (isDeptHead) {
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
            // Sum their scores from overall_total_survey
            final rows = await _supabase
                .from('overall_total_survey')
                .select('overall_mean, total_responses')
                .eq('term_id', termId)
                .filter('instructor_id', 'in', instrIds);
            int total = 0; double sum = 0;
            for (final r in (rows as List)) {
              total += (r['total_responses'] as int? ?? 0);
              sum += (r['overall_mean'] as num? ?? 0).toDouble();
            }
            deptSummary = {
              'instructorCount': instrIds.length,
              'avgScore': (rows).isEmpty ? 0.0 : sum / (rows).length,
              'totalResponses': total,
            };
          }
        }
      } else {
        if (termId != null) {
          subjects = List<Map<String, dynamic>>.from(await _supabase.from('subjects')
              .select('subject_code, subject_name, section').eq('instructor_id', userId).eq('term_id', termId));
        }
        overallScore = await _supabase.from('overall_total_survey')
            .select('overall_mean, management_mean, performance_mean, total_responses')
            .eq('instructor_id', userId).eq('term_id', termId ?? '').maybeSingle();
      }
    } catch (e) { debugPrint('UserDetailsModal error: $e'); }

    if (!mounted) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Row(children: [
              CircleAvatar(radius: 26, backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                  child: Text((ui['first_name'] as String)[0], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                Text(roleName, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                Text(deptName, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
              ])),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: isDeptHead ? _buildDeptModal(deptSummary, deptName) : _buildInstructorModal(overallScore, subjects),
          )),
        ]),
      ),
    );
  }

  Widget _buildDeptModal(Map<String, dynamic>? s, String name) {
    if (s == null) return const Center(child: Text('No department data.', style: TextStyle(color: AppColors.textSecondary)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Department Summary — $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _infoTile('Avg Score', (s['avgScore'] as double).toStringAsFixed(2), AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(child: _infoTile('Instructors', '${s['instructorCount']}', Colors.teal)),
        const SizedBox(width: 10),
        Expanded(child: _infoTile('Responses', '${s['totalResponses']}', AppColors.success)),
      ]),
    ]);
  }

  Widget _buildInstructorModal(Map<String, dynamic>? overall, List<Map<String, dynamic>> subjects) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (overall != null) ...[
        const Text('Score Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _infoTile('Overall', (overall['overall_mean'] as num?)?.toStringAsFixed(2) ?? '-', AppColors.primary)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile('Management', (overall['management_mean'] as num?)?.toStringAsFixed(2) ?? '-', Colors.teal)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile('Performance', (overall['performance_mean'] as num?)?.toStringAsFixed(2) ?? '-', AppColors.success)),
        ]),
        const SizedBox(height: 6),
        Text('${overall['total_responses'] ?? 0} responses this term', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 20),
      ],
      Text('Subjects This Term (${subjects.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
      const SizedBox(height: 12),
      if (subjects.isEmpty) const Text('No subjects assigned.', style: TextStyle(color: AppColors.textSecondary))
      else ...subjects.map((s) => Card(
        color: AppColors.surface, margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: const Icon(Icons.menu_book, color: AppColors.primary, size: 20),
          title: Text('${s['subject_code']} — ${s['subject_name']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 13)),
          subtitle: (s['section'] != null && (s['section'] as String).isNotEmpty)
              ? Text('Section ${s['section']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)) : null,
        ),
      )),
    ]);
  }

  Widget _infoTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
      ]),
    );
  }

  void _showAddUserDialog() {
    TextEditingController firstController = TextEditingController();
    TextEditingController lastController = TextEditingController();
    TextEditingController emailController = TextEditingController();
    TextEditingController idController = TextEditingController();
    TextEditingController codeController = TextEditingController();
    int? selectedRoleId = _roles.isNotEmpty ? _roles.first['id'] : null;
    int? selectedDeptId = _allDeptNames.isNotEmpty ? _allDeptNames.first['id'] : null;
    bool needsCode = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(needsCode ? 'Verify Authorization' : 'Add Academic Personnel', 
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 12),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(controller: idController, decoration: const InputDecoration(labelText: 'University ID')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedRoleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _roles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedDeptId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: _allDeptNames.map((d) => DropdownMenuItem<int>(value: d['id'], child: Text(d['d_name']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedDeptId = val!),
                  ),
                ] else ...[
                  const Text('Creating a Department Head requires authorization.', textAlign: TextAlign.center),
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
                // Validate fields first
                final fn = firstController.text.trim();
                final ln = lastController.text.trim();
                final em = emailController.text.trim();
                final id = idController.text.trim();
                if (fn.isEmpty || ln.isEmpty || em.isEmpty || id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all required fields'), backgroundColor: Colors.red));
                  return;
                }
                if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(em)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email address'), backgroundColor: Colors.red));
                  return;
                }
                if (id.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('University ID must be at least 4 characters'), backgroundColor: Colors.red));
                  return;
                }
                final role = _roles.firstWhere((r) => r['id'] == selectedRoleId);
                final roleName = role['Roles'];

                if (roleName == 'DEPARTMENT_HEAD' && !needsCode) {
                   final currentUser = _supabase.auth.currentUser;
                   setDialogState(() => isSaving = true);
                   try {
                     await _supabase.functions.invoke(
                       'send-admin-code',
                       body: {'email': currentUser?.email},
                       headers: {
                         'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                         'apikey': Env.supabaseAnonKey,
                       },
                     );
                     setDialogState(() { needsCode = true; isSaving = false; });
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification code sent to ${currentUser?.email}')));
                     return;
                   } catch (e) {
                     setDialogState(() => isSaving = false);
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
                     return;
                   }
                }

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
                      'verificationCode': codeController.text.trim(),
                    },
                    headers: {
                      'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                      'apikey': Env.supabaseAnonKey,
                    },
                  );

                  if (response.status == 200) {
                    _fetchData();
                    if (mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Personnel created!'), backgroundColor: AppColors.success));
                  } else {
                    throw response.data['error'] ?? 'Server error';
                  }
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error));
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

  void _showEditUserDialog(Map<String, dynamic> user) {
    final ui = user['user_info'];
    TextEditingController firstController = TextEditingController(text: ui['first_name']);
    TextEditingController lastController = TextEditingController(text: ui['last_name']);
    TextEditingController codeController = TextEditingController();
    int selectedRoleId = user['roles'];
    int selectedDeptId = user['Department_name_ID'];
    bool needsCode = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(needsCode ? 'Verify Authorization' : 'Edit Academic Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!needsCode) ...[
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedRoleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _roles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedDeptId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: _allDeptNames.map((d) => DropdownMenuItem<int>(value: d['id'], child: Text(d['d_name']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedDeptId = val!),
                  ),
                ] else ...[
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
                final role = _roles.firstWhere((r) => r['id'] == selectedRoleId);
                final roleName = role['Roles'];
                final bool isUpgradingToHead = roleName == 'DEPARTMENT_HEAD' && user['role_data']?['Roles'] != 'DEPARTMENT_HEAD';

                if (isUpgradingToHead && !needsCode) {
                   final currentUser = _supabase.auth.currentUser;
                   setDialogState(() => isSaving = true);
                   try {
                     await _supabase.functions.invoke('send-admin-code', body: {'email': currentUser?.email});
                     setDialogState(() { needsCode = true; isSaving = false; });
                     return;
                   } catch (e) {
                     setDialogState(() => isSaving = false);
                     return;
                   }
                }

                setDialogState(() => isSaving = true);
                try {
                  await _supabase.functions.invoke('admin-update-role', body: {
                    'targetUserId': user['user_id'],
                    'firstName': firstController.text.trim(),
                    'lastName': lastController.text.trim(),
                    'roleId': selectedRoleId,
                    'roleName': roleName,
                    'verificationCode': codeController.text.trim(),
                    'isAcademic': true
                  });
                  _fetchData();
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.error));
                }
              },
              child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter & Sort', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: ['Newest', 'Oldest'].map((s) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(s),
                        selected: _sortBy == s,
                        onSelected: (val) { if(val) { setModalState(() => _sortBy = s); setState((){}); } },
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text('Filter By Role', style: TextStyle(fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    children: ['All', ..._roles.map((r) => r['Roles'])].map((r) => ChoiceChip(
                      label: Text(r),
                      selected: _selectedRoleFilter == r,
                      onSelected: (val) { if(val) { setModalState(() => _selectedRoleFilter = r); setState((){}); } },
                    )).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Academic User Management', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: AppColors.primary),
            onPressed: _showAddUserDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: 'Search Name or ID...',
                            prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.filter_list, color: AppColors.primary),
                        onPressed: _showFilterBottomSheet,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: users.isEmpty
                      ? const Center(child: Text('No academic users found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final ui = user['user_info'];
                            final isActive = ui['account_status'] == 'approved';

                            return Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                onTap: () => _showUserDetailsModal(user),
                                leading: CircleAvatar(
                                  backgroundColor: isActive ? AppColors.primary.withValues(alpha: 0.1) : AppColors.borderHairline,
                                  child: Text(ui['first_name'][0], style: TextStyle(color: isActive ? AppColors.primary : AppColors.textSecondary)),
                                ),
                                title: Text('${ui['first_name']} ${ui['last_name']}', style: TextStyle(fontWeight: FontWeight.bold, decoration: isActive ? null : TextDecoration.lineThrough)),
                                subtitle: Text('${ui['university_id']} • ${user['role_data']?['Roles'] ?? 'N/A'}\n${user['dept_data']?['d_name'] ?? 'No Dept'}'),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == 'edit') _showEditUserDialog(user);
                                    if (val == 'status') _toggleUserStatus(user);
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Profile')])),
                                    PopupMenuItem(value: 'status', child: Row(children: [Icon(isActive ? Icons.block : Icons.check_circle, size: 18), SizedBox(width: 8), Text(isActive ? 'Disable' : 'Approve')])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
