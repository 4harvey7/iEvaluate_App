// lib/sao_admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import 'user_management_screen.dart';
import '../login_screen.dart';
import 'personnel_management_screen.dart';
import 'performance_analysis_screen.dart';
import 'system_audit_screen.dart';
import 'sao_admin_settings.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // 👈 UPDATED: Roles removed! Everyone in this queue is assumed to be an Instructor.
  final List<Map<String, String>> _pendingApprovals = [
    {'name': 'Kirito (Kazuto Kirigaya)', 'dept': 'Computer Studies'},
    {'name': 'Asuna Yuuki', 'dept': 'Arts and Sciences'},
    {'name': 'Leafa (Suguha Kirigaya)', 'dept': 'Engineering'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text(
          'SAO-Admin Command Center',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppColors.white),
            onPressed: () {},
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.gold,
              child: Icon(Icons.shield, color: AppColors.deepBlue, size: 20),
            ),
          )
        ],
      ),

      // ==========================================
      // ADMIN NAVIGATION DRAWER (Side Menu)
      // ==========================================
      drawer: Drawer(
        backgroundColor: AppColors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: AppColors.deepBlue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.admin_panel_settings, color: AppColors.gold, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'System Administrator',
                    style: TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Highest Access Level',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),

            _buildDrawerItem(context, Icons.dashboard, 'Dashboard', true, onTap: () {
              Navigator.pop(context);
            }),

            _buildDrawerItem(context, Icons.group, 'User Management', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UserManagementScreen()),
              );
            }),

            _buildDrawerItem(context, Icons.manage_accounts, 'Personnel Management', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PersonnelManagementScreen()),
              );
            }),

            _buildDrawerItem(context, Icons.analytics, 'Performance Analysis', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PerformanceAnalysisScreen()),
              );
            }),
            _buildDrawerItem(context, Icons.admin_panel_settings_rounded, 'System Audit Logs', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SystemAuditScreen()),
              );
            }),
            _buildDrawerItem(context, Icons.group, 'System Settings', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SaoAdminSettings()),
              );
            }),

            _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
              );
            }),
          ],
        ),
      ),

      // ==========================================
      // MAIN DASHBOARD CONTENT
      // ==========================================
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'System Overview',
                style: TextStyle(color: AppColors.darkGray, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(child: _buildMetricCard('Total Users', '1,248', Icons.people, AppColors.royalBlue)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard('Pending', '${_pendingApprovals.length}', Icons.pending_actions, AppColors.gold)),
                ],
              ),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Pending Account Approvals',
                      style: TextStyle(color: AppColors.darkGray, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('View All', style: TextStyle(color: AppColors.royalBlue)),
                  )
                ],
              ),
              const SizedBox(height: 12),

              _pendingApprovals.isEmpty
                  ? const Center(child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text("No pending approvals.", style: TextStyle(color: Colors.grey)),
              ))
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pendingApprovals.length,
                itemBuilder: (context, index) {
                  final user = _pendingApprovals[index];
                  return Card(
                    color: AppColors.white,
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.lightGray,
                        child: Text(user['name']![0], style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(user['name']!, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray)),
                      // 👈 UPDATED: Now only shows the department!
                      subtitle: Text('Department: ${user['dept']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      // 👈 UPDATED: Swapped to Wrap to prevent overflow on smaller screens
                      trailing: Wrap(
                        spacing: -8,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Approved ${user['name']}")),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Rejected ${user['name']}")),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected, {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.red : (isSelected ? AppColors.royalBlue : AppColors.darkGray)),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? Colors.red : (isSelected ? AppColors.royalBlue : AppColors.darkGray),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: onTap ?? () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$title feature coming soon!")),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(color: AppColors.darkGray, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}