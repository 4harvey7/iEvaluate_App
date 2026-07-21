// lib/sao_admin/personnel_management_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env.dart';
import '../core/services/auth_service.dart';
import '../theme/app_colors.dart';

class PersonnelManagementScreen extends StatefulWidget {
  const PersonnelManagementScreen({super.key});

  @override
  State<PersonnelManagementScreen> createState() => _PersonnelManagementScreenState();
}

class _PersonnelManagementScreenState extends State<PersonnelManagementScreen> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();
  
  List<Map<String, dynamic>> _allPersonnel = [];
  List<Map<String, dynamic>> _saoRoles = [];
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
      final currentUser = _supabase.auth.currentUser;
      debugPrint('[PERSONNEL_MGMT] Logged in as: ${currentUser?.email} (ID: ${currentUser?.id})');

      // 1. Fetch Users from Sao_users (SAO Admin/Staff)
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
      final rolesResponse = await _supabase.from('roles').select('id, Roles');

      if (mounted) {
        setState(() {
          _allPersonnel = List<Map<String, dynamic>>.from(personnelResponse);
          _saoRoles = List<Map<String, dynamic>>.from(rolesResponse)
              .where((r) => r['Roles'].toString().toUpperCase().startsWith('SAO'))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[PERSONNEL_MGMT] Fetch Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredPersonnel {
    List<Map<String, dynamic>> filtered = _allPersonnel.where((person) {
      final ui = person['user_info'];
      if (ui == null) return false;
      
      final roleName = person['role_data']?['Roles'] ?? 'Unknown';
      
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
      final uiA = a['user_info'];
      final uiB = b['user_info'];
      if (uiA == null || uiB == null) return 0;
      
      final isActiveA = uiA['account_status'] == 'approved';
      final isActiveB = uiB['account_status'] == 'approved';

      // 1. Blocked/Disabled users first
      if (isActiveA != isActiveB) {
        return isActiveA ? 1 : -1;
      }

      if (_sortBy == 'Newest') {
        return b['id'].toString().compareTo(a['id'].toString());
      } else {
        return a['id'].toString().compareTo(b['id'].toString());
      }
    });

    return filtered;
  }

  Future<void> _toggleStatus(Map<String, dynamic> person) async {
    final ui = person['user_info'];
    final String currentStatus = ui['account_status'];
    final String newStatus = currentStatus == 'approved' ? 'disabled' : 'approved';
    
    try {
      await _supabase.functions.invoke('admin-accept-user', body: {
        'targetUserId': person['user_id'],
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

  // ── Personnel Details Modal ───────────────────────────────────
  Future<void> _showPersonnelDetailsModal(Map<String, dynamic> person) async {
    final ui = person['user_info'];
    final userId = person['user_id'];
    final roleName = person['role_data']?['Roles'] ?? '';
    final fullName = '${ui['first_name']} ${ui['last_name']}';
    final isAdmin = roleName.toUpperCase().contains('ADMIN');

    int totalScans = 0, todayScans = 0, termScans = 0;
    String lastUpload = '';

    if (!isAdmin) {
      try {
        final settings = await _supabase.from('system_settings').select('current_term_id').limit(1).maybeSingle();
        final termId = settings?['current_term_id'];
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();

        // All-time scans by this SAO staff
        final all = await _supabase
            .from('raw_GoogleSheet_data_result')
            .select('created_at')
            .eq('sao_staff_id', userId);
        totalScans = (all as List).length;

        // This term's scans
        var termQ = _supabase
            .from('raw_GoogleSheet_data_result')
            .select('created_at')
            .eq('sao_staff_id', userId);
        if (termId != null) termQ = termQ.eq('term_id', termId);
        final termRows = await termQ;
        termScans = (termRows as List).length;
        todayScans = termRows.where((r) => (r['created_at'] as String? ?? '').compareTo(startOfDay) >= 0).length;

        if (all.isNotEmpty) {
          final sorted = all.map((r) => r['created_at'] as String).toList()..sort((a, b) => b.compareTo(a));
          lastUpload = sorted.first;
        }
      } catch (e) { debugPrint('PersonnelModal error: $e'); }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
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
                Text(ui['email'] ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
              ])),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: isAdmin
                ? _buildAdminProfile(ui)
                : _buildGathererStats(totalScans, termScans, todayScans, lastUpload),
          )),
        ]),
      ),
    );
  }

  Widget _buildAdminProfile(Map<String, dynamic> ui) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Account Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
      const SizedBox(height: 16),
      _profileRow(Icons.badge_outlined, 'University ID', ui['university_id']?.toString() ?? '-'),
      _profileRow(Icons.email_outlined, 'Email', ui['email'] ?? '-'),
      _profileRow(Icons.check_circle_outline, 'Status', ui['account_status'] ?? '-'),
    ]);
  }

  Widget _buildGathererStats(int total, int term, int today, String lastUpload) {
    String lastStr = 'No uploads yet';
    if (lastUpload.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastUpload).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) lastStr = '${diff.inMinutes}m ago';
        else if (diff.inHours < 24) lastStr = '${diff.inHours}h ago';
        else lastStr = '${diff.inDays}d ago';
      } catch (_) {}
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Scan Statistics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _statBox('Today', '$today', AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(child: _statBox('This Term', '$term', Colors.teal)),
        const SizedBox(width: 10),
        Expanded(child: _statBox('All Time', '$total', AppColors.success)),
      ]),
      const SizedBox(height: 16),
      _profileRow(Icons.cloud_upload_outlined, 'Last Upload', lastStr),
    ]);
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 12),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Expanded(child: Text(value, style: const TextStyle(color: AppColors.textSecondary))),
      ]),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]),
    );
  }

  void _showEditPersonnelDialog(Map<String, dynamic> person) {
    final ui = person['user_info'];
    TextEditingController firstController = TextEditingController(text: ui['first_name']);
    TextEditingController lastController = TextEditingController(text: ui['last_name']);
    TextEditingController codeController = TextEditingController();
    int selectedRoleId = person['role_id'];
    bool needsCode = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
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
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedRoleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _saoRoles.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleId = val!),
                  ),
                ] else ...[
                  const Text('Upgrading a user to Admin requires authorization.', textAlign: TextAlign.center),
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
              onPressed: () async {
                final selectedRole = _saoRoles.firstWhere((r) => r['id'] == selectedRoleId);
                final bool isUpgradingToAdmin = selectedRole['Roles'] == 'SAO_ADMIN' && 
                    person['role_data']?['Roles'] != 'SAO_ADMIN';

                if (isUpgradingToAdmin && !needsCode) {
                   final currentUser = _supabase.auth.currentUser;
                   
                   setDialogState(() => isSaving = true);
                   try {
                     // 1. Request the code from the server (Server generates and emails it)
                     await _supabase.functions.invoke(
                       'send-admin-code',
                       body: {
                         'email': currentUser?.email,
                         // We no longer send the code from here!
                       },
                       headers: {
                         'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                         'apikey': Env.supabaseAnonKey,
                       },
                     );
                     
                     setDialogState(() {
                       needsCode = true;
                       isSaving = false;
                     });
                     
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Verification code sent to ${currentUser?.email}'))
                     );
                     return;
                   } catch (e) {
                     setDialogState(() => isSaving = false);
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Failed to send verification: $e'), backgroundColor: Colors.red)
                     );
                     return;
                   }
                }

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
                      'isAcademic': false,
                      'verificationCode': codeController.text.trim(), // Server verifies this!
                    },
                    headers: {
                      'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                      'apikey': Env.supabaseAnonKey,
                    },
                  );

                  if (response.status == 200) {
                    _fetchData();
                    if (mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Personnel updated successfully!'), backgroundColor: AppColors.success)
                    );
                  } else {
                    final errorMsg = response.data is Map ? (response.data['error'] ?? 'Server error') : 'Server error';
                    throw errorMsg;
                  }
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.error)
                  );
                }
              },
              child: isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(needsCode ? 'Verify & Save' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPersonnelDialog() {
    TextEditingController firstController = TextEditingController();
    TextEditingController lastController = TextEditingController();
    TextEditingController emailController = TextEditingController();
    TextEditingController idController = TextEditingController();
    TextEditingController codeController = TextEditingController();
    String? selectedRoleName = _saoRoles.isNotEmpty ? _saoRoles.first['Roles'] : null;
    bool needsCode = false;
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
                  TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 12),
                  TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 12),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(controller: idController, decoration: const InputDecoration(labelText: 'University ID')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRoleName,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: _saoRoles.map((r) => DropdownMenuItem<String>(value: r['Roles'], child: Text(r['Roles']))).toList(),
                    onChanged: (val) => setDialogState(() => selectedRoleName = val),
                  ),
                ] else ...[
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
                if (selectedRoleName == null) return;
                // Validate required fields
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

                if (!needsCode && selectedRoleName == 'SAO_ADMIN') {
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
                    'admin-create-user',
                    body: {
                      'firstName': firstController.text.trim(),
                      'lastName': lastController.text.trim(),
                      'email': emailController.text.trim(),
                      'universityId': idController.text.trim(),
                      'roleName': selectedRoleName!,
                      'address': 'SAO Office',
                      'verificationCode': codeController.text.trim(),
                    },
                    headers: {
                      'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}',
                      'apikey': Env.supabaseAnonKey,
                    },
                  );

                  if (response.status == 200 || response.status == 201) {
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
                    children: ['All', ..._saoRoles.map((r) => r['Roles'])].map((r) => ChoiceChip(
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
    final personnel = _filteredPersonnel;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('SAO Personnel Management', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: AppColors.primary),
            onPressed: _showAddPersonnelDialog,
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
                  child: personnel.isEmpty
                      ? const Center(child: Text('No SAO personnel found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: personnel.length,
                          itemBuilder: (context, index) {
                            final person = personnel[index];
                            final ui = person['user_info'];
                            final isActive = ui['account_status'] == 'approved';
                            final isTargetAdmin = person['role_data']?['Roles'] == 'SAO_ADMIN';

                            return Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                onTap: () => _showPersonnelDetailsModal(person),
                                leading: CircleAvatar(
                                  backgroundColor: isActive ? AppColors.primary.withValues(alpha: 0.1) : AppColors.borderHairline,
                                  child: Text(ui['first_name'][0], style: TextStyle(color: isActive ? AppColors.primary : AppColors.textSecondary)),
                                ),
                                title: Text('${ui['first_name']} ${ui['last_name']}', style: TextStyle(fontWeight: FontWeight.bold, decoration: isActive ? null : TextDecoration.lineThrough)),
                                subtitle: Text('${ui['university_id']} • ${person['role_data']?['Roles'] ?? 'N/A'}'),
                                trailing: isTargetAdmin 
                                  ? const Icon(Icons.shield, color: AppColors.textSecondary, size: 20) // Admins cannot be edited by other admins
                                  : PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == 'edit') _showEditPersonnelDialog(person);
                                    if (val == 'status') _toggleStatus(person);
                                    if (val == 'reset') {
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
              ],
            ),
    );
  }
}
