// lib/gatherer/failed_scan_detail_screen.dart
// When OCR fail to properly read a scan, the scan ends up here.
// This screen let user manually type in all the data that the machine couldnt read.
// It like being the backup plan for when robot fail at their job.
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

// this screen takes one failed scan record and shows its data for correction
class FailedScanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> scan; // the failed scan record from Supabase
  const FailedScanDetailScreen({super.key, required this.scan});

  @override
  State<FailedScanDetailScreen> createState() => _FailedScanDetailScreenState();
}

// the state — lots of controllers and autocomplete logic here
class _FailedScanDetailScreenState extends State<FailedScanDetailScreen> {
  final _supabase = Supabase.instance.client; // database connection

  // Local image (for zoom preview only)
  // we try to find the original scan image so user can see what they correcting
  File? _localImageFile;
  bool _localImageAvailable = false; // false until we find the file

  // Text field controllers — one per editable field
  late TextEditingController _instructorCtrl;
  late TextEditingController _subjectCtrl;
  late TextEditingController _remarksCtrl;
  late TextEditingController _studentIdCtrl;
  // map of score controllers — keys like 'm1', 'p5', etc.
  late Map<String, TextEditingController> _scoreCtrlMap;

  // Autocomplete — Instructor
  // debounce so we dont query database on every keystroke like crazy
  final FocusNode _instructorFocus = FocusNode();
  List<Map<String, dynamic>> _instructorSuggestions = []; // dropdown suggestions
  String? _selectedInstructorId; // set when user pick from suggestions — the actual ID
  Timer? _instructorDebounce; // timer to delay search while user still typing

  // Autocomplete — Subject
  // same debounce pattern as instructor — search after user stop typing for 300ms
  final FocusNode _subjectFocus = FocusNode();
  List<Map<String, dynamic>> _subjectSuggestions = [];
  String? _selectedSubjectId; // set when user pick from suggestions
  Timer? _subjectDebounce;

  // Submission
  bool _isSubmitting = false; // true while we POSTing to n8n — disable the button

  // n8n endpoint for manual corrections — different from the regular scan upload
  static String get _n8nCorrectionUrl => Env.n8nManualCorrectionUrl;

  // initialize everything — pre-fill fields from partial_data if available
  @override
  void initState() {
    super.initState();

    // get partial_data map — this is what OCR managed to read before failing
    final partial =
        (widget.scan['partial_data'] is Map ? Map<String, dynamic>.from(widget.scan['partial_data'] as Map) : {});

    // pre-fill text fields with partial OCR data — even wrong data help user know what to fix
    _instructorCtrl =
        TextEditingController(text: partial['instructor']?.toString() ?? '');
    _subjectCtrl =
        TextEditingController(text: partial['subject']?.toString() ?? '');
    _remarksCtrl =
        TextEditingController(text: partial['remarks']?.toString() ?? '');
    _studentIdCtrl =
        TextEditingController(text: partial['student_id']?.toString() ?? '');

    // build the score controllers from partial ratings data
    _scoreCtrlMap = {};
    final ratings = (partial['ratings'] is Map ? Map<String, dynamic>.from(partial['ratings'] as Map) : {}) as Map<String, dynamic>;
    final mgmt = (ratings['management'] is List ? ratings['management'] as List : []);
    final perf = (ratings['performance'] is List ? ratings['performance'] as List : []);
    for (int i = 0; i < 10; i++) {
      // only pre-fill if the score was actually detected — otherwise leave blank
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
    // we delay 150ms so tap on suggestion register before list disappears
    _instructorFocus.addListener(() {
      if (!_instructorFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _instructorSuggestions = []); // clear dropdown
        });
      }
    });
    _subjectFocus.addListener(() {
      if (!_subjectFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _subjectSuggestions = []); // clear dropdown
        });
      }
    });

    _findLocalImage(); // try to find the original scan image file
  }

  // clean up all controllers and subscriptions — very importente, memory leak kung dili
  @override
  void dispose() {
    _instructorFocus.dispose();
    _subjectFocus.dispose();
    _instructorCtrl.dispose();
    _subjectCtrl.dispose();
    _remarksCtrl.dispose();
    _studentIdCtrl.dispose();
    _instructorDebounce?.cancel(); // cancel pending debounce timers
    _subjectDebounce?.cancel();
    for (final c in _scoreCtrlMap.values) c.dispose(); // dispose all score controllers
    super.dispose();
  }

  // ── Find local image for zoom preview ──────────────────────────────────────

  // look in SharedPreferences queue for the image file matching this task_id
  // if found and file still exist on device, show it for reference
  Future<void> _findLocalImage() async {
    final taskId = widget.scan['task_id']?.toString() ?? '';
    if (taskId.isEmpty) return; // no task_id, cannot find image
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.scan['user_id']?.toString() ?? '';
      final queueKey = 'gatherer_sync_queue_$userId';
      final raw = prefs.getStringList(queueKey) ?? [];
      for (final s in raw) {
        final map = jsonDecode(s) as Map<String, dynamic>;
        final task = ScanTask.fromMap(map);
        if (task.id == taskId) {
          final f = File(task.localPath); // construct File from saved path
          if (await f.exists()) {
            // file still there — set it for display
            if (mounted) setState(() { _localImageFile = f; _localImageAvailable = true; });
          }
          return; // found the task, stop searching
        }
      }
    } catch (e) {
      debugPrint('findLocalImage error: $e'); // file search fail — not critical, just no preview
    }
  }

  // ── Autocomplete — Instructor ───────────────────────────────────────────────

  // called whenever user type in instructor field
  // clears confirmed selection and starts debounce timer for search
  void _onInstructorChanged(String query) {
    _selectedInstructorId = null; // user is editing — clear confirmed selection
    _instructorDebounce?.cancel(); // cancel previous debounce, start fresh
    if (query.trim().length < 2) {
      setState(() => _instructorSuggestions = []); // less than 2 chars, dont search yet
      return;
    }
    // wait 300ms after last keystroke before querying — saves database calls
    _instructorDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchInstructors(query.trim());
    });
  }

  // search supabase for instructors matching the query — up to 6 results
  // matches on first_name OR last_name (case insensitive)
  Future<void> _searchInstructors(String query) async {
    try {
      final results = await _supabase
          .from('user_info')
          .select('id, first_name, last_name')
          .or('first_name.ilike.%$query%,last_name.ilike.%$query%') // partial match both names
          .limit(6); // dont return too many, 6 is enough
      if (mounted) {
        setState(() {
          _instructorSuggestions =
              List<Map<String, dynamic>>.from(results as List);
        });
      }
    } catch (e) {
      debugPrint('Instructor search error: $e'); // search fail, just show nothing
    }
  }

  // user tapped on an instructor suggestion — fill the field and save the ID
  void _selectInstructor(Map<String, dynamic> item) {
    final name =
        '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim();
    setState(() {
      _instructorCtrl.text = name; // show full name in the text field
      _selectedInstructorId = item['id']?.toString(); // store ID for submission
      _instructorSuggestions = []; // hide suggestions dropdown
    });
    _instructorFocus.unfocus(); // dismiss keyboard
  }

  // ── Autocomplete — Subject ─────────────────────────────────────────────────

  // called whenever user type in subject field — same debounce pattern as instructor
  void _onSubjectChanged(String query) {
    _selectedSubjectId = null; // clear confirmed selection on edit
    _subjectDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _subjectSuggestions = []);
      return;
    }
    _subjectDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchSubjects(query.trim());
    });
  }

  // search supabase for subjects matching code or name — up to 6 results
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

  // user tapped on a subject suggestion — fill field with "CODE — Name" format
  void _selectSubject(Map<String, dynamic> item) {
    final display =
        '${item['subject_code'] ?? ''} — ${item['subject_name'] ?? ''}'.trim();
    setState(() {
      _subjectCtrl.text = display; // show formatted subject string
      _selectedSubjectId = item['id']?.toString(); // store ID for submission
      _subjectSuggestions = [];
    });
    _subjectFocus.unfocus();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  // collect all the corrected data and POST it to n8n for processing
  // n8n will then re-run the evaluation pipeline with the manual corrections
  Future<void> _submit() async {
    setState(() => _isSubmitting = true); // disable button, show loading
    try {
      // collect all 20 score values — default to 0 if empty or not a number
      final scores = <String, int>{};
      for (int i = 1; i <= 10; i++) {
        scores['m$i'] = int.tryParse(_scoreCtrlMap['m$i']?.text ?? '') ?? 0;
        scores['p$i'] = int.tryParse(_scoreCtrlMap['p$i']?.text ?? '') ?? 0;
      }

      // build the complete payload — all the corrected data plus metadata
      final payload = <String, dynamic>{
        'failed_scan_id':   widget.scan['id'], // which failed scan we correcting
        'task_id':          widget.scan['task_id'],
        'user_id':          widget.scan['user_id'],
        'term_id':          widget.scan['term_id'],
        'instructor':       _instructorCtrl.text.trim(),
        'instructor_id':    _selectedInstructorId, // null if user typed manually without picking suggestion
        'subject':          _subjectCtrl.text.trim(),
        'subject_id':       _selectedSubjectId, // null if user typed manually
        'remarks':          _remarksCtrl.text.trim(),
        'student_id':       _studentIdCtrl.text.trim(),
        ...scores, // spread all 20 score key-values directly into payload
        'manually_corrected':  true, // flag so n8n knows this came from human correction
        'validation_status':   'corrected',
        'correction_source':   'manual_text',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // POST to n8n correction webhook — 30 second timeout
      final response = await http
          .post(
            Uri.parse(_n8nCorrectionUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // n8n accepted the correction — go back to list
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Submitted! n8n is processing the correction.'),
            backgroundColor: AppColors.success,
          ));
          Navigator.pop(context); // return to failed scans list
        }
      } else {
        // n8n rejected it — show error with status and body for debugging
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
      if (mounted) setState(() => _isSubmitting = false); // re-enable button
    }
  }

  // ── Discard ────────────────────────────────────────────────────────────────

  // ask user to confirm, then mark the failed scan as 'discarded' in supabase
  // once discarded, it disappear from the failed scans list — permanent action
  Future<void> _discard() async {
    // show confirm dialog — this permanent, so ask twice basically
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
              onPressed: () => Navigator.pop(context, false), // cancel, go back
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(context, true), // confirmed discard
            child: const Text('Discard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return; // user cancel or dismiss — do nothing
    try {
      // update the status to 'discarded' — we dont actually delete, just mark it
      await _supabase
          .from('failed_scan_queue')
          .update({'status': 'discarded'}).eq('id', widget.scan['id']);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Scan discarded.')));
        Navigator.pop(context); // return to failed scans list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  // build the entire screen — appbar, failure banner, image preview, form, submit bar
  @override
  Widget build(BuildContext context) {
    final taskId = widget.scan['task_id']?.toString() ?? 'Unknown'; // shown in AppBar subtitle
    final tableFound = widget.scan['table_found'] == true; // was a table detected?
    final gridSource = widget.scan['grid_source']?.toString() ?? 'fallback'; // how OCR made the grid

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true, // resize when keyboard open so fields not hidden
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Correct Failed Scan',
                style: TextStyle(
                    color: AppColors.surface,
                    fontWeight: FontWeight.bold)),
            Text(taskId, // show which scan task this is
                style: const TextStyle(
                    color: AppColors.textInvertedDim, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // discard button in top-right — red because destructive action
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
            label: const Text('Discard',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
            onPressed: _discard, // triggers confirmation dialog first
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFailureBanner(tableFound, gridSource), // show what went wrong
          _buildImagesRow(), // show the original scan image if available
          Expanded(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: 24, // account for keyboard
                ),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, // drag to dismiss keyboard
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fill in or correct the fields below. Tap a suggestion to auto-fill.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Instructor with autocomplete — type 2+ chars to search
                    _buildInstructorField(),

                    // Subject with autocomplete — same pattern
                    _buildSubjectField(),

                    // Other fields — remarks and student ID, no autocomplete
                    _buildSimpleField('Remarks & Suggestions', _remarksCtrl,
                        maxLines: 3),
                    _buildSimpleField('Student ID', _studentIdCtrl,
                        keyboardType: TextInputType.number, digitsOnly: true), // numbers only

                    const SizedBox(height: 24),

                    // Management scores — 10 small inputs in a grid
                    _buildScoreSection('Management Scores (M1–M10)', 'm'),
                    const SizedBox(height: 20),

                    // Performance scores — another 10
                    _buildScoreSection('Performance Scores (P1–P10)', 'p'),
                    const SizedBox(height: 20),
                  ],
                ),
              ),   // SingleChildScrollView
            ),     // AnimatedPadding
          ),       // Expanded
          _buildSubmitBar(), // sticky submit button at the bottom
        ],
      ),
    );
  }

  // ── Failure banner ─────────────────────────────────────────────────────────

  // show what kind of failure this scan had — helps user understand context
  // orange = table found but grid detection failed (less severe)
  // red = no table detected at all (more severe, data less reliable)
  Widget _buildFailureBanner(bool tableFound, String gridSource) {
    final color = tableFound ? AppColors.warning : AppColors.error;
    final msg = tableFound
        ? 'Grid lines not detected — fallback grid was used. Scores may be wrong.'
        : 'Table/corners NOT found — OCR used a proportional crop estimate. All data needs verification.';
    final icon = tableFound ? Icons.grid_off_rounded : Icons.crop_free;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12), // subtle colored background
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

  // show the original scan image so user can see what they correcting
  // user can tap to zoom in for better inspection — useful for small scores
  Widget _buildImagesRow() {
    if (!_localImageAvailable || _localImageFile == null) return const SizedBox.shrink(); // no image, show nothing
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
                height: 110, // compact preview height
                fit: BoxFit.cover,
              ),
            ),
            // "tap to zoom" label overlay — so user know it tappable
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

  // helper widget — wraps an image in a labeled container with optional tap-to-zoom
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
                      // small zoom icon overlay in bottom-right corner
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
              : child, // no tap handler, just show image directly
        ),
      ],
    );
  }

  // show image in a fullscreen zoomable dialog — InteractiveViewer allow pinch-zoom
  void _showZoomedImage(Image image, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black87, // dark backdrop
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5, // can zoom out a bit
              maxScale: 8.0, // up to 8x zoom — enough to read small scores
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), child: image),
            ),
            // close button in top-right
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
            // title + zoom hint at the bottom of the image
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

  // placeholder shown when image is not available — gray box with icon
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

  // build the instructor text field plus its suggestion dropdown
  // the check icon suffix appear when user pick from suggestions (confirming ID selected)
  Widget _buildInstructorField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _instructorCtrl,
          focusNode: _instructorFocus,
          onChanged: _onInstructorChanged, // trigger debounce search on each change
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Instructor Name',
            prefix: Icons.person_outline,
            // green check when instructor ID is confirmed via suggestion selection
            suffix: _selectedInstructorId != null
                ? const Icon(Icons.check_circle,
                    color: AppColors.success, size: 18)
                : null,
          ),
        ),
        // show suggestion card only when there are suggestions
        if (_instructorSuggestions.isNotEmpty)
          _buildSuggestionCard(
            _instructorSuggestions,
            itemBuilder: (item) => Row(
              children: [
                // avatar circle with initials
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _initials(item['first_name'], item['last_name']), // e.g. "JD"
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim(),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onTap: _selectInstructor, // user pick this instructor
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  // build the subject text field plus its suggestion dropdown
  // shows subject code prominently since that the key identifier
  Widget _buildSubjectField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _subjectCtrl,
          focusNode: _subjectFocus,
          onChanged: _onSubjectChanged,
          textCapitalization: TextCapitalization.characters, // course codes usually uppercase
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
                // subject code chip — colored box
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

  // build the dropdown suggestion card container
  // shown below a text field when there are autocomplete matches
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
              offset: const Offset(0, 4)) // small shadow to lift it above content
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1;
            return InkWell(
              onTap: () => onTap(entry.value), // user tap this suggestion
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: isLast
                      ? null // no border on last item
                      : Border(
                          bottom: BorderSide(
                              color: AppColors.borderSubtle, width: 0.8)), // divider between items
                ),
                child: itemBuilder(entry.value), // render the item content
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Simple fields ──────────────────────────────────────────────────────────

  // helper to build a simple text field with optional multiline, keyboard type, digits-only filter
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
            digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null, // enforce numbers only if needed
        decoration: _inputDecoration(label: label),
      ),
    );
  }

  // shared input decoration — consistent look across all fields in this screen
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
        borderSide: const BorderSide(color: AppColors.primary, width: 2), // blue border when focused
      ),
    );
  }

  // ── Score grids ────────────────────────────────────────────────────────────

  // build a section with title and 5x2 grid of score input fields
  // prefix 'm' for management, 'p' for performance
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
          shrinkWrap: true, // dont take extra space
          physics: const NeverScrollableScrollPhysics(), // parent scroll handles scrolling
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5, // 5 columns
            childAspectRatio: 1.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: 10, // always 10 scores
          itemBuilder: (context, index) {
            final key = '$prefix${index + 1}'; // e.g. 'm3', 'p7'
            return TextField(
              controller: _scoreCtrlMap[key],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly], // numbers only
              decoration: InputDecoration(
                labelText: key.toUpperCase(), // M3, P7, etc.
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: EdgeInsets.zero, // compact cell padding
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

  // sticky bottom bar with the submit button
  // disabled and shows spinner while submitting — ayaw mag-double submit
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
                      strokeWidth: 2, color: Colors.white)) // spinner while submitting
              : const Icon(Icons.cloud_upload_outlined, size: 20),
          label: Text(
            _isSubmitting ? 'Submitting…' : 'Submit & Validate',
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: AppColors.success, // green because it a positive action
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _isSubmitting ? null : _submit, // null disables the button
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // get initials from first and last name — used for the avatar in instructor suggestions
  // e.g. "John Doe" -> "JD"
  String _initials(dynamic firstName, dynamic lastName) {
    final f = firstName?.toString() ?? '';
    final l = lastName?.toString() ?? '';
    return '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}'
        .toUpperCase();
  }
}
