// lib/sao_admin/system_audit_screen.dart
// The "who did what and when" screen — basically the security camera of the app
// Every suspicious action is logged here. Importente kaayo ni for accountability.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/safe_button.dart';
import '../widgets/apple_ui.dart';


class SystemAuditScreen extends StatefulWidget {
  const SystemAuditScreen({super.key});

  @override
  State<SystemAuditScreen> createState() => _SystemAuditScreenState();
}

class _SystemAuditScreenState extends State<SystemAuditScreen> {
  // our trusty supabase client — never leaves our side
  final _supabase = Supabase.instance.client;
  bool _isLoading = true; // spinning while fetching the receipts
  bool _isAscending = false; // Toggle for sorting — false means newest first (default, murag news feed)
  List<Map<String, dynamic>> _logs = []; // all the audit log entries, each is a Map of crime scene data

  @override
  void initState() {
    super.initState();
    // fetch logs as soon as screen opens — no delay, we need the evidence
    _fetchLogs();
  }

  // pulls up to 100 audit log entries from supabase
  // joins user_info so we know WHO did the action, not just some random UUID
  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true); // start spinner
    try {
      final response = await _supabase
          .from('audit_logs')
          .select('''
            *,
            user_info:user_id ( first_name, last_name, email )
          ''') // join user info — murag cross-referencing a suspect's identity
          .order('created_at', ascending: _isAscending) // sort by time based on toggle
          .limit(100); // cap at 100 — more than enough to catch someone doing bad things

      setState(() {
        _logs = List<Map<String, dynamic>>.from(response); // cast from dynamic
        _isLoading = false;
      });
    } catch (e) {
      // fetch failed — at least log it, wala choice
      debugPrint('Error fetching logs: $e');
      setState(() => _isLoading = false);
    }
  }

  // flips the sort order between oldest-first and newest-first, then refetches
  // pressing this twice brings you back to where you started, so dili mag-confuse
  Future<void> _toggleSort() async {
    setState(() {
      _isAscending = !_isAscending; // flip the flag
    });
    await _fetchLogs(); // reload with new sort order
  }

  // returns a color based on what kind of action happened
  // green for creates, yellow for updates, blue for OTP stuff, red for deletes
  // like a traffic light but for admin actions — murag color-coding ang receipts
  Color _getActionColor(String action) {
    action = action.toUpperCase(); // normalize to upper so matching works
    if (action.contains('CREATE')) return AppColors.success; // green — good, someone added something
    if (action.contains('UPDATE') || action.contains('ROLE')) return AppColors.warning; // yellow — changed something
    if (action.contains('OTP')) return AppColors.primary; // blue — identity verification stuff
    if (action.contains('DELETE') || action.contains('REJECT')) return AppColors.error; // red — uh oh
    return AppColors.textSecondary; // gray for anything else we didnt think of
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Security Audit Logs', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          // Sort Toggle Button — switches between newest/oldest first
          SafeIconButton(
            icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _isAscending ? 'Showing Oldest First' : 'Showing Newest First',
            onPressed: _toggleSort,
          ),
          // manual refresh button — for when you just KNOW something new happened
          SafeIconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLogs),
        ],
      ),
      body: _isLoading
          ? const AppleLoadingState(label: 'Loading security history…')
          : _logs.isEmpty
              ? _buildEmptyState() // no logs found — either clean system or logs got purged
              : RefreshIndicator(
                  onRefresh: _fetchLogs, // pull down to refresh, like a news feed
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final action = (log['action'] ?? 'UNKNOWN').toString().toUpperCase(); // action type, uppercased
                      final createdAt = DateTime.parse(log['created_at']).toLocal(); // convert UTC to local time
                      final userInfo = log['user_info']; // joined user data (may be null if system action)
                      // show name if user found, otherwise say "System" — bahala na kung wala
                      final userName = userInfo != null
                          ? '${userInfo['first_name']} ${userInfo['last_name']}'
                          : 'System';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        // expandable card — tap to reveal the JSON metadata inside
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: _getActionColor(action).withValues(alpha: 0.1), // tinted circle
                            child: Icon(Icons.history, color: _getActionColor(action), size: 20),
                          ),
                          title: Text(
                            action.replaceAll('_', ' '), // underscores look ugly — replace with spaces
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          // subtitle shows who did it and when — the important stuff
                          subtitle: Text(
                            'By $userName • ${DateFormat('MMM d, h:mm a').format(createdAt)}',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          // expanded section shows the raw JSON metadata for the action
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  // label for the raw JSON block below
                                  const Text('METADATA (JSON):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary)),
                                  const SizedBox(height: 8),
                                  // monospaced container showing raw metadata — looks like a terminal
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.2)),
                                    ),
                                    child: Text(
                                      log['metadata'].toString(), // raw dump of the metadata map
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textPrimary),
                                    ),
                                  ),
                                  // show admin email below JSON if it exists — extra accountability
                                  if (userInfo?['email'] != null) ...[
                                    const SizedBox(height: 12),
                                    Text('Admin Email: ${userInfo['email']}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
                                  ]
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  // shown when there are no logs at all
  // either the system is clean OR someone deleted the evidence — basin dili ta mahibaw-an
  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: AppleEmptyState(
        icon: Icons.shield_outlined,
        title: 'No security events',
        message: 'Audit activity will appear here as administrative actions occur.',
      ),
    );
  }
}
