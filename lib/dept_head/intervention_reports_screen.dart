// lib/dept_head/intervention_reports_screen.dart
// The "problem list" screen — where dean tracks instructors who need intervention.
// Also where they record what action they took. Very official. Very serious.
// Think of it as the academic version of a court — but with more paperwork.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../core/services/evaluation_service.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';

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

  // ─── CACHE FOR INSTANT TAB SWITCHING ─────────────────────────────────────────
  static final Map<String, Map<String, dynamic>> _interventionCache = {};

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
    final userId = widget.userId.isNotEmpty
        ? widget.userId
        : (_supabase.auth.currentUser?.id ?? '');
        
    // Check cache first for instant load
    if (_interventionCache.containsKey(userId)) {
      if (mounted) {
        setState(() {
          _pendingInterventions = _interventionCache[userId]!['pending'] as List<ActionAlert>;
          _completedInterventions = _interventionCache[userId]!['completed'] as List<InterventionReport>;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = true);
    }
    
    try {
      if (userId.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return; // No user ID = no dept = nothing to show
      }

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
          
          // Save to cache!
          _interventionCache[userId] = {
            'pending': _pendingInterventions,
            'completed': _completedInterventions,
          };
          
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
              return AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                // Shift content up when keyboard opens — dili ta hide the form fields
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle — signals this is a sheet
                      Center(
                        child: Container(width: 44, height: 5, decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(100))),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Draft Intervention', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary)),
                          // X to close without saving — ayaw submit if not ready
                          IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Show who this intervention is for — no confusion
                      Text('Instructor: ${alert.instructorName ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      // Show why they were flagged — gives context to the action
                      Text('Flagged for: ${alert.desc}', style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 24),

                      // Dropdown for Action Type — pick what mandated action to apply
                      DropdownButtonFormField<String>(
                        value: selectedAction,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Mandated Action',
                          labelStyle: const TextStyle(color: AppColors.textSecondary),
                          prefixIcon: const Icon(
                            Icons.gavel, // The hammer icon — very official
                            color: AppColors.primaryText,
                          ),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
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
                          labelStyle: const TextStyle(color: AppColors.textSecondary),
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button — the actual "file the report" action
                      // Gradient CTA with a warm glow — the premium treatment
                      Pressable(
                        child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDeep]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          // Disabled while submitting to prevent duplicate inserts
                          onPressed: isSubmitting ? null : () async {
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            final navigator = Navigator.of(context);
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

                              if (!mounted) return;
                              navigator.pop(); // Close the sheet
                              _loadData(); // Reload so the new report appears in the log
                              scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Intervention recorded successfully.'), backgroundColor: AppColors.success));
                            } catch (e) {
                              if (!mounted) return;
                              setSheetState(() => isSubmitting = false); // Re-enable on error
                              scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                            }
                          },
                          // Spinner while submitting, text when idle
                          child: isSubmitting
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                              : const Text('Submit Official Report', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
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
        elevation: 0,
        foregroundColor: AppColors.textInverted,
        iconTheme: const IconThemeData(color: AppColors.textInverted),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E1608), AppColors.textPrimary],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text('Intervention Reports', style: TextStyle(color: AppColors.textInverted, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) // Loading state
          : RefreshIndicator(
              onRefresh: _loadData, // Pull to refresh — reload both lists
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Always scrollable for pull-to-refresh
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Page title and description — sets the serious tone
                    const Text('Administrative Actions', style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text('Manage formal warnings and track mandated training for flagged faculty members.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4)),
                    const SizedBox(height: 28),

                    // ==========================================
                    // PENDING INTERVENTIONS
                    // These are alerts that still need action — dili ta ignore them
                    // ==========================================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pending Action Required', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        // Red pill showing how many pending — like a notification count
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(100)),
                          child: Text('${_pendingInterventions.length}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 12)),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),

                    // No pending interventions — rare and wonderful
                    if (_pendingInterventions.isEmpty)
                      Entrance(
                        index: 0,
                        child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Soft green circle — the good-news icon treatment
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                              child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 32),
                            ),
                            const SizedBox(height: 14),
                            const Text('All caught up!', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 4),
                            const Text('No pending interventions required.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                        ),
                      )
                    else
                      // Got pending items — show each as a card with a "Draft" button
                      Column(
                        children: _pendingInterventions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final alert = entry.value;
                          return Entrance(
                            index: index.clamp(0, 8).toInt(),
                            child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(18.0),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // PENDING badge — soft red pill, very visible
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(100)),
                                        child: const Text('PENDING', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 11, letterSpacing: 0.5)),
                                      ),
                                      // Date when this instructor was flagged — for record
                                      Text('Flagged: ${DateFormat('MMM dd, yyyy').format(alert.dateFlagged)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      // Warning icon in soft red circle — clear visual indicator of trouble
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: AppColors.error.withValues(alpha: 0.10),
                                        child: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Instructor name — who is flagged
                                            Text(alert.instructorName ?? 'Unknown Instructor', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontSize: 16, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 4),
                                            // Description — why they were flagged
                                            Text(alert.desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35), overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Draft button — gradient CTA that opens the bottom sheet form
                                  Pressable(
                                    child: Container(
                                    width: double.infinity,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDeep]),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () => _showDraftingSheet(alert), // Open drafting form
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        foregroundColor: AppColors.textPrimary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                      child: const Text('Draft Intervention Report', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                    ),
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
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // No logs yet — either new dept or nobody has been flagged
                    if (_completedInterventions.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              // Soft tinted circle — friendly empty state
                              Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
                                child: const Icon(Icons.history_rounded, color: AppColors.primaryText, size: 30),
                              ),
                              const SizedBox(height: 14),
                              const Text("No previous interventions recorded.", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ),
                      )
                    else
                      // Show each logged intervention as a list tile card
                      Column(
                        children: _completedInterventions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final report = entry.value;
                          return Entrance(
                            index: index.clamp(0, 8).toInt(),
                            child: Pressable(
                              child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),

                              // Green gavel icon — indicates this was formally recorded
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.12),
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
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.3,
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
                                      color: AppColors.primaryText,
                                      fontWeight: FontWeight.w700,
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
                                  Pressable(
                                    child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      // Resolved (disabled) state gets the soft-pill treatment
                                      disabledBackgroundColor: AppColors.success.withValues(alpha: 0.12),
                                      disabledForegroundColor: AppColors.success,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(100),
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
                                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                                      try {
                                        await _evaluationService.resolveIntervention(report.id); // Update status to Resolved
                                        if (!mounted) return;
                                        _loadData(); // Reload to reflect the change
                                        scaffoldMessenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Intervention marked as resolved.',
                                            ),
                                          ),
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                                      }
                                    },
                                  ),
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
                              ),
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Intervention Report Details', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Who was this intervention for
            Text('Instructor: ${report.instructorName}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            // What action was mandated
            Text('Action: ${report.actionType}', style: const TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            // Dean's notes — could be empty if they didn't write any
            const Text('Notes:', style: TextStyle(color: AppColors.textSecondary)),
            Text(report.notes.isNotEmpty ? report.notes : 'No notes provided.'), // Fallback if blank
            const SizedBox(height: 16),
            // Status — green if resolved, orange if still pending
            Text('Status: ${report.status}', style: TextStyle(fontWeight: FontWeight.w700, color: report.status == 'Resolved' ? AppColors.success : AppColors.warning), overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // Just a close button — this dialog is read-only
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
