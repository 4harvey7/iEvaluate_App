import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'failed_scan_detail_screen.dart';
import '../sao_admin/import_error_detail_screen.dart';
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

  // Primary source section:
  // 0: Failed Scan Queue (Validation & OMR detection results from failed_scan_queue)
  // 1: Import Errors (Spreadsheet & Form errors from import_errors)
  int _sourceSection = 0;

  // Sub-filter tabs:
  // For Failed Scans: 0: All, 1: Instructor Error, 2: Subject Error, 3: OMR Result
  // For Import Errors: 0: All, 1: Instructor Error, 2: Subject Error
  int _failedSubTab = 0;
  int _importSubTab = 0;

  List<Map<String, dynamic>> _failedScans = [];
  List<Map<String, dynamic>> _importErrors = [];

  // Precomputed filtered lists for instant O(1) tab switching and smooth multi-select
  List<Map<String, dynamic>> _failedInstructorItems = [];
  List<Map<String, dynamic>> _failedSubjectItems = [];
  List<Map<String, dynamic>> _failedOmrItems = [];
  List<Map<String, dynamic>> _importInstructorItems = [];
  List<Map<String, dynamic>> _importSubjectItems = [];

  // Multi-select batch deletion state
  bool _isSelectMode = false;
  final Set<String> _selectedIds = {};
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  void _recomputeFilteredLists() {
    _failedInstructorItems =
        _failedScans.where(_isFailedInstructorError).toList();
    _failedSubjectItems = _failedScans.where(_isFailedSubjectError).toList();
    _failedOmrItems = _failedScans.where(_isFailedOmr).toList();

    _importInstructorItems =
        _importErrors.where(_isImportInstructorError).toList();
    _importSubjectItems =
        _importErrors.where(_isImportSubjectError).toList();
  }

  // ── Source Fetching ────────────────────────────────────────────────────────
  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> failed = [];
      List<Map<String, dynamic>> importErrors = [];

      // 1. Failed scan queue (Validation & OMR review)
      try {
        final res = await _supabase
            .from('failed_scan_queue')
            .select()
            .eq('status', 'pending')
            .order('created_at', ascending: false);
        final allFailed = List<Map<String, dynamic>>.from(res as List);
        // Non-SAST forms (food/selfie/undertaking) are handled in sync queue
        failed = allFailed.where((scan) {
          final reasons = (scan['review_reasons']?.toString() ?? '').toLowerCase();
          final gridSource = (scan['grid_source']?.toString() ?? '').toLowerCase();
          final partial = scan['partial_data'] is Map ? scan['partial_data'] as Map : {};
          final reviewNote = (partial['review_note']?.toString() ?? '').toLowerCase();
          return !reasons.contains('not_a_sast_form') &&
              !reasons.contains('not_a_form') &&
              !gridSource.contains('not_a_sast') &&
              !reviewNote.contains('not a sast form');
        }).toList();
      } catch (e) {
        debugPrint('[Validation] Error fetching failed scans: $e');
      }

      // 2. Google Sheet & CSV import errors
      try {
        final res = await _supabase
            .from('import_errors')
            .select('*')
            .eq('status', 'pending')
            .order('created_at', ascending: false);
        importErrors = List<Map<String, dynamic>>.from(res as List);
      } catch (e) {
        debugPrint('[Validation] Error fetching import errors: $e');
      }

      if (mounted) {
        setState(() {
          _failedScans = failed.map((e) => {
                'type': 'failed',
                'id': 'failed_${e['id']}',
                'data': e,
              }).toList();

          _importErrors = importErrors.map((e) => {
                'type': 'import_error',
                'id': 'import_${e['id']}',
                'data': e,
              }).toList();

          _recomputeFilteredLists();

          _isLoading = false;

          final allLiveIds = {
            ..._failedScans.map((e) => e['id'] as String),
            ..._importErrors.map((e) => e['id'] as String),
          };
          _selectedIds.retainAll(allLiveIds);
        });
      }
    } catch (e) {
      debugPrint('[Validation] Error in _fetchData: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Failed Scans Filters (failed_scan_queue) ──────────────────────────────
  bool _isFailedInstructorError(Map<String, dynamic> item) {
    final data = item['data'] as Map<String, dynamic>;
    final reasons = (data['review_reasons']?.toString() ?? '').toLowerCase();
    final partial =
        data['partial_data'] is Map ? data['partial_data'] as Map : {};
    final inst = partial['instructor']?.toString() ?? '';
    return reasons.contains('instructor') || inst.trim().isEmpty;
  }

  bool _isFailedSubjectError(Map<String, dynamic> item) {
    final data = item['data'] as Map<String, dynamic>;
    final reasons = (data['review_reasons']?.toString() ?? '').toLowerCase();
    final partial =
        data['partial_data'] is Map ? data['partial_data'] as Map : {};
    final subj = partial['subject']?.toString() ?? '';
    return reasons.contains('subject') || subj.trim().isEmpty;
  }

  bool _isFailedOmr(Map<String, dynamic> item) {
    final data = item['data'] as Map<String, dynamic>;
    final reasons = (data['review_reasons']?.toString() ?? '').toLowerCase();

    // Check for explicit OMR / bubble / alignment failures
    final hasExplicitOmrIssue = reasons.contains('omr') ||
        reasons.contains('bubble') ||
        reasons.contains('unfilled') ||
        reasons.contains('multiple_mark') ||
        reasons.contains('multiple mark') ||
        reasons.contains('bubble_error') ||
        reasons.contains('blur') ||
        (data['table_found'] == false &&
            (reasons.contains('table') || reasons.contains('corner')));

    return hasExplicitOmrIssue;
  }

  List<Map<String, dynamic>> get _visibleFailedScans {
    switch (_failedSubTab) {
      case 1:
        return _failedInstructorItems;
      case 2:
        return _failedSubjectItems;
      case 3:
        return _failedOmrItems;
      case 0:
      default:
        return _failedScans;
    }
  }

  // ── Import Errors Filters (import_errors) ──────────────────────────────────
  bool _isImportInstructorError(Map<String, dynamic> item) {
    final data = item['data'] as Map<String, dynamic>;
    final errType = (data['error_type']?.toString() ?? '').toLowerCase();
    return errType.contains('instructor');
  }

  bool _isImportSubjectError(Map<String, dynamic> item) {
    final data = item['data'] as Map<String, dynamic>;
    final errType = (data['error_type']?.toString() ?? '').toLowerCase();
    return errType.contains('subject');
  }

  List<Map<String, dynamic>> get _visibleImportErrors {
    switch (_importSubTab) {
      case 1:
        return _importInstructorItems;
      case 2:
        return _importSubjectItems;
      case 0:
      default:
        return _importErrors;
    }
  }

  // Active items currently showing on screen
  List<Map<String, dynamic>> get _visibleItems =>
      _sourceSection == 0 ? _visibleFailedScans : _visibleImportErrors;

  // ── Multi-Select Operations ───────────────────────────────────────────────
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      _selectedIds.clear();
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _isSelectMode = true;
      _selectedIds.add(id);
    });
  }

  void _selectAll() {
    final visibleIds = _visibleItems.map((e) => e['id'] as String).toSet();
    setState(() {
      if (_selectedIds.containsAll(visibleIds) && visibleIds.isNotEmpty) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  void _toggleItemSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _confirmBatchDelete() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete selected records?',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Delete $count record${count == 1 ? '' : 's'}? These records will be permanently removed from the system. This cannot be undone.',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isDeleting = true);

    try {
      final allItems = [..._failedScans, ..._importErrors];
      final itemsToDelete =
          allItems.where((item) => _selectedIds.contains(item['id'])).toList();

      final importErrorIds = <dynamic>[];
      final failedScanIds = <dynamic>[];

      for (final item in itemsToDelete) {
        final type = item['type'] as String;
        final data = item['data'] as Map<String, dynamic>;

        if (type == 'import_error') {
          importErrorIds.add(data['id']);
        } else if (type == 'failed') {
          failedScanIds.add(data['id']);
        }
      }

      const chunkSize = 100;

      // 1. Delete import errors
      for (var i = 0; i < importErrorIds.length; i += chunkSize) {
        final chunk = importErrorIds.sublist(
            i,
            i + chunkSize > importErrorIds.length
                ? importErrorIds.length
                : i + chunkSize);
        await _supabase.from('import_errors').delete().inFilter('id', chunk);
      }

      // 2. Discard failed scans
      for (var i = 0; i < failedScanIds.length; i += chunkSize) {
        final chunk = failedScanIds.sublist(
            i,
            i + chunkSize > failedScanIds.length
                ? failedScanIds.length
                : i + chunkSize);
        await _supabase
            .from('failed_scan_queue')
            .update({'status': 'discarded'}).inFilter('id', chunk);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count record${count == 1 ? '' : 's'} removed.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Validation] Batch delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting records: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _isSelectMode = false;
          _selectedIds.clear();
        });
        _fetchData();
      }
    }
  }

  // ── Navigation & Format Helpers ───────────────────────────────────────────
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
    final rawReasons = scan['review_reasons'];
    if (rawReasons is List && rawReasons.isNotEmpty) {
      final raw = rawReasons.first.toString();
      final s = (raw.contains(':') ? raw.substring(0, raw.indexOf(':')).trim() : raw)
          .replaceAll('_', ' ');
      return s.isEmpty ? 'Detection issue' : s[0].toUpperCase() + s.substring(1);
    }
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

  String _importErrorReason(Map<String, dynamic> error) {
    final type = error['error_type']?.toString() ?? '';
    if (type == 'instructor_not_found') return 'Instructor not found';
    if (type == 'subject_not_found') return 'Subject not found';
    if (type == 'instructor_and_subject_not_found') {
      return 'Instructor & subject not found';
    }
    return type.replaceAll('_', ' ');
  }

  bool _isScanSource(Map<String, dynamic> error) {
    final source = (error['source']?.toString() ?? '').toLowerCase();
    if (source.contains('scan')) return true;
    if (source.contains('sheet')) return false;

    final taskId = (error['task_id'] ??
            (error['raw_data'] is Map ? error['raw_data']['task_id'] : null))
        ?.toString() ??
        '';
    if (taskId.isNotEmpty && taskId.toLowerCase() != 'null') return true;

    final scanImg = error['scan_image']?.toString() ?? '';
    if (scanImg.isNotEmpty && scanImg.toLowerCase() != 'null') return true;

    return false;
  }

  void _openImportErrorDetail(Map<String, dynamic> error) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImportErrorDetailScreen(error: error),
      ),
    );
    _fetchData();
  }

  // ── Empty States ──────────────────────────────────────────────────────────
  IconData get _emptyIcon {
    if (_sourceSection == 0) {
      switch (_failedSubTab) {
        case 1:
          return Icons.person_off_outlined;
        case 2:
          return Icons.menu_book_outlined;
        case 3:
          return Icons.document_scanner_outlined;
        case 0:
        default:
          return Icons.check_circle_outline;
      }
    } else {
      switch (_importSubTab) {
        case 1:
          return Icons.person_off_outlined;
        case 2:
          return Icons.menu_book_outlined;
        case 0:
        default:
          return Icons.table_chart_outlined;
      }
    }
  }

  String get _emptyTitle {
    if (_sourceSection == 0) {
      switch (_failedSubTab) {
        case 1:
          return 'No instructor errors in scans';
        case 2:
          return 'No subject errors in scans';
        case 3:
          return 'No OMR or bubble issues';
        case 0:
        default:
          return 'No failed scans to validate';
      }
    } else {
      switch (_importSubTab) {
        case 1:
          return 'No imported instructor errors';
        case 2:
          return 'No imported subject errors';
        case 0:
        default:
          return 'No import errors found';
      }
    }
  }

  String get _emptyMessage {
    if (_sourceSection == 0) {
      switch (_failedSubTab) {
        case 1:
          return 'All instructors in scanned forms were resolved successfully.';
        case 2:
          return 'All subjects in scanned forms were resolved successfully.';
        case 3:
          return 'All scan bubble detections and OMR forms are valid.';
        case 0:
        default:
          return 'All scan records in failed_scan_queue have been resolved.';
      }
    } else {
      switch (_importSubTab) {
        case 1:
          return 'All instructors in Google Sheet / CSV imports are resolved.';
        case 2:
          return 'All subjects in Google Sheet / CSV imports are resolved.';
        case 0:
        default:
          return 'All records from import_errors have been addressed.';
      }
    }
  }

  // ── Top Navigation (Separates Failed Scan Queue vs Import Errors) ─────────
  Widget _buildTopSourceSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          // Section 0: Failed Scan Queue (Validation & OMR)
          Expanded(
            child: _buildSectionTabButton(
              sectionIndex: 0,
              title: 'Failed Scans',
              subtitle: 'Validation & OMR',
              icon: Icons.document_scanner_rounded,
              count: _failedScans.length,
            ),
          ),
          const SizedBox(width: 4),
          // Section 1: Import Errors (From other table)
          Expanded(
            child: _buildSectionTabButton(
              sectionIndex: 1,
              title: 'Import Errors',
              subtitle: 'Sheet Imports',
              icon: Icons.table_chart_outlined,
              count: _importErrors.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTabButton({
    required int sectionIndex,
    required String title,
    required String subtitle,
    required IconData icon,
    required int count,
  }) {
    final isSelected = _sourceSection == sectionIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_sourceSection == sectionIndex) return;
        setState(() {
          _sourceSection = sectionIndex;
          _selectedIds.clear();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.2)
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppColors.textSecondary,
                      fontSize: 9.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : (sectionIndex == 0
                          ? AppColors.indigo.withValues(alpha: 0.15)
                          : AppColors.primary.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : (sectionIndex == 0
                            ? AppColors.indigo
                            : AppColors.primary),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectMultipleButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _toggleSelectMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rounded, size: 16, color: AppColors.primary),
            SizedBox(width: 5),
            Text(
              'Select Multiple',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sub-Filter Chips ───────────────────────────────────────────────────────
  Widget _buildSubFilterChips() {
    final showSelect = !_isLoading && _visibleItems.isNotEmpty && !_isSelectMode;

    if (_sourceSection == 0) {
      // Failed Scans: Select Multiple (if available), All, Instructor Error, Subject Error, OMR Result
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Row(
          children: [
            if (showSelect) ...[
              _buildSelectMultipleButton(),
              const SizedBox(width: 8),
            ],
            _buildSubChip(0, 'All', _failedScans.length, isFailedSection: true),
            const SizedBox(width: 8),
            _buildSubChip(1, 'Instructor Error', _failedInstructorItems.length,
                isFailedSection: true),
            const SizedBox(width: 8),
            _buildSubChip(2, 'Subject Error', _failedSubjectItems.length,
                isFailedSection: true),
            const SizedBox(width: 8),
            _buildSubChip(3, 'OMR Result', _failedOmrItems.length,
                isFailedSection: true),
          ],
        ),
      );
    } else {
      // Import Errors: Select Multiple (if available), All, Instructor Error, Subject Error
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Row(
          children: [
            if (showSelect) ...[
              _buildSelectMultipleButton(),
              const SizedBox(width: 8),
            ],
            _buildSubChip(0, 'All', _importErrors.length, isFailedSection: false),
            const SizedBox(width: 8),
            _buildSubChip(1, 'Instructor Error', _importInstructorItems.length,
                isFailedSection: false),
            const SizedBox(width: 8),
            _buildSubChip(2, 'Subject Error', _importSubjectItems.length,
                isFailedSection: false),
          ],
        ),
      );
    }
  }

  Widget _buildSubChip(int index, String label, int count,
      {required bool isFailedSection}) {
    final activeIndex = isFailedSection ? _failedSubTab : _importSubTab;
    final isSelected = activeIndex == index;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (activeIndex == index) return;
        setState(() {
          if (isFailedSection) {
            _failedSubTab = index;
          } else {
            _importSubTab = index;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? (isFailedSection ? AppColors.indigo : AppColors.primary)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (isFailedSection ? AppColors.indigo : AppColors.primary)
                : AppColors.borderSubtle,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isFailedSection ? AppColors.indigo : AppColors.primary)
                        .withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : (isFailedSection ? AppColors.indigo : AppColors.primary)
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isFailedSection ? AppColors.indigo : AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    final visibleIds = visibleItems.map((e) => e['id'] as String).toSet();
    final allVisibleSelected =
        visibleIds.isNotEmpty && _selectedIds.containsAll(visibleIds);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary Navigation Switch: [ Failed Scans (Queue/OMR) ] vs [ Import Errors ]
          _buildTopSourceSelector(),

          // Sub-filter chips for active section (with Select Multiple leading)
          _buildSubFilterChips(),

          // Multi-Select Action Bar (shown when in select mode)
          if (_isSelectMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: allVisibleSelected,
                      onChanged: (_) => _selectAll(),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${_selectedIds.length}/${visibleItems.length} selected',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isDeleting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.error),
                      )
                    else
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedIds.isEmpty
                              ? AppColors.textSecondary
                              : AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed:
                            _selectedIds.isEmpty ? null : _confirmBatchDelete,
                        icon: const Icon(Icons.delete_outline, size: 15),
                        label: Text('Delete (${_selectedIds.length})',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    const SizedBox(width: 6),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _toggleSelectMode,
                      child: const Text('Done',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: _isLoading
                ? const AppleLoadingState(label: 'Loading records…')
                : visibleItems.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppleEmptyState(
                          icon: _emptyIcon,
                          title: _emptyTitle,
                          message: _emptyMessage,
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _fetchData,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          itemCount: visibleItems.length,
                          itemBuilder: (context, index) {
                            final item = visibleItems[index];
                            final id = item['id'] as String;
                            final isSelected = _selectedIds.contains(id);

                            if (item['type'] == 'import_error') {
                              return _buildImportErrorCard(
                                id: id,
                                error: item['data'] as Map<String, dynamic>,
                                isSelected: isSelected,
                              );
                            } else {
                              return _buildFailedCard(
                                id: id,
                                scan: item['data'] as Map<String, dynamic>,
                                isSelected: isSelected,
                              );
                            }
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Import Error Card ─────────────────────────────────────────────────────
  Widget _buildImportErrorCard({
    required String id,
    required Map<String, dynamic> error,
    required bool isSelected,
  }) {
    final reason = _importErrorReason(error);
    final isScan = _isScanSource(error);
    final rawData = (error['raw_data'] is Map)
        ? Map<String, dynamic>.from(error['raw_data'] as Map)
        : <String, dynamic>{};
    final instructor = error['raw_instructor_name'] ??
        rawData['instructor'] ??
        'Unknown Instructor';
    final subject = error['raw_subject_name'] ?? rawData['subject'] ?? '';

    return Card(
      color: isSelected
          ? AppColors.primary.withValues(alpha: 0.07)
          : AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? AppColors.primary
              : (isScan ? AppColors.indigo : AppColors.primary)
                  .withValues(alpha: 0.3),
          width: isSelected ? 2.0 : 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (_isSelectMode) {
            _toggleItemSelection(id);
          } else {
            _openImportErrorDetail(error);
          }
        },
        onLongPress: () {
          if (!_isSelectMode) {
            _enterSelection(id);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_isSelectMode) ...[
                IgnorePointer(
                  child: Checkbox(
                    value: isSelected,
                    activeColor: AppColors.primary,
                    onChanged: null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (isScan ? AppColors.indigo : AppColors.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isScan
                      ? Icons.document_scanner_rounded
                      : Icons.table_chart_outlined,
                  color: isScan ? AppColors.indigo : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isScan
                                    ? AppColors.textSecondary
                                    : AppColors.primary)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isScan ? 'SCAN' : 'GOOGLE SHEET',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isScan
                                  ? AppColors.textSecondary
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              reason,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      instructor.toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subject.toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Subject: $subject',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(error['created_at']?.toString()),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!_isSelectMode) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    color: isScan ? AppColors.indigo : AppColors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Failed Scan Card (failed_scan_queue) ──────────────────────────────────
  Widget _buildFailedCard({
    required String id,
    required Map<String, dynamic> scan,
    required bool isSelected,
  }) {
    final partial = (scan['partial_data'] is Map
        ? Map<String, dynamic>.from(scan['partial_data'] as Map)
        : {});
    final failColor = _failColor(scan);
    final failIcon = _failIcon(scan);
    final reason = _failReason(scan);
    final studentId = partial['student_id']?.toString() ?? '';
    final instructor = partial['instructor']?.toString() ?? '';

    return Card(
      color: isSelected
          ? AppColors.primary.withValues(alpha: 0.07)
          : AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? AppColors.primary
              : failColor.withValues(alpha: 0.35),
          width: isSelected ? 2.0 : 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (_isSelectMode) {
            _toggleItemSelection(id);
          } else {
            _openFailedDetail(scan);
          }
        },
        onLongPress: () {
          if (!_isSelectMode) {
            _enterSelection(id);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_isSelectMode) ...[
                IgnorePointer(
                  child: Checkbox(
                    value: isSelected,
                    activeColor: AppColors.primary,
                    onChanged: null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.textSecondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SCAN',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: failColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              reason,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: failColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scan['task_id']?.toString() ?? 'Failed Scan',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (instructor.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Instructor: $instructor',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (studentId.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Student ID: $studentId',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(scan['created_at']?.toString()),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!_isSelectMode) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
