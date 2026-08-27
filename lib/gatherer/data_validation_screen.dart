// lib/gatherer/data_validation_screen.dart
// This screen is where we fix the messes. Two tabs:
// 1. Flagged Records — forms where the instructor ID is null (OCR couldn't match them)
// 2. Failed Scans — scans where the table/grid wasn't detected at all
// Importente kaayo this screen. Without it, bad data go to database.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'failed_scans_screen.dart';
import '../widgets/apple_ui.dart';

// StatefulWidget with two tabs — we need state for loading and tab controller
class DataValidationScreen extends StatefulWidget {
  final String userId;
  const DataValidationScreen({super.key, required this.userId});

  @override
  State<DataValidationScreen> createState() => _DataValidationScreenState();
}

// the state — has a tab controller plus two separate data lists
class _DataValidationScreenState extends State<DataValidationScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client; // our database connection
  late TabController _tabController; // controls switching between the two tabs

  // ── Flagged records tab ────────────────────────────────────────────────────
  // loading spinner flag — true while fetching from database
  bool _isLoading = true;
  // list of forms where instructor_ID is null — these need manual review
  List<Map<String, dynamic>> _flaggedForms = [];

  // ── Failed scans badge count ───────────────────────────────────────────────
  // shown as a red badge on the "Failed Scans" tab to tell user how many pending
  int _failedCount = 0;

  // initialize everything when screen open
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // 2 tabs, simple
    _fetchFlaggedData(); // load flagged records on start
    _loadFailedCount(); // load the badge count for failed scans tab
  }

  // always dispose the tab controller or flutter will complain loudly
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ask FailedScansScreen for the count of pending failed scans
  // used to show the badge number on the tab — so user know something need attention
  Future<void> _loadFailedCount() async {
    final count = await FailedScansScreen.getPendingCount(widget.userId);
    if (mounted) setState(() => _failedCount = count); // update badge
  }

  // fetch all records where instructor_ID is null — these are "flagged"
  // meaning OCR scanned the form but couldnt identify the instructor
  Future<void> _fetchFlaggedData() async {
    setState(() => _isLoading = true); // show spinner
    try {
      final response = await _supabase
          .from('sast_all_raw_data_survey')
          .select()
          .isFilter('instructor_ID', null) // only records with no instructor linked
          .order('created_at', ascending: false); // newest first

      if (mounted) {
        setState(() {
          _flaggedForms = List<Map<String, dynamic>>.from(response);
          _isLoading = false; // hide spinner
        });
      }
    } catch (e) {
      debugPrint('Error fetching flagged data: $e'); // something wrong with db query
      if (mounted) setState(() => _isLoading = false); // hide spinner even on error
    }
  }

  // ── Flagged record detail sheet ────────────────────────────────────────────

  // show a bottom sheet to edit a flagged record
  // user can fix the instructor name, remarks, and all 20 score fields (m1-m10, p1-p10)
  void _showValidationSheet(Map<String, dynamic> form) {
    // pre-fill with existing data from the record
    final instructorCtrl =
        TextEditingController(text: form['instructor'] ?? '');
    final remarksCtrl =
        TextEditingController(text: form['Remarks_and_Suggestions'] ?? '');

    // create controllers for all 20 score fields — m1 to m10 and p1 to p10
    final Map<String, TextEditingController> scoreCtrl = {};
    for (int i = 1; i <= 10; i++) {
      scoreCtrl['m$i'] =
          TextEditingController(text: form['m$i']?.toString() ?? '');
      scoreCtrl['p$i'] =
          TextEditingController(text: form['p$i']?.toString() ?? '');
    }

    // show as a bottom sheet so user can scroll and edit all fields
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // allow sheet to expand to nearly full screen
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, _) => AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom), // move up when keyboard open
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.90, // take 90% of screen height
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)), // rounded top corners
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
                        onPressed: () => Navigator.pop(ctx)), // close without saving
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
                        _sheetField('Instructor Name (Raw)', instructorCtrl), // editable instructor name
                        const SizedBox(height: 12),
                        TextField(
                          controller: remarksCtrl,
                          maxLines: 3, // multi-line for remarks
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
                        _scoreGrid(scoreCtrl, 'm'), // grid of m1-m10 inputs
                        const SizedBox(height: 24),
                        const Text('Performance Scores (1–5)',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _scoreGrid(scoreCtrl, 'p'), // grid of p1-p10 inputs
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
                        onPressed: () => _handleDelete(form['id']), // delete this record entirely
                        child: const Text('Discard',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2, // save button is bigger — more important
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

  // helper: build a single labeled text field for the bottom sheet
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

  // build a 5-column grid of score input fields
  // prefix is 'm' for management scores or 'p' for performance scores
  Widget _scoreGrid(
      Map<String, TextEditingController> controllers, String prefix) {
    return GridView.builder(
      shrinkWrap: true, // dont take more space than needed
      physics: const NeverScrollableScrollPhysics(), // disable grid's own scroll — parent handles it
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, // 5 columns = 2 rows of 5 for 10 scores
        childAspectRatio: 1.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 10, // m1-m10 or p1-p10, always 10
      itemBuilder: (_, i) {
        final key = '$prefix${i + 1}'; // e.g. 'm1', 'p5'
        return TextField(
          controller: controllers[key],
          keyboardType: TextInputType.number, // only numbers allowed
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: key.toUpperCase(), // M1, P5, etc.
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.zero, // compact — it a small grid cell
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        );
      },
    );
  }

  // save the edited record back to supabase
  // updates instructor name, remarks, and all score fields
  // then refreshes the flagged list — if instructor_ID got filled, it disappear from list
  Future<void> _handleSave(
      Map<String, dynamic> form,
      String instructorName,
      String remarks,
      Map<String, TextEditingController> scoreCtrl) async {
    try {
      // build the update map with instructor and remarks
      final updates = <String, dynamic>{
        'instructor': instructorName,
        'Remarks_and_Suggestions': remarks,
      };
      // add all score fields — parse to int, default 0 if empty or not a number
      for (final e in scoreCtrl.entries) {
        updates[e.key] = int.tryParse(e.value.text) ?? 0;
      }
      // push the update to supabase — match by row ID
      await _supabase
          .from('sast_all_raw_data_survey')
          .update(updates)
          .eq('id', form['id']);
      if (mounted) {
        Navigator.pop(context); // close the bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Data updated and queued for processing.'),
            backgroundColor: AppColors.success));
        _fetchFlaggedData(); // refresh the list — saved record may no longer be flagged
      }
    } catch (e) {
      if (!mounted) return;
      // show error — something wrong with the update, check network/db
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: AppColors.error));
    }
  }

  // permanently delete a flagged record from the database
  // user click Discard — this cannot be undone, so ayaw mag-click by mistake
  Future<void> _handleDelete(dynamic id) async {
    try {
      await _supabase
          .from('sast_all_raw_data_survey')
          .delete()
          .eq('id', id); // delete by primary key
      if (mounted) {
        Navigator.pop(context); // close the sheet
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record discarded.')));
        _fetchFlaggedData(); // refresh the list — removed record gone now
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting: $e'),
          backgroundColor: AppColors.error));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  // build the main validation screen with header + tabs + content
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── TabBar ────────────────────────────────────────────────────────
          // two tabs with badge counts — so user see at a glance how much work waiting
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
                      // show badge only if there are flagged records
                      if (_flaggedForms.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _badge(_flaggedForms.length, AppColors.warning), // orange badge
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
                      // show badge only if there are failed scans waiting
                      if (_failedCount > 0) ...[
                        const SizedBox(width: 6),
                        _badge(_failedCount, AppColors.error), // red badge — more urgent
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
                _buildFlaggedTab(), // flagged records list
                FailedScansScreen(userId: widget.userId), // failed scans list
              ],
            ),
          ),
        ],
      ),
    );
  }

  // small colored rounded badge widget — shows a count number
  // used on the tab labels to show how many items need attention
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

  // build the content of the first tab — list of flagged records
  // shows loading spinner, empty state, or the list
  Widget _buildFlaggedTab() {
    if (_isLoading) {
      // still fetching from database — show spinner
      return const AppleLoadingState(label: 'Loading flagged records…');
    }
    if (_flaggedForms.isEmpty) {
      // no flagged records — everything linked, sayang effort pero okay
      return const Padding(
        padding: EdgeInsets.all(16),
        child: AppleEmptyState(
          icon: Icons.verified_outlined,
          title: 'No pending verification',
          message: 'All records are linked to an instructor.',
        ),
      );
    }
    // has flagged records — show the list with pull-to-refresh
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _fetchFlaggedData, // pull down to refresh
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        itemCount: _flaggedForms.length,
        itemBuilder: (_, i) {
          final form = _flaggedForms[i];
          // each flagged record shown as a card with warning border
          return Card(
            color: AppColors.surface,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: AppColors.warning.withValues(alpha: 0.35), // subtle warning border
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
                    color: AppColors.warning, size: 20), // person with magnifier — searching for instructor
              ),
              title: Text(
                  form['instructor'] ?? 'Unknown Instructor', // show instructor name or fallback
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      overflow: TextOverflow.ellipsis)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Student ID: ${form['student_id'] ?? 'N/A'}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          overflow: TextOverflow.ellipsis)),
                  Text('Date: ${form['submitted_date'] ?? 'N/A'}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          overflow: TextOverflow.ellipsis)),
                ],
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.primary), // tap arrow to open detail sheet
              onTap: () => _showValidationSheet(form), // open edit sheet on tap
            ),
          );
        },
      ),
    );
  }
}
