// lib/gatherer/failed_scan_detail_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/config/env.dart';
import 'models/scan_task.dart';

class FailedScanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> scan;
  const FailedScanDetailScreen({super.key, required this.scan});

  @override
  State<FailedScanDetailScreen> createState() => _FailedScanDetailScreenState();
}

class _FailedScanDetailScreenState extends State<FailedScanDetailScreen> {
  final _supabase = Supabase.instance.client;

  // Local image (for zoom preview only)
  File? _localImageFile;
  bool _localImageAvailable = false;

  // Text field controllers
  late TextEditingController _instructorCtrl;
  late TextEditingController _subjectCtrl;
  late TextEditingController _remarksCtrl;
  late TextEditingController _studentIdCtrl;
  late Map<String, TextEditingController> _scoreCtrlMap;

  // Autocomplete — Instructor
  final FocusNode _instructorFocus = FocusNode();
  List<Map<String, dynamic>> _instructorSuggestions = [];
  String? _selectedInstructorId;
  Timer? _instructorDebounce;

  // Autocomplete — Subject
  final FocusNode _subjectFocus = FocusNode();
  List<Map<String, dynamic>> _subjectSuggestions = [];
  String? _selectedSubjectId;
  Timer? _subjectDebounce;

  // Submission
  bool _isSubmitting = false;

  static String get _n8nCorrectionUrl => Env.n8nManualCorrectionUrl;

  @override
  void initState() {
    super.initState();

    final partial =
        (widget.scan['partial_data'] is Map ? Map<String, dynamic>.from(widget.scan['partial_data'] as Map) : {});

    _instructorCtrl =
        TextEditingController(text: partial['instructor']?.toString() ?? '');
    _subjectCtrl =
        TextEditingController(text: partial['subject']?.toString() ?? '');
    _remarksCtrl =
        TextEditingController(text: partial['remarks']?.toString() ?? '');
    _studentIdCtrl =
        TextEditingController(text: partial['student_id']?.toString() ?? '');

    _scoreCtrlMap = {};
    final ratings = (partial['ratings'] is Map ? Map<String, dynamic>.from(partial['ratings'] as Map) : {}) as Map<String, dynamic>;
    final mgmt = (ratings['management'] is List ? ratings['management'] as List : []);
    final perf = (ratings['performance'] is List ? ratings['performance'] as List : []);
    for (int i = 0; i < 10; i++) {
      final mScore = (i < mgmt.length && mgmt[i]['detected'] == true)
          ? mgmt[i]['score']?.toString() ?? ''
          : '';
      final pScore = (i < perf.length && perf[i]['detected'] == true)
          ? perf[i]['score']?.toString() ?? ''
          : '';
      _scoreCtrlMap['m${i + 1}'] = TextEditingController(text: mScore);
      _scoreCtrlMap['p${i + 1}'] = TextEditingController(text: pScore);
    }

    // Hide suggestions when focus leaves the field
    _instructorFocus.addListener(() {
      if (!_instructorFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _instructorSuggestions = []);
        });
      }
    });
    _subjectFocus.addListener(() {
      if (!_subjectFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _subjectSuggestions = []);
        });
      }
    });

    _findLocalImage();
  }

  @override
  void dispose() {
    _instructorFocus.dispose();
    _subjectFocus.dispose();
    _instructorCtrl.dispose();
    _subjectCtrl.dispose();
    _remarksCtrl.dispose();
    _studentIdCtrl.dispose();
    _instructorDebounce?.cancel();
    _subjectDebounce?.cancel();
    for (final c in _scoreCtrlMap.values) c.dispose();
    super.dispose();
  }

  // ── Find local image for zoom preview ──────────────────────────────────────

  Future<void> _findLocalImage() async {
    final taskId = widget.scan['task_id']?.toString() ?? '';
    if (taskId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('gatherer_sync_queue') ?? [];
      for (final s in raw) {
        final map = jsonDecode(s) as Map<String, dynamic>;
        final task = ScanTask.fromMap(map);
        if (task.id == taskId) {
          final f = File(task.localPath);
          if (await f.exists()) {
            if (mounted) setState(() { _localImageFile = f; _localImageAvailable = true; });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('findLocalImage error: $e');
    }
  }

  // ── Autocomplete — Instructor ───────────────────────────────────────────────

  void _onInstructorChanged(String query) {
    _selectedInstructorId = null; // user is editing — clear confirmed selection
    _instructorDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _instructorSuggestions = []);
      return;
    }
    _instructorDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchInstructors(query.trim());
    });
  }

  Future<void> _searchInstructors(String query) async {
    try {
      final results = await _supabase
          .from('user_info')
          .select('id, first_name, last_name')
          .or('first_name.ilike.%$query%,last_name.ilike.%$query%')
          .limit(6);
      if (mounted) {
        setState(() {
          _instructorSuggestions =
              List<Map<String, dynamic>>.from(results as List);
        });
      }
    } catch (e) {
      debugPrint('Instructor search error: $e');
    }
  }

  void _selectInstructor(Map<String, dynamic> item) {
    final name =
        '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim();
    setState(() {
      _instructorCtrl.text = name;
      _selectedInstructorId = item['id']?.toString();
      _instructorSuggestions = [];
    });
    _instructorFocus.unfocus();
  }

  // ── Autocomplete — Subject ─────────────────────────────────────────────────

  void _onSubjectChanged(String query) {
    _selectedSubjectId = null;
    _subjectDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _subjectSuggestions = []);
      return;
    }
    _subjectDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchSubjects(query.trim());
    });
  }

  Future<void> _searchSubjects(String query) async {
    try {
      final results = await _supabase
          .from('subjects')
          .select('id, subject_code, subject_name')
          .or('subject_code.ilike.%$query%,subject_name.ilike.%$query%')
          .limit(6);
      if (mounted) {
        setState(() {
          _subjectSuggestions =
              List<Map<String, dynamic>>.from(results as List);
        });
      }
    } catch (e) {
      debugPrint('Subject search error: $e');
    }
  }

  void _selectSubject(Map<String, dynamic> item) {
    final display =
        '${item['subject_code'] ?? ''} — ${item['subject_name'] ?? ''}'.trim();
    setState(() {
      _subjectCtrl.text = display;
      _selectedSubjectId = item['id']?.toString();
      _subjectSuggestions = [];
    });
    _subjectFocus.unfocus();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final scores = <String, int>{};
      for (int i = 1; i <= 10; i++) {
        scores['m$i'] = int.tryParse(_scoreCtrlMap['m$i']?.text ?? '') ?? 0;
        scores['p$i'] = int.tryParse(_scoreCtrlMap['p$i']?.text ?? '') ?? 0;
      }

      final payload = <String, dynamic>{
        'failed_scan_id':   widget.scan['id'],
        'task_id':          widget.scan['task_id'],
        'user_id':          widget.scan['user_id'],
        'term_id':          widget.scan['term_id'],
        'instructor':       _instructorCtrl.text.trim(),
        'instructor_id':    _selectedInstructorId,
        'subject':          _subjectCtrl.text.trim(),
        'subject_id':       _selectedSubjectId,
        'remarks':          _remarksCtrl.text.trim(),
        'student_id':       _studentIdCtrl.text.trim(),
        ...scores,
        'manually_corrected':  true,
        'validation_status':   'corrected',
        'correction_source':   'manual_text',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse(_n8nCorrectionUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Submitted! n8n is processing the correction.'),
            backgroundColor: AppColors.success,
          ));
          Navigator.pop(context);
        }
      } else {
        throw Exception('n8n returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error submitting: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Discard ────────────────────────────────────────────────────────────────

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Discard Scan?',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
            'This will permanently remove this failed scan record. Are you sure?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _supabase
          .from('failed_scan_queue')
          .update({'status': 'discarded'}).eq('id', widget.scan['id']);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Scan discarded.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final taskId = widget.scan['task_id']?.toString() ?? 'Unknown';
    final tableFound = widget.scan['table_found'] == true;
    final gridSource = widget.scan['grid_source']?.toString() ?? 'fallback';

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Correct Failed Scan',
                style: TextStyle(
                    color: AppColors.surface,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            Text(taskId,
                style: const TextStyle(
                    color: AppColors.textInvertedDim, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
            label: const Text('Discard',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
            onPressed: _discard,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFailureBanner(tableFound, gridSource),
          _buildImagesRow(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fill in or correct the fields below. Tap a suggestion to auto-fill.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Instructor with autocomplete
                  _buildInstructorField(),

                  // Subject with autocomplete
                  _buildSubjectField(),

                  // Other fields
                  _buildSimpleField('Remarks & Suggestions', _remarksCtrl,
                      maxLines: 3),
                  _buildSimpleField('Student ID', _studentIdCtrl,
                      keyboardType: TextInputType.number, digitsOnly: true),

                  const SizedBox(height: 24),

                  // Management scores
                  _buildScoreSection('Management Scores (M1–M10)', 'm'),
                  const SizedBox(height: 20),

                  // Performance scores
                  _buildScoreSection('Performance Scores (P1–P10)', 'p'),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildSubmitBar(),
        ],
      ),
    );
  }

  // ── Failure banner ─────────────────────────────────────────────────────────

  Widget _buildFailureBanner(bool tableFound, String gridSource) {
    final color = tableFound ? AppColors.warning : AppColors.error;
    final msg = tableFound
        ? 'Grid lines not detected — fallback grid was used. Scores may be wrong.'
        : 'Table/corners NOT found — OCR used a proportional crop estimate. All data needs verification.';
    final icon = tableFound ? Icons.grid_off_rounded : Icons.crop_free;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ── Images row (zoom only, no crop) ───────────────────────────────────────

  Widget _buildImagesRow() {
    if (!_localImageAvailable || _localImageFile == null) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: GestureDetector(
        onTap: () => _showZoomedImage(
          Image.file(_localImageFile!, fit: BoxFit.contain),
          'Original Scan',
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                _localImageFile!,
                width: double.infinity,
                height: 110,
                fit: BoxFit.cover,
              ),
            ),
            Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_in, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Tap to zoom',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageCard(
      {required String label,
      required Widget child,
      VoidCallback? onTap}) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: onTap != null
              ? GestureDetector(
                  onTap: onTap,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      child,
                      Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.zoom_in,
                            color: Colors.white, size: 14),
                      ),
                    ],
                  ),
                )
              : child,
        ),
      ],
    );
  }

  void _showZoomedImage(Image image, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 8.0,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), child: image),
            ),
            Positioned(
              top: 0, right: 0,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12)),
                ),
                child: Text('$title  •  Pinch to zoom',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder(String label) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                color: AppColors.textTertiary, size: 28),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Autocomplete fields ────────────────────────────────────────────────────

  Widget _buildInstructorField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _instructorCtrl,
          focusNode: _instructorFocus,
          onChanged: _onInstructorChanged,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Instructor Name',
            prefix: Icons.person_outline,
            suffix: _selectedInstructorId != null
                ? const Icon(Icons.check_circle,
                    color: AppColors.success, size: 18)
                : null,
          ),
        ),
        if (_instructorSuggestions.isNotEmpty)
          _buildSuggestionCard(
            _instructorSuggestions,
            itemBuilder: (item) => Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _initials(item['first_name'], item['last_name']),
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim(),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                ),
              ],
            ),
            onTap: _selectInstructor,
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildSubjectField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _subjectCtrl,
          focusNode: _subjectFocus,
          onChanged: _onSubjectChanged,
          textCapitalization: TextCapitalization.characters,
          decoration: _inputDecoration(
            label: 'Subject / Course Code',
            prefix: Icons.book_outlined,
            suffix: _selectedSubjectId != null
                ? const Icon(Icons.check_circle,
                    color: AppColors.success, size: 18)
                : null,
          ),
        ),
        if (_subjectSuggestions.isNotEmpty)
          _buildSuggestionCard(
            _subjectSuggestions,
            itemBuilder: (item) => Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item['subject_code']?.toString() ?? '',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item['subject_name']?.toString() ?? '',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onTap: _selectSubject,
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildSuggestionCard(
    List<Map<String, dynamic>> items, {
    required Widget Function(Map<String, dynamic>) itemBuilder,
    required void Function(Map<String, dynamic>) onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1;
            return InkWell(
              onTap: () => onTap(entry.value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                              color: AppColors.borderSubtle, width: 0.8)),
                ),
                child: itemBuilder(entry.value),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Simple fields ──────────────────────────────────────────────────────────

  Widget _buildSimpleField(String label, TextEditingController ctrl,
      {int maxLines = 1,
      TextInputType keyboardType = TextInputType.text,
      bool digitsOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters:
            digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: _inputDecoration(label: label),
      ),
    );
  }

  InputDecoration _inputDecoration(
      {required String label, IconData? prefix, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefix != null ? Icon(prefix, size: 18) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  // ── Score grids ────────────────────────────────────────────────────────────

  Widget _buildScoreSection(String title, String prefix) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            childAspectRatio: 1.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: 10,
          itemBuilder: (context, index) {
            final key = '$prefix${index + 1}';
            return TextField(
              controller: _scoreCtrlMap[key],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: key.toUpperCase(),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: EdgeInsets.zero,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            );
          },
        ),
      ],
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────

  Widget _buildSubmitBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.cloud_upload_outlined, size: 20),
          label: Text(
            _isSubmitting ? 'Submitting…' : 'Submit & Validate',
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _isSubmitting ? null : _submit,
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _initials(dynamic firstName, dynamic lastName) {
    final f = firstName?.toString() ?? '';
    final l = lastName?.toString() ?? '';
    return '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}'
        .toUpperCase();
  }
}
