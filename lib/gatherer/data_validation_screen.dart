// lib/gatherer/data_validation_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'failed_scans_screen.dart';

class DataValidationScreen extends StatefulWidget {
  final String userId;
  const DataValidationScreen({super.key, required this.userId});

  @override
  State<DataValidationScreen> createState() => _DataValidationScreenState();
}

class _DataValidationScreenState extends State<DataValidationScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // ── Flagged records tab ────────────────────────────────────────────────────
  bool _isLoading = true;
  List<Map<String, dynamic>> _flaggedForms = [];

  // ── Failed scans badge count ───────────────────────────────────────────────
  int _failedCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchFlaggedData();
    _loadFailedCount();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFailedCount() async {
    final count = await FailedScansScreen.getPendingCount(widget.userId);
    if (mounted) setState(() => _failedCount = count);
  }

  Future<void> _fetchFlaggedData() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('raw_GoogleSheet_data_result')
          .select()
          .isFilter('instructor_ID', null)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _flaggedForms = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching flagged data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Flagged record detail sheet ────────────────────────────────────────────

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
        builder: (ctx, _) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.90,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
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
          style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
          .from('raw_GoogleSheet_data_result')
          .update(updates)
          .eq('id', form['id']);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Data updated and queued for processing.'),
            backgroundColor: AppColors.success));
        _fetchFlaggedData();
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
          .from('raw_GoogleSheet_data_result')
          .delete()
          .eq('id', id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record discarded.')));
        _fetchFlaggedData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting: $e'),
          backgroundColor: AppColors.error));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Data Validation',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Review unlinked records and correct failed scans.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),

          // ── TabBar ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              dividerColor: AppColors.borderSubtle,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.fact_check_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('Flagged Records',
                          style: TextStyle(fontSize: 13)),
                      if (_flaggedForms.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _badge(_flaggedForms.length, AppColors.warning),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16),
                      const SizedBox(width: 6),
                      const Text('Failed Scans',
                          style: TextStyle(fontSize: 13)),
                      if (_failedCount > 0) ...[
                        const SizedBox(width: 6),
                        _badge(_failedCount, AppColors.error),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Tab content ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFlaggedTab(),
                FailedScansScreen(userId: widget.userId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── Flagged records tab ────────────────────────────────────────────────────

  Widget _buildFlaggedTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_flaggedForms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified,
                color: AppColors.success.withValues(alpha: 0.5), size: 80),
            const SizedBox(height: 16),
            const Text('No pending verifications',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('All records have been linked to an instructor.',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 12)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _fetchFlaggedData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        itemCount: _flaggedForms.length,
        itemBuilder: (_, i) {
          final form = _flaggedForms[i];
          return Card(
            color: AppColors.surface,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: AppColors.warning.withValues(alpha: 0.35),
                  width: 1.2),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_search,
                    color: AppColors.warning, size: 20),
              ),
              title: Text(
                  form['instructor'] ?? 'Unknown Instructor',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Student ID: ${form['student_id'] ?? 'N/A'}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                  Text('Date: ${form['submitted_date'] ?? 'N/A'}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.primary),
              onTap: () => _showValidationSheet(form),
            ),
          );
        },
      ),
    );
  }
}
