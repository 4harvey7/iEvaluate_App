// lib/sao_admin/admin_dashboard.dart
// The big boss screen. This is where admin feel very important.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../core/config/env.dart';
import '../core/services/system_settings_service.dart';
import '../core/navigation/main_scaffold.dart';
import 'user_management_screen.dart';

import '../widgets/safe_button.dart';
import '../widgets/apple_ui.dart';
import '../core/services/term_aware_state.dart';


// This widget is the throne of the admin. Very holy. Dili ta puwede diri if not admin.
class AdminDashboardScreen extends StatefulWidget {
  final String userId;
  const AdminDashboardScreen({super.key, required this.userId});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TermAwareState<AdminDashboardScreen> {
  final _supabase = Supabase.instance.client; // our connection to the almighty database
  final _settingsService = SystemSettingsService(); // fetches system settings, importente kaayo


  bool _isPendingLoading = true; // true means still fetching, bahala na wait
  List<Map<String, dynamic>> _livePendingApprovals = []; // poor souls waiting for admin approval
  int _totalUsersCount = 0; // how many people exist in the system
  int _filesScannedCount = 0; // how many files got scanned this term, very busy

  String? _currentTermId; // which semester we currently living in


  // System status — is everything alive or is it dead already
  bool _n8nOnline = false; // n8n workflow engine, alive or nah
  bool _supabaseOnline = false; // the database, without this nothing work
  bool _checkingStatus = false; // true when we currently pinging the servers

  // the URL we ping to check if n8n is breathing
  static String get _n8nHealthUrl => Env.n8nHealthUrl;

  Future<void> _loadCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('admin_dashboard_${widget.userId}');
      if (cached != null) {
        final data = jsonDecode(cached);
        if (mounted) {
          setState(() {
            _currentTermId = data['termId'] ?? _currentTermId;
            _totalUsersCount = data['totalUsersCount'] ?? _totalUsersCount;
            _filesScannedCount = data['filesScannedCount'] ?? _filesScannedCount;
            if (data['livePendingApprovals'] != null) {
              _livePendingApprovals = List<Map<String, dynamic>>.from(data['livePendingApprovals'].map((x) => Map<String, dynamic>.from(x)));
            }
          });
          debugPrint('[ADMIN] ⚡ Loaded cached dashboard instantly.');
        }
      }
    } catch (e) {
      debugPrint('[ADMIN] Failed to load cache: $e');
    }
  }

  // initState — the very first thing that runs when admin open this screen
  @override
  void initState() {
    super.initState();
    _loadCachedDashboard(); // Load stale data instantly!
    _fetchAdminProfile(); // get the admin's name so dashboard not say just "Admin"
    _fetchTermThenData(); // fetch current term first, then fetch all the dashboard data
    _checkSystemStatus(); // ping the servers to see if they still alive
  }

  // Reload when the SAO office switches the active term, instead of
  // showing the previous term's figures until this screen is rebuilt.
  @override
  void onTermChanged() {
    _fetchTermThenData();
  }

  // go to DB and get admin's first and last name — dili ta wala ngalan
  Future<void> _fetchAdminProfile() async {
    try {
      // Profile fetch kept in case _adminName is re-used in future dashboard UI.
      // _adminName display moved to MainScaffold drawer header.
      await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', widget.userId)
          .maybeSingle();

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
            email, address, university_id, employment_status, created_at,
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
      var fileQuery = _supabase.from('sast_all_raw_data_survey').select('id');
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

        // Save to cache so the user doesn't wait next time they open the app
        try {
          final prefs = await SharedPreferences.getInstance();
          final cacheData = {
            'termId': _currentTermId,
            'totalUsersCount': _totalUsersCount,
            'filesScannedCount': _filesScannedCount,
            'livePendingApprovals': _livePendingApprovals,
          };
          await prefs.setString('admin_dashboard_${widget.userId}', jsonEncode(cacheData));
        } catch (e) {
          debugPrint('[ADMIN] Failed to save cache: $e');
        }
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
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        // Hamburger opens the outer MainScaffold drawer (not the inner Scaffold).
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Dashboard',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
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
      // drawer removed — MainScaffold now owns the side drawer for all roles
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
              const ApplePageHeader(
                eyebrow: 'SAO Administration',
                title: 'System Overview',
                subtitle: 'Operations, evaluation progress, and account activity.',
              ),
              const SizedBox(height: 22),

              // ── System Status Row ────────────────────────────────────
              // tap this to manually re-check if servers are alive or resting in peace
              AppleSurface(
                onTap: _checkingStatus ? null : _checkSystemStatus, // disabled while checking
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(child: _statusDot(_n8nOnline, 'Automation')), // n8n status indicator
                    const SizedBox(width: 12),
                    Expanded(child: _statusDot(_supabaseOnline, 'Database')), // supabase status
                    if (_checkingStatus)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textTertiary),
                  ],
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
              AppleSectionHeader(
                title: 'Pending Approvals',
                subtitle: 'Review new accounts before granting access.',
                action: TextButton(
                    onPressed: () {
                      // go to the full user management page to see everyone
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                    },
                    child: const Text('View All'),
                  ),
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
      return const AppleEmptyState(
        icon: Icons.verified_user_outlined,
        title: 'All caught up',
        message: 'There are no accounts waiting for approval.',
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
        // tap the card to see full details
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppleSurface(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _showPendingUserDetails(context, user, fullName, subDetail),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryTint,
                    child: Text(firstName.isNotEmpty ? firstName[0] : '?',
                        style: AppTextStyles.titleSmall.copyWith(color: AppColors.primary)),
                  ),
                  title: Text(fullName, style: AppTextStyles.titleSmall, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subDetail, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('Tap to view full details',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
                    ],
                  ),
                  trailing: Wrap(
                    spacing: -8,
                    children: [
                      SafeIconButton(
                        icon: const Icon(Icons.check_circle, color: AppColors.success),
                        onPressed: () => _handleApproval(user['id'], fullName, true),
                      ),
                      SafeIconButton(
                        icon: const Icon(Icons.cancel, color: AppColors.error),
                        onPressed: () => _handleApproval(user['id'], fullName, false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Shows the full account details of a pending user in a bottom sheet
  void _showPendingUserDetails(BuildContext context, Map<String, dynamic> user, String fullName, String department) {
    final email = user['email'] ?? 'Not provided';
    final address = user['address'] ?? 'Not provided';
    final universityId = user['university_id']?.toString() ?? 'Not provided';
    final employment = user['employment_status'] ?? 'Not provided';
    final createdAt = user['created_at'] != null
        ? DateTime.tryParse(user['created_at'].toString())
        : null;
    final registeredOn = createdAt != null
        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
        : 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.solidSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Avatar + name header
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primaryTint,
                  child: Text(
                    fullName.isNotEmpty ? fullName[0] : '?',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fullName, style: AppTextStyles.titleMedium),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text('Pending Approval',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.warning)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            // Detail rows
            _detailRow(Icons.badge_outlined,        'University ID',       universityId),
            _detailRow(Icons.email_outlined,         'Email Address',       email),
            _detailRow(Icons.location_on_outlined,   'Address',             address),
            _detailRow(Icons.apartment_outlined,     'Department',          department),
            _detailRow(Icons.work_outline,           'Employment Status',   employment),
            _detailRow(Icons.calendar_today_outlined,'Registered On',       registeredOn),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel, color: AppColors.error),
                    label: const Text('Reject', style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _handleApproval(user['id'], fullName, false);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: const Text('Approve', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _handleApproval(user['id'], fullName, true);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Single detail row with icon, label and value
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

  // approve or reject a user — this is the admin's divine power right here
  Future<void> _handleApproval(String userId, String name, bool approved) async {
    try {
      if (approved) {
        // call the edge function to officially welcome them to the system
        await _supabase.functions.invoke('admin-accept-user', body: {'targetUserId': userId});
      } else {
        // Rejected — this is a NEW pending account so we DELETE it completely.
        // No evaluation data exists yet, so nothing valuable is lost.
        // Clean up ALL related rows first — order matters because of foreign keys.
        try {
          // For instructors / dept heads
          await _supabase.from('instructor_departments').delete().eq('instructor_id', userId);
        } catch (_) {}
        try {
          await _supabase.from('department_table').delete().eq('user_id', userId);
        } catch (_) {}
        try {
          // For SAO Staff — Sao_users has a FK to user_info so MUST be deleted first
          await _supabase.from('Sao_users').delete().eq('user_id', userId);
        } catch (_) {}
        // Now safe to delete the main user record
        await _supabase.from('user_info').delete().eq('id', userId);
        debugPrint('[DASHBOARD] Rejected pending account fully deleted: $userId');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved
                ? '$name has been approved'       // welcome message
                : '$name\'s request was rejected and removed'), // clear message
            backgroundColor: approved ? AppColors.success : AppColors.error,
          ),
        );
        _fetchDashboardData(); // refresh the list after decision
      }
    } catch (e) {
      debugPrint('[DASHBOARD] Approval/Rejection Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed. Please try again.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // builds a metric card with icon, big number, and optional subtitle
  // this is the "look at this big number" widget
  Widget _buildMetricCard(String title, String value, IconData icon, Color iconColor, {String? sub}) {
    return AppleMetricCard(
      label: title,
      value: value,
      icon: icon,
      color: iconColor,
      detail: sub,
    );
  }

  // _buildDrawer() and _buildDrawerItem() removed — drawer is now managed by
  // MainScaffold via role_nav_config.dart. Do not re-add here.
}
