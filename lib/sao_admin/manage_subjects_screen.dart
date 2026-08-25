// lib/sao_admin/manage_subjects_screen.dart
// This screen is for managing subject assignments — who teaches what, this term.
// Two ways to add: bulk import from Google Sheets (via n8n), or one-by-one manually.
// Both entry points are behind clean action buttons — no inline forms cluttering the main list.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../core/config/env.dart';
import '../core/services/system_settings_service.dart';
import '../widgets/safe_button.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';


// outer widget — just holds the state, nothing interesting yet
class ManageSubjectsScreen extends StatefulWidget {
  const ManageSubjectsScreen({super.key});

  @override
  State<ManageSubjectsScreen> createState() => _ManageSubjectsScreenState();
}

class _ManageSubjectsScreenState extends State<ManageSubjectsScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _settingsService = SystemSettingsService();

  // Data
  List<Map<String, dynamic>> _instructors = [];
  List<Map<String, dynamic>> _departments = []; // from department_name table
  // Each group: {'subject': {...}, 'assignments': [...instructor_subjects rows]}
  // assignments may be empty for subjects with no instructor yet
  List<Map<String, dynamic>> _subjectGroups = [];
  String? _currentTermId;
  String _currentTermLabel = '...';
  bool _isLoading = true;

  // Search + filter
  String _searchQuery = '';
  String _filterMode = 'unassigned'; // 'assigned' | 'unassigned'

  // Speed dial open state
  bool _isFabOpen = false;
  late AnimationController _fabAnimController;
  late Animation<double> _fabScaleAnim;

  // the n8n webhook URL for bulk import
  static String get _n8nBulkImportUrl => Env.n8nSubjectBulkImportUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fabScaleAnim = CurvedAnimation(parent: _fabAnimController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    super.dispose();
  }

  void _toggleFab() {
    setState(() => _isFabOpen = !_isFabOpen);
    if (_isFabOpen) {
      _fabAnimController.forward();
    } else {
      _fabAnimController.reverse();
    }
  }

  void _closeFab() {
    if (_isFabOpen) {
      setState(() => _isFabOpen = false);
      _fabAnimController.reverse();
    }
  }

  // loads the active term, departments, instructors, all subjects, and assignments
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _settingsService.getSettings();
      _currentTermId = settings.termId;
      _currentTermLabel = '${settings.semester} ${settings.academicYear}';

      // Load all departments — used for the department dropdown in the form
      final deptRes = await _supabase
          .from('department_name')
          .select('id, d_name')
          .order('d_name');

      // Load instructors with their department ID so we can auto-fill department on selection
      final instRes = await _supabase
          .from('department_table')
          .select('user_id, Department_name_ID, user_info!user_id(first_name, last_name)')
          .not('user_id', 'is', null);

      // Load ALL subjects (not filtered by term — subjects exist across terms)
      final subjectsRes = await _supabase
          .from('subjects')
          .select('id, subject_code, subject_name, department_id, department_name!department_id(d_name)')
          .order('subject_code');

      // Load instructor assignments for the current term only
      List<Map<String, dynamic>> assignmentsRes = [];
      if (_currentTermId != null) {
        final res = await _supabase
            .from('instructor_subjects')
            .select('id, subject_id, instructor_id, term_id, user_info!instructor_id(first_name, last_name)')
            .eq('term_id', _currentTermId!);
        assignmentsRes = List<Map<String, dynamic>>.from(res as List);
      }

      if (mounted) {
        setState(() {
          _departments = (deptRes as List)
              .map((d) => {
                    'id': d['id'].toString(),
                    'name': d['d_name']?.toString() ?? '',
                  })
              .toList();

          // Store departmentId per instructor so the form can auto-fill
          _instructors = (instRes as List)
              .where((i) => i['user_info'] != null)
              .map((i) => {
                    'id': i['user_id'],
                    'name': '${i['user_info']['first_name']} ${i['user_info']['last_name']}',
                    'departmentId': i['Department_name_ID']?.toString(),
                  })
              .toList();

          // Group assignments by subject_id for O(1) lookup
          final Map<String, List<Map<String, dynamic>>> bySubject = {};
          for (final a in assignmentsRes) {
            final sid = a['subject_id']?.toString() ?? '';
            bySubject.putIfAbsent(sid, () => []).add(a);
          }

          // Build subject groups — every subject gets a group, even with no assignments
          _subjectGroups = (subjectsRes as List).map((s) {
            final sid = s['id']?.toString() ?? '';
            return <String, dynamic>{
              'subject': s,
              'assignments': bySubject[sid] ?? <Map<String, dynamic>>[],
            };
          }).toList();

          // Sort so subjects with instructors assigned appear first
          _subjectGroups.sort((a, b) {
            final aHas = (a['assignments'] as List).isNotEmpty;
            final bHas = (b['assignments'] as List).isNotEmpty;
            if (aHas && !bHas) return -1;
            if (!aHas && bHas) return 1;
            
            // secondary sort by subject code
            final aCode = (a['subject']['subject_code']?.toString() ?? '').toLowerCase();
            final bCode = (b['subject']['subject_code']?.toString() ?? '').toLowerCase();
            return aCode.compareTo(bCode);
          });

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ManageSubjects load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Open Add Subject modal ──────────────────────────────────────
  void _openAddSubjectModal({Map<String, dynamic>? editingAssignment}) {
    _closeFab();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSubjectModal(
        instructors: _instructors,
        departments: _departments,
        currentTermId: _currentTermId,
        supabase: _supabase,
        editingAssignment: editingAssignment,
        onSaved: () {
          _loadData();
          _showSnack(editingAssignment != null ? 'Assignment updated successfully' : 'Subject assigned successfully');
        },
        onError: (msg) => _showSnack(msg, isError: true),
      ),
    );
  }

  // ── Open Bulk Import modal ──────────────────────────────────────
  void _openBulkImportModal() {
    _closeFab();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BulkImportModal(
        currentTermId: _currentTermId,
        supabase: _supabase,
        n8nUrl: _n8nBulkImportUrl,
        onSuccess: () {
          _loadData();
          _showSnack('Subjects imported successfully!');
        },
        onError: (msg) => _showSnack(msg, isError: true),
      ),
    );
  }

  // Delete assignment row only — not the subject itself
  Future<void> _deleteAssignment(String assignmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Remove Assignment',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        content: const Text('Remove this instructor from this subject for the current term? The subject will remain available for other terms.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          Pressable(
            child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _supabase.from('instructor_subjects').delete().eq('id', assignmentId);
      _showSnack('Assignment removed');
      _loadData();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  // ── Filtered + searched subject groups ───────────────────────────
  List<Map<String, dynamic>> get _filteredGroups {
    var groups = _subjectGroups;

    // Filter by assignment status
    if (_filterMode == 'assigned') {
      groups = groups.where((g) => (g['assignments'] as List).isNotEmpty).toList();
    } else if (_filterMode == 'unassigned') {
      groups = groups.where((g) => (g['assignments'] as List).isEmpty).toList();
    }

    // Search by subject code, name, or instructor name
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      groups = groups.where((g) {
        final s = g['subject'] as Map<String, dynamic>;
        final code = (s['subject_code'] as String? ?? '').toLowerCase();
        final name = (s['subject_name'] as String? ?? '').toLowerCase();
        if (code.contains(q) || name.contains(q)) return true;
        // also match instructor names
        final assignments = g['assignments'] as List;
        return assignments.any((a) {
          final info = a['user_info'];
          if (info == null) return false;
          final instrName = '${info['first_name']} ${info['last_name']}'.toLowerCase();
          return instrName.contains(q);
        });
      }).toList();
    }

    return groups;
  }

  // Opens the subject detail modal — shows all instructors teaching this subject
  void _openSubjectDetailModal(Map<String, dynamic> group) {
    _closeFab();
    final subject = group['subject'] as Map<String, dynamic>;
    final subjectAssignments = group['assignments'] as List<Map<String, dynamic>>;
    final subjectCode = subject['subject_code']?.toString() ?? '';
    final subjectName = subject['subject_name']?.toString() ?? '';
    final departmentId = subject['department_id']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubjectDetailModal(
        subject: subject,
        assignments: subjectAssignments,
        onEdit: (a) {
          Navigator.pop(context);
          // Build a fake editingAssignment compatible with _AddSubjectModal
          final fakeAssignment = {
            ...a,
            'subjects': subject,
          };
          _openAddSubjectModal(editingAssignment: fakeAssignment);
        },
        onDelete: (id) async {
          Navigator.pop(context);
          await _deleteAssignment(id);
        },
        onAddInstructor: () {
          Navigator.pop(context);
          _openAddSubjectModalPrefilledSubject(
            subjectCode: subjectCode,
            subjectName: subjectName,
            departmentId: departmentId,
          );
        },
      ),
    );
  }

  // Opens Add Subject modal with code + name pre-filled (for adding another instructor)
  void _openAddSubjectModalPrefilledSubject({
    required String subjectCode,
    required String subjectName,
    String? departmentId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSubjectModal(
        instructors: _instructors,
        departments: _departments,
        currentTermId: _currentTermId,
        supabase: _supabase,
        editingAssignment: null,
        prefilledCode: subjectCode,
        prefilledName: subjectName,
        prefilledDepartmentId: departmentId,
        onSaved: () {
          _loadData();
          _showSnack('Instructor assigned successfully');
        },
        onError: (msg) => _showSnack(msg, isError: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _closeFab, // tap outside closes FAB menu
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E1608), AppColors.textPrimary],
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textInverted,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textInverted),
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.textInverted),
            tooltip: 'Open menu',
            onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Subject Management',
                  style: TextStyle(
                      color: AppColors.textInverted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              Text(_currentTermLabel, style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12), overflow: TextOverflow.ellipsis),
            ],
          ),
          actions: [
            SafeIconButton(icon: const Icon(Icons.refresh, color: AppColors.primary), onPressed: _loadData),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Search bar ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Entrance(
                      index: 0,
                      child: Container(
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
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search subject or instructor...',
                          hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary, size: 18),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                  // ── Filter chips ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Entrance(
                      index: 1,
                      child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip('With Instructor', 'assigned', Icons.person_rounded,
                              activeColor: AppColors.success),
                          const SizedBox(width: 8),
                          _buildFilterChip('No Instructor', 'unassigned', Icons.person_off_rounded,
                              activeColor: AppColors.warning),
                        ],
                      ),
                    ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Count label ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_filteredGroups.length} subject${_filteredGroups.length == 1 ? '' : 's'}'.toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── List ───────────────────────────────────────
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      color: AppColors.primary,
                      child: _filteredGroups.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                              itemCount: _filteredGroups.length,
                              itemBuilder: (context, index) => Entrance(
                                  index: index.clamp(0, 8),
                                  child: _buildSubjectCard(_filteredGroups[index])),
                            ),
                    ),
                  ),
                ],
              ),
        // ── Speed Dial FAB ──────────────────────────────────────
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Mini FAB: Bulk Import — shows only when open
            ScaleTransition(
              scale: _fabScaleAnim,
              child: Pressable(
                child: _buildMiniFab(
                icon: Icons.table_chart_rounded,
                label: 'Send Bulk',
                color: AppColors.warning,
                onTap: _openBulkImportModal,
              ),
              ),
            ),
            const SizedBox(height: 10),
            // Mini FAB: Add Subject — shows only when open
            ScaleTransition(
              scale: _fabScaleAnim,
              child: Pressable(
                child: _buildMiniFab(
                icon: Icons.add_circle_outline_rounded,
                label: 'Add Subject',
                color: AppColors.success,
                onTap: () => _openAddSubjectModal(),
              ),
              ),
            ),
            const SizedBox(height: 12),
            // Main FAB — always visible
            Pressable(
              child: FloatingActionButton(
              onPressed: _toggleFab,
              backgroundColor: AppColors.primary,
              elevation: 4,
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 220),
                turns: _isFabOpen ? 0.125 : 0, // rotate 45° when open
                child: const Icon(Icons.add, color: AppColors.textPrimary, size: 28),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniFab({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // label chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          // mini fab circle
          Material(
            color: color,
            elevation: 4,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter chip builder ──────────────────────────────────
  Widget _buildFilterChip(String label, String mode, IconData icon,
      {Color activeColor = AppColors.primary}) {
    final isActive = _filterMode == mode;
    return Pressable(
      child: GestureDetector(
      onTap: () => setState(() => _filterMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isActive
              ? null
              : [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isActive ? activeColor : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _searchQuery.isNotEmpty || _filterMode != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFiltered ? Icons.search_off_rounded : Icons.library_books_outlined,
                size: 34,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered ? 'No results found' : 'No subjects to show',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              isFiltered
                  ? 'Try a different search or filter.'
                  : 'Tap the + button to add a subject\nor bulk import from Google Sheets.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // One card per subject — color-coded by assignment status
  Widget _buildSubjectCard(Map<String, dynamic> group) {
    final subject = group['subject'] as Map<String, dynamic>;
    final assignments = group['assignments'] as List<Map<String, dynamic>>;
    final isAssigned = assignments.isNotEmpty;

    final subjectCode = subject['subject_code']?.toString() ?? '??';
    final subjectName = subject['subject_name']?.toString() ?? 'Unknown Subject';
    final deptInfo = subject['department_name'];
    final deptName = deptInfo is Map ? deptInfo['d_name']?.toString() : null;

    // Color palette: green = assigned, amber = unassigned
    const assignedColor  = AppColors.success;
    const unassignedColor = AppColors.warning;
    final statusColor = isAssigned ? assignedColor : unassignedColor;

    // Build instructor preview text
    String previewName;
    if (!isAssigned) {
      previewName = 'No instructor assigned';
    } else {
      final first = assignments.first;
      final info = first['user_info'];
      final firstName = info != null
          ? '${info['first_name']} ${info['last_name']}'
          : 'Unknown';
      previewName = assignments.length > 1
          ? '$firstName +${assignments.length - 1} more'
          : firstName;
    }

    return Pressable(
      child: Container(
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
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openSubjectDetailModal(group),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                // Avatar with status color
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    subjectCode.length >= 2
                        ? subjectCode.substring(0, 2).toUpperCase()
                        : subjectCode.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subject code + name
                      Text(
                        '$subjectCode — $subjectName',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Department badge + instructor preview
                      Row(
                        children: [
                          if (deptName != null) ...[
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 80),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryTint,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  deptName,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      color: AppColors.primaryText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Icon(
                            isAssigned ? Icons.person_rounded : Icons.person_off_rounded,
                            size: 12,
                            color: statusColor,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              previewName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                  color: isAssigned
                                      ? AppColors.textSecondary
                                      : unassignedColor,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status badge pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isAssigned ? '${assignments.length} instr.' : 'Unassigned',
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary, size: 18),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// ADD SUBJECT MODAL
// ════════════════════════════════════════════════════════════════════
class _AddSubjectModal extends StatefulWidget {
  final List<Map<String, dynamic>> instructors;
  final List<Map<String, dynamic>> departments;  // from department_name table
  final String? currentTermId;
  final SupabaseClient supabase;
  final Map<String, dynamic>? editingAssignment;
  final VoidCallback onSaved;
  final void Function(String) onError;
  final String? prefilledCode;         // used when adding instructor to existing subject
  final String? prefilledName;
  final String? prefilledDepartmentId; // auto-set from subject when adding instructor

  const _AddSubjectModal({
    required this.instructors,
    required this.departments,
    required this.currentTermId,
    required this.supabase,
    required this.onSaved,
    required this.onError,
    this.editingAssignment,
    this.prefilledCode,
    this.prefilledName,
    this.prefilledDepartmentId,
  });

  @override
  State<_AddSubjectModal> createState() => _AddSubjectModalState();
}

class _AddSubjectModalState extends State<_AddSubjectModal> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _instructorSearchController = TextEditingController();
  final _instructorFocusNode = FocusNode();

  String? _selectedInstructorId;
  String? _selectedInstructorName;
  String? _selectedDepartmentId; // department_name.id
  bool _showSuggestions = false;
  List<Map<String, dynamic>> _filteredInstructors = [];
  bool _isSaving = false;
  String? _editingAssignmentId;

  @override
  void initState() {
    super.initState();
    _filteredInstructors = widget.instructors;

    // Pre-fill if editing an existing assignment
    final editing = widget.editingAssignment;
    if (editing != null) {
      _editingAssignmentId = editing['id'].toString();
      final subjectData = editing['subjects'];
      final subject = subjectData is Map
          ? subjectData
          : (subjectData is List && subjectData.isNotEmpty ? subjectData[0] : null);
      _codeController.text = subject?['subject_code'] ?? '';
      _nameController.text = subject?['subject_name'] ?? '';
      // Pre-fill department from existing subject
      _selectedDepartmentId = subject?['department_id']?.toString();
      _selectedInstructorId = editing['instructor_id'];
      final instrInfo = editing['user_info'];
      if (instrInfo != null) {
        _selectedInstructorName = '${instrInfo['first_name']} ${instrInfo['last_name']}';
        _instructorSearchController.text = _selectedInstructorName!;
      }
    } else if (widget.prefilledCode != null) {
      // Pre-fill subject code+name+department when adding another instructor to existing subject
      _codeController.text = widget.prefilledCode!;
      _nameController.text = widget.prefilledName ?? '';
      _selectedDepartmentId = widget.prefilledDepartmentId;
    }

    _instructorSearchController.addListener(_onInstructorSearch);
    _instructorFocusNode.addListener(() {
      if (!_instructorFocusNode.hasFocus) {
        // slight delay so tap on suggestion registers first
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showSuggestions = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _instructorSearchController.dispose();
    _instructorFocusNode.dispose();
    super.dispose();
  }

  void _onInstructorSearch() {
    final query = _instructorSearchController.text.trim().toLowerCase();
    setState(() {
      // Base list: instructors in the selected department (or all if no dept chosen)
      final base = _selectedDepartmentId == null
          ? widget.instructors
          : widget.instructors
              .where((i) => i['departmentId']?.toString() == _selectedDepartmentId)
              .toList();

      _filteredInstructors = query.isEmpty
          ? base
          : base.where((i) => (i['name'] as String).toLowerCase().contains(query)).toList();
      _showSuggestions = _instructorFocusNode.hasFocus;
      // If user cleared the field, also clear selection
      if (_instructorSearchController.text.isEmpty) {
        _selectedInstructorId = null;
        _selectedInstructorName = null;
      }
    });
  }

  void _selectInstructor(Map<String, dynamic> instructor) {
    setState(() {
      _selectedInstructorId = instructor['id'];
      _selectedInstructorName = instructor['name'];
      _instructorSearchController.text = instructor['name'];
      _showSuggestions = false;
      // Auto-fill department from the instructor's department if not already set
      final instrDeptId = instructor['departmentId']?.toString();
      if (instrDeptId != null && _selectedDepartmentId == null) {
        _selectedDepartmentId = instrDeptId;
      }
    });
    _instructorFocusNode.unfocus();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDepartmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a department'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    // instructor is optional — subject can be saved without one
    if (widget.currentTermId == null) {
      widget.onError('No active term set. Please configure a term first.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final code = _codeController.text.trim().toUpperCase();
      final name = _nameController.text.trim();

      // Step 1: Find or create the subject (always saves department_id)
      final existingSubject = await widget.supabase
          .from('subjects')
          .select('id')
          .eq('subject_code', code)
          .maybeSingle();

      String subjectId;
      if (existingSubject != null) {
        subjectId = existingSubject['id'].toString();
        // Update name and department in case they changed
        await widget.supabase
            .from('subjects')
            .update({
              'subject_name': name,
              'department_id': int.tryParse(_selectedDepartmentId!),
            })
            .eq('id', subjectId);
      } else {
        final insertResult = await widget.supabase
            .from('subjects')
            .insert({
              'subject_code': code,
              'subject_name': name,
              'department_id': int.tryParse(_selectedDepartmentId!),
            })
            .select('id')
            .single();
        subjectId = insertResult['id'].toString();
      }

      // Step 2: instructor_subjects — only when an instructor is selected.
      // instructor_id is NOT NULL in the DB, so we skip entirely if none chosen.
      if (_selectedInstructorId != null) {
        if (_editingAssignmentId != null) {
          await widget.supabase.from('instructor_subjects').update({
            'subject_id': subjectId,
            'instructor_id': _selectedInstructorId,
          }).eq('id', _editingAssignmentId!);
        } else {
          await widget.supabase.from('instructor_subjects').upsert({
            'subject_id': subjectId,
            'instructor_id': _selectedInstructorId,
            'term_id': widget.currentTermId,
          }, onConflict: 'subject_id,instructor_id,term_id');
        }
      }
      // If no instructor, the subject is saved/updated with no assignment row — that's fine.

      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      widget.onError('Error saving: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDec(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.primaryText),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error, width: 1)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _editingAssignmentId != null;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomPadding),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Handle bar ──
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // ── Header ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isEditing ? Icons.edit_rounded : Icons.add_circle_rounded,
                        color: AppColors.primaryText,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit Assignment' : 'Add Subject',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          isEditing ? 'Update subject details' : 'Assign a subject to an instructor',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Subject Code ──
                TextFormField(
                  controller: _codeController,
                  decoration: _inputDec('Subject Code *', Icons.code, hint: 'e.g. CS101'),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Subject code is required' : null,
                ),
                const SizedBox(height: 14),

                // ── Subject Name ──
                TextFormField(
                  controller: _nameController,
                  decoration: _inputDec('Subject Name *', Icons.menu_book, hint: 'e.g. Introduction to Programming'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Subject name is required' : null,
                ),
                const SizedBox(height: 14),

                // ── Department Dropdown (required) ──
                // Uses DropdownButtonFormField so it validates like a normal form field
                DropdownButtonFormField<String>(
                  value: _selectedDepartmentId,
                  isExpanded: true, // prevents RenderFlex overflow
                  decoration: _inputDec('Department *', Icons.business_rounded),
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  hint: const Text('Select department',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  icon: const Icon(Icons.expand_more_rounded,
                      color: AppColors.textSecondary),
                  items: widget.departments
                      .map((d) => DropdownMenuItem<String>(
                            value: d['id'],
                            child: Text(
                              d['name'],
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14),
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedDepartmentId = val;
                      // Clear instructor selection when department changes
                      // so the user picks from the correct department's list
                      _selectedInstructorId = null;
                      _selectedInstructorName = null;
                      _instructorSearchController.clear();
                      _showSuggestions = false;
                    });
                    _onInstructorSearch(); // re-filter to the new department
                  },
                  validator: (_) =>
                      _selectedDepartmentId == null ? 'Department is required' : null,
                ),
                const SizedBox(height: 14),

                // ── Instructor Typeahead (optional) ──
                // Selecting an instructor auto-fills the department if not set yet
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _instructorSearchController,
                      focusNode: _instructorFocusNode,
                      decoration: _inputDec(
                        'Assign Instructor (optional)',
                        Icons.person_search_rounded,
                        hint: _selectedDepartmentId == null
                            ? 'Select a department first...'
                            : 'Type to search instructor name...',
                      ).copyWith(
                        suffixIcon: _selectedInstructorId != null
                            ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                            : const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                      ),
                      onTap: () => setState(() => _showSuggestions = true),
                      validator: (_) => null, // optional — no validation needed
                    ),
                    // Suggestion dropdown
                    if (_showSuggestions && _filteredInstructors.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        clipBehavior: Clip.antiAlias,
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
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: _filteredInstructors.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 48),
                          itemBuilder: (_, i) {
                            final instr = _filteredInstructors[i];
                            final isSelected = instr['id'] == _selectedInstructorId;
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                child: Text(
                                  (instr['name'] as String).isNotEmpty
                                      ? (instr['name'] as String)[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                instr['name'],
                                style: TextStyle(
                                  color: isSelected ? AppColors.primaryText : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check, color: AppColors.primaryText, size: 18)
                                  : null,
                              onTap: () => _selectInstructor(instr),
                            );
                          },
                        ),
                      ),
                    if (_showSuggestions && _filteredInstructors.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(16),
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
                        child: const Row(
                          children: [
                            Icon(Icons.person_off_outlined, color: AppColors.textSecondary, size: 18),
                            SizedBox(width: 8),
                            Text('No matching instructors found',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Action Buttons ──
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.borderSubtle),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Pressable(
                        child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryDeep]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                              : Icon(isEditing ? Icons.save_rounded : Icons.check_rounded,
                                  color: AppColors.textPrimary),
                          label: Text(
                            _isSaving ? 'Saving...' : (isEditing ? 'Save Changes' : 'Assign Subject'),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            foregroundColor: AppColors.textPrimary,
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
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
}

// ════════════════════════════════════════════════════════════════════
// BULK IMPORT MODAL
// ════════════════════════════════════════════════════════════════════
class _BulkImportModal extends StatefulWidget {
  final String? currentTermId;
  final SupabaseClient supabase;
  final String n8nUrl;
  final VoidCallback onSuccess;
  final void Function(String) onError;

  const _BulkImportModal({
    required this.currentTermId,
    required this.supabase,
    required this.n8nUrl,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_BulkImportModal> createState() => _BulkImportModalState();
}

class _BulkImportModalState extends State<_BulkImportModal> {
  final _linkController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isImporting = false;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isImporting = true);
    try {
      final res = await http
          .post(
            Uri.parse(widget.n8nUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'link': _linkController.text.trim(),
              'term_id': widget.currentTermId ?? '',
              'user_id': widget.supabase.auth.currentUser?.id ?? '',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) Navigator.pop(context);
        widget.onSuccess();
      } else {
        widget.onError('Import failed: ${res.body}');
      }
    } catch (e) {
      widget.onError('Error: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomPadding),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.table_chart_rounded, color: AppColors.warning, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bulk Import', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 20)),
                      Text('Import subjects via Google Sheets', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Info box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Required columns: subject_code, subject_name, instructor_id (optional). Make sure the sheet is publicly accessible.',
                        style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Link field
              TextFormField(
                controller: _linkController,
                decoration: InputDecoration(
                  labelText: 'Google Sheet Link *',
                  hintText: 'https://docs.google.com/spreadsheets/...',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  prefixIcon: const Icon(Icons.link_rounded, color: AppColors.warning),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.warning, width: 1.5)),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error, width: 1)),
                  focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Please enter a Google Sheet link';
                  if (!v.contains('spreadsheets')) return 'Must be a valid Google Sheets URL';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.borderSubtle),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Pressable(
                      child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppColors.warning,
                          AppColors.warning.withValues(alpha: 0.85),
                        ]),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.warning.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isImporting ? null : _import,
                        icon: _isImporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_sync_rounded, color: Colors.white),
                        label: Text(
                          _isImporting ? 'Importing...' : 'Import via n8n',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),       // SingleChildScrollView
        ),       // Form
      ),         // AnimatedPadding
    );           // Container
  }
}

// ════════════════════════════════════════════════════════════════════
// SUBJECT DETAIL MODAL
// Shows all instructors assigned to a single subject this term.
// ════════════════════════════════════════════════════════════════════
class _SubjectDetailModal extends StatelessWidget {
  final Map<String, dynamic> subject;           // subject data directly
  final List<Map<String, dynamic>> assignments; // all assignments for ONE subject (may be empty)
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(String) onDelete;
  final VoidCallback onAddInstructor;

  const _SubjectDetailModal({
    required this.subject,
    required this.assignments,
    required this.onEdit,
    required this.onDelete,
    required this.onAddInstructor,
  });

  @override
  Widget build(BuildContext context) {
    // Use subject data passed directly (works even when assignments is empty)
    final subjectCode = subject['subject_code']?.toString() ?? '??';
    final subjectName = subject['subject_name']?.toString() ?? 'Unknown Subject';
    final deptInfo = subject['department_name'];
    final deptName = deptInfo is Map ? deptInfo['d_name']?.toString() : null;

    final assignedInstructors =
        assignments.where((a) => a['instructor_id'] != null).toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject avatar
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    subjectCode.length >= 2
                        ? subjectCode.substring(0, 2).toUpperCase()
                        : subjectCode.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectCode,
                        style: const TextStyle(
                            color: AppColors.primaryText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subjectName,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      if (deptName != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            deptName,
                            style: const TextStyle(
                                color: AppColors.primaryText,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section: Instructors header + Add button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.people_outline_rounded,
                    size: 16, color: AppColors.primaryText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Instructors This Term  (${assignedInstructors.length})',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                // ── Add Instructor button ──
                Pressable(
                  child: GestureDetector(
                  onTap: onAddInstructor,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add_rounded,
                            size: 14, color: AppColors.primaryText),
                        SizedBox(width: 5),
                        Text('Add Instructor',
                            style: TextStyle(
                                color: AppColors.primaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Instructor list — scrollable if many
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: assignedInstructors.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Row(
                      children: [
                        Icon(Icons.person_off_outlined,
                            color: AppColors.textSecondary.withValues(alpha: 0.5),
                            size: 20),
                        const SizedBox(width: 10),
                        const Text(
                          'No instructor assigned yet.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    itemCount: assignedInstructors.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final a = assignedInstructors[i];
                      final instrInfo = a['user_info'];
                      final instrName = instrInfo != null
                          ? '${instrInfo['first_name']} ${instrInfo['last_name']}'
                          : 'Unknown';
                      final initials = instrName
                          .split(' ')
                          .where((w) => w.isNotEmpty)
                          .take(2)
                          .map((w) => w[0].toUpperCase())
                          .join();

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primaryTint,
                          child: Text(
                            initials,
                            style: const TextStyle(
                                color: AppColors.primaryText,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ),
                        title: Text(
                          instrName,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Edit this assignment
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppColors.primaryText, size: 18),
                              onPressed: () => onEdit(a),
                              tooltip: 'Edit',
                              visualDensity: VisualDensity.compact,
                            ),
                            // Remove this assignment
                            IconButton(
                              icon: const Icon(Icons.person_remove_outlined,
                                  color: AppColors.error, size: 18),
                              onPressed: () =>
                                  onDelete(a['id'].toString()),
                              tooltip: 'Remove',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),


          const SizedBox(height: 20),

          // Close button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderSubtle),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text('Close',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
