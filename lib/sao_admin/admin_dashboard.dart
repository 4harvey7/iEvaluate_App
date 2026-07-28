// lib/sao_admin/admin_dashboard.dart
// The big boss screen. This is where admin feel very important.
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

import '../widgets/safe_button.dart';

// This widget is the throne of the admin. Very holy. Dili ta puwede diri if not admin.
class AdminDashboardScreen extends StatefulWidget {
  final String userId;
  const AdminDashboardScreen({super.key, required this.userId});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _supabase = Supabase.instance.client; // our connection to the almighty database
  final _authService = AuthService(); // handles login/logout, pray lang it works
  final _settingsService = SystemSettingsService(); // fetches system settings, importente kaayo

  bool _isPendingLoading = true; // true means still fetching, bahala na wait
  List<Map<String, dynamic>> _livePendingApprovals = []; // poor souls waiting for admin approval
  int _totalUsersCount = 0; // how many people exist in the system
  int _filesScannedCount = 0; // how many files got scanned this term, very busy

  String _adminName = 'Admin'; // default name in case DB forgot who you are
  String? _currentTermId; // which semester we currently living in

  // System status — is everything alive or is it dead already
  bool _n8nOnline = false; // n8n workflow engine, alive or nah
  bool _supabaseOnline = false; // the database, without this nothing work
  bool _checkingStatus = false; // true when we currently pinging the servers

  // the URL we ping to check if n8n is breathing
  static String get _n8nHealthUrl => Env.n8nHealthUrl;

  // initState — the very first thing that runs when admin open this screen
  @override
  void initState() {
    super.initState();
    _fetchAdminProfile(); // get the admin's name so dashboard not say just "Admin"
    _fetchTermThenData(); // fetch current term first, then fetch all the dashboard data
    _checkSystemStatus(); // ping the servers to see if they still alive
  }

  // go to DB and get admin's first and last name — dili ta wala ngalan
  Future<void> _fetchAdminProfile() async {
    try {
      final user = await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', widget.userId)
          .maybeSingle();
      if (user != null && mounted) {
        // combine the name parts, simple lang
        setState(() => _adminName = '${user['first_name']} ${user['last_name']}');
      }
    } catch (e) {
      debugPrint('Error fetching admin profile: $e'); // something went wrong, log it
    }
  }

  // first get the current term from settings, then load the rest of the data
  // order matters here or the queries be wrong — dili ta skip this
  Future<void> _fetchTermThenData() async {
    try {
      final settings = await _settingsService.getSettings();
      if (mounted) setState(() => _currentTermId = settings.termId); // store term id for later
    } catch (_) {} // if settings fail, just continue anyway, bahala na
    await _fetchDashboardData(); // now go get the actual dashboard numbers
  }

  // the big fetch — grabs pending approvals, total user count, and file scan count
  Future<void> _fetchDashboardData() async {
    setState(() => _isPendingLoading = true); // show loading spinner while we wait
    try {
      // fetch all users who are still "pending" — they want to be approved
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
          .eq('account_status', 'pending'); // only the waiting ones

      // count how many total users exist, admin need to feel powerful
      final countRes = await _supabase
          .from('user_info')
          .select('id')
          .count(CountOption.exact);

      // Files scanned this term — filter by term if available
      var fileQuery = _supabase.from('raw_GoogleSheet_data_result').select('id');
      if (_currentTermId != null) {
        fileQuery = fileQuery.eq('term_id', _currentTermId!); // only this term's scans
      }
      final fileRes = await fileQuery;

      if (mounted) {
        setState(() {
          _livePendingApprovals = List<Map<String, dynamic>>.from(pendingResponse); // save the pending list
          _totalUsersCount = countRes.count; // save user count
          _filesScannedCount = (fileRes as List).length; // save file count
          _isPendingLoading = false; // done loading, hide spinner
        });
      }
    } catch (e) {
      debugPrint('[DASHBOARD] Fetch Error: $e'); // something broke, log and move on
      if (mounted) setState(() => _isPendingLoading = false); // hide spinner even on error
    }
  }

  // ping both n8n and supabase to see if they still breathing
  // if _checkingStatus already true, someone else is pinging — ayaw double ping
  Future<void> _checkSystemStatus() async {
    if (_checkingStatus) return; // don't run two checks at the same time
    setState(() => _checkingStatus = true);
    try {
      // Check n8n — give it 5 seconds or we declare it dead
      final n8nRes = await http
          .get(Uri.parse(_n8nHealthUrl))
          .timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _n8nOnline = n8nRes.statusCode >= 200 && n8nRes.statusCode < 300);
    } catch (_) {
      if (mounted) setState(() => _n8nOnline = false); // no response = dead, simple
    }

    try {
      // Check Supabase with a lightweight ping — just select one row, very gentle
      await _supabase.from('system_settings').select('id').limit(1);
      if (mounted) setState(() => _supabaseOnline = true); // alive!
    } catch (_) {
      if (mounted) setState(() => _supabaseOnline = false); // dead. panic later.
    }

    if (mounted) setState(() => _checkingStatus = false); // done pinging, reset flag
  }

  // the main build — constructs the whole dashboard screen that admin stare at all day
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text(
          'SAO-Admin Command Center', // fancy name for "admin home page"
          style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold),
        ),
        actions: [
          SafeIconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () async {
              // refresh everything — dashboard data AND server status
              await _fetchDashboardData();
              await _checkSystemStatus();
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context), // the side menu with all the navigation options
      body: RefreshIndicator(
        onRefresh: () async {
          // pull down to refresh, like refreshing the soul
          await _fetchDashboardData();
          await _checkSystemStatus();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // always scrollable even if content is short
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'System Overview', // the header of the whole situation
                style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // ── System Status Row ────────────────────────────────────
              // tap this to manually re-check if servers are alive or resting in peace
              GestureDetector(
                onTap: _checkingStatus ? null : _checkSystemStatus, // disabled while checking
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderHairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _statusDot(_n8nOnline, 'n8n')), // n8n status indicator
                      const SizedBox(width: 12),
                      Expanded(child: _statusDot(_supabaseOnline, 'Supabase')), // supabase status
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
              // two big number cards to make admin feel in control
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Total Users', '$_totalUsersCount', Icons.people, AppColors.primary)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard(
                    'Files Scanned',
                    '$_filesScannedCount',
                    Icons.document_scanner_outlined,
                    Colors.teal,
                    sub: 'this term', // only counts current term, dili all-time
                  )),
                ],
              ),
              const SizedBox(height: 32),


              // ── Pending Approvals ─────────────────────────────────────
              // list of people who registered but still waiting for admin's blessing
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Pending Account Approvals', // people in the waiting room
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      // go to the full user management page to see everyone
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                    },
                    child: const Text('View All', style: TextStyle(color: AppColors.primary)),
                  )
                ],
              ),
              const SizedBox(height: 12),
              // show spinner while loading, show list when done
              _isPendingLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildPendingList(),
            ],
          ),
        ),
      ),
    );
  }

  // builds a colored dot with label — green = alive, red = ded
  Widget _statusDot(bool online, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: online ? AppColors.success : AppColors.error), // the actual dot
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '$label ${online ? "✓" : "✗"}', // checkmark if alive, X if not
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: online ? AppColors.success : AppColors.error, // green or red, no in-between
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // build the list of pending approval cards — if empty, tell admin to relax
  Widget _buildPendingList() {
    if (_livePendingApprovals.isEmpty) {
      // wala pending, everyone been approved or nobody signed up
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text("No pending approvals.", style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    // build a card for each person waiting for approval
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // dili ta scroll inside scroll
      itemCount: _livePendingApprovals.length,
      itemBuilder: (context, index) {
        final user = _livePendingApprovals[index];
        final firstName = user['first_name'] ?? 'Unknown'; // fallback if name is gone
        final lastName = user['last_name'] ?? '';
        final fullName = '$firstName $lastName';

        // figure out if they're academic (show dept) or SAO staff (show role)
        String subDetail = 'Pending Verification'; // default text if no dept/role found
        final deptData = user['dept_join'] as List?;
        final saoData = user['sao_join'] as List?;

        if (deptData != null && deptData.isNotEmpty) {
          // academic user — show their department name
          final deptObj = deptData[0]['dept_name_join'];
          subDetail = (deptObj is List)
              ? (deptObj.isNotEmpty ? deptObj[0]['d_name'] : 'Academic Dept')
              : (deptObj?['d_name'] ?? 'Academic Dept');
        } else if (saoData != null && saoData.isNotEmpty) {
          // SAO staff — show their role instead
          final roleObj = saoData[0]['role_join'];
          subDetail = (roleObj is List)
              ? (roleObj.isNotEmpty ? roleObj[0]['Roles'] : 'SAO Staff')
              : (roleObj?['Roles'] ?? 'SAO Staff');
        }

        // each pending user gets a card with approve/reject buttons
        return Card(
          color: AppColors.surface,
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppColors.background,
              child: Text(firstName.isNotEmpty ? firstName[0] : '?', // first letter of name as avatar
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ),
            title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
            subtitle: Text(subDetail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis),
            trailing: Wrap(
              spacing: -8,
              children: [
                SafeIconButton(
                  icon: const Icon(Icons.check_circle, color: AppColors.success),
                  onPressed: () => _handleApproval(user['id'], fullName, true), // approve this person
                ),
                SafeIconButton(
                  icon: const Icon(Icons.cancel, color: AppColors.error),
                  onPressed: () => _handleApproval(user['id'], fullName, false), // reject this person, sorry
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // approve or reject a user — this is the admin's divine power right here
  Future<void> _handleApproval(String userId, String name, bool approved) async {
    try {
      if (approved) {
        // call the edge function to officially welcome them to the system
        await _supabase.functions.invoke('admin-accept-user', body: {'targetUserId': userId});
      } else {
        // rejected — just update their status directly, no ceremony needed
        await _supabase.from('user_info').update({'account_status': 'rejected'}).eq('id', userId);
      }
      final status = approved ? 'approved' : 'rejected'; // the verdict
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$name has been $status"), // announce the decision
              backgroundColor: approved ? AppColors.success : AppColors.error),
        );
        _fetchDashboardData(); // refresh the list after decision
      }
    } catch (e) {
      if (mounted) {
        // something went wrong, show the error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // builds a metric card with icon, big number, and optional subtitle
  // this is the "look at this big number" widget
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
          Icon(icon, color: iconColor, size: 28), // the icon on top
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis), // the big number
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis), // the label below
          if (sub != null)
            Text(sub, style: TextStyle(color: iconColor.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis), // optional small label
        ],
      ),
    );
  }

  // build the side drawer — the navigation menu, like a secret panel
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // the fancy header at the top of the drawer, shows admin name and rank
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.admin_panel_settings, color: AppColors.primary, size: 48), // big admin icon, very cool
                const SizedBox(height: 12),
                Text(_adminName, style: const TextStyle(color: AppColors.surface, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis), // the admin's name in big text
                const Text('Highest Access Level', style: TextStyle(color: AppColors.textSecondary, fontSize: 14), overflow: TextOverflow.ellipsis), // flex on everyone
              ],
            ),
          ),
          // Dashboard item — tapping it just closes the drawer
          _buildDrawerItem(context, Icons.dashboard, 'Dashboard', true, onTap: () => Navigator.pop(context)),
          // go to user management — for managing academic users
          _buildDrawerItem(context, Icons.group, 'User Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
          }),
          // go to subject management — add/edit subjects per term
          _buildDrawerItem(context, Icons.book_rounded, 'Subject Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageSubjectsScreen()));
          }),
          // go to department management — wala choice, someone has to manage departments
          _buildDrawerItem(context, Icons.domain, 'Department Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageDepartmentsScreen()));
          }),
          // go to personnel management — for SAO staff, not the profs
          _buildDrawerItem(context, Icons.manage_accounts, 'Personnel Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonnelManagementScreen()));
          }),
          // go to performance analysis — the screen full of charts and numbers
          _buildDrawerItem(context, Icons.analytics, 'Performance Analysis', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceAnalysisScreen()));
          }),
          // live metrics — for when you want to watch the system breathe in real time
          _buildDrawerItem(context, Icons.admin_panel_settings_rounded, 'Live System Metrics', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveSystemMetricsScreen()));
          }),
          // security audit — who did what and when, wala makalusot
          _buildDrawerItem(context, Icons.security, 'Security Audit Logs', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemAuditScreen()));
          }),
          // settings — system configuration, importente kaayo dili puwede ma-ignore
          _buildDrawerItem(context, Icons.settings, 'System Settings', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SaoAdminSettings()));
          }),
          // log out — bye bye admin, thanks for your service
          _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
            await _authService.signOut(); // actually sign out from supabase
            if (mounted) {
              // kick them all the way back to login, dili ta stay here
              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
            }
          }),
        ],
      ),
    );
  }

  // builds one row in the drawer — icon, label, and optional red badge for counts
  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected,
      {bool isLogout = false, int badgeCount = 0, VoidCallback? onTap}) {
    // color is red for logout, primary for selected, else normal dark color
    final color = isLogout
        ? AppColors.error
        : (isSelected ? AppColors.primary : AppColors.textPrimary);
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: color),
          if (badgeCount > 0)
            // little red badge number on top of the icon, like notifications
            Positioned(
              top: -4, right: -6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: AppColors.error, shape: BoxShape.circle),
                child: Text('$badgeCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      title: Text(title,
          style: TextStyle(
            color: color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // bold if currently selected
          )),
      selected: isSelected,
      onTap: onTap,
    );
  }
}