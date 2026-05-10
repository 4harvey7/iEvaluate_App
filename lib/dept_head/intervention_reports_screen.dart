// lib/dept_head/intervention_reports_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class InterventionReportsScreen extends StatefulWidget {
  const InterventionReportsScreen({super.key});

  @override
  State<InterventionReportsScreen> createState() => _InterventionReportsScreenState();
}

class _InterventionReportsScreenState extends State<InterventionReportsScreen> {
  // --- DUMMY PENDING INTERVENTIONS ---
  final List<Map<String, dynamic>> _pendingInterventions = [
    {
      'id': 'INT-001',
      'name': 'Klein (Ryotaro Tsuboi)',
      'issue': 'Score below 3.0 threshold (2.85)',
      'dateFlagged': 'Oct 24, 2026',
    },
    {
      'id': 'INT-002',
      'name': 'Agil (Andrew Gilbert)',
      'issue': 'High negative sentiment in IT201 (45%)',
      'dateFlagged': 'Oct 22, 2026',
    }
  ];

  // --- DUMMY COMPLETED INTERVENTIONS ---
  final List<Map<String, dynamic>> _completedInterventions = [
    {
      'id': 'INT-000',
      'name': 'Sinon (Shino Asada)',
      'actionTaken': 'Peer Mentoring Assigned',
      'dateCompleted': 'Oct 15, 2026',
      'status': 'Resolved'
    }
  ];

  final List<String> _actionTypes = [
    'Peer Mentoring Program',
    'Pedagogy & Teaching Workshop',
    'Curriculum Review Meeting',
    'Formal Administrative Warning'
  ];

  // ==========================================
  // INTERACTIVE: DRAFT REPORT BOTTOM SHEET
  // ==========================================
  void _showDraftingSheet(Map<String, dynamic> instructor) {
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
                      Text('Instructor: ${instructor['name']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text('Flagged for: ${instructor['issue']}', style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),

                      // Dropdown for Action Type
                      DropdownButtonFormField<String>(
                        value: selectedAction,
                        decoration: InputDecoration(
                          labelText: 'Mandated Action',
                          prefixIcon: const Icon(Icons.gavel, color: AppColors.primary),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                        ),
                        items: _actionTypes.map((String action) {
                          return DropdownMenuItem<String>(value: action, child: Text(action, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)));
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) setSheetState(() => selectedAction = newValue);
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
                          onPressed: () {
                            // Interactive Logic: Remove from pending, add to completed
                            setState(() {
                              _pendingInterventions.remove(instructor);
                              _completedInterventions.insert(0, {
                                'id': instructor['id'],
                                'name': instructor['name'],
                                'actionTaken': selectedAction,
                                'dateCompleted': 'Today',
                                'status': 'Active Tracking'
                              });
                            });
                            Navigator.pop(context); // Close sheet
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention recorded successfully.'), backgroundColor: AppColors.success));
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
        child: SingleChildScrollView(
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
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
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
                  children: _pendingInterventions.map((instructor) {
                    return Card(
                      color: AppColors.surface,
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.error.withOpacity(0.5), width: 1)
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(instructor['id'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error, fontSize: 12)),
                                Text('Flagged: ${instructor['dateFlagged']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.error.withOpacity(0.1),
                                  child: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(instructor['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16)),
                                      const SizedBox(height: 4),
                                      Text(instructor['issue'], style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => _showDraftingSheet(instructor), // 👈 Opens interactive sheet
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
              const Text('Intervention Log', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              Column(
                children: _completedInterventions.map((report) {
                  return Card(
                    color: AppColors.surface,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.gavel, color: AppColors.success),
                      ),
                      title: Text(report['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(report['actionTaken'], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('Completed: ${report['dateCompleted']} • Status: ${report['status']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textSecondary),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening read-only report...')));
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}