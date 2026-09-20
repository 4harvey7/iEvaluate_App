// lib/sao_admin/import_errors_screen.dart
// The "broken records hall of shame" — all the entries that failed to match
// Shows errors grouped by type: All, Instructor Not Found, Subject Not Found
// Someone has to fix these. Wala choice. That someone is the admin.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import 'import_error_detail_screen.dart';
import '../widgets/apple_ui.dart';


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

  // ── Bulk selection ─────────────────────────────────────────────────────────
  // A single bad import writes one error row per survey row, so these arrive in
  // the hundreds. Fixing them one at a time is not a real option, hence select
  // all + delete.
  //
  // The set holds import_errors.id, never list indexes: _fetch() can replace
  // the list underneath the user, and an index-based selection would then point
  // at a different record than the one they ticked.
  final Set<int> _selectedIds = <int>{};
  bool _selectionMode = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    // 3 tabs — All errors, Instructor errors, Subject errors
    _tabController = TabController(length: 3, vsync: this);
    // Select-all reads the current tab, and the counter in the title says "N of
    // M". Both go stale on a tab swipe unless this rebuilds.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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
          // Drop ticks whose row is gone -- resolved elsewhere, or deleted by
          // another admin -- so the count in the title can never promise more
          // than the delete could actually act on.
          final live = _allErrors.map(_idOf).whereType<int>().toSet();
          _selectedIds.retainAll(live);
          if (_selectedIds.isEmpty) _selectionMode = false;
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
  //
  // 'instructor_and_subject_not_found' is included on purpose. That is the type
  // the importer actually writes when BOTH lookups miss, and matching only
  // 'instructor_not_found' meant those rows showed up under All and in neither
  // tab -- 89 of them in the last sheet import, invisible to anyone filtering.
  List<Map<String, dynamic>> get _instructorErrors => _allErrors
      .where((e) =>
          e['error_type'] == 'instructor_not_found' ||
          e['error_type'] == 'instructor_and_subject_not_found')
      .toList();

  // filtered list of only subject-not-found errors
  // these happen when the subject code/name doesnt match anything in the subjects table
  // Same reasoning as above: a combined failure is a subject failure too, so it
  // belongs in both tabs rather than falling out of both.
  List<Map<String, dynamic>> get _subjectErrors => _allErrors
      .where((e) =>
          e['error_type'] == 'subject_not_found' ||
          e['error_type'] == 'instructor_and_subject_not_found')
      .toList();

  // ── Selection helpers ──────────────────────────────────────────────────────

  /// The list the user is currently looking at. Select-all has to mean "all of
  /// what is on screen", not all of what is loaded, or ticking it on the
  /// Subject tab would quietly take instructor rows with it.
  List<Map<String, dynamic>> get _visibleErrors {
    switch (_tabController.index) {
      case 1:
        return _instructorErrors;
      case 2:
        return _subjectErrors;
      default:
        return _allErrors;
    }
  }

  static int? _idOf(Map<String, dynamic> e) {
    final raw = e['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  void _toggleSelected(Map<String, dynamic> error) {
    final id = _idOf(error);
    if (id == null) return;
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
      // Leaving the last item deselected drops out of selection mode, so the
      // user is never stranded in a mode with nothing selected and no button.
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelection(Map<String, dynamic> error) {
    final id = _idOf(error);
    if (id == null) return;
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll() {
    final visible = _visibleErrors.map(_idOf).whereType<int>().toSet();
    final allChosen = visible.isNotEmpty && _selectedIds.containsAll(visible);
    setState(() {
      if (allChosen) {
        _selectedIds.removeAll(visible);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(visible);
        _selectionMode = _selectedIds.isNotEmpty;
      }
    });
  }

  // ── Bulk delete ────────────────────────────────────────────────────────────

  /// Deletes every selected row, then PROVES they are gone.
  ///
  /// The proof is not defensive padding. import_errors is only ever written by
  /// n8n and only ever updated by the detail screen, so a DELETE policy may
  /// well not exist -- and PostgREST answers a delete that matched no rows with
  /// a perfectly ordinary success. Without the re-count this would report
  /// "Deleted 916" over a table that still holds 916 rows.
  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(children: [
          const Icon(Icons.delete_outline, color: AppColors.error),
          const SizedBox(width: 10),
          Flexible(child: Text('Delete ${ids.length} record${ids.length == 1 ? '' : 's'}?')),
        ]),
        content: const Text(
          'These import errors will be permanently removed. The survey data in '
          'them is discarded and cannot be recovered — re-run the import if you '
          'still need it.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      // Chunked because these ids travel in the URL as id=in.(...): a few
      // hundred at a time keeps every request well inside the URL length limit
      // that a single 900-id delete would blow straight past.
      const chunkSize = 200;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(
            i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
        await _supabase.from('import_errors').delete().inFilter('id', chunk);
      }

      final remaining = await _supabase
          .from('import_errors')
          .select('id')
          .inFilter('id', ids);
      final stillThere = (remaining as List).length;

      if (!mounted) return;
      if (stillThere == 0) {
        _exitSelection();
        await _fetch();
        if (mounted) {
          _snack('Deleted ${ids.length} record${ids.length == 1 ? '' : 's'}.',
              AppColors.success);
        }
      } else {
        // The delete was accepted and changed nothing — almost always a missing
        // RLS DELETE policy on import_errors. Say that, rather than claiming a
        // success the table does not agree with.
        await _fetch();
        if (mounted) {
          _snack(
            '$stillThere of ${ids.length} could not be deleted. The database '
            'refused the delete — import_errors is likely missing a DELETE '
            'policy for your role.',
            AppColors.error,
          );
        }
      }
    } catch (e) {
      debugPrint('[ImportErrors] Bulk delete failed: $e');
      if (mounted) _snack('Delete failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: AppColors.textPrimary),
                tooltip: 'Cancel selection',
                onPressed: _isDeleting ? null : _exitSelection,
              )
            : widget.showBackButton
                ? const BackButton(color: AppColors.textPrimary)
                : IconButton(
                    icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
                    tooltip: 'Open menu',
                    onPressed: widget.onMenuPressed ?? () => MainScaffold.drawerKey.currentState?.openDrawer(),
                  ),
        // title shows count of pending errors — a number that should always be going down
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectionMode ? '${_selectedIds.length} selected' : 'Import Errors',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              _selectionMode
                  ? 'of ${_visibleErrors.length} shown'
                  : '${_allErrors.length} pending resolution', // how many still need fixing
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
            ),
          ],
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: Icon(
                    _visibleErrors.isNotEmpty &&
                            _selectedIds.containsAll(
                                _visibleErrors.map(_idOf).whereType<int>())
                        ? Icons.deselect
                        : Icons.select_all,
                    color: AppColors.primary,
                  ),
                  tooltip: 'Select all in this tab',
                  onPressed: _isDeleting ? null : _toggleSelectAll,
                ),
                _isDeleting
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.error),
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error),
                        tooltip: 'Delete selected',
                        onPressed:
                            _selectedIds.isEmpty ? null : _deleteSelected,
                      ),
              ]
            : [
                // Enters selection mode with nothing ticked, so "select all" is
                // reachable without first long-pressing some arbitrary card.
                if (_allErrors.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.checklist_rounded,
                        color: AppColors.primary),
                    tooltip: 'Select records',
                    onPressed: () => setState(() => _selectionMode = true),
                  ),
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
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
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
          ? const AppleLoadingState(label: 'Loading import issues…')
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
      return const Padding(
        padding: EdgeInsets.all(16),
        child: AppleEmptyState(
          icon: Icons.check_circle_outline,
          title: 'No pending errors',
          message: 'All imported records matched successfully.',
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
    final type = error['error_type']?.toString() ?? '';
    final isBoth = type == 'instructor_and_subject_not_found';
    final isInstructor = type == 'instructor_not_found' || isBoth; // true = instructor problem
    final isSheet = error['source'] == 'google_sheet'; // true = from sheet, false = from scan
    final errorColor = isInstructor ? AppColors.error : AppColors.warning; // red for instructor, yellow for subject
    final id = _idOf(error);
    final selected = id != null && _selectedIds.contains(id);
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
        // A selected card is outlined in the primary colour instead, so the
        // tick is not the only thing distinguishing it in a long list.
        border: Border.all(
            color: selected
                ? AppColors.primary
                : errorColor.withValues(alpha: 0.25),
            width: selected ? 2 : 1.2),
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
          // In selection mode a tap must never open the detail screen -- that
          // is how a bulk delete turns into an accidental single edit.
          onTap: () => _selectionMode
              ? _toggleSelected(error)
              : _openDetail(error), // tap anywhere on the card to open detail screen
          onLongPress: () => _enterSelection(error),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: badges + time ──────────────────────────────
                // shows error type badge, source badge (sheet/scan), and how long ago
                Row(
                  children: [
                    if (_selectionMode) ...[
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _badge(
                      isBoth
                          ? 'Instructor + Subject'
                          : isInstructor
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
                // Student ID is deliberately not shown here or on the detail
                // screen. Resolving an import error needs the instructor and
                // the subject; who submitted the evaluation is not the admin's
                // business, and evaluations are answered on that basis.
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
                    // Greyed out while selecting: the card's own tap is bound to
                    // the tick, and a live Fix button here would contradict it.
                    onPressed: _selectionMode
                        ? null
                        : () => _openDetail(error), // same as tapping the card
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
