// The main mothership screen for the data gatherer.
// This file hold everything together — dashboard, scanner, validation, sync,
// settings. If this file break, everything break. ayaw pag-touch unless sure ka.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../core/navigation/role_nav_config.dart'; // Added this import for UserRole
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/services/push_notification_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/config/env.dart';
import '../core/services/system_settings_service.dart';
import '../core/services/auth_service.dart';
import 'gatherer_dashboard_view.dart';
import 'gatherer_scanner_view.dart';
import 'gatherer_sync_view.dart';
import 'gatherer_settings_view.dart';
import 'google_sheet_import_screen.dart';
import 'data_validation_screen.dart';
import '../sao_admin/import_errors_screen.dart';
import 'failed_scans_screen.dart';
import '../widgets/apple_ui.dart';

import 'gatherer_drawer.dart';
import 'models/scan_task.dart';

// The widget itself — it a StatefulWidget because EVERYTHING here change constantly
class DataGathererScreen extends StatefulWidget {
  final String userId;
  final UserRole? originalRole; // Pass this if accessed via Role Switcher

  const DataGathererScreen({
    super.key,
    required this.userId,
    this.originalRole,
  });

  @override
  State<DataGathererScreen> createState() => _DataGathererScreenState();
}

// The state class where the real suffering happen
class _DataGathererScreenState extends State<DataGathererScreen> {
  final _settingsService = SystemSettingsService();
  final _authService = AuthService(); // for getting who this poor person is
  final _supabase = Supabase.instance.client; // our database overlord
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // key for the drawer, importente kaayo

  // semester and year — starts as '...' because we dont know yet, bahala na
  String _currentSemester = '...';
  String _currentYear = '...';
  String? _currentTermId; // null until settings load, wala choice
  String _userName = '...';
  String _userRole = 'Data Gatherer'; // default role, assume gatherer first
  StreamSubscription<SystemSettings>?
  _settingsSubscription; // listen for changes, ayaw kalimti cancel!

  // which tab is currently showing — 0 = Dashboard, the starting tab
  int _currentIndex = 0;

  // --- SHARED APP STATE ---
  // how many scans done today — this affect the progress bar sa dashboard
  int _scannedToday = 0;
  final int _dailyTarget = 500; // 500 scans a day, pray lang maabot
  bool _isSyncing = false; // true when actively pushing scans to n8n
  bool _isPaused = false; // when true, no uploads happen — manual break mode

  // --- N8N STATUS ---
  // whether the n8n automation server is alive or dead na
  bool _n8nOnline = false;
  bool _checkingN8n = false; // true while we pinging the server

  // --- REFRESH ---
  // true while refresh icon is spinning — show spinner, hide button
  bool _isRefreshing = false;

  // --- SUPABASE STATS ---
  // counts from the actual database, not just the local queue
  int _entriesToday = 0;
  int _overallSurveyCount = 0; // all surveys for this term, shown on dashboard

  final TextEditingController _linkController =
      TextEditingController(); // for manual link input
  final List<ScanTask> _localQueue =
      []; // local queue list of scans pending upload

  // key for storing queue in SharedPreferences — like saving your progress
  String get _queueKey => 'gatherer_sync_queue_${widget.userId}';
  // n8n health check URL, from env so we dont hardcode secrets. smart.
  static String get _n8nHealthUrl => Env.n8nHealthUrl;

  Future<void> _loadCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('gatherer_dashboard_${widget.userId}');
      if (cached != null) {
        final data = jsonDecode(cached);
        if (mounted) {
          setState(() {
            _userName = data['userName'] ?? _userName;
            _userRole = data['userRole'] ?? _userRole;
            _entriesToday = data['entriesToday'] ?? _entriesToday;
            _overallSurveyCount =
                data['overallSurveyCount'] ?? _overallSurveyCount;
            _scannedToday = data['entriesToday'] ?? _entriesToday;
            _currentSemester = data['semester'] ?? _currentSemester;
            _currentYear = data['year'] ?? _currentYear;
            _currentTermId = data['termId'] ?? _currentTermId;
          });
          debugPrint('[GATHERER] ⚡ Loaded cached dashboard instantly.');
        }
      }
    } catch (e) {
      debugPrint('[GATHERER] Failed to load cache: $e');
    }
  }

  Future<void> _saveCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'userName': _userName,
        'userRole': _userRole,
        'entriesToday': _entriesToday,
        'overallSurveyCount': _overallSurveyCount,
        'semester': _currentSemester,
        'year': _currentYear,
        'termId': _currentTermId,
      };
      await prefs.setString(
        'gatherer_dashboard_${widget.userId}',
        jsonEncode(cacheData),
      );
    } catch (e) {
      debugPrint('[GATHERER] Failed to save cache: $e');
    }
  }

  // runs when screen first open — start all the loading things
  @override
  void initState() {
    super.initState();
    _loadCachedDashboard(); // Load stale data instantly!
    _subscribeToSettings(); // listen for semester/term changes
    _fetchUserInfo(); // get the name and role of whoever logged in
    _loadQueueFromStorage(); // restore queue from last session, murag resurrection
    _checkN8nStatus(); // ping n8n to see if its alive
    _fetchSupabaseStats(); // pull the numbers from the database

    try {
      PushNotificationService().init();
    } catch (e) {
      debugPrint('Error init push notifications: $e');
    }
  }

  // ─── User Info ────────────────────────────────────────────────────────────

  // fetch the name and role of the logged-in user from supabase
  // if it fail, we just print error and move on — bahala na
  Future<void> _fetchUserInfo() async {
    try {
      final info = await _authService.getUserInfo(widget.userId);
      if (mounted && info != null) {
        // combine first and last name into one string for display
        setState(
          () => _userName = '${info['first_name']} ${info['last_name']}',
        );
      }
      // Fetch role — check the Sao_users table for the role linked to this user
      final saoData = await _supabase
          .from('Sao_users')
          .select('roles:roles(Roles)')
          .eq('user_id', widget.userId)
          .maybeSingle();
      if (mounted && saoData != null) {
        final role = saoData['roles'];
        // if role is a Map, get the 'Roles' key; if dili, default to 'Data Gatherer'
        setState(
          () => _userRole = role is Map
              ? role['Roles'] ?? 'Data Gatherer'
              : 'Data Gatherer',
        );
      }
      await _saveCachedDashboard();
    } catch (e) {
      debugPrint('fetchUserInfo error: $e'); // failed, but we survive
    }
  }

  void _subscribeToSettings() {
    _settingsSubscription = _settingsService.streamSettings().listen((
      settings,
    ) async {
      if (!mounted) return;

      // Check if term changed from last known term in storage
      final prefs = await SharedPreferences.getInstance();
      final savedTermId = prefs.getString('gatherer_last_term_id');

      // If we have a saved term and it's different from the new one, wipe the queue
      if (savedTermId != null && savedTermId != settings.termId) {
        _clearLocalQueue();
      }

      // Save the new term ID for next time if it's not null
      if (settings.termId != null) {
        await prefs.setString('gatherer_last_term_id', settings.termId!);
      }

      if (mounted) {
        final termChanged =
            settings.termId != _currentTermId; // did the term change?
        setState(() {
          _currentSemester = settings.semester;
          _currentYear = settings.academicYear;
          _currentTermId = settings.termId;
        });
        if (termChanged)
          _fetchSupabaseStats(); // term changed, re-fetch everything
      }
    });
  }

  // clean up when this widget die — very importente to cancel the subscription
  @override
  void dispose() {
    _settingsSubscription?.cancel(); // if we dont cancel, memory leak. bad.
    super.dispose();
  }

  // ─── N8N Health Check ─────────────────────────────────────────────────────

  // ping n8n health endpoint to see if the automation server is running
  // if no response in 5 seconds, assume it dead. n8nOnline = false.
  Future<void> _checkN8nStatus() async {
    if (_checkingN8n) return; // already checking, dili ta mag-double check
    setState(() => _checkingN8n = true);
    try {
      final response = await http
          .get(Uri.parse(_n8nHealthUrl))
          .timeout(const Duration(seconds: 5)); // 5 seconds max patience
      if (mounted) {
        // status 200-299 = alive, anything else = problem
        setState(
          () => _n8nOnline =
              response.statusCode >= 200 && response.statusCode < 300,
        );
      }
    } catch (_) {
      // timeout or connection error — server probably dead, or wrong IP
      if (mounted) setState(() => _n8nOnline = false);
    } finally {
      if (mounted)
        setState(
          () => _checkingN8n = false,
        ); // done checking, whether success or not
    }
  }

  // ─── Supabase Stats ───────────────────────────────────────────────────────

  // pull two numbers from the database:
  // 1. how many entries were created TODAY (midnight UTC to now)
  // 2. how many entries exist for the CURRENT TERM overall
  Future<void> _fetchSupabaseStats() async {
    try {
      final today = DateTime.now();
      // start of today in UTC — so we only count today's submissions
      final startOfDay = DateTime(
        today.year,
        today.month,
        today.day,
      ).toUtc().toIso8601String();

      // query for entries created since midnight today
      final todayData = await _supabase
          .from('sast_all_raw_data_survey')
          .select('id')
          .gte('created_at', startOfDay);

      // Overall filtered by current term — if no term yet, get all
      var overallQuery = _supabase
          .from('sast_all_raw_data_survey')
          .select('id');
      if (_currentTermId != null) {
        overallQuery = overallQuery.eq(
          'term_id',
          _currentTermId!,
        ); // filter by term
      }
      final overallData = await overallQuery;

      if (mounted) {
        setState(() {
          _entriesToday = (todayData as List).length; // count of today's rows
          _overallSurveyCount =
              (overallData as List).length; // count for whole term
          _scannedToday =
              _entriesToday; // sync local counter with database reality
        });
      }
      await _saveCachedDashboard();
    } catch (e) {
      debugPrint('fetchSupabaseStats error: $e'); // database angry, we sad
    }
  }

  // ─── Persistent Queue ─────────────────────────────────────────────────────

  // load the saved scan queue from SharedPreferences on app start
  // if a task was "uploading" when app closed, we treat it as "pending" again
  // because we dont know if upload actually finish — bahala na, retry it
  Future<void> _loadQueueFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docDir = await getApplicationDocumentsDirectory();
      final raw =
          prefs.getStringList(_queueKey) ?? []; // empty list if nothing saved
      final loaded = raw
          .map((s) => ScanTask.fromMap(jsonDecode(s) as Map<String, dynamic>))
          .map((t) {
            // Reconstruct absolute path safely because app sandbox dir changes on iOS/Android updates
            final filename = p.basename(t.localPath);
            final newPath = p.join(docDir.path, filename);
            // Don't restore "uploading" — treat as pending on restart
            final status = t.status == SyncStatus.uploading
                ? SyncStatus.pending
                : t.status;
            return ScanTask(
              id: t.id,
              localPath: newPath,
              status: status,
              retryCount: t.retryCount,
              errorMessage: t.errorMessage,
            );
          })
          .toList();
      if (mounted)
        setState(
          () => _localQueue.addAll(loaded),
        ); // put them back in the queue
    } catch (e) {
      debugPrint('loadQueue error: $e'); // storage broken? that unusual
    }
  }

  // save the current queue to SharedPreferences so it survive app restarts
  // encode each task as JSON string — simple but effective
  Future<void> _saveQueueToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _localQueue.map((t) => jsonEncode(t.toMap())).toList();
      await prefs.setStringList(_queueKey, encoded); // overwrite old queue
    } catch (e) {
      debugPrint(
        'saveQueue error: $e',
      ); // if this fail, queue lost on restart. oops.
    }
  }

  // clear the entire local queue and delete the image files
  // called automatically when the term changes to free up space
  void _clearLocalQueue() {
    for (var task in _localQueue) {
      try {
        final file = File(task.localPath);
        if (file.existsSync()) {
          file.deleteSync(); // delete the actual image file to save storage
        }
      } catch (e) {
        debugPrint('Failed to delete file: $e'); // ignore if delete fails
      }
    }
    if (mounted) {
      setState(() {
        _localQueue.clear();
      });
    }
    _saveQueueToStorage();
  }

  // ─── Queue Actions ────────────────────────────────────────────────────────

  // remove one task from the local queue and save immediately
  // user swipe-delete or press delete — task gone, image file still on device
  void _deleteTask(ScanTask task) {
    setState(() => _localQueue.remove(task)); // remove from memory
    _saveQueueToStorage(); // persist the removal
  }

  // pause all uploads — no more sending to n8n until resume is called
  void _pauseSync() {
    setState(() => _isPaused = true); // simple flag flip
  }

  // resume uploads after pause — also auto-retry all pending tasks
  void _resumeSync() {
    setState(() => _isPaused = false); // unpause
    // Auto-retry any pending after resuming — dont make user tap retry manually
    final pending = _localQueue
        .where((t) => t.status == SyncStatus.pending)
        .toList();
    for (final t in pending) {
      _uploadToN8N(t); // kick off upload for each pending task
    }
  }

  // ─── Link Import ──────────────────────────────────────────────────────────

  // submit a Google Form/Sheet link to n8n for processing
  // shows a loading dialog while waiting — we not impatient but 30s timeout lang
  Future<void> _submitLink(String? manualLink) async {
    String link =
        manualLink ?? _linkController.text.trim(); // use provided or from field
    if (link.isEmpty) return; // nothing to submit, ayaw

    // show a spinner dialog so user know something is happening
    showDialog(
      context: context,
      barrierDismissible: false, // user cannot close this — they must wait
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 24),
            Text(
              'Processing Data...',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            SizedBox(height: 12),
            Text(
              'Please wait, we are validating and processing your Google Sheet data. This may take a moment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );

    final n8nLinkWebhookUrl =
        Env.n8nLinkUploadUrl; // the n8n webhook URL for link imports
    bool dialogPopped = false; // track if we already closed the dialog

    try {
      // POST the link and metadata to n8n — it will fetch the sheet and process
      final response = await http
          .post(
            Uri.parse(n8nLinkWebhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': widget.userId,
              'term_id': _currentTermId, // which term this import belongs to
              'link': link,
              'type': 'google_form_import',
              'semester': _currentSemester,
              'academic_year': _currentYear,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(
            const Duration(seconds: 30),
          ); // 30 seconds — if n8n slow, we wait

      if (mounted) {
        Navigator.of(context).pop(); // close the loading dialog
        dialogPopped = true;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _linkController.clear(); // clear the input field, import done
        if (mounted)
          _showStatusDialog(
            title: 'Import Successful',
            message: 'The data has been successfully sent and processed.',
            isSuccess: true,
          );
      } else {
        // n8n return an error status — something wrong server-side
        if (mounted)
          _showStatusDialog(
            title: 'Import Failed',
            message: 'Server returned an error (${response.statusCode}).',
            isSuccess: false,
          );
      }
    } catch (e) {
      // network error or timeout — n8n might be down, check IP/URL
      if (mounted && !dialogPopped)
        Navigator.of(context).pop(); // close dialog if not already closed
      if (mounted)
        _showStatusDialog(
          title: 'Import Failed',
          message: 'Could not connect to n8n. Make sure the server is running.',
          isSuccess: false,
        );
    }
  }

  // show a simple success or error dialog after an operation
  // used after link import and probably other places too
  void _showStatusDialog({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            // green check if success, red error icon if fail — very visual, importente
            Icon(
              isSuccess ? Icons.check_circle : Icons.error_outline,
              color: isSuccess ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Scan Logic ───────────────────────────────────────────────────────────

  // called when scanner captures a photo — creates a new ScanTask and queues it
  // also trigger haptic if enabled, and auto-upload if not paused
  void _performScan(String path) {
    // create a new scan task with unique ID based on current timestamp
    final newTask = ScanTask(
      id: 'SCAN-${DateTime.now().millisecondsSinceEpoch}', // unique enough. basin mag-duplicate if very fast
      localPath: path,
      status: SyncStatus.pending, // starts as pending, will upload soon
    );

    setState(() {
      _localQueue.insert(0, newTask); // put new scan at top of list
      _scannedToday++; // increment today's counter
    });

    _saveQueueToStorage(); // save to storage immediately — dont lose this scan

    // Haptic feedback if enabled — vibrate phone so scanner know it worked
    SharedPreferences.getInstance().then((prefs) {
      final hapticEnabled = prefs.getBool('gatherer_haptic_feedback') ?? true;
      if (hapticEnabled)
        HapticFeedback.mediumImpact(); // medium buzz, not too strong
    });

    // only auto-upload if we not paused — if paused, stays pending until resume
    if (!_isPaused) _uploadToN8N(newTask);

    // show quick snackbar — "captured!" so user know it registered
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Captured! Syncing in background...'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 1), // short — no need to be annoying
      ),
    );
  }

  // ─── Upload to N8N ────────────────────────────────────────────────────────

  // read the image file, encode it as base64, and POST it to n8n webhook
  // if success, mark as success. if fail, mark as failed and increment retry count
  Future<void> _uploadToN8N(ScanTask task) async {
    if (task.status == SyncStatus.success) return; // already done, skip
    if (_isPaused) return; // paused, ayaw mag-upload

    // mark as uploading so UI shows spinner for this task
    setState(() {
      task.status = SyncStatus.uploading;
      task.errorMessage = null; // clear previous error
    });

    try {
      final file = File(task.localPath);
      if (!await file.exists())
        throw Exception('File not found'); // image missing? error

      final bytes = await file.readAsBytes(); // read raw image bytes
      final base64Image = base64Encode(
        bytes,
      ); // encode to base64 string for JSON transport
      final paperSize = _extractPaperSize(
        task.localPath,
      ); // read paper size from filename tag

      final n8nWebhookUrl = Env.n8nScanUploadUrl; // the scan upload endpoint

      // POST the scan data — n8n will OCR the image and process it
      final response = await http
          .post(
            Uri.parse(n8nWebhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': widget.userId,
              'term_id': _currentTermId,
              'image': base64Image, // the actual image encoded as base64
              'task_id': task.id,
              'filename': task.localPath
                  .split(Platform.pathSeparator)
                  .last, // just the filename, not full path
              'paper_size':
                  paperSize, // explicit paper size — no need for n8n to parse filename
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 30)); // 30 seconds max, then timeout

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(
          () => task.status = SyncStatus.success,
        ); // n8n accept it, we done
      } else {
        throw Exception(
          'Server error: ${response.statusCode}',
        ); // n8n reject it
      }
    } catch (e) {
      debugPrint('Upload Error: $e');
      final errorStr = e.toString();
      final isConnectionError =
          errorStr.contains('SocketException') ||
          errorStr.contains('TimeoutException');

      setState(() {
        task.status = SyncStatus.failed; // mark as failed so user can retry
        // give a human-readable error — SocketException mean IP/URL wrong probably
        task.errorMessage = isConnectionError
            ? 'Connection Refused (Check IP/URL)'
            : 'Sync Failed';
        task.retryCount++; // track how many times this task has failed
      });

      if (isConnectionError && mounted) {
        _isPaused =
            true; // Auto-pause the rest of the queue so it doesn't spam errors

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              'Connection Interrupted',
              style: TextStyle(color: AppColors.error),
            ),
            content: const Text(
              'If data transmission is interrupted. Try again. No data transmitted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      _saveQueueToStorage(); // always save after upload attempt, success or not
    }
  }

  // extracts the paper size tag from the filename — scanner embeds it as _SHORT, _A4, or _LONG
  // e.g. "SCAN-1234_A4.jpg" → "A4",  "SCAN-5678_LONG.jpg" → "LONG"
  String _extractPaperSize(String path) {
    final filename = path.split(Platform.pathSeparator).last;
    if (filename.contains('_SHORT')) return 'SHORT';
    if (filename.contains('_A4')) return 'A4';
    if (filename.contains('_LONG')) return 'LONG';
    return 'UNKNOWN'; // fallback — should not happen if scanner always tags the file
  }

  // sync all non-success tasks — loops through and uploads one by one
  // stops if paused mid-loop — respect the pause flag
  void _syncData() async {
    if (_isPaused) return; // paused? stay paused, dili mag-upload
    final pendingTasks = _localQueue
        .where((t) => t.status != SyncStatus.success)
        .toList();
    if (pendingTasks.isEmpty) return; // nothing to do

    setState(() => _isSyncing = true); // show syncing state
    for (var task in pendingTasks) {
      if (_isPaused) break; // user pause mid-sync, we respect that
      await _uploadToN8N(task); // await each upload before moving to next
    }
    if (mounted) setState(() => _isSyncing = false); // done, clear syncing flag
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  // this the main build method — returns the complete screen with AppBar + drawer
  @override
  Widget build(BuildContext context) {
    // tab titles shown in the AppBar — order must match the screens list below
    final List<String> tabTitles = [
      'Dashboard',
      'Scanner',
      'Validation',
      'Sync Queue',
      'Import Errors',
      'Settings',
      'Import Instructions',
    ];

    // count how many tasks are pending or failed — shown as badge in drawer
    final int pendingCount = _localQueue
        .where(
          (t) =>
              t.status == SyncStatus.pending || t.status == SyncStatus.failed,
        )
        .length;
    final int successCount = _localQueue
        .where((t) => t.status == SyncStatus.success)
        .length;

    // the 5 screens — index must match tab titles above
    final List<Widget> screens = [
      GathererDashboardView(
        userName: _userName,
        userRole: _userRole,
        currentTerm: '$_currentSemester, $_currentYear',
        scanned: _scannedToday,
        target: _dailyTarget,
        queueCount: _localQueue.length,
        pendingCount: pendingCount,
        successCount: successCount,
        overallSurveyCount: _overallSurveyCount,
        n8nOnline: _n8nOnline,
        checkingN8n: _checkingN8n,
        onCheckN8n: _checkN8nStatus,
        onStartScan: () =>
            setState(() => _currentIndex = 1), // jump to scanner tab
        onImportData: () =>
            setState(() => _currentIndex = 6), // jump to import screen
      ),
      GathererScannerView(
        onScan: _performScan, // called when a photo is taken
        queueCount: _localQueue.length,
        onOpenSync: () =>
            setState(() => _currentIndex = 3), // jump to sync queue tab
        onMenuPressed: () =>
            _scaffoldKey.currentState?.openDrawer(), // open the side drawer
        onOpenImportData: () =>
            setState(() => _currentIndex = 6), // jump to import screen
      ),
      DataValidationScreen(
        userId: widget.userId,
      ), // validation tab — check flagged records
      GathererSyncView(
        queue: _localQueue,
        isSyncing: _isSyncing,
        isPaused: _isPaused,
        onSync: _syncData,
        onRetry: (task) => _uploadToN8N(task), // retry single failed task
        onDelete: _deleteTask,
        onPause: _pauseSync,
        onResume: _resumeSync,
      ),
      ImportErrorsScreen(
        showBackButton: false,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ), // import errors integrated as tab
      const GathererSettingsView(), // settings — profile, haptic, password, logout
      GoogleSheetImportScreen(
        userId: widget.userId,
        onSubmit: (link) {
          _submitLink(link);
          setState(() => _currentIndex = 0); // Return to dashboard after submit
        },
      ),
    ];

    return Scaffold(
      key: _scaffoldKey, // need this key to programmatically open the drawer
      backgroundColor: AppColors.background,
      appBar: _currentIndex == 4
          ? null
          : AppBar(
              backgroundColor: AppColors.surface,
              elevation: 0,
              iconTheme: const IconThemeData(color: AppColors.textPrimary),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // show the current tab name — updates when tab changes
                  Text(
                    tabTitles[_currentIndex],
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // show semester and year below — always visible for context
                  Text(
                    '$_currentSemester, $_currentYear',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              actions: [
                // if refreshing, show spinner; else show refresh button
                _isRefreshing
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: AppColors.primary,
                        ),
                        tooltip: 'Refresh',
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _isRefreshing = true);
                          // fetch stats and check n8n at the same time — parallel, faster
                          await Future.wait([
                            _fetchSupabaseStats(),
                            _checkN8nStatus(),
                          ]);
                          if (mounted) setState(() => _isRefreshing = false);
                          if (mounted) {
                            // tell user refresh done
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Dashboard refreshed'),
                                backgroundColor: AppColors.success,
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
              ],
            ),
      // side drawer — handles navigation between tabs and logout
      drawer: GathererDrawer(
        currentIndex: _currentIndex,
        onMenuTap: (index) =>
            setState(() => _currentIndex = index), // switch tab from drawer
        onImportTap: () => setState(() => _currentIndex = 6),
        userName: _userName,
        userRole: _userRole,
        originalRole:
            widget.originalRole, // Pass this to show the return button
      ),
      body: screens[_currentIndex], // show whichever screen is selected
      bottomNavigationBar: AppleFloatingTabBar(
        selectedIndex: _currentIndex < 4
            ? _currentIndex
            : 0, // Fallback so it doesn't crash on drawer screens
        onSelected: (idx) {
          setState(() => _currentIndex = idx);
        },
        items: const [
          AppleTabItem(
            icon: Icons.dashboard_rounded,
            selectedIcon: Icons.dashboard,
            label: 'Dashboard',
          ),
          AppleTabItem(
            icon: Icons.camera_alt_rounded,
            selectedIcon: Icons.camera_alt,
            label: 'Scanner',
          ),
          AppleTabItem(
            icon: Icons.fact_check_rounded,
            selectedIcon: Icons.fact_check,
            label: 'Validation',
          ),
          AppleTabItem(
            icon: Icons.cloud_upload_rounded,
            selectedIcon: Icons.cloud_upload,
            label: 'Sync Queue',
          ),
        ],
      ),
    );
  }
}
