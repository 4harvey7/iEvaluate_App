// lib/sao_admin/manage_subjects_screen.dart
// This screen is for managing subject assignments — who teaches what, this term.
// Two ways to add: bulk import from Google Sheets (via n8n), or one-by-one manually.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/config/env.dart';
import '../core/services/system_settings_service.dart';
import '../widgets/safe_button.dart';

// outer widget — just holds the state, nothing interesting yet
class ManageSubjectsScreen extends StatefulWidget {
  const ManageSubjectsScreen({super.key});

  @override
  State<ManageSubjectsScreen> createState() => _ManageSubjectsScreenState();
}

class _ManageSubjectsScreenState extends State<ManageSubjectsScreen> {
  final _supabase = Supabase.instance.client; // the almighty database connection
  final _settingsService = SystemSettingsService(); // needed to get current term ID

  // Bulk import — for when admin too lazy to enter subjects one by one (valid choice)
  final _bulkImportController = TextEditingController(); // text field for Google Sheet link
  bool _isBulkImporting = false; // true while n8n is processing the sheet

  // Individual subject assignment form — one at a time, manual entry
  final _subjectCodeController = TextEditingController(); // e.g. "CS101"
  final _subjectNameController = TextEditingController(); // e.g. "Intro to Computer Science"
  String? _selectedInstructorId; // who will teach this subject
  String? _editingAssignmentId; // ID of the instructor_subjects row being edited — null if adding new

  // Data
  List<Map<String, dynamic>> _instructors = []; // all instructors available for dropdown
  List<Map<String, dynamic>> _assignments = []; // joined instructor_subjects + subjects + user_info
  String? _currentTermId; // UUID of active term — all assignments scoped to this
  String _currentTermLabel = '...'; // human-readable label shown in appbar
  bool _isLoading = true; // loading flag for the whole page
  bool _isSaving = false; // true while saving an assignment

  // the n8n webhook URL for bulk import — defined in env config
  static String get _n8nBulkImportUrl => Env.n8nSubjectBulkImportUrl;

  // called once when screen opens
  @override
  void initState() {
    super.initState();
    _loadData(); // fetch instructors and assignments
  }

  // clean up text controllers when screen is destroyed — memory leak prevention, importente
  @override
  void dispose() {
    _bulkImportController.dispose();
    _subjectCodeController.dispose();
    _subjectNameController.dispose();
    super.dispose();
  }

  // loads the active term, all instructors, and all subject assignments for this term
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // get current active term settings first — we need the term ID for queries
      final settings = await _settingsService.getSettings();
      _currentTermId = settings.termId;
      _currentTermLabel = '${settings.semester} ${settings.academicYear}'; // e.g. "1st Sem 2025-2026"

      // Load instructors from department_table — only academic users
      final instRes = await _supabase
          .from('department_table')
          .select('user_id, user_info!user_id(first_name, last_name)')
          .not('user_id', 'is', null); // skip rows with no user attached, wala silbi

      // Load assignments for current term via instructor_subjects junction table
      // only load if we have a term — otherwise empty list
      List<Map<String, dynamic>> assignmentsRes = [];
      if (_currentTermId != null) {
        final res = await _supabase
            .from('instructor_subjects')
            .select('id, subject_id, instructor_id, term_id, subjects(id, subject_code, subject_name, department_id), user_info!instructor_id(first_name, last_name)')
            .eq('term_id', _currentTermId!) // only this term's assignments
            .order('created_at', ascending: false); // newest first
        assignmentsRes = List<Map<String, dynamic>>.from(res as List);
      }

      if (mounted) {
        setState(() {
          // map to id+name for dropdown — only include ones with valid user_info
          _instructors = (instRes as List)
              .where((i) => i['user_info'] != null)
              .map((i) => {
                    'id': i['user_id'],
                    'name': '${i['user_info']['first_name']} ${i['user_info']['last_name']}',
                  })
              .toList();
          _assignments = assignmentsRes;
          _isLoading = false; // done loading
        });
      }
    } catch (e) {
      debugPrint('ManageSubjects load error: $e');
      if (mounted) setState(() => _isLoading = false); // stop spinner even on error
    }
  }

  // ── Bulk Import via n8n ───────────────────────────────────────
  // admin pastes a Google Sheet link, we send it to n8n which processes and inserts subjects
  // much faster than entering one by one — this is the smart lazy approach
  Future<void> _triggerBulkImport() async {
    final link = _bulkImportController.text.trim();
    // basic validation — must have something and must look like a spreadsheet link
    if (link.isEmpty || !link.contains('spreadsheets')) {
      _showSnack('Please enter a valid Google Sheet link', isError: true);
      return;
    }
    setState(() => _isBulkImporting = true); // show loading on the button
    try {
      // POST to n8n webhook with the link and current context
      final res = await http
          .post(
            Uri.parse(_n8nBulkImportUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'link': link, // the Google Sheet URL
              'term_id': _currentTermId ?? '', // so n8n knows which term to assign to
              'user_id': _supabase.auth.currentUser?.id ?? '', // for tracking who triggered this
            }),
          )
          .timeout(const Duration(seconds: 30)); // 30 sec timeout, if n8n slower than this we have a problem

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _showSnack('Subjects imported successfully!'); // celebrate
        _bulkImportController.clear(); // clear the link field after success
        _loadData(); // reload list to show the new subjects
      } else {
        _showSnack('Import failed: ${res.body}', isError: true); // server said no
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true); // network error, timeout, etc.
    } finally {
      if (mounted) setState(() => _isBulkImporting = false); // always stop the spinner
    }
  }

  // ── Save individual subject assignment ────────────────────────
  // In the new 2NF schema:
  //   1. Upsert the subject into 'subjects' (by code+dept, if already exists just get its id)
  //   2. Upsert the assignment into 'instructor_subjects' (subject+instructor+term)
  // This function handles both creating new and editing existing assignments
  Future<void> _saveAssignment() async {
    final code = _subjectCodeController.text.trim().toUpperCase(); // force uppercase for consistency
    final name = _subjectNameController.text.trim();

    // basic validation — code and name are required, instructor is optional
    if (code.isEmpty || name.isEmpty) {
      _showSnack('Subject Code and Name are required', isError: true);
      return;
    }
    if (_currentTermId == null) {
      // cannot assign a subject if there is no active term set
      _showSnack('No active term set. Please configure a term first.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Step 1: Find or create the subject (upsert by subject_code)
      // We use upsert with ignoreDuplicates=false to get back the id
      final existingSubject = await _supabase
          .from('subjects')
          .select('id')
          .eq('subject_code', code)
          .maybeSingle();

      String subjectId;
      if (existingSubject != null) {
        // Subject already exists — update name if changed, but keep the same ID
        subjectId = existingSubject['id'].toString();
        await _supabase
            .from('subjects')
            .update({'subject_name': name}) // update name in case it changed
            .eq('id', subjectId);
      } else {
        // Insert new subject — brand new code, never seen before
        final insertResult = await _supabase
            .from('subjects')
            .insert({'subject_code': code, 'subject_name': name})
            .select('id')
            .single();
        subjectId = insertResult['id'].toString();
      }

      // Step 2: Create or update the instructor_subjects assignment
      if (_editingAssignmentId != null) {
        // Editing an existing assignment row — just update subject and instructor
        await _supabase.from('instructor_subjects').update({
          'subject_id': subjectId,
          'instructor_id': _selectedInstructorId, // can be null if removing instructor
        }).eq('id', _editingAssignmentId!); // target the specific assignment row
        _showSnack('Assignment updated successfully');
      } else {
        // New assignment — upsert to handle duplicate gracefully
        // if same subject+instructor+term already exists, do nothing — dili ta crash
        await _supabase.from('instructor_subjects').upsert({
          'subject_id': subjectId,
          'instructor_id': _selectedInstructorId,
          'term_id': _currentTermId, // always scoped to current term
        }, onConflict: 'subject_id,instructor_id,term_id'); // conflict resolution key
        _showSnack('Subject assigned successfully');
      }

      _clearForm(); // reset form fields after save
      _loadData(); // reload the assignments list
    } catch (e) {
      _showSnack('Error saving assignment: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false); // stop spinner always
    }
  }

  // populate the form fields with an existing assignment's data for editing
  // also scrolls to the form so admin can see it without manually scrolling
  void _startEdit(Map<String, dynamic> assignment) {
    // subject data can be a Map or List depending on how Supabase returned it
    final subjectData = assignment['subjects'];
    final subject = subjectData is Map ? subjectData : (subjectData is List && (subjectData as List).isNotEmpty ? subjectData[0] : null);

    setState(() {
      _editingAssignmentId = assignment['id'].toString(); // mark as "editing" mode
      _subjectCodeController.text = subject?['subject_code'] ?? ''; // fill in code
      _subjectNameController.text = subject?['subject_name'] ?? ''; // fill in name
      _selectedInstructorId = assignment['instructor_id']; // pre-select instructor
    });
    // scroll up to the form so admin doesn't have to scroll manually — convenience feature
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // clear all form fields and exit edit mode — basically reset the form to blank
  void _clearForm() {
    setState(() {
      _editingAssignmentId = null; // exit edit mode, back to "add new" mode
      _subjectCodeController.clear();
      _subjectNameController.clear();
      _selectedInstructorId = null; // deselect instructor
    });
  }

  // Delete removes ONLY the instructor_subjects assignment row,
  // NOT the subject itself (preserves it for other terms/instructors)
  // This is importente — we dili want to delete subjects that other terms might reference
  Future<void> _deleteAssignment(String assignmentId) async {
    // ask admin to confirm before deleting — ayaw accidental delete
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Assignment'),
        content: const Text('Remove this instructor from this subject for the current term? The subject will remain available for other terms.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true), // confirmed — proceed with delete
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return; // admin changed mind, skip
    try {
      await _supabase.from('instructor_subjects').delete().eq('id', assignmentId); // delete only the assignment row
      _showSnack('Assignment removed');
      _loadData(); // reload to reflect removal
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  // utility to show a success or error snackbar — used everywhere
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return; // screen gone, skip
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
    ));
  }

  // the main build — shows loading spinner or the scrollable content
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        // shows both the screen title and the current term — so admin knows what term they managing
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Subject Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(_currentTermLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12), overflow: TextOverflow.ellipsis), // current term as subtitle
          ],
        ),
        actions: [
          SafeIconButton(icon: const Icon(Icons.refresh, color: AppColors.primary), onPressed: _loadData), // manual refresh
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData, // pull to refresh
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Section A: Bulk Import ──────────────────────────
                    // paste a Google Sheet link, press import — the easy way
                    _buildSectionHeader('Bulk Import via Google Sheets', Icons.table_chart_outlined),
                    const SizedBox(height: 12),
                    _buildBulkImportCard(),
                    const SizedBox(height: 32),

                    // ── Section B: Add / Edit Assignment ────────
                    // manual form for adding or editing one assignment at a time
                    _buildSectionHeader(
                      _editingAssignmentId != null ? 'Edit Assignment' : 'Add Subject Assignment', // title changes in edit mode
                      _editingAssignmentId != null ? Icons.edit : Icons.add_circle_outline,
                    ),
                    const SizedBox(height: 12),
                    _buildAssignmentCard(),
                    const SizedBox(height: 32),

                    // ── Section C: Current Assignments List ───────────────
                    // shows all assignments for this term with edit/remove options
                    _buildSectionHeader('Assignments This Term (${_assignments.length})', Icons.list_alt_rounded),
                    const SizedBox(height: 12),
                    _buildAssignmentsList(),
                  ],
                ),
              ),
            ),
    );
  }

  // section header with icon and bold text — used three times above
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 22), // icon on the left
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  // the bulk import card — text field for Google Sheet link + import button
  Widget _buildBulkImportCard() {
    return Card(
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // instructions text — what columns the sheet must have
            Text(
              'Paste your Google Sheet link. Required columns: subject_code, subject_name, instructor_id (optional)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            // text field for the Google Sheet URL
            TextFormField(
              controller: _bulkImportController,
              decoration: _inputDecoration('Google Sheet Link', Icons.link),
            ),
            const SizedBox(height: 16),
            // import button — disabled while importing, shows spinner
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isBulkImporting ? null : _triggerBulkImport, // disabled during import
                icon: _isBulkImporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_sync, color: Colors.white),
                label: Text(_isBulkImporting ? 'Importing...' : 'Import via n8n', // label changes while importing
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // the manual assignment form card — subject code, name, instructor dropdown
  Widget _buildAssignmentCard() {
    return Card(
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextFormField(controller: _subjectCodeController, decoration: _inputDecoration('Subject Code *', Icons.code)), // required
            const SizedBox(height: 14),
            TextFormField(controller: _subjectNameController, decoration: _inputDecoration('Subject Name *', Icons.menu_book)), // required
            const SizedBox(height: 14),
            // instructor dropdown — optional, can assign without instructor for now
            DropdownButtonFormField<String>(
              value: _selectedInstructorId,
              isExpanded: true,
              decoration: _inputDecoration('Assign Instructor (optional)', Icons.person_outline),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('— No instructor —')), // no instructor option
                ..._instructors.map((i) => DropdownMenuItem<String>(
                  value: i['id'],
                  child: Text(i['name'], overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (val) => setState(() => _selectedInstructorId = val),
            ),
            const SizedBox(height: 20),
            // buttons: Cancel (in edit mode only) + Save/Assign
            Row(
              children: [
                if (_editingAssignmentId != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearForm, // cancel editing, go back to add mode
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.textSecondary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                if (_editingAssignmentId != null) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAssignment, // disabled while saving
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_editingAssignmentId != null ? Icons.save : Icons.add, color: Colors.white),
                    label: Text(_editingAssignmentId != null ? 'Save Changes' : 'Assign Subject', // label changes in edit mode
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // list of all current term assignments — each row shows subject, instructor, edit/remove buttons
  Widget _buildAssignmentsList() {
    if (_assignments.isEmpty) {
      // empty state — nothing assigned this term yet
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(Icons.library_books_outlined, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)), // faded book icon
              const SizedBox(height: 12),
              const Text('No subject assignments for this term yet.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    // the list of assignment cards
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // dili scroll inside scroll
      itemCount: _assignments.length,
      itemBuilder: (context, index) {
        final a = _assignments[index];
        // subject data can be Map or List depending on how Supabase returns it
        final subjectData = a['subjects'];
        final subject = subjectData is Map
            ? subjectData
            : (subjectData is List && (subjectData as List).isNotEmpty ? subjectData[0] : null);
        final instrInfo = a['user_info'];
        // show instructor name or fallback if no instructor assigned
        final instrName = instrInfo != null
            ? '${instrInfo['first_name']} ${instrInfo['last_name']}'
            : 'No Instructor';
        final subjectCode = subject?['subject_code']?.toString() ?? '??'; // fallback if code missing
        final subjectName = subject?['subject_name']?.toString() ?? 'Unknown Subject';

        return Card(
          color: AppColors.surface,
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            // avatar shows first 2 chars of subject code
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(
                subjectCode.length >= 2 ? subjectCode.substring(0, 2).toUpperCase() : subjectCode.toUpperCase(),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            title: Text('$subjectCode — $subjectName', // code dash name format
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
            subtitle: Text(instrName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis), // who teaches it
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                  onPressed: () => _startEdit(a), // populate form with this assignment's data
                  tooltip: 'Edit',
                ),
                SafeIconButton(
                  icon: const Icon(Icons.person_remove_outlined, color: AppColors.error, size: 20),
                  onPressed: () => _deleteAssignment(a['id'].toString()), // remove only the assignment, not the subject
                  tooltip: 'Remove Assignment',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // reusable input decoration for all text fields — consistent style throughout
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.primary), // colored icon on left
      filled: true,
      fillColor: AppColors.background.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), // no default border
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)), // primary color border when focused
    );
  }
}
