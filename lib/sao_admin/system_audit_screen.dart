// lib/sao_admin/system_audit_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

class SystemAuditScreen extends StatefulWidget {
  const SystemAuditScreen({super.key});

  @override
  State<SystemAuditScreen> createState() => _SystemAuditScreenState();
}

class _SystemAuditScreenState extends State<SystemAuditScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isAscending = false; // Toggle for sorting
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('audit_logs')
          .select('''
            *,
            user_info:user_id ( first_name, last_name, email )
          ''')
          .order('created_at', ascending: _isAscending)
          .limit(100);

      setState(() {
        _logs = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching logs: $e');
      setState(() => _isLoading = false);
    }
  }

  void _toggleSort() {
    setState(() {
      _isAscending = !_isAscending;
    });
    _fetchLogs();
  }

  Color _getActionColor(String action) {
    action = action.toUpperCase();
    if (action.contains('CREATE')) return AppColors.success;
    if (action.contains('UPDATE') || action.contains('ROLE')) return AppColors.warning;
    if (action.contains('OTP')) return AppColors.primary;
    if (action.contains('DELETE') || action.contains('REJECT')) return AppColors.error;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Security Audit Logs', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        actions: [
          // Sort Toggle Button
          IconButton(
            icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _isAscending ? 'Showing Oldest First' : 'Showing Newest First',
            onPressed: _toggleSort,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLogs),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty 
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _fetchLogs,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final action = (log['action'] ?? 'UNKNOWN').toString().toUpperCase();
                      final createdAt = DateTime.parse(log['created_at']).toLocal();
                      final userInfo = log['user_info'];
                      final userName = userInfo != null 
                          ? '${userInfo['first_name']} ${userInfo['last_name']}' 
                          : 'System';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: _getActionColor(action).withValues(alpha: 0.1),
                            child: Icon(Icons.history, color: _getActionColor(action), size: 20),
                          ),
                          title: Text(
                            action.replaceAll('_', ' '),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            'By $userName • ${DateFormat('MMM d, h:mm a').format(createdAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  const Text('METADATA (JSON):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary)),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.2)),
                                    ),
                                    child: Text(
                                      log['metadata'].toString(),
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textPrimary),
                                    ),
                                  ),
                                  if (userInfo?['email'] != null) ...[
                                    const SizedBox(height: 12),
                                    Text('Admin Email: ${userInfo['email']}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
                                  ]
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          const Text('No security logs found', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
        ],
      ),
    );
  }
}
