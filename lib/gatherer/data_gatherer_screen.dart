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

  final List<Map<String, dynamic>> _localQueue = [
    {'id': 'FORM-892', 'subject': 'CS101', 'status': 'Ready to Sync'},
    {'id': 'FORM-893', 'subject': 'CS101', 'status': 'Ready to Sync'},
  ];

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
            duration: Duration(seconds: 1)
        ));
      }
    });
  }

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
          backgroundColor: Colors.green
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic titles for the AppBar to match the current tab
    final List<String> tabTitles = [
      'Gatherer Dashboard', // Index 0
      'Data Scanner',       // Index 1
      'Data Validation',    // Index 2
      'Cloud Sync',         // Index 3
      'Account Settings'    // Index 4
    ];

    final List<Widget> screens = [
      GathererDashboardView(
        scanned: _scannedToday,
        target: _dailyTarget,
        queueCount: _localQueue.length,
        onStartScan: () {
          setState(() => _currentIndex = 1); // Jumps to the Scanner Tab
        },
      ),
      GathererScannerView(onScan: _performScan),
      const DataValidationScreen(),
      GathererSyncView(queue: _localQueue, isSyncing: _isSyncing, onSync: _syncData),
      const GathererSettingsView(),
    ];

    return Scaffold(
      backgroundColor: AppColors.lightGray,

      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: Text(tabTitles[_currentIndex], style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
      ),

      drawer: GathererDrawer(
        currentIndex: _currentIndex,
        onMenuTap: (index) {
          setState(() => _currentIndex = index);
        },
      ),

      // Load the current screen
      body: screens[_currentIndex],

      // 👈 THE FLOATING ACTION BUTTON HAS BEEN COMPLETELY REMOVED FROM HERE!
    );
  }
}