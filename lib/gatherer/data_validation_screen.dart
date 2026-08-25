// lib/gatherer/data_validation_screen.dart
// This screen is where we fix the messes. Two tabs:
// 1. Flagged Records — forms where the instructor ID is null (OCR couldn't match them)
// 2. Failed Scans — scans where the table/grid wasn't detected at all
// Importente kaayo this screen. Without it, bad data go to database.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'failed_scans_screen.dart';

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
                // grab handle — signals the sheet is draggable
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Edit Record',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
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
                        const Text('INSTRUCTOR & REMARKS',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
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
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('MANAGEMENT SCORES (1–5)',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        _scoreGrid(scoreCtrl, 'm'), // grid of m1-m10 inputs
                        const SizedBox(height: 24),
                        const Text('PERFORMANCE SCORES (1–5)',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
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
                      // destructive — soft error tint pill, no hairline border
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          onPressed: () => _handleDelete(form['id']), // delete this record entirely
                          child: const Text('Discard',
                              style: TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2, // save button is bigger — more important
                      // gradient CTA with warm glow — the primary action
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.primaryDeep],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              foregroundColor: AppColors.textPrimary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          onPressed: () => _handleSave(form,
                              instructorCtrl.text, remarksCtrl.text, scoreCtrl),
                          child: const Text('Approve & Sync',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2)),
                        ),
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
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
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
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5)),
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                splashBorderRadius: BorderRadius.circular(12),
                labelColor: AppColors.primaryText,
                unselectedLabelColor: AppColors.textSecondary,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        '$count',
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ── Flagged records tab ────────────────────────────────────────────────────

  // build the content of the first tab — list of flagged records
  // shows loading spinner, empty state, or the list
  Widget _buildFlaggedTab() {
    if (_isLoading) {
      // still fetching from database — show spinner
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_flaggedForms.isEmpty) {
      // no flagged records — everything linked, sayang effort pero okay
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // soft icon in a tinted circle — friendly empty state
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_outlined,
                  color: AppColors.primaryText, size: 40),
            ),
            const SizedBox(height: 18),
            const Text('No pending verifications',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3)),
            const SizedBox(height: 6),
            const Text('All records have been linked to an instructor.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }
    // has flagged records — show the list with pull-to-refresh
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _fetchFlaggedData, // pull down to refresh
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: _flaggedForms.length,
        itemBuilder: (_, i) {
          final form = _flaggedForms[i];
          // each flagged record shown as a soft floating card — no hairline borders
          return Container(
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
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showValidationSheet(form), // open edit sheet on tap
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    // warning icon — soft tinted circle
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_search,
                          color: AppColors.warning, size: 22), // person with magnifier — searching for instructor
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              form['instructor'] ?? 'Unknown Instructor', // show instructor name or fallback
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                  overflow: TextOverflow.ellipsis)),
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
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.primaryText), // tap arrow to open detail sheet
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
