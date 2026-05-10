// lib/sao_admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'user_management_screen.dart';
import '../login_screen.dart';
import 'personnel_management_screen.dart';
import 'performance_analysis_screen.dart';
import 'live_system_metrics_screen.dart';
import 'sao_admin_settings.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // 👈 NEW: Track the number of scanned files
  final int _filesScannedCount = 842;

  final List<Map<String, String>> _pendingApprovals = [
    {'name': 'Kirito (Kazuto Kirigaya)', 'dept': 'Computer Studies'},
    {'name': 'Asuna Yuuki', 'dept': 'Arts and Sciences'},
    {'name': 'Leafa (Suguha Kirigaya)', 'dept': 'Engineering'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text(
          'SAO-Admin Command Center',
          style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppColors.surface),
            onPressed: () {},
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.shield, color: AppColors.textPrimary, size: 20),
            ),
          )
        ],
      ),
      drawer: _buildDrawer(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'System Overview',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // ==========================================
              // UPDATED METRIC CARDS
              // ==========================================
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Total Users', '1,248', Icons.people, AppColors.primary)),
                  const SizedBox(width: 16),
                  // 👈 UPDATED: "Pending" is now "Files Scanned"
                  Expanded(child: _buildMetricCard('Files Scanned', '$_filesScannedCount', Icons.document_scanner_outlined, Colors.teal)),
                ],
              ),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Pending Account Approvals',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('View All', style: TextStyle(color: AppColors.primary)),
                  )
                ],
              ),
              const SizedBox(height: 12),

              _buildPendingList(),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI Components ---

  Widget _buildPendingList() {
    return _pendingApprovals.isEmpty
        ? const Center(child: Padding(
      padding: EdgeInsets.all(24.0),
      child: Text("No pending approvals.", style: TextStyle(color: AppColors.textSecondary)),
    ))
        : ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _pendingApprovals.length,
      itemBuilder: (context, index) {
        final user = _pendingApprovals[index];
        return Card(
          color: AppColors.surface,
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppColors.background,
              child: Text(user['name']![0], style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ),
            title: Text(user['name']!, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            subtitle: Text('Department: ${user['dept']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            trailing: Wrap(
              spacing: -8,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: AppColors.success),
                  onPressed: () => _handleApproval(user['name']!, true),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: AppColors.error),
                  onPressed: () => _handleApproval(user['name']!, false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleApproval(String name, bool approved) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${approved ? 'Approved' : 'Rejected'} $name")),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.textPrimary.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: AppColors.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.admin_panel_settings, color: AppColors.primary, size: 48),
                SizedBox(height: 12),
                Text('System Administrator', style: TextStyle(color: AppColors.surface, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Highest Access Level', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              ],
            ),
          ),
          _buildDrawerItem(context, Icons.dashboard, 'Dashboard', true, onTap: () => Navigator.pop(context)),
          _buildDrawerItem(context, Icons.group, 'User Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementScreen()));
          }),
          _buildDrawerItem(context, Icons.manage_accounts, 'Personnel Management', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const PersonnelManagementScreen()));
          }),
          _buildDrawerItem(context, Icons.analytics, 'Performance Analysis', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const PerformanceAnalysisScreen()));
          }),
          _buildDrawerItem(context, Icons.admin_panel_settings_rounded, 'Live System Metrics', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveSystemMetricsScreen()));
          }),
          _buildDrawerItem(context, Icons.settings, 'System Settings', false, onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SaoAdminSettings()));
          }),
          _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
          }),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected, {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary)),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: onTap,
    );
  }
}