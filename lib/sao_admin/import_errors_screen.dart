// lib/sao_admin/import_errors_screen.dart
// The "broken records hall of shame" — all the entries that failed to match
// Shows errors grouped by type: All, Instructor Not Found, Subject Not Found
// Someone has to fix these. Wala choice. That someone is the admin.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import 'import_error_detail_screen.dart';


class ImportErrorsScreen extends StatefulWidget {
  /// When pushed from a context that does NOT use MainScaffold (e.g. the gatherer),
  /// set this to true so the AppBar shows a back arrow instead of the hamburger menu.
  final bool showBackButton;
  final VoidCallback? onMenuPressed;

  const ImportErrorsScreen({
    super.key, 
    this.showBackButton = false,
    this.onMenuPressed,
  });

  @override
  State<ImportErrorsScreen> createState() => _ImportErrorsScreenState();
}

class _ImportErrorsScreenState extends State<ImportErrorsScreen>
    with SingleTickerProviderStateMixin {
  // supabase client — the source of all pending problems
  final _supabase = Supabase.instance.client;
  late TabController _tabController; // controls the 3 tabs: All, Instructor, Subject

  List<Map<String, dynamic>> _allErrors = []; // all unresolved import errors
  bool _isLoading = true; // true while fetching the list of shame

  @override
  void initState() {
    super.initState();
    // 3 tabs — All errors, Instructor errors, Subject errors
    _tabController = TabController(length: 3, vsync: this);
    _fetch(); // grab errors right away, dili ta mag-pahuway muna
  }

  @override
  void dispose() {
    _tabController.dispose(); // clean up the tab controller — memory leaks are bad
    super.dispose();
  }

  // fetches all pending import errors from supabase
  // "pending" means nobody has fixed or discarded them yet — they still need attention
  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final results = await _supabase
          .from('import_errors')
          .select('*') // grab everything — we need all the details
          .eq('status', 'pending') // only unresolved ones — ignore the fixed ones
          .order('created_at', ascending: false); // newest first — fresh problems on top
      if (mounted) {
        setState(() {
          _allErrors = List<Map<String, dynamic>>.from(results as List); // cast from dynamic
          _isLoading = false;
        });
      }
    } catch (e) {
      // fetch failed — log it and stop the spinner
      debugPrint('[ImportErrors] Fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // filtered list of only instructor-not-found errors
  // these happen when the scanned/sheet name doesnt match any instructor in the DB
  List<Map<String, dynamic>> get _instructorErrors =>
      _allErrors.where((e) => e['error_type'] == 'instructor_not_found').toList();

  // filtered list of only subject-not-found errors
  // these happen when the subject code/name doesnt match anything in the subjects table
  List<Map<String, dynamic>> get _subjectErrors =>
      _allErrors.where((e) => e['error_type'] == 'subject_not_found').toList();

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        leading: widget.showBackButton
            ? const BackButton(color: AppColors.surface)
            : IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppColors.surface),
                tooltip: 'Open menu',
                onPressed: widget.onMenuPressed ?? () => MainScaffold.drawerKey.currentState?.openDrawer(),
              ),
        // title shows count of pending errors — a number that should always be going down
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import Errors',
              style: TextStyle(
                  color: AppColors.surface,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              '${_allErrors.length} pending resolution', // how many still need fixing
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
            ),
          ],
        ),
        actions: [
          // refresh button — pull latest errors manually
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _fetch,
            tooltip: 'Refresh',
          ),
        ],
        // three tabs at the bottom of the appbar — each shows filtered errors
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.surface, // selected tab label color
          unselectedLabelColor: const Color(0xFF888888), // dimmed for unselected
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: [
            Tab(text: 'All (${_allErrors.length})'), // all errors combined
            Tab(text: 'Instructor (${_instructorErrors.length})'), // instructor mismatch count
            Tab(text: 'Subject (${_subjectErrors.length})'), // subject mismatch count
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary)) // loading spinner
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_allErrors),       // all tab content
                _buildList(_instructorErrors), // instructor tab content
                _buildList(_subjectErrors),    // subject tab content
              ],
            ),
    );
  }

  // ── List ───────────────────────────────────────────────────────────────────

  // builds a scrollable list of error cards, or an empty state if nothing's there
  // also wraps with RefreshIndicator so pull-to-refresh works — importente kaayo
  Widget _buildList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      // no errors in this category — green checkmark, the good ending
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                color: AppColors.success, size: 60), // big green check — all good
            const SizedBox(height: 14),
            const Text('No pending errors',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('All imports matched successfully.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetch, // pull to refresh — fetch fresh errors from DB
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), // bottom padding so last card visible
        itemCount: items.length,
        itemBuilder: (_, i) => _buildErrorCard(items[i]), // build one card per error
      ),
    );
  }

  // ── Error card ─────────────────────────────────────────────────────────────

  // builds a single error card showing what went wrong and who/what was affected
  // tappable and has a "Fix This" button that opens the detail/correction screen
  Widget _buildErrorCard(Map<String, dynamic> error) {
    final isInstructor = error['error_type'] == 'instructor_not_found'; // true = instructor problem
    final isSheet = error['source'] == 'google_sheet'; // true = from sheet, false = from scan
    final errorColor = isInstructor ? AppColors.error : AppColors.warning; // red for instructor, yellow for subject
    final createdAt =
        DateTime.tryParse(error['created_at']?.toString() ?? '');
    final timeAgo =
        createdAt != null ? _timeAgo(createdAt) : '—'; // how long ago this error showed up

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        // subtle colored border based on error type — visual cue for severity
        border: Border.all(
            color: errorColor.withValues(alpha: 0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(error), // tap anywhere on the card to open detail screen
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: badges + time ──────────────────────────────
                // shows error type badge, source badge (sheet/scan), and how long ago
                Row(
                  children: [
                    _badge(
                      isInstructor
                          ? 'Instructor Not Found'
                          : 'Subject Not Found', // which thing is missing
                      errorColor,
                    ),
                    const SizedBox(width: 6),
                    _badge(
                      isSheet ? '📊 Sheet' : '📷 Scan', // where the error came from
                      isSheet
                          ? const Color(0xFF1565C0) // blue for sheet
                          : const Color(0xFF6A1B9A), // purple for scan
                    ),
                    const Spacer(),
                    // time ago — so you know how long this error been waiting
                    Text(timeAgo,
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Data rows ───────────────────────────────────────────
                // shows the raw data values that failed to match — the actual evidence
                _infoRow(Icons.person_outline, 'Instructor',
                    error['raw_instructor_name'] ?? '—'), // name the AI/importer tried
                const SizedBox(height: 5),
                _infoRow(Icons.book_outlined, 'Subject',
                    error['raw_subject_name'] ?? '—'), // subject it tried to match
                const SizedBox(height: 5),
                _infoRow(Icons.badge_outlined, 'Student ID',
                    error['raw_student_id'] ?? '—'), // which student's record this is
                const SizedBox(height: 14),

                // ── Fix button ──────────────────────────────────────────
                // the big "Fix This" button — opens the correction screen
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Fix This',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: () => _openDetail(error), // same as tapping the card
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // navigates to the detail/correction screen for a specific error
  // after returning, refresh the list — the error might have been resolved already
  Future<void> _openDetail(Map<String, dynamic> error) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ImportErrorDetailScreen(error: error)));
    _fetch(); // Refresh after returning — maybe someone fixed it, check again
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // builds a small colored badge/chip — used for error type and source labels
  // colored border and background based on the given color parameter
  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), // light tint background
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)), // subtle border
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }

  // builds a single info row with an icon, label, and value
  // used inside the error card to show instructor name, subject, student ID
  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary), // small icon as visual indicator
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)), // bold label
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 12),
              overflow: TextOverflow.ellipsis), // truncate if value is too long
        ),
      ],
    );
  }

  // converts a DateTime to a short "X ago" string
  // min, hours, days — simple relative time, not seconds because calm down
  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
