// lib/sao_admin/import_error_detail_screen.dart
// The correction screen — this is where admin manually fixes broken import records
// Shows the original bad data, lets you pick the correct instructor + subject,
// and optionally edit scores if it was a scan (not a sheet).
// After fixing, it sends to n8n for re-processing. Importente kaayo ni sya.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/config/env.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';

class ImportErrorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> error; // the error record from the parent screen
  const ImportErrorDetailScreen({super.key, required this.error});

  @override
  State<ImportErrorDetailScreen> createState() =>
      _ImportErrorDetailScreenState();
}

class _ImportErrorDetailScreenState extends State<ImportErrorDetailScreen> {
  // supabase client — for searching instructors, subjects, and saving corrections
  final _supabase = Supabase.instance.client;

  // ── Autocomplete — Instructor ─────────────────────────────────────────────
  late TextEditingController _instructorCtrl; // text input for instructor name search
  final FocusNode _instructorFocus = FocusNode(); // tracks focus to dismiss suggestions
  List<Map<String, dynamic>> _instructorSuggestions = []; // dropdown results from DB
  String? _selectedInstructorId; // the ID of the instructor the admin picked
  Timer? _instructorDebounce; // debounce timer — wait 300ms before querying DB

  // ── Autocomplete — Subject ────────────────────────────────────────────────
  late TextEditingController _subjectCtrl; // text input for subject search
  final FocusNode _subjectFocus = FocusNode(); // focus listener to clear suggestions
  List<Map<String, dynamic>> _subjectSuggestions = []; // dropdown results from DB
  String? _selectedSubjectId; // the ID of the subject the admin picked
  Timer? _subjectDebounce; // debounce timer — same idea, dili mag-query every keystroke

  // ── Score editing (scan errors only) ─────────────────────────────────────
  // map of "m1" to "p10" controllers — for editing scores when source is scan
  Map<String, TextEditingController> _scoreCtrlMap = {};

  // ── Image (scan errors only, loaded from failed_scan_queue) ──────────────
  Uint8List? _imageBytes; // raw bytes of the scanned form image — may be null if not available
  bool _isLoadingImage = false; // true while fetching the image from DB

  bool _isSubmitting = false; // true while sending correction to n8n
  bool _isDiscarding = false; // true while marking record as discarded

  // Convenience getters — shorter than checking widget.error['source'] every time
  bool get _isSheet => widget.error['source'] == 'google_sheet'; // true if from google sheet
  bool get _isInstructorError =>
      widget.error['error_type'] == 'instructor_not_found'; // true if instructor is the problem
  // safely parse the raw_data JSON — if it's not a Map, return empty map to avoid crash
  Map<String, dynamic> get _rawData => (widget.error['raw_data'] is Map)
      ? Map<String, dynamic>.from(widget.error['raw_data'] as Map)
      : <String, dynamic>{};

  @override
  void initState() {
    super.initState();

    // pre-fill the text fields with the raw names from the error record
    _instructorCtrl = TextEditingController(
        text: widget.error['raw_instructor_name']?.toString() ?? '');
    _subjectCtrl = TextEditingController(
        text: widget.error['raw_subject_name']?.toString() ?? '');

    // Score controllers only needed for scan errors (staff may edit)
    // sheet scores are trusted and locked — dili ta mag-edit sa sheet data
    if (!_isSheet) {
      _initScoreControllers(); // set up m1-m10 and p1-p10 controllers
      _loadScanImage();        // fetch the scanned form image for reference
    }

    // clear instructor suggestions when focus leaves the field
    // small delay to allow tap on suggestion before it disappears
    _instructorFocus.addListener(() {
      if (!_instructorFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _instructorSuggestions = []);
        });
      }
    });
    // same for subject field — ayaw instantly disappear ang suggestions
    _subjectFocus.addListener(() {
      if (!_subjectFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _subjectSuggestions = []);
        });
      }
    });
  }

  @override
  void dispose() {
    // clean up all controllers and focus nodes — memory hygiene is importente
    _instructorCtrl.dispose();
    _subjectCtrl.dispose();
    _instructorFocus.dispose();
    _subjectFocus.dispose();
    _instructorDebounce?.cancel(); // cancel pending debounce if screen closes
    _subjectDebounce?.cancel();
    for (final c in _scoreCtrlMap.values) {
      c.dispose(); // dispose each score controller individually
    }
    super.dispose();
  }

  // ── Score controllers init ────────────────────────────────────────────────

  // creates text controllers for all 20 score fields: m1-m10 and p1-p10
  // pre-fills them from the raw_data in the error record if values exist
  void _initScoreControllers() {
    final raw = _rawData;
    for (int i = 1; i <= 10; i++) {
      // management scores m1 to m10
      _scoreCtrlMap['m$i'] =
          TextEditingController(text: raw['m$i']?.toString() ?? '');
      // performance scores p1 to p10
      _scoreCtrlMap['p$i'] =
          TextEditingController(text: raw['p$i']?.toString() ?? '');
    }
  }

  // ── Load image from failed_scan_queue ─────────────────────────────────────

  // fetches the base64-encoded scanned form image from the database
  // uses the task_id from the error to find the corresponding scan record
  Future<void> _loadScanImage() async {
    final taskId = widget.error['task_id']?.toString();
    if (taskId == null || taskId.isEmpty) return; // no task ID — wala image to load

    setState(() => _isLoadingImage = true);
    try {
      final result = await _supabase
          .from('failed_scan_queue')
          .select('n8n_ocr_image') // the base64 image column
          .eq('task_id', taskId)
          .maybeSingle(); // might not exist — use maybeSingle to avoid crash

      if (mounted && result != null) {
        final b64 = result['n8n_ocr_image']?.toString();
        if (b64 != null && b64.isNotEmpty) {
          // decode base64 string into raw image bytes
          setState(() => _imageBytes = base64Decode(b64));
        }
      }
    } catch (e) {
      debugPrint('[ImportErrorDetail] Load image error: $e'); // log and move on
    } finally {
      if (mounted) setState(() => _isLoadingImage = false); // stop image loading spinner
    }
  }

  // ── Instructor autocomplete ────────────────────────────────────────────────

  // called on every keystroke in the instructor text field
  // resets the selected ID and debounces the DB query — dili ta mag-spam ang supabase
  void _onInstructorChanged(String query) {
    _selectedInstructorId = null; // clear selection since text changed
    _instructorDebounce?.cancel(); // cancel previous timer if still pending
    if (query.trim().length < 2) {
      setState(() => _instructorSuggestions = []); // too short to search — clear suggestions
      return;
    }
    // wait 300ms after last keystroke before actually searching
    _instructorDebounce = Timer(const Duration(milliseconds: 300),
        () => _searchInstructors(query.trim()));
  }

  // searches the user_info table for instructors matching the query
  // does a case-insensitive partial match on both first and last name
  Future<void> _searchInstructors(String query) async {
    try {
      final results = await _supabase
          .from('user_info')
          .select('id, first_name, last_name')
          .or('first_name.ilike.%$query%,last_name.ilike.%$query%') // partial match, both names
          .limit(6); // max 6 suggestions — enough, dili ta mag-overwhelm ang admin
      if (mounted) {
        setState(() => _instructorSuggestions =
            List<Map<String, dynamic>>.from(results as List));
      }
    } catch (e) {
      debugPrint('[ImportErrorDetail] Instructor search: $e');
    }
  }

  // called when admin taps a suggestion from the instructor dropdown
  // fills the text field and saves the selected ID for submission
  void _selectInstructor(Map<String, dynamic> item) {
    setState(() {
      _instructorCtrl.text =
          '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim(); // fill with full name
      _selectedInstructorId = item['id']?.toString(); // save ID — this is what actually gets submitted
      _instructorSuggestions = []; // hide the dropdown
    });
    _instructorFocus.unfocus(); // dismiss keyboard after selection
  }

  // ── Subject autocomplete ───────────────────────────────────────────────────

  // called on every keystroke in the subject field — same debounce pattern as instructor
  void _onSubjectChanged(String query) {
    _selectedSubjectId = null; // reset selection
    _subjectDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _subjectSuggestions = []); // too short — clear and wait
      return;
    }
    _subjectDebounce = Timer(const Duration(milliseconds: 300),
        () => _searchSubjects(query.trim()));
  }

  // searches the subjects table for matches by code or name
  // both code and name are searched so admin can type either — flexible kaayo
  Future<void> _searchSubjects(String query) async {
    try {
      final results = await _supabase
          .from('subjects')
          .select('id, subject_code, subject_name')
          .or('subject_code.ilike.%$query%,subject_name.ilike.%$query%') // match code OR name
          .limit(6); // same cap — 6 is enough for autocomplete
      if (mounted) {
        setState(() => _subjectSuggestions =
            List<Map<String, dynamic>>.from(results as List));
      }
    } catch (e) {
      debugPrint('[ImportErrorDetail] Subject search: $e');
    }
  }

  // called when admin picks a subject from the suggestions dropdown
  // fills the field with "CODE — Name" format and stores the ID
  void _selectSubject(Map<String, dynamic> item) {
    setState(() {
      _subjectCtrl.text =
          '${item['subject_code'] ?? ''} — ${item['subject_name'] ?? ''}'.trim(); // readable format
      _selectedSubjectId = item['id']?.toString(); // ID is what matters for DB
      _subjectSuggestions = []; // hide dropdown
    });
    _subjectFocus.unfocus(); // bye keyboard
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  // submits the corrected data to n8n for re-processing
  // requires both instructor and subject to be selected — no shortcuts here, ayaw mag-skip
  Future<void> _submit() async {
    if (_selectedInstructorId == null) {
      _showSnack('Select an instructor from the suggestions.', AppColors.warning);
      return; // cannot proceed without valid instructor ID
    }
    if (_selectedSubjectId == null) {
      _showSnack('Select a subject from the suggestions.', AppColors.warning);
      return; // same — subject is required too
    }

    setState(() => _isSubmitting = true); // lock the button
    try {
      // For scan errors, collect the (possibly corrected) scores
      // start with original raw data and overwrite scores if they were edited
      final correctedRawData = Map<String, dynamic>.from(_rawData);
      if (!_isSheet) {
        // parse each score field — invalid or empty values default to 0
        for (int i = 1; i <= 10; i++) {
          correctedRawData['m$i'] =
              int.tryParse(_scoreCtrlMap['m$i']?.text.trim() ?? '') ?? 0;
          correctedRawData['p$i'] =
              int.tryParse(_scoreCtrlMap['p$i']?.text.trim() ?? '') ?? 0;
        }
      }

      final currentUserId = _supabase.auth.currentUser?.id; // who is doing the fixing — accountability

      // build the payload for n8n — all the corrected info in one object
      final payload = <String, dynamic>{
        'import_error_id': widget.error['id'],      // the specific error being resolved
        'corrected_instructor_id': _selectedInstructorId, // the correct instructor
        'corrected_subject_id': _selectedSubjectId,       // the correct subject
        'term_id': widget.error['raw_term_id'],           // academic term context
        'resolved_by': currentUserId,                     // who fixed it
        'raw_data': correctedRawData,                     // the (possibly edited) score data
        'source': widget.error['source'],                 // 'google_sheet' or 'scan'
        'timestamp': DateTime.now().toIso8601String(),    // when the fix was made
      };

      // POST the correction payload to n8n for re-processing
      // n8n will pick up from here and insert into the proper tables
      final response = await http
          .post(
            Uri.parse(Env.n8nImportErrorCorrectionUrl), // the n8n webhook URL from env config
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30)); // 30 second timeout — if slower than this, something wrong

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // n8n accepted it — now mark the error as resolved directly in Supabase too
        await _supabase.from('import_errors').update({
          'status': 'resolved',           // no longer pending
          'resolved_at': DateTime.now().toIso8601String(),
          'resolved_by': currentUserId,
        }).eq('id', widget.error['id']);

        if (mounted) {
          _showSnack('✅ Submitted! Data is now being processed.', AppColors.success);
          Navigator.pop(context); // go back — the error is no longer in the list
        }
      } else {
        // n8n returned an error status — throw so we land in catch
        throw Exception('n8n error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', AppColors.error); // show what went wrong
    } finally {
      if (mounted) setState(() => _isSubmitting = false); // unlock the button — wala choice
    }
  }

  // ── Discard ────────────────────────────────────────────────────────────────

  // marks the error record as "discarded" — means we're intentionally ignoring it
  // shows a confirmation dialog first because this is semi-permanent
  Future<void> _discard() async {
    // ask user to confirm before discarding — prevent accidental clicks
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Discard Error?',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        // note: original scan data stays in DB even after discard — it's not deleted
        content: const Text(
            'This will mark the record as discarded. The original scan stays in the database.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), // cancel — go back
              child: const Text('Cancel')),
          Pressable(
            child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(context, true), // confirm discard
            child: const Text('Discard',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          ),
        ],
      ),
    );
    if (confirmed != true) return; // user cancelled — do nothing, dili ta mag-force

    setState(() => _isDiscarding = true); // show spinner in discard button
    try {
      // update the status to 'discarded' in supabase — simple update, no n8n needed
      await _supabase
          .from('import_errors')
          .update({'status': 'discarded'}).eq('id', widget.error['id']);
      if (mounted) {
        _showSnack('Record discarded.', AppColors.textSecondary); // inform user
        Navigator.pop(context); // go back to the list
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', AppColors.error); // show error if update failed
    } finally {
      if (mounted) setState(() => _isDiscarding = false); // unlock button
    }
  }

  // shorthand for showing a snackbar — used many times so worth extracting
  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final raw = _rawData; // the raw data from the original failed record

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true, // important — form shifts up when keyboard appears
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fix Import Error',
                style: TextStyle(
                    color: AppColors.textInverted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            // shows source type in subtitle — sheet or scan
            Text(
              _isSheet ? '📊 From Google Sheet' : '📷 From Scan',
              style: const TextStyle(
                  color: AppColors.textInvertedDim, fontSize: 11),
            ),
          ],
        ),
        actions: [
          // discard button in top right — with spinner while in progress
          Pressable(
            child: TextButton.icon(
            icon: _isDiscarding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.error))
                : const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 18),
            label: const Text('Discard',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
            onPressed: _isDiscarding ? null : _discard, // disabled while discarding
          ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Error type banner ───────────────────────────────────────────
          // colored banner at the top explaining what is wrong — hard to miss
          Entrance(index: 0, child: _buildErrorBanner()),

          // ── Scanned image (scan errors only) ────────────────────────────
          // only show the image section if it came from a scan — sheet has no image
          if (!_isSheet) Entrance(index: 1, child: _buildImageSection()),

          // ── Scrollable form ─────────────────────────────────────────────
          // the main correction form — instructor search, subject search, scores
          Expanded(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  left: 20, right: 20, top: 16,
                  bottom: 24, // extra space above keyboard
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Original data reference card — shows what the importer received
                    Entrance(index: 2, child: _buildOriginalDataCard(raw)),
                    const SizedBox(height: 20),

                    // Correction section heading
                    const Text('CORRECT THE ASSIGNMENT',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    // brief instructions on what to do — different message for sheet vs scan
                    Text(
                      'Search and select the correct instructor and subject. '
                      '${_isSheet ? 'Scores are locked (sheet values are trusted).' : 'You can also edit the scores below.'}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // Autocomplete fields for instructor and subject
                    _buildInstructorField(),
                    _buildSubjectField(),

                    const SizedBox(height: 20),

                    // Scores section — editable for scan source, read-only for sheet
                    // sheet scores are trusted as-is — importente to remember this
                    Entrance(
                      index: 3,
                      child: _isSheet
                        ? _buildScoresReadOnly(raw)   // locked view for sheet data
                        : _buildScoresEditable(),      // editable grid for scan data
                    ),

                    const SizedBox(height: 20),
                  ],
                ),   // Column
              ),     // SingleChildScrollView
            ),       // AnimatedPadding
          ),         // Expanded

          // ── Submit bar ──────────────────────────────────────────────────
          // sticky bottom bar with the submit button — always visible
          _buildSubmitBar(),
        ],
      ),
    );
  }

  // ── Error banner ───────────────────────────────────────────────────────────

  // colored banner at the top of the screen explaining what kind of error this is
  // red for instructor not found, yellow for subject not found — color codes matter
  Widget _buildErrorBanner() {
    final color = _isInstructorError ? AppColors.error : AppColors.warning; // severity color
    final icon = _isInstructorError
        ? Icons.person_off_outlined   // person with X — instructor missing
        : Icons.menu_book_outlined;   // open book — subject missing
    final rawValue = _isInstructorError
        ? widget.error['raw_instructor_name'] ?? '(unknown)'
        : widget.error['raw_subject_name'] ?? '(unknown)'; // the thing that failed to match
    final msg = _isInstructorError
        ? 'Instructor "$rawValue" was not found.\nSearch and select the correct one below.'
        : 'Subject "$rawValue" was not found.\nSearch and select the correct one below.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10), // very light background tint
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20), // icon matching error type
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.5)), // 1.5 line height for readability
          ),
        ],
      ),
    );
  }

  // ── Image section (scan only) ──────────────────────────────────────────────

  // shows the original scanned form image so admin can see what was actually submitted
  // has three states: loading, image available (tappable), image not available
  Widget _buildImageSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SCANNED FORM IMAGE',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_isLoadingImage)
            // loading state — image is being fetched from DB
            Container(
              height: 130,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              ),
            )
          else if (_imageBytes != null)
            // image loaded successfully — show it and allow zooming on tap
            GestureDetector(
              onTap: () => _showZoomedImage(_imageBytes!), // tap to open fullscreen viewer
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      _imageBytes!,
                      width: double.infinity,
                      height: 130, // fixed thumbnail height
                      fit: BoxFit.cover, // cover the box, crop if needed
                    ),
                  ),
                  // "tap to zoom" overlay hint in bottom right corner
                  Container(
                    margin: const EdgeInsets.all(6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black54, // semi-transparent dark bg
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Tap to zoom',
                            style:
                                TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            // no image available — maybe it was never stored or the task_id is wrong
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported_outlined,
                        color: AppColors.textTertiary, size: 20),
                    SizedBox(width: 8),
                    Text('Image not available',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // opens a fullscreen zoomable image viewer dialog
  // allows pinch-to-zoom up to 8x — for when admin needs to really squint at the handwriting
  void _showZoomedImage(Uint8List bytes) {
    showDialog(
      context: context,
      barrierColor: Colors.black87, // dark background for focus
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            // zoomable image — pinch to zoom, drag to pan
            InteractiveViewer(
              minScale: 0.5,  // can zoom out a bit
              maxScale: 8.0,  // up to 8x zoom — importente for blurry handwriting
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            // X button in top right to close the viewer
            Positioned(
              top: 0, right: 0,
              child: GestureDetector(
                onTap: () => Navigator.pop(context), // close the dialog
                child: Container(
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
            // bottom hint text — tell user they can pinch to zoom
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
                child: const Text('Scanned Form  •  Pinch to zoom',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Original data card ────────────────────────────────────────────────────

  // shows a read-only card with the original raw data from the failed import
  // useful for admin to see what the system received before they start correcting
  Widget _buildOriginalDataCard(Map<String, dynamic> raw) {
    final remarks = raw['remarks']?.toString() ?? ''; // optional remarks field
    final studentId = widget.error['raw_student_id']?.toString() ?? '—'; // the student's ID

    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // icon differs based on source — table for sheet, scanner for scan
              Icon(
                _isSheet
                    ? Icons.table_chart_outlined
                    : Icons.document_scanner_outlined,
                color: AppColors.primaryText, size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Original Data from ${_isSheet ? 'Google Sheet' : 'Scan'}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const Divider(height: 16),
          // display the four key data points from the original record
          _dataRow('Instructor (raw)',
              widget.error['raw_instructor_name'] ?? '—'), // what the importer received
          _dataRow('Subject (raw)', widget.error['raw_subject_name'] ?? '—'),
          _dataRow('Student ID', studentId),
          if (remarks.isNotEmpty) _dataRow('Remarks', remarks), // only show if has value
        ],
      ),
    );
  }

  // builds a label-value row inside the original data card
  // fixed-width label column so all values line up nicely
  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110, // fixed label width for alignment
            child: Text('$label:',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Scores — READ-ONLY (Google Sheet) ─────────────────────────────────────

  // shows the scores from a google sheet import in a locked grid
  // sheet scores are trusted — dili ta mag-edit, just displaying for reference
  Widget _buildScoresReadOnly(Map<String, dynamic> raw) {
    // check if either management or performance scores have any values
    final hasM = List.generate(10, (i) => raw['m${i + 1}']).any((v) => v != null);
    final hasP = List.generate(10, (i) => raw['p${i + 1}']).any((v) => v != null);
    if (!hasM && !hasP) return const SizedBox.shrink(); // no scores — hide this section entirely

    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline,
                  size: 14, color: AppColors.textTertiary), // lock icon — read only
              const SizedBox(width: 6),
              const Text('Scores (locked — from Google Sheet)',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              const Spacer(),
              // "Read-only" badge on the right — so nobody tries to edit
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Read-only',
                    style: TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // management scores grid — only if any m values exist
          if (hasM) ...[
            _sectionLabel('Management'),
            const SizedBox(height: 6),
            _scoreGridReadOnly(raw, 'm'), // read-only grid for m1-m10
            const SizedBox(height: 12),
          ],
          // performance scores grid — only if any p values exist
          if (hasP) ...[
            _sectionLabel('Performance'),
            const SizedBox(height: 6),
            _scoreGridReadOnly(raw, 'p'), // read-only grid for p1-p10
          ],
        ],
      ),
    );
  }

  // builds a 5-column read-only score grid for either "m" or "p" prefix
  // each cell shows the key (e.g. M1) and its value — empty cells are grayed out
  Widget _scoreGridReadOnly(Map<String, dynamic> raw, String prefix) {
    return GridView.builder(
      shrinkWrap: true, // don't try to fill all available height
      physics: const NeverScrollableScrollPhysics(), // parent handles scrolling
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, childAspectRatio: 1.4,
        crossAxisSpacing: 6, mainAxisSpacing: 6,
      ),
      itemCount: 10, // always 10 items (1 through 10)
      itemBuilder: (_, i) {
        final key = '$prefix${i + 1}'; // e.g. "m1", "p5"
        final val = raw[key]?.toString() ?? '—'; // value or dash if missing
        final isEmpty = val == '—' || val.isEmpty; // flag for grayed styling
        return Container(
          decoration: BoxDecoration(
            // empty cells have lighter background and border
            color: isEmpty
                ? AppColors.background
                : AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isEmpty
                    ? AppColors.borderHairline
                    : AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(key.toUpperCase(), // label like "M1", "P3"
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              Text(val, // the actual score value
                  style: TextStyle(
                      color: isEmpty
                          ? AppColors.textTertiary // grayed if empty
                          : AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  // ── Scores — EDITABLE (Scan errors) ───────────────────────────────────────

  // shows an editable score grid for scan-sourced errors
  // admin can correct scores that the OCR may have read wrong — numbers only, 1 digit max
  Widget _buildScoresEditable() {
    final hasAny =
        _scoreCtrlMap.values.any((c) => c.text.isNotEmpty); // any pre-filled scores?
    if (_scoreCtrlMap.isEmpty) return const SizedBox.shrink(); // no controllers — hide section

    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note,
                  size: 16, color: AppColors.primaryText), // pencil icon — this is editable
              const SizedBox(width: 6),
              const Text('Scores (editable — from Scan)',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              const Spacer(),
              // "Tap to edit" badge — tell the admin they can change these
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Tap to edit',
                    style: TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          // warning if OCR didn't detect any scores — needs manual entry
          if (!hasAny)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Scores were not detected in the scan. Enter them manually.',
                style: TextStyle(
                    color: AppColors.warning.withValues(alpha: 0.9),
                    fontSize: 11),
              ),
            ),
          const SizedBox(height: 12),
          _sectionLabel('Management (M1 – M10)'), // label for management scores
          const SizedBox(height: 8),
          _scoreGridEditable('m'), // editable grid for m1-m10
          const SizedBox(height: 14),
          _sectionLabel('Performance (P1 – P10)'), // label for performance scores
          const SizedBox(height: 8),
          _scoreGridEditable('p'), // editable grid for p1-p10
        ],
      ),
    );
  }

  // builds a 5-column editable score grid for a given prefix ("m" or "p")
  // each cell is a TextField that only accepts single digits — murag a scoresheet
  Widget _scoreGridEditable(String prefix) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // let parent scroll
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1.1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 10,
      itemBuilder: (_, i) {
        final key = '$prefix${i + 1}'; // e.g. "m1", "p10"
        return TextField(
          controller: _scoreCtrlMap[key], // bound to the pre-initialized controller
          keyboardType: TextInputType.number, // number keyboard — dili text
          textAlign: TextAlign.center, // center the digit in the cell
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,   // only allow numbers
            LengthLimitingTextInputFormatter(1),       // max 1 digit — score is 0-9
          ],
          decoration: InputDecoration(
            labelText: key.toUpperCase(), // label like "M1", "P5"
            labelStyle: const TextStyle(fontSize: 11),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: EdgeInsets.zero, // no extra padding inside the cell
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5), // orange when focused
            ),
          ),
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16), // big bold digit
        );
      },
    );
  }

  // tiny section label — lighter gray text used as subheadings in score sections
  Widget _sectionLabel(String text) => Text(text.toUpperCase(),
      style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700));

  // ── Autocomplete fields ────────────────────────────────────────────────────

  // builds the instructor search field with live autocomplete suggestions below it
  // shows a green checkmark suffix when an instructor has been selected
  Widget _buildInstructorField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _instructorCtrl,
          focusNode: _instructorFocus,
          onChanged: _onInstructorChanged, // triggers debounced search on each keystroke
          textCapitalization: TextCapitalization.words, // auto-capitalize names
          decoration: _inputDecoration(
            label: 'Correct Instructor Name',
            prefix: Icons.person_search_outlined,
            suffix: _selectedInstructorId != null
                ? const Icon(Icons.check_circle,
                    color: AppColors.success, size: 20) // green check when selected
                : null,
          ),
        ),
        // show suggestion dropdown only when there are results — ayaw mag-show if empty
        if (_instructorSuggestions.isNotEmpty)
          _buildSuggestions(
            _instructorSuggestions,
            itemBuilder: (item) => Row(children: [
              _avatar(_initials(item['first_name'], item['last_name'])), // avatar with initials
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim(),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  overflow: TextOverflow.ellipsis, // truncate long names
                ),
              ),
            ]),
            onTap: _selectInstructor, // call this when user picks a suggestion
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  // builds the subject search field with live autocomplete suggestions below it
  // shows subject code prominently since that's usually what people search by
  Widget _buildSubjectField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _subjectCtrl,
          focusNode: _subjectFocus,
          onChanged: _onSubjectChanged, // debounced subject search
          textCapitalization: TextCapitalization.characters, // subject codes are usually uppercase
          decoration: _inputDecoration(
            label: 'Correct Subject / Course Code',
            prefix: Icons.search_rounded,
            suffix: _selectedSubjectId != null
                ? const Icon(Icons.check_circle,
                    color: AppColors.success, size: 20) // green check when selected
                : null,
          ),
        ),
        // subject suggestions dropdown — only when results exist
        if (_subjectSuggestions.isNotEmpty)
          _buildSuggestions(
            _subjectSuggestions,
            itemBuilder: (item) => Row(children: [
              // subject code in an orange chip — easier to scan
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item['subject_code']?.toString() ?? '',
                  style: const TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item['subject_name']?.toString() ?? '',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  overflow: TextOverflow.ellipsis, // truncate long subject names
                ),
              ),
            ]),
            onTap: _selectSubject, // pick a subject
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  // builds the dropdown suggestions panel used under both autocomplete fields
  // displays items with separators, rounded corners, and a subtle shadow
  Widget _buildSuggestions(
    List<Map<String, dynamic>> items, {
    required Widget Function(Map<String, dynamic>) itemBuilder, // how to render each item
    required void Function(Map<String, dynamic>) onTap,         // what to do on tap
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8)) // shadow below — floating panel feel
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          // map each item to a tappable row, separated by thin borders except the last
          children: items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1; // no bottom border on last item
            return InkWell(
              onTap: () => onTap(entry.value), // pass item to callback
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: isLast
                      ? null // last item has no border below
                      : Border(
                          bottom: BorderSide(
                              color: AppColors.borderSubtle, width: 0.8)), // thin separator
                ),
                child: itemBuilder(entry.value), // render the item using provided builder
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────

  // sticky bottom bar with the submit button
  // button is disabled until both instructor and subject are selected — wala choice
  Widget _buildSubmitBar() {
    final canSubmit =
        _selectedInstructorId != null && _selectedSubjectId != null; // both required to enable
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        children: [
          // reminder hint shown when submit is disabled — tells user what they're missing
          if (!canSubmit)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline,
                      size: 13, color: AppColors.textTertiary),
                  SizedBox(width: 5),
                  Text(
                    'Select both instructor and subject to enable submit',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          // the big submit button — sends correction to n8n for re-processing
          Pressable(
            child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: canSubmit
                  ? const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDeep])
                  : null,
              color: canSubmit ? null : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(16),
              boxShadow: canSubmit
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: ElevatedButton.icon(
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textPrimary)) // spinner while sending
                  : const Icon(Icons.cloud_upload_outlined, size: 20), // upload icon
              label: Text(
                _isSubmitting ? 'Sending to n8n…' : 'Submit & Re-Process', // label changes while busy
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                foregroundColor: AppColors.textPrimary,
                disabledForegroundColor: AppColors.textSecondary,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: (_isSubmitting || !canSubmit) ? null : _submit, // disabled if not ready
            ),
          ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // builds a small circle avatar with initials inside
  // used in the instructor suggestion dropdown to make it look less boring
  Widget _avatar(String initials) {
    return Container(
      width: 34, height: 34,
      decoration: const BoxDecoration(
        color: AppColors.primaryTint, // light orange background
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(initials,
            style: const TextStyle(
                color: AppColors.primaryText,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ),
    );
  }

  // extracts up to 2 initials from first and last name strings
  // returns uppercase string like "JD" for "John Doe"
  String _initials(dynamic first, dynamic last) {
    final f = first?.toString() ?? '';
    final l = last?.toString() ?? '';
    return '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}'.toUpperCase();
  }

  // reusable input decoration for the autocomplete text fields
  // consistent styling with optional prefix icon and suffix widget
  InputDecoration _inputDecoration(
      {required String label, IconData? prefix, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixIcon: prefix != null
          ? Icon(prefix, size: 18, color: AppColors.primaryText)
          : null, // optional left icon
      suffixIcon: suffix, // optional right widget (e.g. checkmark)
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
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5), // orange when focused
      ),
    );
  }
}
