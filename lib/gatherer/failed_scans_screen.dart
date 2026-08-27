// lib/gatherer/failed_scans_screen.dart
// The hall of shame — scans where OCR completely gave up.
// Table not detected, corners not found, grid broke.
// User must open each one and manually type the data. Bahala na, pero importente.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'failed_scan_detail_screen.dart';
import '../widgets/apple_ui.dart';

// shows a list of failed scans that need manual correction
class FailedScansScreen extends StatefulWidget {
  final String userId;
  const FailedScansScreen({super.key, required this.userId});

  /// Call this from outside to get the pending count for the drawer badge.
  /// Static method so we can call it without creating the widget first.
  /// Returns 0 on error because we rather show nothing than crash.
  static Future<int> getPendingCount(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('failed_scan_queue')
          .select('id')
          .eq('status', 'pending') // only pending ones, not discarded or corrected
          .eq('user_id', userId); // only this user's failed scans
      return (response as List).length;
    } catch (_) {
      return 0; // something fail, return 0 — badge wont show, thats fine
    }
  }

  @override
  State<FailedScansScreen> createState() => _FailedScansScreenState();
}

// the state — loading flag and the list of failed scans
class _FailedScansScreenState extends State<FailedScansScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true; // show spinner while fetching
  List<Map<String, dynamic>> _failedScans = []; // the actual list data

  // fetch failed scans when screen open
  @override
  void initState() {
    super.initState();
    _fetchFailedScans();
  }

  // fetch all failed scans for this user that are still 'pending' (not yet corrected/discarded)
  // ordered newest first — most recent problem at top
  Future<void> _fetchFailedScans() async {
    setState(() => _isLoading = true); // show loading spinner
    try {
      final response = await _supabase
          .from('failed_scan_queue')
          .select()
          .eq('status', 'pending') // only pending — already corrected ones not shown
          .eq('user_id', widget.userId) // only this user's scans
          .order('created_at', ascending: false); // newest problem first

      if (mounted) {
        setState(() {
          _failedScans = List<Map<String, dynamic>>.from(response);
          _isLoading = false; // hide spinner
        });
      }
    } catch (e) {
      debugPrint('Error fetching failed scans: $e');
      if (mounted) setState(() => _isLoading = false); // hide spinner even on error
    }
  }

  // format an ISO date string into a human-readable format
  // e.g. "2025-07-27T10:30:00Z" → "Jul 27, 2025  10:30"
  String _formatDate(String? isoDate) {
    if (isoDate == null) return 'Unknown date'; // no date, say so
    try {
      final dt = DateTime.parse(isoDate).toLocal(); // convert to local timezone
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      // format like "Jul 27, 2025  10:30" — readable but compact
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate; // parse fail, just show raw date string bahala na
    }
  }

  // determine a human-readable failure reason from the scan data
  // used in the little chip on each list item
  String _failReason(Map<String, dynamic> scan) {
    final tableFound = scan['table_found'];
    final gridSource = scan['grid_source'];
    if (tableFound == false) return 'Table/corners not detected'; // worst case — nothing found
    if (gridSource == 'fallback') return 'Grid detection failed'; // table found but grid broke
    return 'Detection issue'; // something else wrong, generic fallback
  }

  // color for the failure badge — red for total failure, orange for partial
  Color _failColor(Map<String, dynamic> scan) {
    if (scan['table_found'] == false) return AppColors.error; // red — worse failure
    return AppColors.warning; // orange — partial failure
  }

  // icon for the failure badge — different icon for different failure types
  IconData _failIcon(Map<String, dynamic> scan) {
    if (scan['table_found'] == false) return Icons.crop_free; // frame icon — no table detected
    return Icons.grid_off_rounded; // grid-off icon — grid detection failed
  }

  // navigate to the detail screen for a specific failed scan
  // when user return from detail (after correcting or discarding), refresh the list
  void _openDetail(Map<String, dynamic> scan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FailedScanDetailScreen(scan: scan),
      ),
    );
    // Refresh list after returning from detail (user may have validated/discarded)
    _fetchFailedScans(); // re-fetch so corrected/discarded items disappear
  }

  // build the whole screen — header, stats bar, and the list
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ApplePageHeader(
                  eyebrow: 'Recovery Queue',
                  title: 'Failed Scans',
                  subtitle: 'Correct forms where the table, grid, or page corners were not detected.',
                ),
              ],
            ),
          ),

          // ── Stats bar ────────────────────────────────────────────────
          // show how many scans need correction — only when there are some
          if (!_isLoading && _failedScans.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08), // subtle red background
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    // pluralize "scan" vs "scans" properly
                    Text(
                      '${_failedScans.length} scan${_failedScans.length == 1 ? '' : 's'} need manual correction',
                      style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // ── List ─────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                // loading: show centered spinner
                ? const AppleLoadingState(label: 'Loading failed scans…')
                : _failedScans.isEmpty
                    // empty: show happy empty state — all scan processed, good job
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: AppleEmptyState(
                          icon: Icons.check_circle_outline,
                          title: 'No failed scans',
                          message: 'Every scan has been processed successfully.',
                        ),
                      )
                    // has items: show list with pull-to-refresh
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _fetchFailedScans, // pull down to reload
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _failedScans.length,
                          itemBuilder: (context, index) {
                            final scan = _failedScans[index];
                            // partial_data is the OCR's best guess — may have some correct fields
                            final partial =
                                (scan['partial_data'] is Map ? Map<String, dynamic>.from(scan['partial_data'] as Map) : {});
                            final failColor = _failColor(scan); // red or orange
                            final failIcon = _failIcon(scan);
                            final reason = _failReason(scan); // short description of failure
                            final studentId =
                                partial['student_id']?.toString() ?? '';
                            final instructor =
                                partial['instructor']?.toString() ?? '';

                            return Card(
                              color: AppColors.surface,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                    color: failColor.withValues(alpha: 0.25), // colored border = severity indicator
                                    width: 1.5),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _openDetail(scan), // tap to open correction screen
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      // Fail icon — square container with colored icon
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: failColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(failIcon,
                                            color: failColor, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      // Info — task ID, failure reason chip, instructor, student ID, date
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Task ID + reason chip in a row
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    scan['task_id']
                                                            ?.toString() ??
                                                        'Unknown', // the SCAN-12345 ID
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                        color:
                                                            AppColors.textPrimary),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // failure reason chip — small colored label
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: failColor.withValues(
                                                        alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    reason,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: failColor),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            // Instructor (partial OCR) — may be wrong or partial name
                                            if (instructor.isNotEmpty)
                                              Text(
                                                'Instructor: $instructor',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textSecondary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            // Student ID from partial OCR data
                                            if (studentId.isNotEmpty)
                                              Text(
                                                'Student ID: $studentId',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textSecondary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            // Date — when was this scan submitted
                                            Text(
                                              _formatDate(
                                                  scan['created_at']?.toString()),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textTertiary),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // chevron arrow — tells user this is tappable
                                      const Icon(Icons.chevron_right,
                                          color: AppColors.primary),
                                    ],
                                  ),
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
