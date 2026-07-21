import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../core/services/evaluation_service.dart';

class InterventionReportsScreen extends StatefulWidget {
  final String userId;
  const InterventionReportsScreen({super.key, required this.userId});

  @override
  State<InterventionReportsScreen> createState() => _InterventionReportsScreenState();
}

class _InterventionReportsScreenState extends State<InterventionReportsScreen> {
  final _evaluationService = EvaluationService();
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  List<ActionAlert> _pendingInterventions = [];
  List<InterventionReport> _completedInterventions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = widget.userId.isNotEmpty
          ? widget.userId
          : (_supabase.auth.currentUser?.id ?? '');
      if (userId.isEmpty) return;

      // Fetch dept average first — same threshold used on the dashboard
      final summary = await _evaluationService.getDepartmentSummary(userId);
      final deptAvg = summary.averageScore > 0 ? summary.averageScore : 3.0;

      final alerts = await _evaluationService.getDepartmentAlerts(userId, threshold: deptAvg);
      final logs = await _evaluationService.getInterventionLog(userId);

      if (mounted) {
        setState(() {
          // Only show alerts that don't have a corresponding log entry yet
          _pendingInterventions = alerts.where((alert) {
            if (alert.instructorId == null) return false;
            return !logs.any((log) => log.instructorId == alert.instructorId);
          }).toList();
          
          _completedInterventions = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading intervention data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  final List<String> _actionTypes = [
    'Peer Mentoring Program',
    'Pedagogy & Teaching Workshop',
    'Curriculum Review Meeting',
    'Formal Administrative Warning'
  ];

  // ==========================================
  // INTERACTIVE: DRAFT REPORT BOTTOM SHEET
  // ==========================================
  void _showDraftingSheet(ActionAlert alert) {
    String selectedAction = _actionTypes.first;
    final TextEditingController notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Draft Intervention', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Instructor: ${alert.instructorName ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text('Flagged for: ${alert.desc}', style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),

                      // Dropdown for Action Type
                      DropdownButtonFormField<String>(
                        value: selectedAction,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Mandated Action',
                          prefixIcon: const Icon(
                            Icons.gavel,
                            color: AppColors.primary,
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                        ),

                        items: _actionTypes.map((String action) {
                          return DropdownMenuItem<String>(
                            value: action,
                            child: Text(
                              action,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }).toList(),

                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setSheetState(() {
                              selectedAction = newValue;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Notes input
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: "Dean's Remarks / Notes",
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            try {
                              final deanId = _supabase.auth.currentUser?.id;
                              if (deanId == null || alert.instructorId == null) return;

                              await _evaluationService.createIntervention(
                                instructorId: alert.instructorId!,
                                deanId: deanId,
                                actionType: selectedAction,
                                notes: notesController.text,
                              );

                              if (mounted) {
                                Navigator.pop(context);
                                _loadData();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention recorded successfully.'), backgroundColor: AppColors.success));
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                            }
                          },
                          child: const Text('Submit Official Report', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Intervention Reports', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Administrative Actions', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Manage formal warnings and track mandated training for flagged faculty members.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    const SizedBox(height: 24),

                    // ==========================================
                    // PENDING INTERVENTIONS
                    // ==========================================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pending Action Required', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12)),
                          child: Text('${_pendingInterventions.length}', style: const TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_pendingInterventions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                        child: const Column(
                          children: [
                            Icon(Icons.check_circle_outline, color: AppColors.success, size: 40),
                            SizedBox(height: 8),
                            Text('All caught up!', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                            Text('No pending interventions required.', style: TextStyle(color: AppColors.success, fontSize: 12)),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: _pendingInterventions.map((alert) {
                          return Card(
                            color: AppColors.surface,
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: AppColors.error.withValues(alpha: 0.5), width: 1)
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('PENDING', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error, fontSize: 12)),
                                      Text('Flagged: ${DateFormat('MMM dd, yyyy').format(alert.dateFlagged)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: AppColors.error.withValues(alpha: 0.1),
                                        child: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(alert.instructorName ?? 'Unknown Instructor', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16)),
                                            const SizedBox(height: 4),
                                            Text(alert.desc, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () => _showDraftingSheet(alert),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.textPrimary,
                                        side: const BorderSide(color: AppColors.textPrimary),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Draft Intervention Report', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 32),

                    // ==========================================
                    // INTERVENTION HISTORY (COMPLETED)
                    // ==========================================
                    const Text(
                      'Intervention Log',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_completedInterventions.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text("No previous interventions recorded.", style: TextStyle(color: AppColors.textSecondary)),
                      ))
                    else
                      Column(
                        children: _completedInterventions.map((report) {
                          return Card(
                            color: AppColors.surface,
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),

                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.gavel,
                                  color: AppColors.success,
                                ),
                              ),

                              title: Text(
                                report.instructorName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),

                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),

                                  Text(
                                    report.actionType,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),

                                  const SizedBox(height: 2),

                                  Text(
                                    'Created: ${DateFormat('MMM dd, yyyy').format(report.createdAt)} • Status: ${report.status}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  // BUTTON
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),

                                    icon: const Icon(Icons.check_circle, size: 18),

                                    label: Text(
                                      report.status == 'Resolved'
                                          ? 'Resolved'
                                          : 'Mark as Resolved',
                                    ),

                                    onPressed: report.status == 'Resolved'
                                        ? null
                                        : () async {
                                      try {
                                        await _evaluationService.resolveIntervention(report.id);
                                        _loadData();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Intervention marked as resolved.',
                                            ),
                                          ),
                                        );
                                      } catch (e) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                      }
                                    },
                                  ),
                                ],
                              ),

                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),

                              onTap: () {
                                _showReportDetails(report);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  void _showReportDetails(InterventionReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Intervention Report Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Instructor: ${report.instructorName}', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Action: ${report.actionType}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Notes:', style: TextStyle(color: AppColors.textSecondary)),
            Text(report.notes.isNotEmpty ? report.notes : 'No notes provided.'),
            SizedBox(height: 16),
            Text('Status: ${report.status}', style: TextStyle(color: report.status == 'Resolved' ? AppColors.success : AppColors.warning)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
        ],
      ),
    );
  }
}
