// lib/gatherer/failed_scan_detail_screen.dart
// Manual correction screen for scans flagged during OCR/OMR processing.
// UI aligned with ImportErrorDetailScreen for a clean, consistent experience.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/automation_service.dart';
import '../core/services/scan_image_service.dart';
import '../theme/app_colors.dart';
import 'services/correction_pickers.dart';
import 'services/stamp.dart';

class FailedScanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> scan; // the failed scan record from Supabase
  const FailedScanDetailScreen({super.key, required this.scan});

  @override
  State<FailedScanDetailScreen> createState() => _FailedScanDetailScreenState();
}

class _FailedScanDetailScreenState extends State<FailedScanDetailScreen> {
  final _supabase = Supabase.instance.client;

  // ── Scanned Image ─────────────────────────────────────────────────────────
  Uint8List? _imageBytes;
  bool _isLoadingImage = false;

  // ── Form Controllers ──────────────────────────────────────────────────────
  late TextEditingController _instructorCtrl;
  late TextEditingController _subjectCtrl;
  late TextEditingController _remarksCtrl;
  late TextEditingController _studentIdCtrl;

  // 20 score controllers: m1-m10 and p1-p10
  final Map<String, TextEditingController> _scoreCtrlMap = {};

  // ── Pickers: Instructor + Subject ─────────────────────────────────────────
  // Backed by the people a form can be credited to (approved instructors and
  // placeholders) and the subjects, loaded once. Pre-selected from the AI's
  // suggestion or a clear match of the scan text, so staff usually only check
  // them. The ids are what n8n credits; without them the scan used to end up
  // in Import Errors and had to be corrected twice.
  late final ScanIdentity _scanIdentity;
  CorrectionPickerData? _pickers;
  bool _pickersLoading = true;

  final FocusNode _instructorFocus = FocusNode();
  List<PickerInstructor> _instructorSuggestions = [];
  String? _selectedInstructorId;
  bool _instructorTouched = false; // staff typed/picked: no auto pre-select
  bool _instructorError = false;

  final FocusNode _subjectFocus = FocusNode();
  List<PickerSubject> _subjectSuggestions = [];
  String? _selectedSubjectId;
  PickerSubject? _selectedSubject;
  bool _subjectTouched = false;
  bool _subjectError = false;

  // n8n's 422: instructor/subject not found. Nothing was saved.
  CorrectionNotFoundAnswer? _notFound;

  // ── Stamp Number ──────────────────────────────────────────────────────────
  // The numbering-machine stamp: what n8n read, what staff confirm or type.
  late final QueueStamp _stamp;
  late TextEditingController _stampCtrl;
  bool _noStamp = false; // staff say the paper has no stamp at all
  String? _stampError;
  DuplicateStampAnswer? _duplicateStamp; // n8n's 409: already saved this term

  // ── Action States ─────────────────────────────────────────────────────────
  bool _isSubmitting = false;
  bool _isDiscarding = false;

  Map<String, dynamic> get _partial => (widget.scan['partial_data'] is Map)
      ? Map<String, dynamic>.from(widget.scan['partial_data'] as Map)
      : <String, dynamic>{};

  @override
  void initState() {
    super.initState();

    final partial = _partial;
    _instructorCtrl =
        TextEditingController(text: partial['instructor']?.toString() ?? '');
    _subjectCtrl =
        TextEditingController(text: partial['subject']?.toString() ?? '');
    _remarksCtrl =
        TextEditingController(text: partial['remarks']?.toString() ?? '');
    _studentIdCtrl =
        TextEditingController(text: partial['student_id']?.toString() ?? '');
    _stamp = QueueStamp.fromRow(widget.scan);
    _stampCtrl = TextEditingController(text: _stamp.stampNo ?? '');
    _scanIdentity = ScanIdentity.fromPartial(partial);

    _initScores();
    _loadScanImage();
    _loadPickers();

    // Show the list when a field gets focus; hide it when focus leaves
    // (small delay so a tap on a suggestion still lands).
    _instructorFocus.addListener(() {
      if (_instructorFocus.hasFocus) {
        _showInstructorSuggestions();
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _instructorSuggestions = []);
        });
      }
    });

    _subjectFocus.addListener(() {
      if (_subjectFocus.hasFocus) {
        _showSubjectSuggestions();
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _subjectSuggestions = []);
        });
      }
    });
  }

  @override
  void dispose() {
    _instructorFocus.dispose();
    _subjectFocus.dispose();
    _instructorCtrl.dispose();
    _subjectCtrl.dispose();
    _remarksCtrl.dispose();
    _studentIdCtrl.dispose();
    _stampCtrl.dispose();
    for (final c in _scoreCtrlMap.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Robust Score Extraction ───────────────────────────────────────────────
  void _initScores() {
    final partial = _partial;
    final pyRaw = (partial['python_raw_ratings'] is Map
        ? Map<String, dynamic>.from(partial['python_raw_ratings'] as Map)
        : <String, dynamic>{});
    final omrComp = widget.scan['omr_comparison'];

    for (int i = 1; i <= 10; i++) {
      final mScore = _extractScore('m', i, partial, pyRaw, omrComp);
      final pScore = _extractScore('p', i, partial, pyRaw, omrComp);
      _scoreCtrlMap['m$i'] = TextEditingController(text: mScore);
      _scoreCtrlMap['p$i'] = TextEditingController(text: pScore);
    }
  }

  String _extractScore(
    String prefix,
    int index,
    Map<String, dynamic> partial,
    Map<String, dynamic> pyRaw,
    dynamic omrComparison,
  ) {
    final lowerKey = '$prefix$index'; // e.g. m1
    final upperKey = '${prefix.toUpperCase()}$index'; // e.g. M1
    final i0 = index - 1;

    // Helper to normalize score (handles letter ratings and digits)
    String normalize(dynamic val) {
      if (val == null) return '';
      final s = val.toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'blank' || s.toLowerCase() == 'null') {
        return '';
      }
      const letters = {
        'O': '5',
        'VS': '4',
        'S': '3',
        'F': '2',
        'US': '1',
      };
      final mapped = letters[s.toUpperCase()];
      if (mapped != null) return mapped;
      final numVal = int.tryParse(s);
      if (numVal != null && numVal >= 1 && numVal <= 5) return '$numVal';
      return '';
    }

    // 1. Check partial.ratings
    final ratings = partial['ratings'];
    if (ratings is Map) {
      if (ratings[lowerKey] != null) {
        final res = normalize(ratings[lowerKey]);
        if (res.isNotEmpty) return res;
      }
      if (ratings[upperKey] != null) {
        final res = normalize(ratings[upperKey]);
        if (res.isNotEmpty) return res;
      }

      // Check nested management / performance
      final sec = prefix == 'm'
          ? (ratings['management'] ?? ratings['Management'])
          : (ratings['performance'] ?? ratings['Performance']);
      if (sec is Map) {
        if (sec[lowerKey] != null) {
          final res = normalize(sec[lowerKey]);
          if (res.isNotEmpty) return res;
        }
        if (sec[upperKey] != null) {
          final res = normalize(sec[upperKey]);
          if (res.isNotEmpty) return res;
        }
        if (sec['$index'] != null) {
          final res = normalize(sec['$index']);
          if (res.isNotEmpty) return res;
        }
      } else if (sec is List && i0 < sec.length) {
        final item = sec[i0];
        if (item is Map) {
          final res = normalize(item['score'] ?? item['rating_name'] ?? item['answer']);
          if (res.isNotEmpty) return res;
        } else {
          final res = normalize(item);
          if (res.isNotEmpty) return res;
        }
      }
    }

    // 2. Check omr_comparison
    List comparisonsList = [];
    if (omrComparison is Map && omrComparison['comparisons'] is List) {
      comparisonsList = omrComparison['comparisons'] as List;
    } else if (omrComparison is List) {
      comparisonsList = omrComparison;
    }
    for (final comp in comparisonsList) {
      if (comp is Map) {
        final q = comp['question']?.toString().toLowerCase();
        if (q == lowerKey) {
          final res = normalize(comp['used'] ?? comp['python'] ?? comp['gemini']);
          if (res.isNotEmpty) return res;
        }
      }
    }

    // 3. Check partial_data flat fields
    if (partial[lowerKey] != null) {
      final res = normalize(partial[lowerKey]);
      if (res.isNotEmpty) return res;
    }
    if (partial[upperKey] != null) {
      final res = normalize(partial[upperKey]);
      if (res.isNotEmpty) return res;
    }

    // 4. Check partial_data.scores
    if (partial['scores'] is Map) {
      final s = partial['scores'] as Map;
      final res = normalize(s[lowerKey] ?? s[upperKey]);
      if (res.isNotEmpty) return res;
    }

    // 5. Check python_raw_ratings
    if (pyRaw[lowerKey] != null) {
      final res = normalize(pyRaw[lowerKey]);
      if (res.isNotEmpty) return res;
    }
    if (pyRaw[upperKey] != null) {
      final res = normalize(pyRaw[upperKey]);
      if (res.isNotEmpty) return res;
    }

    // 6. Check gemini_scores
    if (partial['gemini_scores'] is Map) {
      final g = partial['gemini_scores'] as Map;
      final res = normalize(g[lowerKey] ?? g[upperKey]);
      if (res.isNotEmpty) return res;
    }

    // 7. Check top-level widget.scan
    if (widget.scan[lowerKey] != null) {
      final res = normalize(widget.scan[lowerKey]);
      if (res.isNotEmpty) return res;
    }
    if (widget.scan[upperKey] != null) {
      final res = normalize(widget.scan[upperKey]);
      if (res.isNotEmpty) return res;
    }
    if (widget.scan['raw_scores'] is Map) {
      final rs = widget.scan['raw_scores'] as Map;
      final res = normalize(rs[lowerKey] ?? rs[upperKey]);
      if (res.isNotEmpty) return res;
    }

    return '';
  }

  // ── Image Loading (Direct Base64 + scan_error_images) ─────────────────────
  Future<void> _loadScanImage() async {
    // 1. Direct base64 string from n8n_ocr_image or scan_image
    final direct = widget.scan['n8n_ocr_image'] ??
        widget.scan['scan_image'] ??
        widget.scan['image_base64'];
    if (direct is String && direct.trim().isNotEmpty) {
      try {
        final cleanB64 = direct.trim().replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
        final bytes = base64Decode(cleanB64);
        if (mounted) setState(() => _imageBytes = bytes);
        return;
      } catch (e) {
        debugPrint('[FailedScanDetail] Direct base64 error: $e');
      }
    }

    // 2. Fetch via scan_image_id from scan_error_images
    final scanImageId = widget.scan['scan_image_id']?.toString();
    if (scanImageId != null && scanImageId.isNotEmpty) {
      setState(() => _isLoadingImage = true);
      try {
        final bytes = await ScanImageService.fetchScanImageBytes(_supabase, scanImageId);
        if (mounted && bytes != null) {
          setState(() => _imageBytes = bytes);
          return;
        }
      } finally {
        if (mounted) setState(() => _isLoadingImage = false);
      }
    }

    // 3. Fallback: check partial_data
    final partial = _partial;
    final partialImg = partial['scan_image'] ??
        partial['image_base64'] ??
        partial['n8n_ocr_image'];
    if (partialImg is String && partialImg.trim().isNotEmpty) {
      try {
        final cleanB64 = partialImg.trim().replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
        final bytes = base64Decode(cleanB64);
        if (mounted) setState(() => _imageBytes = bytes);
        return;
      } catch (_) {}
    }
  }

  // ── Pickers: load + pre-select ────────────────────────────────────────────
  Future<void> _loadPickers() async {
    CorrectionPickerData data;
    try {
      data = await CorrectionPickerData.load(_supabase);
    } catch (e) {
      debugPrint('[FailedScanDetail] Picker lists error: $e');
      data = const CorrectionPickerData([], []);
    }
    if (!mounted) return;
    setState(() {
      _pickers = data;
      _pickersLoading = false;
      // Pre-select what the AI suggested / the scan clearly names, unless
      // staff already started typing or picking.
      if (!_instructorTouched && _selectedInstructorId == null) {
        final p = _scanIdentity.pickInstructor(data.instructors);
        if (p != null) _applyInstructor(p);
      }
      if (!_subjectTouched && _selectedSubjectId == null) {
        final s = _scanIdentity.pickSubject(data.subjects);
        if (s != null) _applySubject(s);
      }
    });
  }

  List<PickerInstructor> get _instructorList => _pickers?.instructors ?? const [];
  List<PickerSubject> get _subjectList => _pickers?.subjects ?? const [];

  // ── Picker: Instructor ────────────────────────────────────────────────────
  void _showInstructorSuggestions() {
    // a picked entry shows the whole list; typed text filters it
    final q = _selectedInstructorId != null ? '' : _instructorCtrl.text;
    setState(() => _instructorSuggestions = PickerSearch.instructors(q, _instructorList));
  }

  void _onInstructorChanged(String query) {
    setState(() {
      _instructorTouched = true;
      _selectedInstructorId = null;
      _instructorSuggestions = PickerSearch.instructors(query, _instructorList);
    });
  }

  void _applyInstructor(PickerInstructor item) {
    _instructorCtrl.text = item.name;
    _selectedInstructorId = item.id;
    _instructorSuggestions = [];
    _instructorError = false;
  }

  void _selectInstructor(PickerInstructor item) {
    setState(() {
      _instructorTouched = true;
      _applyInstructor(item);
    });
    _instructorFocus.unfocus();
  }

  // ── Picker: Subject ───────────────────────────────────────────────────────
  void _showSubjectSuggestions() {
    final q = _selectedSubjectId != null ? '' : _subjectCtrl.text;
    setState(() => _subjectSuggestions = PickerSearch.subjects(q, _subjectList));
  }

  void _onSubjectChanged(String query) {
    setState(() {
      _subjectTouched = true;
      _selectedSubjectId = null;
      _selectedSubject = null;
      _subjectSuggestions = PickerSearch.subjects(query, _subjectList);
    });
  }

  void _applySubject(PickerSubject item) {
    _subjectCtrl.text = item.display;
    _selectedSubjectId = item.id;
    _selectedSubject = item;
    _subjectSuggestions = [];
    _subjectError = false;
  }

  void _selectSubject(PickerSubject item) {
    setState(() {
      _subjectTouched = true;
      _applySubject(item);
    });
    _subjectFocus.unfocus();
  }

  // ── Discard ───────────────────────────────────────────────────────────────
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
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDiscarding = true);
    try {
      await _supabase
          .from('failed_scan_queue')
          .update({'status': 'discarded'}).eq('id', widget.scan['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan discarded.'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isDiscarding = false);
    }
  }

  // ── Stamp Checks ──────────────────────────────────────────────────────────
  /// Why the stamp field cannot be sent as it is, or null when it can.
  String? _checkStamp() {
    if (_noStamp) return null;
    final typed = Stamp.normalize(_stampCtrl.text);
    if (typed.isEmpty) {
      return _stamp.needsStaffInput
          ? 'Type the stamp number, or tick "This form has no stamp".'
          : null;
    }
    return Stamp.validationError(typed);
  }

  void _onStampEdited() {
    if (_stampError != null || _duplicateStamp != null) {
      setState(() {
        _stampError = null;
        _duplicateStamp = null;
      });
    }
  }

  // ── Submit Correction ─────────────────────────────────────────────────────
  Future<void> _submit() async {
    final stampError = _checkStamp();
    if (stampError != null) {
      setState(() => _stampError = stampError);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(stampError),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    // Instructor and subject must be picked from the lists (their ids are
    // what gets credited). Only when a list could not be loaded is the typed
    // text sent on its own; n8n then matches it and answers 422 if unsure.
    if (_pickersLoading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Still loading the instructor and subject lists. Try again in a moment.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    final needInstructor = _instructorList.isNotEmpty && _selectedInstructorId == null;
    final needSubject = _subjectList.isNotEmpty && _selectedSubjectId == null;
    if (needInstructor || needSubject) {
      setState(() {
        _instructorError = needInstructor;
        _subjectError = needSubject;
      });
      final what = needInstructor && needSubject
          ? 'the instructor and the subject'
          : (needInstructor ? 'the instructor' : 'the subject');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pick $what from the list before submitting.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // A blank cell is an unanswered question and is sent as null (the key
      // is kept, value null). It must never become 0: a 0 would be averaged
      // in and drag the instructor's mean down. Only 1..5 is a real answer.
      int? rating(String key) {
        final v = int.tryParse(_scoreCtrlMap[key]?.text.trim() ?? '');
        return (v != null && v >= 1 && v <= 5) ? v : null;
      }

      final scores = <String, int?>{};
      for (int i = 1; i <= 10; i++) {
        scores['m$i'] = rating('m$i');
        scores['p$i'] = rating('p$i');
      }

      final payload = <String, dynamic>{
        'failed_scan_id': widget.scan['id'],
        'task_id': widget.scan['task_id'],
        'user_id': widget.scan['user_id'],
        'term_id': widget.scan['term_id'],
        // ids are what n8n credits; the names ride along (older n8n builds
        // and the import-error fallback read them)
        'instructor': _instructorCtrl.text.trim(),
        'instructor_id': _selectedInstructorId,
        'subject': (_selectedSubject != null && _selectedSubject!.code.isNotEmpty)
            ? _selectedSubject!.code
            : _subjectCtrl.text.trim(),
        'subject_name': _selectedSubject?.name,
        'subject_id': _selectedSubjectId,
        'remarks': _remarksCtrl.text.trim(),
        'student_id': _studentIdCtrl.text.trim(),
        // Digits exactly as printed (leading zeros kept), or null when the
        // form has no stamp. n8n refuses a stamp already saved this term.
        'stamp_no': Stamp.toPayload(_stampCtrl.text, noStamp: _noStamp),
        'stamp_source': 'staff',
        ...scores,
        'manually_corrected': true,
        'validation_status': 'corrected',
        'correction_source': 'manual_text',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final result = await AutomationService.instance.submitManualCorrection(payload);

      // 409 duplicate_stamp: nothing was saved. Keep the screen open so the
      // number can be fixed (or the scan discarded if it is the same form).
      final duplicate =
          DuplicateStampAnswer.tryParse(result.statusCode, result.data);
      if (duplicate != null) {
        if (mounted) {
          setState(() {
            _duplicateStamp = duplicate;
            _stampError = 'Already saved this term. Check the number.';
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Not saved: ${duplicate.explanation}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 6),
          ));
        }
        return;
      }

      // 422 instructor/subject not found: nothing was saved and the scan
      // stays pending. Keep the screen open with the pickers highlighted.
      final notFound =
          CorrectionNotFoundAnswer.tryParse(result.statusCode, result.data);
      if (notFound != null) {
        if (mounted) {
          setState(() {
            _notFound = notFound;
            _instructorError = notFound.instructorMissing;
            _subjectError = notFound.subjectMissing;
            if (notFound.instructorMissing) _selectedInstructorId = null;
            if (notFound.subjectMissing) {
              _selectedSubjectId = null;
              _selectedSubject = null;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(notFound.message),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 6),
          ));
        }
        return;
      }

      if (result.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Submitted! Correction is being processed.'),
            backgroundColor: AppColors.success,
          ));
          Navigator.pop(context);
        }
      } else {
        throw Exception('Server returned ${result.statusCode}: ${result.errorMessage}');
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

  // ── Build Screen ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final taskId = widget.scan['task_id']?.toString() ?? 'Unknown';
    final tableFound = widget.scan['table_found'] == true;
    final gridSource = widget.scan['grid_source']?.toString() ?? 'fallback';

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Correct Failed Scan',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '📷 $taskId',
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: _isDiscarding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.error,
                    ),
                  )
                : const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
            label: const Text(
              'Discard',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            // Not while a submit is in flight: both pop this screen on success,
            // and the second pop would take the route underneath.
            onPressed: (_isDiscarding || _isSubmitting) ? null : _discard,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Failure Message Banner right at the top
                  _buildFailureBanner(tableFound, gridSource),

                  // 2. Scanned Form Image (Clean preview + zoom)
                  _buildImageSection(),

                  // 3. Content Form with cards matching Fix Import Error
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),

                        // Original Data Reference Card
                        _buildOriginalDataCard(),
                        const SizedBox(height: 16),

                        // Stamp number: what was read, fix or confirm it
                        _buildStampCard(),
                        const SizedBox(height: 20),

                        // Correction Section Heading
                        const Text(
                          'Correct the Scan Data',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'The instructor and subject were pre-selected from the scan where it was clear. Check them, search and pick another if needed, and adjust any scores below.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 16),

                        // Autocomplete fields
                        _buildInstructorField(),
                        _buildSubjectField(),

                        // Additional fields
                        _buildSimpleField('Remarks & Suggestions', _remarksCtrl, maxLines: 3),
                        _buildSimpleField('Student ID', _studentIdCtrl,
                            keyboardType: TextInputType.number, digitsOnly: true),

                        // OMR Disagreement / Comparison Details (if available)
                        _buildOmrComparisonSection(),

                        const SizedBox(height: 16),

                        // Editable Scores Card matching ImportErrorDetailScreen
                        _buildScoresEditable(),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Sticky bottom submit bar
          _buildSubmitBar(),
        ],
      ),
    );
  }

  // ── 1. Top Failure Message Banner ─────────────────────────────────────────
  Widget _buildFailureBanner(bool tableFound, String gridSource) {
    final rawReasons = widget.scan['review_reasons'];
    final reasonsList = (rawReasons is List && rawReasons.isNotEmpty) ? rawReasons : null;

    final isOmrDispute = reasonsList?.any((r) => r.toString().toLowerCase().contains('omr')) ?? false;
    final color = (!tableFound) ? AppColors.error : (isOmrDispute ? AppColors.indigo : AppColors.warning);
    final icon = (!tableFound)
        ? Icons.crop_free
        : (isOmrDispute ? Icons.fact_check_outlined : Icons.grid_off_rounded);

    final partial = _partial;
    final reviewNote = partial['review_note']?.toString() ?? '';

    final String msg;
    if (reasonsList != null) {
      msg = reasonsList.map((r) {
        final stampLabel = Stamp.reasonLabel(r);
        if (stampLabel != null) return stampLabel;
        final raw = r.toString();
        final s = (raw.contains(':') ? raw.substring(0, raw.indexOf(':')).trim() : raw)
            .replaceAll('_', ' ');
        return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
      }).join(' • ');
    } else {
      msg = tableFound
          ? 'Grid lines not detected — fallback grid was used. Scores need human review.'
          : 'Table corners NOT found — proportional crop was used. All fields require verification.';
    }

    final String displayText = reviewNote.isNotEmpty ? '$msg\nDetails: $reviewNote' : msg;

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Scanned Image Section ──────────────────────────────────────────────
  Widget _buildImageSection() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scanned Form Image',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (_isLoadingImage)
            Container(
              height: 130,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderHairline),
              ),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            )
          else if (_imageBytes != null)
            GestureDetector(
              onTap: () => _showZoomedImage(_imageBytes!),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _imageBytes!,
                      width: double.infinity,
                      height: 130,
                      fit: BoxFit.cover,
                      // A thumbnail: decode at screen width, not the full photo.
                      cacheWidth: (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
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
                        Text(
                          'Tap to zoom',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderHairline),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported_outlined,
                        color: AppColors.textTertiary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Image preview not available',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showZoomedImage(Uint8List bytes) {
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
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  // Room to zoom without decoding a full-sensor photo.
                  cacheWidth: (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context) *
                          3)
                      .round(),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: const Text(
                  'Scanned Form  •  Pinch to zoom',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3. Original Data Reference Card ───────────────────────────────────────
  Widget _buildOriginalDataCard() {
    final partial = _partial;
    final instructor = partial['instructor']?.toString() ?? '—';
    final subject = partial['subject']?.toString() ?? '—';
    final studentId = partial['student_id']?.toString() ?? '';
    final remarks = partial['remarks']?.toString() ?? '';
    final gridSource = widget.scan['grid_source']?.toString() ?? 'auto-detected';
    final tableFound = widget.scan['table_found'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.document_scanner_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                'Original Data from Scan',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _dataRow('Instructor (detected)', instructor),
          _dataRow('Subject (detected)', subject),
          if (studentId.isNotEmpty) _dataRow('Student ID', studentId),
          if (remarks.isNotEmpty) _dataRow('Remarks', remarks),
          _dataRow(
            'Table / Grid Detection',
            tableFound ? 'Table found ($gridSource)' : 'Table not found ($gridSource)',
          ),
        ],
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3b. Stamp Number Card ─────────────────────────────────────────────────
  Widget _buildStampCard() {
    final status = _stamp.status;
    final statusOk = status == 'ok' && _stamp.reasons.isEmpty;
    final accent = _duplicateStamp != null
        ? AppColors.error
        : (statusOk ? AppColors.success : AppColors.warning);
    final choices = _stamp.choices;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.confirmation_number_outlined, size: 16, color: accent),
              const SizedBox(width: 6),
              const Text(
                'Stamp Number',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  Stamp.statusLabel(status),
                  style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _dataRow('Read from scan', _stamp.stampNo ?? '—'),
          // Plain-English reasons (missing / unreadable / several stamps).
          ..._stamp.reasons.map((code) {
            final text = Stamp.reasonText(code);
            if (text == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 15, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (choices.isNotEmpty) ...[
            const Text(
              'Stamped numbers found — tap the right one:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: choices.map((c) {
                final selected =
                    !_noStamp && Stamp.normalize(_stampCtrl.text) == c;
                return ChoiceChip(
                  label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
                  selected: selected,
                  selectedColor: AppColors.primary.withValues(alpha: 0.18),
                  onSelected: _isSubmitting
                      ? null
                      : (_) {
                          setState(() {
                            _noStamp = false;
                            _stampCtrl.text = c;
                            _stampError = null;
                            _duplicateStamp = null;
                          });
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          TextField(
            controller: _stampCtrl,
            enabled: !_noStamp && !_isSubmitting,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(Stamp.maxDigits),
            ],
            onChanged: (_) => _onStampEdited(),
            decoration: _inputDecoration(
              label: 'Stamp number',
              prefix: Icons.tag,
            ).copyWith(
              helperText: 'Digits exactly as printed, keep leading zeros (3–12).',
              errorText: _stampError,
            ),
          ),
          CheckboxListTile(
            value: _noStamp,
            onChanged: _isSubmitting
                ? null
                : (v) => setState(() {
                      _noStamp = v ?? false;
                      _stampError = null;
                      _duplicateStamp = null;
                    }),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
            title: const Text(
              'This form has no stamp',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          if (_duplicateStamp != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.copy_all_rounded, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _duplicateStamp!.explanation,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 4. OMR Disagreement / Comparison Details ──────────────────────────────
  Widget _buildOmrComparisonSection() {
    final omrComp = widget.scan['omr_comparison'];
    List comparisons = [];
    if (omrComp is Map && omrComp['comparisons'] is List) {
      comparisons = omrComp['comparisons'] as List;
    } else if (omrComp is List) {
      comparisons = omrComp;
    }

    // Filter to rows with disputes or weak confidence
    final conflicts = comparisons.where((c) {
      if (c is! Map) return false;
      final p = c['python'];
      final g = c['gemini'];
      final weak = c['python_weak'] == true;
      return (p != null && g != null && p != g) || weak;
    }).toList();

    if (conflicts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.indigo.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows_rounded, size: 16, color: AppColors.indigo),
              const SizedBox(width: 6),
              const Text(
                'OMR Engine Cross-Check Details',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${conflicts.length} disputed',
                  style: const TextStyle(
                    color: AppColors.indigo,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Python OMR and Gemini AI disagreed on the following bubble rows. Reconciled values were pre-filled below for your review:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          ...conflicts.map((c) {
            final q = (c['question']?.toString() ?? '').toUpperCase();
            final p = c['python']?.toString() ?? 'blank';
            final g = c['gemini']?.toString() ?? 'blank';
            final used = c['used']?.toString() ?? '—';
            final isWeak = c['python_weak'] == true;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderHairline),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.indigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      q,
                      style: const TextStyle(
                        color: AppColors.indigo,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Python: $p', style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
                  const SizedBox(width: 8),
                  Text('Gemini: $g', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text('Used: $used', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  if (isWeak) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 5. Editable Scores Card (Matching ImportErrorDetailScreen) ─────────────
  Widget _buildScoresEditable() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'Scores (editable — from Scan)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Tap to edit',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('Management (M1 – M10)'),
          const SizedBox(height: 8),
          _scoreGridEditable('m'),
          const SizedBox(height: 14),
          _sectionLabel('Performance (P1 – P10)'),
          const SizedBox(height: 8),
          _scoreGridEditable('p'),
        ],
      ),
    );
  }

  Widget _scoreGridEditable(String prefix) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1.1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 10,
      itemBuilder: (_, i) {
        final key = '$prefix${i + 1}';
        return TextField(
          controller: _scoreCtrlMap[key],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[1-5]')),
            LengthLimitingTextInputFormatter(1),
          ],
          decoration: InputDecoration(
            labelText: key.toUpperCase(),
            labelStyle: const TextStyle(fontSize: 10),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        );
      },
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );

  // ── Picker Input Widgets ───────────────────────────────────────────────────
  /// "Scan read: …" under a picker label, so staff can compare.
  Widget _scanReadHint(String read) {
    if (read.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        'Scan read: $read',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }

  Widget? _pickerSuffix(bool selected) {
    if (_pickersLoading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return selected ? const Icon(Icons.check_circle, color: AppColors.success, size: 20) : null;
  }

  /// "Did you mean" chips from n8n's 422 candidates.
  Widget _candidateChips<T>(List<T> items, String Function(T) label, void Function(T) onTap) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Did you mean:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ...items.map((c) => ActionChip(
                label: Text(label(c), style: const TextStyle(fontSize: 12)),
                onPressed: _isSubmitting ? null : () => onTap(c),
              )),
        ],
      ),
    );
  }

  Widget _buildInstructorField() {
    final candidates = _notFound?.instructorMissing == true && _selectedInstructorId == null
        ? _notFound!.instructorCandidates
        : const <PickerInstructor>[];
    final noList = !_pickersLoading && _instructorList.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _scanReadHint(_scanIdentity.instructorRead),
        TextField(
          key: const Key('instructorPicker'),
          controller: _instructorCtrl,
          focusNode: _instructorFocus,
          onChanged: _onInstructorChanged,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Instructor (search and pick)',
            prefix: Icons.person_search_outlined,
            suffix: _pickerSuffix(_selectedInstructorId != null),
          ).copyWith(
            errorText: _instructorError ? 'Pick the instructor from the list' : null,
            helperText: noList ? 'Instructor list unavailable: the typed name is sent as it is.' : null,
          ),
        ),
        if (_instructorSuggestions.isNotEmpty)
          _buildSuggestionCard<PickerInstructor>(
            _instructorSuggestions,
            itemBuilder: (item) => Row(
              children: [
                _avatar(_initialsOf(item.name)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    item.isPlaceholder ? '${item.name} (placeholder)' : item.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onTap: _selectInstructor,
          ),
        _candidateChips<PickerInstructor>(candidates, (c) => c.name, _selectInstructor),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildSubjectField() {
    final candidates = _notFound?.subjectMissing == true && _selectedSubjectId == null
        ? _notFound!.subjectCandidates
        : const <PickerSubject>[];
    final noList = !_pickersLoading && _subjectList.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _scanReadHint(_scanIdentity.subjectRead),
        TextField(
          key: const Key('subjectPicker'),
          controller: _subjectCtrl,
          focusNode: _subjectFocus,
          onChanged: _onSubjectChanged,
          textCapitalization: TextCapitalization.characters,
          decoration: _inputDecoration(
            label: 'Subject / Course Code (search and pick)',
            prefix: Icons.book_outlined,
            suffix: _pickerSuffix(_selectedSubjectId != null),
          ).copyWith(
            errorText: _subjectError ? 'Pick the subject from the list' : null,
            helperText: noList ? 'Subject list unavailable: the typed text is sent as it is.' : null,
          ),
        ),
        if (_subjectSuggestions.isNotEmpty)
          _buildSuggestionCard<PickerSubject>(
            _subjectSuggestions,
            itemBuilder: (item) => Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.code,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onTap: _selectSubject,
          ),
        _candidateChips<PickerSubject>(candidates, (c) => c.display, _selectSubject),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildSuggestionCard<T>(
    List<T> items, {
    required Widget Function(T) itemBuilder,
    required void Function(T) onTap,
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
            offset: const Offset(0, 4),
          ),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: AppColors.borderSubtle, width: 0.8),
                        ),
                ),
                child: itemBuilder(entry.value),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSimpleField(
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    bool digitsOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: _inputDecoration(label: label),
      ),
    );
  }

  InputDecoration _inputDecoration({required String label, IconData? prefix, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefix != null ? Icon(prefix, size: 18) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  // ── 6. Sticky Submit Bar ──────────────────────────────────────────────────
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.cloud_upload_outlined, size: 20),
          label: Text(
            _isSubmitting ? 'Submitting…' : 'Submit & Validate',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: (_isSubmitting || _isDiscarding) ? null : _submit,
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _avatar(String initials) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initials,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      );

  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final f = parts.first[0];
    final l = parts.length > 1 ? parts.last[0] : '';
    return '$f$l'.toUpperCase();
  }
}
