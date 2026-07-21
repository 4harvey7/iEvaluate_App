// lib/gatherer/failed_scans_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'failed_scan_detail_screen.dart';

class FailedScansScreen extends StatefulWidget {
  final String userId;
  const FailedScansScreen({super.key, required this.userId});

  /// Call this from outside to get the pending count for the drawer badge.
  static Future<int> getPendingCount(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('failed_scan_queue')
          .select('id')
          .eq('status', 'pending')
          .eq('sao_staff_id', userId);
      return (response as List).length;
    } catch (_) {
      return 0;
    }
  }

  @override
  State<FailedScansScreen> createState() => _FailedScansScreenState();
}

class _FailedScansScreenState extends State<FailedScansScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _failedScans = [];

  @override
  void initState() {
    super.initState();
    _fetchFailedScans();
  }

  Future<void> _fetchFailedScans() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('failed_scan_queue')
          .select()
          .eq('status', 'pending')
          .eq('sao_staff_id', widget.userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _failedScans = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching failed scans: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return 'Unknown date';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  String _failReason(Map<String, dynamic> scan) {
    final tableFound = scan['table_found'];
    final gridSource = scan['grid_source'];
    if (tableFound == false) return 'Table/corners not detected';
    if (gridSource == 'fallback') return 'Grid detection failed';
    return 'Detection issue';
  }

  Color _failColor(Map<String, dynamic> scan) {
    if (scan['table_found'] == false) return AppColors.error;
    return AppColors.warning;
  }

  IconData _failIcon(Map<String, dynamic> scan) {
    if (scan['table_found'] == false) return Icons.crop_free;
    return Icons.grid_off_rounded;
  }

  void _openDetail(Map<String, dynamic> scan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FailedScanDetailScreen(scan: scan),
      ),
    );
    // Refresh list after returning from detail (user may have validated/discarded)
    _fetchFailedScans();
  }

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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: AppColors.error, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Failed Scans',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scans where the OMR/OCR couldn\'t detect the table or page corners. '
                  'Open each to manually correct the data.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),

          // ── Stats bar ────────────────────────────────────────────────
          if (!_isLoading && _failedScans.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
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
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _failedScans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: AppColors.success.withValues(alpha: 0.5),
                                size: 80),
                            const SizedBox(height: 16),
                            const Text(
                              'No failed scans!',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'All scans were processed successfully.',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _fetchFailedScans,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _failedScans.length,
                          itemBuilder: (context, index) {
                            final scan = _failedScans[index];
                            final partial =
                                (scan['partial_data'] is Map ? Map<String, dynamic>.from(scan['partial_data'] as Map) : {});
                            final failColor = _failColor(scan);
                            final failIcon = _failIcon(scan);
                            final reason = _failReason(scan);
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
                                    color: failColor.withValues(alpha: 0.25),
                                    width: 1.5),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _openDetail(scan),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      // Fail icon
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
                                      // Info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Task ID + reason chip
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    scan['task_id']
                                                            ?.toString() ??
                                                        'Unknown',
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
                                            // Instructor (partial OCR)
                                            if (instructor.isNotEmpty)
                                              Text(
                                                'Instructor: $instructor',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textSecondary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            // Student ID
                                            if (studentId.isNotEmpty)
                                              Text(
                                                'Student ID: $studentId',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textSecondary),
                                              ),
                                            // Date
                                            Text(
                                              _formatDate(
                                                  scan['created_at']?.toString()),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textTertiary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
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
