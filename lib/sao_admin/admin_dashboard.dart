// lib/sao_admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/config/env.dart';
import '../core/services/auth_service.dart';
import '../core/services/system_settings_service.dart';
import 'user_management_screen.dart';
import '../login_screen.dart';
import 'personnel_management_screen.dart';
import 'performance_analysis_screen.dart';
import 'live_system_metrics_screen.dart';
import 'system_audit_screen.dart';
import 'sao_admin_settings.dart';
import 'manage_subjects_screen.dart';
import 'manage_departments_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String userId;
  const AdminDashboardScreen({super.key, required this.userId});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();
  final _settingsService = SystemSettingsService();

  bool _isPendingLoading = true;
  List<Map<String, dynamic>> _livePendingApprovals = [];
  int _totalUsersCount = 0;
  int _filesScannedCount = 0;
  String _adminName = 'Admin';
  String? _currentTermId;

  // System status
  bool _n8nOnline = false;
  bool _supabaseOnline = false;
  bool _checkingStatus = false;

  static String get _n8nHealthUrl => Env.n8nHealthUrl;

  @override
  void initState() {
    super.initState();
    _fetchAdminProfile();
    _fetchTermThenData();
    _checkSystemStatus();
  }

  Future<void> _fetchAdminProfile() async {
    try {
      final user = await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', widget.userId)
          .maybeSingle();
      if (user != null && mounted) {
        setState(() => _adminName = '${user['first_name']} ${user['last_name']}');
      }
    } catch (e) {
      debugPrint('Error fetching admin profile: $e');
    }
  }

  Future<void> _fetchTermThenData() async {
    try {
      final settings = await _settingsService.getSettings();
      if (mounted) setState(() => _currentTermId = settings.termId);
    } catch (_) {}
    await _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isPendingLoading = true);
    try {
      final pendingResponse = await _supabase
          .from('user_info')
          .select('''
            id, first_name, last_name, account_status,
            dept_join:department_table!user_id (
              dept_name_join:department_name!Department_name_ID ( d_name )
            ),
            sao_join:Sao_users!user_id (
              role_join:roles!role_id ( Roles )
            )
          ''')
          .eq('account_status', 'pending');

      final countRes = await _supabase
          .from('user_info')
          .select('id')
          .count(CountOption.exact);

      // Files scanned this term
      var fileQuery = _supabase.from('raw_GoogleSheet_data_result').select('id');
      if (_currentTermId != null) {
        fileQuery = fileQuery.eq('term_id', _currentTermId!);
      }
      final fileRes = await fileQuery;

      if (mounted) {
        setState(() {
          _livePendingApprovals = List<Map<String, dynamic>>.from(pendingResponse);
          _totalUsersCount = countRes.count;
          _filesScannedCount = (fileRes as List).length;
          _isPendingLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DASHBOARD] Fetch Error: $e');
      if (mounted) setState(() => _isPendingLoading = false);
    }
  }

  Future<void> _checkSystemStatus() async {
    if (_checkingStatus) return;
    setState(() => _checkingStatus = true);
    try {
      // Check n8n
      final n8nRes = await http
          .get(Uri.parse(_n8nHealthUrl))
          .timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _n8nOnline = n8nRes.statusCode >= 200 && n8nRes.statusCode < 300);
    } catch (_) {
      if (mounted) setState(() => _n8nOnline = false);
    }

    try {
      // Check Supabase with a lightweight ping
      await _supabase.from('system_settings').select('id').limit(1);
      if (mounted) setState(() => _supabaseOnline = true);
    } catch (_) {
      if (mounted) setState(() => _supabaseOnline = false);
    }

    if (mounted) setState(() => _checkingStatus = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text(
          'SAO-Admin Command Center',
          style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () {
              _fetchDashboardData();
              _checkSystemStatus();
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchDashboardData();
          await _checkSystemStatus();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'System Overview',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // ── System Status Row ────────────────────────────────────
              GestureDetector(
                onTap: _checkingStatus ? null : _checkSystemStatus,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderHairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _statusDot(_n8nOnline, 'n8n')),
                      const SizedBox(width: 12),
                      Expanded(child: _statusDot(_supabaseOnline, 'Supabase')),
                      const SizedBox(width: 8),
                      if (_checkingStatus)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      else
                        Text('tap to refresh', style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Metric Cards ─────────────────────────────────────────
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Total Users', '$_totalUsersCount', Icons.people, AppColors.primary)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard(
                    'Files Scanned',
                    '$_filesScannedCount',
                    Icons.document_scanner_outlined,
                    Colors.teal,
                    sub: 'this term',
                  )),
                ],
              ),
              const SizedBox(height: 32),

              // ── Pending Approvals ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Pending Account Approvals',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                    },
                    child: const Text('View All', style: TextStyle(color: AppColors.primary)),
                  )
                ],
              ),
              const SizedBox(height: 12),
              _isPendingLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildPendingList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusDot(bool online, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: online ? AppColors.success : AppColors.error),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '$label ${online ? "✓" : "✗"}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: online ? AppColors.success : AppColors.error,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingList() {
    if (_livePendingApprovals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text("No pending approvals.", style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _livePendingApprovals.length,
      itemBuilder: (context, index) {
        final user = _livePendingApprovals[index];
        final firstName = user['first_name'] ?? 'Unknown';
        final lastName = user['last_name'] ?? '';
        final fullName = '$firstName $lastName';

        String subDetail = 'Pending Verification';
        final deptData = user['dept_join'] as List?;
        final saoData = user['sao_join'] as List?;

        if (deptData != null && deptData.isNotEmpty) {
          final deptObj = deptData[0]['dept_name_join'];
          subDetail = (deptObj is List)
              ? (deptObj.isNotEmpty ? deptObj[0]['d_name'] : 'Academic Dept')
              : (deptObj?['d_name'] ?? 'Academic Dept');
        } else if (saoData != null && saoData.isNotEmpty) {
          final roleObj = saoData[0]['role_join'];
          subDetail = (roleObj is List)
              ? (roleObj.isNotEmpty ? roleObj[0]['Roles'] : 'SAO Staff')
              : (roleObj?['Roles'] ?? 'SAO Staff');
        }

        return Card(
          color: AppColors.surface,
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppColors.background,
              child: Text(firstName.isNotEmpty ? firstName[0] : '?',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ),
            title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            subtitle: Text(subDetail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            trailing: Wrap(
              spacing: -8,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: AppColors.success),
                  onPressed: () => _handleApproval(user['id'], fullName, true),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: AppColors.error),
                  onPressed: () => _handleApproval(user['id'], fullName, false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleApproval(String userId, String name, bool approved) async {
    try {
      if (approved) {
        await _supabase.functions.invoke('admin-accept-user', body: {'targetUserId': userId});
      } else {
        await _supabase.from('user_info').update({'account_status': 'rejected'}).eq('id', userId);
      }
      final status = approved ? 'approved' : 'rejected';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$name has been $status"),
              backgroundColor: approved ? AppColors.success : AppColors.error),
        );
        _fetchDashboardData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color iconColor, {String? sub}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          if (sub != null)
            Text(sub, style: TextStyle(color: iconColor.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.admin_panel_settings, color: AppColors.primary, size: 48),
                const SizedBox(height: 12),
                Text(_adminName, style: const TextStyle(color: AppColors.surface, fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Highest Access Level', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              ],
            ),
          ),
          _buildDrawerItem(context, Icons.dashboard, 'Dashboard', true, onTap: () => Navigator.pop(context)),
          _buildDrawerItem(context, Icons.group, 'User Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
          }),
          _buildDrawerItem(context, Icons.book_rounded, 'Subject Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageSubjectsScreen()));
          }),
          _buildDrawerItem(context, Icons.domain, 'Department Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageDepartmentsScreen()));
          }),
          _buildDrawerItem(context, Icons.manage_accounts, 'Personnel Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonnelManagementScreen()));
          }),
          _buildDrawerItem(context, Icons.analytics, 'Performance Analysis', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceAnalysisScreen()));
          }),
          _buildDrawerItem(context, Icons.admin_panel_settings_rounded, 'Live System Metrics', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveSystemMetricsScreen()));
          }),
          _buildDrawerItem(context, Icons.security, 'Security Audit Logs', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemAuditScreen()));
          }),
          _buildDrawerItem(context, Icons.settings, 'System Settings', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SaoAdminSettings()));
          }),
          _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
            await _authService.signOut();
            if (mounted) {
              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
            }
          }),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected,
      {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary)),
      title: Text(title,
          style: TextStyle(
            color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          )),
      selected: isSelected,
      onTap: onTap,
    );
  }
}