import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'failed_scan_detail_screen.dart';
import '../widgets/apple_ui.dart';

class DataValidationScreen extends StatefulWidget {
  final String userId;
  const DataValidationScreen({super.key, required this.userId});

  @override
  State<DataValidationScreen> createState() => _DataValidationScreenState();
}

class _DataValidationScreenState extends State<DataValidationScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _combinedItems = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final flaggedFuture = _supabase
          .from('sast_all_raw_data_survey')
          .select()
          .isFilter('instructor_ID', null)
          .order('created_at', ascending: false);

      final failedFuture = _supabase
          .from('failed_scan_queue')
          .select()
          .eq('status', 'pending')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);

      final results = await Future.wait([flaggedFuture, failedFuture]);

      final flagged = List<Map<String, dynamic>>.from(results[0]);
      final failed = List<Map<String, dynamic>>.from(results[1]);

      final combined = [
        ...flagged.map((e) => {'type': 'flagged', 'data': e}),
        ...failed.map((e) => {'type': 'failed', 'data': e}),
      ];

      combined.sort((a, b) {
        final aData = a['data'] as Map<String, dynamic>;
        final bData = b['data'] as Map<String, dynamic>;
        
        final dateA = DateTime.tryParse(
                aData['created_at']?.toString() ??
                    aData['submitted_date']?.toString() ??
                    '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(
                bData['created_at']?.toString() ??
                    bData['submitted_date']?.toString() ??
                    '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        setState(() {
          _combinedItems = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching validation data: $e');
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

  void _openFailedDetail(Map<String, dynamic> scan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FailedScanDetailScreen(scan: scan),
      ),
    );
    _fetchData();
  }

  void _showValidationSheet(Map<String, dynamic> form) {
    final instructorCtrl =
        TextEditingController(text: form['instructor'] ?? '');
    final remarksCtrl =
        TextEditingController(text: form['Remarks_and_Suggestions'] ?? '');

    final Map<String, TextEditingController> scoreCtrl = {};
    for (int i = 1; i <= 10; i++) {
      scoreCtrl['m$i'] =
          TextEditingController(text: form['m$i']?.toString() ?? '');
      scoreCtrl['p$i'] =
          TextEditingController(text: form['p$i']?.toString() ?? '');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, _) => AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.90,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Edit Record',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                    IconButton(
                        icon: const Icon(Icons.close,
                            color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Instructor & Remarks',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _sheetField('Instructor Name (Raw)', instructorCtrl),
                        const SizedBox(height: 12),
                        TextField(
                          controller: remarksCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Remarks & Suggestions',
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Management Scores (1–5)',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _scoreGrid(scoreCtrl, 'm'),
                        const SizedBox(height: 24),
                        const Text('Performance Scores (1–5)',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _scoreGrid(scoreCtrl, 'p'),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: AppColors.error),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _handleDelete(form['id']),
                        child: const Text('Discard',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppColors.success,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _handleSave(form,
                            instructorCtrl.text, remarksCtrl.text, scoreCtrl),
                        child: const Text('Approve & Sync',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _scoreGrid(
      Map<String, TextEditingController> controllers, String prefix) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 10,
      itemBuilder: (_, i) {
        final key = '$prefix${i + 1}';
        return TextField(
          controller: controllers[key],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: key.toUpperCase(),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        );
      },
    );
  }

  Future<void> _handleSave(
      Map<String, dynamic> form,
      String instructorName,
      String remarks,
      Map<String, TextEditingController> scoreCtrl) async {
    try {
      final updates = <String, dynamic>{
        'instructor': instructorName,
        'Remarks_and_Suggestions': remarks,
      };
      for (final e in scoreCtrl.entries) {
        updates[e.key] = int.tryParse(e.value.text) ?? 0;
      }
      await _supabase
          .from('sast_all_raw_data_survey')
          .update(updates)
          .eq('id', form['id']);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Data updated and queued for processing.'),
            backgroundColor: AppColors.success));
        _fetchData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: AppColors.error));
    }
  }

  Future<void> _handleDelete(dynamic id) async {
    try {
      await _supabase
          .from('sast_all_raw_data_survey')
          .delete()
          .eq('id', id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record discarded.')));
        _fetchData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting: $e'),
          backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: ApplePageHeader(
              eyebrow: 'Validation',
              title: 'Pending Actions',
              subtitle: 'Correct flagged records and failed scans.',
            ),
          ),
          if (!_isLoading && _combinedItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${_combinedItems.length} record${_combinedItems.length == 1 ? '' : 's'} need manual correction',
                      style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const AppleLoadingState(label: 'Loading tasks…')
                : _combinedItems.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: AppleEmptyState(
                          icon: Icons.check_circle_outline,
                          title: 'No pending validation',
                          message: 'All records have been processed successfully.',
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _fetchData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _combinedItems.length,
                          itemBuilder: (context, index) {
                            final item = _combinedItems[index];
                            if (item['type'] == 'flagged') {
                              return _buildFlaggedCard(item['data'] as Map<String, dynamic>);
                            } else {
                              return _buildFailedCard(item['data'] as Map<String, dynamic>);
                            }
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlaggedCard(Map<String, dynamic> form) {
    return Card(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: AppColors.warning.withValues(alpha: 0.35), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showValidationSheet(form),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_search,
                    color: AppColors.warning, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            form['instructor'] ?? 'Unknown Instructor',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Missing ID',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Student ID: ${form['student_id'] ?? 'N/A'}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatDate(form['created_at']?.toString() ?? form['submitted_date']?.toString()),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedCard(Map<String, dynamic> scan) {
    final partial = (scan['partial_data'] is Map
        ? Map<String, dynamic>.from(scan['partial_data'] as Map)
        : {});
    final failColor = _failColor(scan);
    final failIcon = _failIcon(scan);
    final reason = _failReason(scan);
    final studentId = partial['student_id']?.toString() ?? '';
    final instructor = partial['instructor']?.toString() ?? '';

    return Card(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: failColor.withValues(alpha: 0.25), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFailedDetail(scan),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: failColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(failIcon, color: failColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            scan['task_id']?.toString() ?? 'Unknown',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: failColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            reason,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: failColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (instructor.isNotEmpty)
                      Text(
                        'Instructor: $instructor',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (studentId.isNotEmpty)
                      Text(
                        'Student ID: $studentId',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      _formatDate(scan['created_at']?.toString()),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
