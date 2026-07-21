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
import '../core/services/system_settings_service.dart';
import '../core/services/auth_service.dart';
import 'gatherer_dashboard_view.dart';
import 'gatherer_scanner_view.dart';
import 'gatherer_sync_view.dart';
import 'gatherer_settings_view.dart';
import 'google_sheet_import_screen.dart';
import 'data_validation_screen.dart';

import 'gatherer_drawer.dart';
import 'models/scan_task.dart';

class DataGathererScreen extends StatefulWidget {
  final String userId;
  const DataGathererScreen({super.key, required this.userId});

  @override
  State<DataGathererScreen> createState() => _DataGathererScreenState();
}

class _DataGathererScreenState extends State<DataGathererScreen> {
  final _settingsService = SystemSettingsService();
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _currentSemester = '...';
  String _currentYear = '...';
  String? _currentTermId;
  String _userName = '...';
  String _userRole = 'Data Gatherer';
  StreamSubscription<SystemSettings>? _settingsSubscription;

  int _currentIndex = 0;

  // --- SHARED APP STATE ---
  int _scannedToday = 0;
  final int _dailyTarget = 500;
  bool _isSyncing = false;
  bool _isPaused = false;

  // --- N8N STATUS ---
  bool _n8nOnline = false;
  bool _checkingN8n = false;

  // --- SUPABASE STATS ---
  int _entriesToday = 0;
  int _overallSurveyCount = 0;

  final TextEditingController _linkController = TextEditingController();
  final List<ScanTask> _localQueue = [];

  static const _queueKey = 'gatherer_sync_queue';
  static String get _n8nHealthUrl => Env.n8nHealthUrl;

  @override
  void initState() {
    super.initState();
    _subscribeToSettings();
    _fetchUserInfo();
    _loadQueueFromStorage();
    _checkN8nStatus();
    _fetchSupabaseStats();
  }

  // ─── User Info ────────────────────────────────────────────────────────────

  Future<void> _fetchUserInfo() async {
    try {
      final info = await _authService.getUserInfo(widget.userId);
      if (mounted && info != null) {
        setState(() => _userName = '${info['first_name']} ${info['last_name']}');
      }
      // Fetch role
      final saoData = await _supabase
          .from('Sao_users')
          .select('roles:roles(Roles)')
          .eq('user_id', widget.userId)
          .maybeSingle();
      if (mounted && saoData != null) {
        final role = saoData['roles'];
        setState(() => _userRole = role is Map ? role['Roles'] ?? 'Data Gatherer' : 'Data Gatherer');
      }
    } catch (e) {
      debugPrint('fetchUserInfo error: $e');
    }
  }

  void _subscribeToSettings() {
    _settingsSubscription = _settingsService.streamSettings().listen((settings) {
      if (mounted) {
        final termChanged = settings.termId != _currentTermId;
        setState(() {
          _currentSemester = settings.semester;
          _currentYear = settings.academicYear;
          _currentTermId = settings.termId;
        });
        if (termChanged) _fetchSupabaseStats();
      }
    });
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    super.dispose();
  }

  // ─── N8N Health Check ─────────────────────────────────────────────────────

  Future<void> _checkN8nStatus() async {
    if (_checkingN8n) return;
    setState(() => _checkingN8n = true);
    try {
      final response = await http
          .get(Uri.parse(_n8nHealthUrl))
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() => _n8nOnline = response.statusCode >= 200 && response.statusCode < 300);
      }
    } catch (_) {
      if (mounted) setState(() => _n8nOnline = false);
    } finally {
      if (mounted) setState(() => _checkingN8n = false);
    }
  }

  // ─── Supabase Stats ───────────────────────────────────────────────────────

  Future<void> _fetchSupabaseStats() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();

      final todayData = await _supabase
          .from('raw_GoogleSheet_data_result')
          .select('id')
          .gte('created_at', startOfDay);

      // Overall filtered by current term
      var overallQuery = _supabase
          .from('raw_GoogleSheet_data_result')
          .select('id');
      if (_currentTermId != null) {
        overallQuery = overallQuery.eq('term_id', _currentTermId!);
      }
      final overallData = await overallQuery;

      if (mounted) {
        setState(() {
          _entriesToday = (todayData as List).length;
          _overallSurveyCount = (overallData as List).length;
          _scannedToday = _entriesToday;
        });
      }
    } catch (e) {
      debugPrint('fetchSupabaseStats error: $e');
    }
  }

  // ─── Persistent Queue ─────────────────────────────────────────────────────

  Future<void> _loadQueueFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_queueKey) ?? [];
      final loaded = raw
          .map((s) => ScanTask.fromMap(jsonDecode(s) as Map<String, dynamic>))
          // Don't restore "uploading" — treat as pending on restart
          .map((t) => t.status == SyncStatus.uploading
              ? (ScanTask(id: t.id, localPath: t.localPath, status: SyncStatus.pending, retryCount: t.retryCount))
              : t)
          .toList();
      if (mounted) setState(() => _localQueue.addAll(loaded));
    } catch (e) {
      debugPrint('loadQueue error: $e');
    }
  }

  Future<void> _saveQueueToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _localQueue.map((t) => jsonEncode(t.toMap())).toList();
      await prefs.setStringList(_queueKey, encoded);
    } catch (e) {
      debugPrint('saveQueue error: $e');
    }
  }

  // ─── Queue Actions ────────────────────────────────────────────────────────

  void _deleteTask(ScanTask task) {
    setState(() => _localQueue.remove(task));
    _saveQueueToStorage();
  }

  void _pauseSync() {
    setState(() => _isPaused = true);
  }

  void _resumeSync() {
    setState(() => _isPaused = false);
    // Auto-retry any pending after resuming
    final pending = _localQueue.where((t) => t.status == SyncStatus.pending).toList();
    for (final t in pending) {
      _uploadToN8N(t);
    }
  }

  // ─── Link Import ──────────────────────────────────────────────────────────

  Future<void> _submitLink(String? manualLink) async {
    String link = manualLink ?? _linkController.text.trim();
    if (link.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 24),
            Text('Processing Data...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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

    final n8nLinkWebhookUrl = Env.n8nLinkUploadUrl;
    bool dialogPopped = false;

    try {
      final response = await http.post(
        Uri.parse(n8nLinkWebhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'term_id': _currentTermId,
          'link': link,
          'type': 'google_form_import',
          'semester': _currentSemester,
          'academic_year': _currentYear,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (mounted) {
        Navigator.of(context).pop();
        dialogPopped = true;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _linkController.clear();
        if (mounted) _showStatusDialog(title: 'Import Successful', message: 'The data has been successfully sent and processed.', isSuccess: true);
      } else {
        if (mounted) _showStatusDialog(title: 'Import Failed', message: 'Server returned an error (${response.statusCode}).', isSuccess: false);
      }
    } catch (e) {
      if (mounted && !dialogPopped) Navigator.of(context).pop();
      if (mounted) _showStatusDialog(title: 'Import Failed', message: 'Could not connect to n8n. Make sure the server is running.', isSuccess: false);
    }
  }

  void _showStatusDialog({required String title, required String message, required bool isSuccess}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(children: [
          Icon(isSuccess ? Icons.check_circle : Icons.error_outline, color: isSuccess ? AppColors.success : AppColors.error),
          const SizedBox(width: 10),
          Text(title),
        ]),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)))],
      ),
    );
  }

  // ─── Scan Logic ───────────────────────────────────────────────────────────

  void _performScan(String path) {
    final newTask = ScanTask(
      id: 'SCAN-${DateTime.now().millisecondsSinceEpoch}',
      localPath: path,
      status: SyncStatus.pending,
    );

    setState(() {
      _localQueue.insert(0, newTask);
      _scannedToday++;
    });

    _saveQueueToStorage();

    // Haptic feedback if enabled
    SharedPreferences.getInstance().then((prefs) {
      final hapticEnabled = prefs.getBool('gatherer_haptic_feedback') ?? true;
      if (hapticEnabled) HapticFeedback.mediumImpact();
    });

    if (!_isPaused) _uploadToN8N(newTask);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Captured! Syncing in background...'),
      backgroundColor: AppColors.success,
      duration: Duration(seconds: 1),
    ));
  }

  // ─── Upload to N8N ────────────────────────────────────────────────────────

  Future<void> _uploadToN8N(ScanTask task) async {
    if (task.status == SyncStatus.success) return;
    if (_isPaused) return;

    setState(() {
      task.status = SyncStatus.uploading;
      task.errorMessage = null;
    });

    try {
      final file = File(task.localPath);
      if (!await file.exists()) throw Exception('File not found');

      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final n8nWebhookUrl = Env.n8nScanUploadUrl;

      final response = await http.post(
        Uri.parse(n8nWebhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'term_id': _currentTermId,
          'image': base64Image,
          'task_id': task.id,
          'filename': task.localPath.split(Platform.pathSeparator).last,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => task.status = SyncStatus.success);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Upload Error: $e');
      setState(() {
        task.status = SyncStatus.failed;
        task.errorMessage = e.toString().contains('SocketException')
            ? 'Connection Refused (Check IP/URL)'
            : 'Sync Failed';
        task.retryCount++;
      });
    } finally {
      _saveQueueToStorage();
    }
  }

  void _syncData() async {
    if (_isPaused) return;
    final pendingTasks = _localQueue.where((t) => t.status != SyncStatus.success).toList();
    if (pendingTasks.isEmpty) return;

    setState(() => _isSyncing = true);
    for (var task in pendingTasks) {
      if (_isPaused) break;
      await _uploadToN8N(task);
    }
    if (mounted) setState(() => _isSyncing = false);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final List<String> tabTitles = ['Dashboard', 'Scanner', 'Validation', 'Sync Queue', 'Settings'];

    final int pendingCount = _localQueue.where((t) => t.status == SyncStatus.pending || t.status == SyncStatus.failed).length;
    final int successCount = _localQueue.where((t) => t.status == SyncStatus.success).length;

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
        onStartScan: () => setState(() => _currentIndex = 1),
        onImportData: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GoogleSheetImportScreen(
                userId: widget.userId,
                onSubmit: (link) => _submitLink(link),
              ),
            ),
          );
        },
      ),
      GathererScannerView(
        onScan: _performScan,
        queueCount: _localQueue.length,
        onOpenSync: () => setState(() => _currentIndex = 3),
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        onSendFormLink: (url) => _submitLink(url),
      ),
      DataValidationScreen(userId: widget.userId),
      GathererSyncView(
        queue: _localQueue,
        isSyncing: _isSyncing,
        isPaused: _isPaused,
        onSync: _syncData,
        onRetry: (task) => _uploadToN8N(task),
        onDelete: _deleteTask,
        onPause: _pauseSync,
        onResume: _resumeSync,
      ),
      const GathererSettingsView(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tabTitles[_currentIndex],
                style: const TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold, fontSize: 18)),
            Text('$_currentSemester, $_currentYear',
                style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 11)),
          ],
        ),
      ),
      drawer: GathererDrawer(
        currentIndex: _currentIndex,
        onMenuTap: (index) => setState(() => _currentIndex = index),
        userName: _userName,
        userRole: _userRole,
      ),
      body: screens[_currentIndex],
    );
  }
}
