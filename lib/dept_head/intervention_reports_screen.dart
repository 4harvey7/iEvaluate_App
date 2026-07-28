// lib/dept_head/intervention_reports_screen.dart
// The "problem list" screen — where dean tracks instructors who need intervention.
// Also where they record what action they took. Very official. Very serious.
// Think of it as the academic version of a court — but with more paperwork.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../core/services/evaluation_service.dart';

// The main widget — needs userId to find the right dept
class InterventionReportsScreen extends StatefulWidget {
  final String userId;
  const InterventionReportsScreen({super.key, required this.userId});

  @override
  State<InterventionReportsScreen> createState() => _InterventionReportsScreenState();
}

class _InterventionReportsScreenState extends State<InterventionReportsScreen> {
  final _evaluationService = EvaluationService();
  final _supabase = Supabase.instance.client;
  bool _isLoading = true; // Show spinner on first load

  // Pending = alerts that have no intervention report yet — need action from dean
  List<ActionAlert> _pendingInterventions = [];
  // Completed = interventions that have been officially recorded — for tracking
  List<InterventionReport> _completedInterventions = [];

  // Load data on screen open
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Fetches pending alerts and completed intervention logs from the backend.
  // Pending = flagged instructors with no matching log entry yet — dean must act.
  // Completed = already recorded. bahala na, at least documented.
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Resolve userId — prefer passed value, fallback to current auth user
      final userId = widget.userId.isNotEmpty
          ? widget.userId
          : (_supabase.auth.currentUser?.id ?? '');
      if (userId.isEmpty) return; // No user ID = no dept = nothing to show

      // Fetch dept average first — same threshold used on the dashboard
      // This keeps the alert criteria consistent across all screens
      final summary = await _evaluationService.getDepartmentSummary(userId);
      final deptAvg = summary.averageScore > 0 ? summary.averageScore : 3.0; // Default 3.0 if no data

      // Get all current alerts for this department
      final alerts = await _evaluationService.getDepartmentAlerts(userId, threshold: deptAvg);
      // Get all previously recorded intervention logs
      final logs = await _evaluationService.getInterventionLog(userId);

      if (mounted) {
        setState(() {
          // Only show alerts that don't have a corresponding log entry yet
          // We filter out instructors who already have an intervention recorded
          _pendingInterventions = alerts.where((alert) {
            if (alert.instructorId == null) return false; // Skip alerts without instructor ID
            return !logs.any((log) => log.instructorId == alert.instructorId); // Not yet logged
          }).toList();
          
          _completedInterventions = logs; // All logged interventions — includes resolved ones
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading intervention data: $e');
      if (mounted) setState(() => _isLoading = false); // Stop spinner even on error
    }
  }

  // The four possible mandated actions — dean picks one when drafting a report
  // These are predefined options — dili pwede just write anything. must be official.
  final List<String> _actionTypes = [
    'Peer Mentoring Program',
    'Pedagogy & Teaching Workshop',
    'Curriculum Review Meeting',
    'Formal Administrative Warning' // The scary one — use only when really needed
  ];

  // ==========================================
  // INTERACTIVE: DRAFT REPORT BOTTOM SHEET
  // Opens a form where dean fills in the mandated action and remarks.
  // On submit, creates a new intervention record in the database.
  // ==========================================
  void _showDraftingSheet(ActionAlert alert) {
    String selectedAction = _actionTypes.first; // Default to first option
    final TextEditingController notesController = TextEditingController();
    bool isSubmitting = false; // Prevent double submit — importente

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allow sheet to grow when keyboard appears
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return Padding(
                // Shift content up when keyboard opens — dili ta hide the form fields
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
                          // X to close without saving — ayaw submit if not ready
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Show who this intervention is for — no confusion
                      Text('Instructor: ${alert.instructorName ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                      // Show why they were flagged — gives context to the action
                      Text('Flagged for: ${alert.desc}', style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 24),

                      // Dropdown for Action Type — pick what mandated action to apply
                      DropdownButtonFormField<String>(
                        value: selectedAction,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Mandated Action',
                          prefixIcon: const Icon(
                            Icons.gavel, // The hammer icon — very official
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

                        // Map action types to dropdown items
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

                        // Update selectedAction when user picks a different option
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setSheetState(() {
                              selectedAction = newValue;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Notes input — dean can write remarks, context, or additional info
                      // Multi-line so dean can write properly, dili just one line
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

                      // Submit Button — the actual "file the report" action
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          // Disabled while submitting to prevent duplicate inserts
                          onPressed: isSubmitting ? null : () async {
                            final deanId = _supabase.auth.currentUser?.id;
                            // Must have deanId and instructorId — otherwise something is very wrong
                            if (deanId == null || alert.instructorId == null) return;

                            setSheetState(() => isSubmitting = true); // Lock button while submitting
                            try {
                              // Create the intervention record in the database
                              await _evaluationService.createIntervention(
                                instructorId: alert.instructorId!,
                                deanId: deanId,
                                actionType: selectedAction, // The mandated action dean picked
                                notes: notesController.text, // Dean's remarks
                              );

                              if (mounted) {
                                Navigator.pop(context); // Close the sheet
                                _loadData(); // Reload so the new report appears in the log
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention recorded successfully.'), backgroundColor: AppColors.success));
                              }
                            } catch (e) {
                              setSheetState(() => isSubmitting = false); // Re-enable on error
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                            }
                          },
                          // Spinner while submitting, text when idle
                          child: isSubmitting
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Submit Official Report', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
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

  // The main build — shows pending alerts on top, completed log below
  // Both sections are clearly separated so dean know what still need action
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
          ? const Center(child: CircularProgressIndicator()) // Loading state
          : RefreshIndicator(
              onRefresh: _loadData, // Pull to refresh — reload both lists
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Always scrollable for pull-to-refresh
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Page title and description — sets the serious tone
                    const Text('Administrative Actions', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Manage formal warnings and track mandated training for flagged faculty members.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    const SizedBox(height: 24),

                    // ==========================================
                    // PENDING INTERVENTIONS
                    // These are alerts that still need action — dili ta ignore them
                    // ==========================================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pending Action Required', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                        // Red badge showing how many pending — like a notification count
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12)),
                          child: Text('${_pendingInterventions.length}', style: const TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),

                    // No pending interventions — rare and wonderful
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
                      // Got pending items — show each as a card with a "Draft" button
                      Column(
                        children: _pendingInterventions.map((alert) {
                          return Card(
                            color: AppColors.surface,
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: AppColors.error.withValues(alpha: 0.5), width: 1) // Red border — look urgent
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // PENDING badge — very visible red text
                                      const Text('PENDING', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error, fontSize: 12)),
                                      // Date when this instructor was flagged — for record
                                      Text('Flagged: ${DateFormat('MMM dd, yyyy').format(alert.dateFlagged)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      // Warning icon in red circle — clear visual indicator of trouble
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
                                            // Instructor name — who is flagged
                                            Text(alert.instructorName ?? 'Unknown Instructor', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16), overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 4),
                                            // Description — why they were flagged
                                            Text(alert.desc, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Draft button — opens the bottom sheet form to record action
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () => _showDraftingSheet(alert), // Open drafting form
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
                    // All recorded interventions — including resolved ones.
                    // This is the audit trail. importente for accountability.
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

                    // No logs yet — either new dept or nobody has been flagged
                    if (_completedInterventions.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text("No previous interventions recorded.", style: TextStyle(color: AppColors.textSecondary)),
                      ))
                    else
                      // Show each logged intervention as a list tile card
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

                              // Green gavel icon — indicates this was formally recorded
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.gavel,
                                  color: AppColors.success, // Green because it was acted on
                                ),
                              ),

                              // Instructor name at the top of the tile
                              title: Text(
                                report.instructorName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),

                              // Subtitle contains action type, date, status, and resolve button
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),

                                  // The action type that was mandated — e.g. "Formal Administrative Warning"
                                  Text(
                                    report.actionType,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  const SizedBox(height: 2),

                                  // Created date and current status — for quick overview
                                  Text(
                                    'Created: ${DateFormat('MMM dd, yyyy').format(report.createdAt)} • Status: ${report.status}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  const SizedBox(height: 10),

                                  // BUTTON — Mark as Resolved or show "Resolved" if already done
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

                                    // Label changes based on status — "Resolved" or "Mark as Resolved"
                                    label: Text(
                                      report.status == 'Resolved'
                                          ? 'Resolved' // Already done — just show label
                                          : 'Mark as Resolved', // Still open — show action button
                                    ),

                                    // Disabled if already resolved — dili ta allow re-resolving
                                    onPressed: report.status == 'Resolved'
                                        ? null // Button does nothing if already resolved
                                        : () async {
                                      try {
                                        await _evaluationService.resolveIntervention(report.id); // Update status to Resolved
                                        _loadData(); // Reload to reflect the change
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

                              // Right arrow — tap to open full details dialog
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),

                              // Tap anywhere on the tile to see full report details
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

  // Shows a dialog with the full details of a recorded intervention report.
  // For when dean want to see the notes they wrote — or someone want to audit.
  void _showReportDetails(InterventionReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Intervention Report Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Who was this intervention for
            Text('Instructor: ${report.instructorName}', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            SizedBox(height: 8),
            // What action was mandated
            Text('Action: ${report.actionType}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            SizedBox(height: 8),
            // Dean's notes — could be empty if they didn't write any
            Text('Notes:', style: TextStyle(color: AppColors.textSecondary)),
            Text(report.notes.isNotEmpty ? report.notes : 'No notes provided.'), // Fallback if blank
            SizedBox(height: 16),
            // Status — green if resolved, orange if still pending
            Text('Status: ${report.status}', style: TextStyle(color: report.status == 'Resolved' ? AppColors.success : AppColors.warning), overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // Just a close button — this dialog is read-only
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
        ],
      ),
    );
  }
}
