// lib/sao_admin/admin_dashboard.dart
// The big boss screen. This is where admin feel very important.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/config/env.dart';
import '../core/services/system_settings_service.dart';
import '../core/navigation/main_scaffold.dart';
import 'user_management_screen.dart';

import '../widgets/safe_button.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';


// This widget is the throne of the admin. Very holy. Dili ta puwede diri if not admin.
class AdminDashboardScreen extends StatefulWidget {
  final String userId;
  const AdminDashboardScreen({super.key, required this.userId});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E1608), AppColors.textPrimary],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textInverted,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textInverted),
        // Hamburger opens the outer MainScaffold drawer (not the inner Scaffold).
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textInverted),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Dashboard',
          style: TextStyle(
            color: AppColors.textInverted,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
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
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Espresso hero header with warm glow ──────────────────
              Entrance(
                index: 0,
                child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E1608), AppColors.textPrimary],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -70,
                      right: -50,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.35),
                              AppColors.primary.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'System Overview', // the header of the whole situation
                            style: TextStyle(
                              color: AppColors.textInverted,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Everything across iEvaluate, at a glance.',
                            style: TextStyle(
                              color: AppColors.textInvertedDim,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

              // ── System Status Row ────────────────────────────────────
              // tap this to manually re-check if servers are alive or resting in peace
              Entrance(
                index: 1,
                child: Pressable(
                child: GestureDetector(
                onTap: _checkingStatus ? null : _checkSystemStatus, // disabled while checking
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
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
                        Text('tap to refresh', style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ),
              ),
              ),
              const SizedBox(height: 16),

              // ── Metric Cards ─────────────────────────────────────────
              // two big number cards to make admin feel in control
              Row(
                children: [
                  Expanded(child: Entrance(index: 2, child: _buildMetricCard('Total Users', '$_totalUsersCount', Icons.people, AppColors.primaryText))),
                  const SizedBox(width: 16),
                  Expanded(child: Entrance(index: 3, child: _buildMetricCard(
                    'Files Scanned',
                    '$_filesScannedCount',
                    Icons.document_scanner_outlined,
                    AppColors.success,
                    sub: 'this term', // only counts current term, dili all-time
                  ))),
                ],
              ),
              const SizedBox(height: 32),


              // ── Pending Approvals ─────────────────────────────────────
              // list of people who registered but still waiting for admin's blessing
              Entrance(
                index: 4,
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Pending Account Approvals', // people in the waiting room
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Pressable(
                    child: TextButton(
                    onPressed: () {
                      // go to the full user management page to see everyone
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                    },
                    child: const Text('View All',
                        style: TextStyle(
                            color: AppColors.primaryText,
                            fontWeight: FontWeight.w700)),
                  ),
                  )
                ],
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.how_to_reg_rounded,
                    color: AppColors.primaryText, size: 34),
              ),
              const SizedBox(height: 14),
              const Text("No pending approvals.",
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text("New sign-ups will appear here for review.",
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
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
        return Entrance(
          index: index.clamp(0, 8),
          child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryTint,
              child: Text(firstName.isNotEmpty ? firstName[0] : '?', // first letter of name as avatar
                  style: const TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.bold)),
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
      debugPrint('[DASHBOARD] Approval/Rejection Error: $e'); // log raw error for debugging
      if (mounted) {
        // show a friendly message — dili ta expose raw exception to the admin UI
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed. Please try again.'), backgroundColor: AppColors.error),
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
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24), // the icon on top
          ),
          const SizedBox(height: 14),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5), overflow: TextOverflow.ellipsis), // the big number
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis), // the label below
          if (sub != null)
            Text(sub, style: TextStyle(color: iconColor.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis), // optional small label
        ],
      ),
    );
  }

  // _buildDrawer() and _buildDrawerItem() removed — drawer is now managed by
  // MainScaffold via role_nav_config.dart. Do not re-add here.
}