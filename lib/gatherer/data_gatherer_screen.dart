// lib/gatherer/data_gatherer_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart';
import 'gatherer_dashboard_view.dart';
import 'gatherer_scanner_view.dart';
import 'gatherer_sync_view.dart';
import 'gatherer_settings_view.dart';
import 'data_validation_screen.dart';
import 'gatherer_drawer.dart';
import 'package:url_launcher/url_launcher.dart';

class DataGathererScreen extends StatefulWidget {
  const DataGathererScreen({super.key});

  @override
  State<DataGathererScreen> createState() => _DataGathererScreenState();
}

class _DataGathererScreenState extends State<DataGathererScreen> {
  int _currentIndex = 0;

  // --- SHARED APP STATE ---
  int _scannedToday = 145;
  final int _dailyTarget = 500;
  bool _isSyncing = false;

  // 👇 Controller for link (used in dashboard)
  final TextEditingController _linkController = TextEditingController();

  final List<Map<String, dynamic>> _localQueue = [
    {'id': 'FORM-892', 'subject': 'CS101', 'status': 'Ready to Sync'},
    {'id': 'FORM-893', 'subject': 'CS101', 'status': 'Ready to Sync'},
  ];

  // ==========================================
  // 🔗 OPEN LINK FUNCTION
  // ==========================================
  Future<void> _openLink() async {
    String link = _linkController.text.trim();

    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a link first')),
      );
      return;
    }

    // 👉 Auto add https if missing
    if (!link.startsWith('http')) {
      link = 'https://$link';
    }

    final Uri url = Uri.parse(link);

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid or cannot open link')),
      );
    }
  }

  // ==========================================
  // 📸 SCAN LOGIC
  // ==========================================
  void _performScan() {
    setState(() {
      _localQueue.insert(0, {
        'id': 'FORM-${894 + _localQueue.length}',
        'subject': 'Auto-Detected',
        'status': 'Processing...'
      });
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _localQueue[0]['status'] = 'Ready to Sync';
          _scannedToday++;
        });

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Form Scanned!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ));
      }
    });
  }

  // ==========================================
  // ☁️ SYNC LOGIC
  // ==========================================
  void _syncData() async {
    if (_localQueue.isEmpty) return;

    setState(() => _isSyncing = true);

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _localQueue.clear();
        _isSyncing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cloud Sync Complete!'),
        backgroundColor: Colors.green,
      ));
    }
  }

  @override
  void dispose() {
    _linkController.dispose(); // ✅ prevent memory leak
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final List<String> tabTitles = [
      'Gatherer Dashboard',
      'Scanner',
      'Data Validation',
      'Sync Queue',
      'Settings'
    ];

    final List<Widget> screens = [
      GathererDashboardView(
        scanned: _scannedToday,
        target: _dailyTarget,
        queueCount: _localQueue.length,
        onStartScan: () {
          setState(() => _currentIndex = 1);
        },
        linkController: _linkController,
        onOpenLink: _openLink,
      ),

      // 👈 FIXED: Added the required parameters here
      GathererScannerView(
        onScan: _performScan,
        queueCount: _localQueue.length,
        onOpenSync: () {
          setState(() => _currentIndex = 3); // Switches to the Sync Queue tab
        },
      ),

      const DataValidationScreen(),
      GathererSyncView(
        queue: _localQueue,
        isSyncing: _isSyncing,
        onSync: _syncData,
      ),
      const GathererSettingsView(),
    ];

    return Scaffold(
      backgroundColor: AppColors.lightGray,

      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: Text(
          tabTitles[_currentIndex],
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      drawer: GathererDrawer(
        currentIndex: _currentIndex,
        onMenuTap: (index) {
          setState(() => _currentIndex = index);
        },
      ),

      // 👇 CLEAN: NO EXTRA LINK UI HERE
      body: screens[_currentIndex],
    );
  }
}