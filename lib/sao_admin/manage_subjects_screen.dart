// lib/sao_admin/manage_subjects_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/config/env.dart';
import '../core/services/system_settings_service.dart';

class ManageSubjectsScreen extends StatefulWidget {
  const ManageSubjectsScreen({super.key});

  @override
  State<ManageSubjectsScreen> createState() => _ManageSubjectsScreenState();
}

class _ManageSubjectsScreenState extends State<ManageSubjectsScreen> {
  final _supabase = Supabase.instance.client;
  final _settingsService = SystemSettingsService();

  // Bulk import
  final _bulkImportController = TextEditingController();
  bool _isBulkImporting = false;

  // Individual subject form
  final _subjectCodeController = TextEditingController();
  final _subjectNameController = TextEditingController();
  final _sectionController = TextEditingController();
  String? _selectedInstructorId;
  String? _editingSubjectId; // non-null = edit mode

  // Data
  List<Map<String, dynamic>> _instructors = [];
  List<Map<String, dynamic>> _subjects = [];
  String? _currentTermId;
  String _currentTermLabel = '...';
  bool _isLoading = true;
  bool _isSaving = false;

  static String get _n8nBulkImportUrl => Env.n8nSubjectBulkImportUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _bulkImportController.dispose();
    _subjectCodeController.dispose();
    _subjectNameController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _settingsService.getSettings();
      _currentTermId = settings.termId;
      _currentTermLabel = '${settings.semester} ${settings.academicYear}';

      // Load instructors from department_table
      final instRes = await _supabase
          .from('department_table')
          .select('user_id, user_info!user_id(first_name, last_name)')
          .not('user_id', 'is', null);

      // Load subjects for current term
      var subQuery = _supabase
          .from('subjects')
          .select('id, subject_code, subject_name, section, instructor_id, user_info!instructor_id(first_name, last_name)');
      if (_currentTermId != null) {
        subQuery = subQuery.eq('term_id', _currentTermId!);
      }
      final subRes = await subQuery.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _instructors = (instRes as List)
              .where((i) => i['user_info'] != null)
              .map((i) => {
                    'id': i['user_id'],
                    'name': '${i['user_info']['first_name']} ${i['user_info']['last_name']}',
                  })
              .toList();
          _subjects = List<Map<String, dynamic>>.from(subRes as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ManageSubjects load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Bulk Import via n8n ───────────────────────────────────────
  Future<void> _triggerBulkImport() async {
    final link = _bulkImportController.text.trim();
    if (link.isEmpty || !link.contains('spreadsheets')) {
      _showSnack('Please enter a valid Google Sheet link', isError: true);
      return;
    }
    setState(() => _isBulkImporting = true);
    try {
      final res = await http
          .post(
            Uri.parse(_n8nBulkImportUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'link': link,
              'term_id': _currentTermId ?? '',
              'user_id': _supabase.auth.currentUser?.id ?? '',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _showSnack('✅ Subjects imported successfully!');
        _bulkImportController.clear();
        _loadData();
      } else {
        _showSnack('Import failed: ${res.body}', isError: true);
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBulkImporting = false);
    }
  }

  // ── Save individual subject ───────────────────────────────────
  Future<void> _saveSubject() async {
    final code = _subjectCodeController.text.trim();
    final name = _subjectNameController.text.trim();
    final section = _sectionController.text.trim();

    if (code.isEmpty || name.isEmpty) {
      _showSnack('Subject Code and Name are required', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final data = {
        'subject_code': code,
        'subject_name': name,
        'section': section,
        'instructor_id': _selectedInstructorId,
        'term_id': _currentTermId,
      };

      if (_editingSubjectId != null) {
        await _supabase.from('subjects').update(data).eq('id', _editingSubjectId!);
        _showSnack('Subject updated successfully');
      } else {
        await _supabase.from('subjects').insert(data);
        _showSnack('Subject added successfully');
      }

      _clearForm();
      _loadData();
    } catch (e) {
      _showSnack('Error saving subject: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _startEdit(Map<String, dynamic> subject) {
    setState(() {
      _editingSubjectId = subject['id'].toString();
      _subjectCodeController.text = subject['subject_code'] ?? '';
      _subjectNameController.text = subject['subject_name'] ?? '';
      _sectionController.text = subject['section'] ?? '';
      _selectedInstructorId = subject['instructor_id'];
    });
    // Scroll to form
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _clearForm() {
    setState(() {
      _editingSubjectId = null;
      _subjectCodeController.clear();
      _subjectNameController.clear();
      _sectionController.clear();
      _selectedInstructorId = null;
    });
  }

  Future<void> _deleteSubject(String subjectId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Subject'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _supabase.from('subjects').delete().eq('id', subjectId);
      _showSnack('Subject deleted');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Subject Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(_currentTermLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.primary), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section A: Bulk Import ──────────────────────────
                  _buildSectionHeader('Bulk Import via Google Sheets', Icons.table_chart_outlined),
                  const SizedBox(height: 12),
                  _buildBulkImportCard(),
                  const SizedBox(height: 32),

                  // ── Section B: Add / Edit Individual Subject ────────
                  _buildSectionHeader(
                    _editingSubjectId != null ? 'Edit Subject' : 'Add Individual Subject',
                    _editingSubjectId != null ? Icons.edit : Icons.add_circle_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildIndividualCard(),
                  const SizedBox(height: 32),

                  // ── Section C: Current Subjects List ───────────────
                  _buildSectionHeader('Subjects This Term (${_subjects.length})', Icons.list_alt_rounded),
                  const SizedBox(height: 12),
                  _buildSubjectsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

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
            Text(
              'Paste your Google Sheet link. Required columns: subject_code, subject_name, section, instructor_id (optional)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bulkImportController,
              decoration: _inputDecoration('Google Sheet Link', Icons.link),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isBulkImporting ? null : _triggerBulkImport,
                icon: _isBulkImporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_sync, color: Colors.white),
                label: Text(_isBulkImporting ? 'Importing...' : 'Import via n8n',
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

  Widget _buildIndividualCard() {
    return Card(
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextFormField(controller: _subjectCodeController, decoration: _inputDecoration('Subject Code *', Icons.code)),
            const SizedBox(height: 14),
            TextFormField(controller: _subjectNameController, decoration: _inputDecoration('Subject Name *', Icons.menu_book)),
            const SizedBox(height: 14),
            TextFormField(controller: _sectionController, decoration: _inputDecoration('Section', Icons.group)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedInstructorId,
              isExpanded: true,
              decoration: _inputDecoration('Assign Instructor (optional)', Icons.person_outline),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('— No instructor —')),
                ..._instructors.map((i) => DropdownMenuItem<String>(
                  value: i['id'],
                  child: Text(i['name'], overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (val) => setState(() => _selectedInstructorId = val),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_editingSubjectId != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearForm,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.textSecondary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                if (_editingSubjectId != null) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveSubject,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_editingSubjectId != null ? Icons.save : Icons.add, color: Colors.white),
                    label: Text(_editingSubjectId != null ? 'Save Changes' : 'Add Subject',
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

  Widget _buildSubjectsList() {
    if (_subjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(Icons.library_books_outlined, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              const Text('No subjects for this term yet.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _subjects.length,
      itemBuilder: (context, index) {
        final s = _subjects[index];
        final instrInfo = s['user_info'];
        final instrName = instrInfo != null
            ? '${instrInfo['first_name']} ${instrInfo['last_name']}'
            : 'No Instructor';

        return Card(
          color: AppColors.surface,
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(
                (s['subject_code'] ?? '??').toString().length >= 2 ? (s['subject_code'] ?? '??').toString().substring(0, 2).toUpperCase() : (s['subject_code'] ?? '??').toString().toUpperCase(),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            title: Text('${s['subject_code']} — ${s['subject_name']}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((s['section'] ?? '').isNotEmpty)
                  Text('Section ${s['section']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                Text(instrName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                  onPressed: () => _startEdit(s),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                  onPressed: () => _deleteSubject(s['id'].toString()),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.primary),
      filled: true,
      fillColor: AppColors.background.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
    );
  }
}
