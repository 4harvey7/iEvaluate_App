import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/apple_ui.dart';

class GoogleSheetImportScreen extends StatefulWidget {
  final String userId;
  // (link, form type): 'SAST-20', 'SET-15' or 'SUP-15' (no default: staff must pick)
  final void Function(String, String) onSubmit;
  // Label of the current semester (where the import is saved), e.g. '1st Semester 2026-2027'.
  final String termLabel;

  const GoogleSheetImportScreen({
    super.key,
    required this.userId,
    required this.onSubmit,
    this.termLabel = '',
  });

  @override
  State<GoogleSheetImportScreen> createState() => _GoogleSheetImportScreenState();
}

class _GoogleSheetImportScreenState extends State<GoogleSheetImportScreen> {
  final TextEditingController _linkController = TextEditingController();
  String? _formType; // no default: the form must be chosen on purpose

  static const _formNames = {
    'SAST-20': 'Old SAST form (20 items)',
    'SET-15': 'Student Evaluation of Teachers - SET (15 items)',
    'SUP-15': "Supervisor's Evaluation of Faculty (15 items)",
  };

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndSubmit(String link, String form) async {
    final term = widget.termLabel.trim().isEmpty || widget.termLabel.contains('...')
        ? 'the current semester'
        : widget.termLabel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start this import?'),
        content: Text(
          'Form: ${_formNames[form] ?? form}\nSaved to: $term\n\nMake sure the sheet is from this form.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok == true && mounted) widget.onSubmit(link, form);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ApplePageHeader(
              eyebrow: 'Import',
              title: 'Google Sheets Import',
              subtitle: 'Prepare the sheet, verify its columns, then submit the share link.',
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Will be saved to: ${widget.termLabel.trim().isEmpty || widget.termLabel.contains('...') ? 'loading the current semester...' : widget.termLabel}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const AppleSectionHeader(title: 'Form type'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(value: 'SAST-20', label: Text('Old SAST form (20 items)')),
                ButtonSegment(value: 'SET-15', label: Text('Student Evaluation of Teachers – SET (15 items)')),
                ButtonSegment(value: 'SUP-15', label: Text("Supervisor's Evaluation of Faculty (15 items)")),
              ],
              selected: {?_formType},
              onSelectionChanged: (v) => setState(() => _formType = v.isEmpty ? null : v.first),
            ),
            if (_formType == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Choose which form this sheet is from before importing.',
                  style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 28),
            const AppleSectionHeader(title: '1. Set the sheet name'),
            const SizedBox(height: 8),
            const Text(
              'The tab at the bottom must be renamed exactly to:',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.drive_file_rename_outline, color: AppColors.warning),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'SAST Survey Data',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/sast_tab_guide.png',
                fit: BoxFit.cover,
                errorBuilder: (context, e, s) => Container(
                  height: 80,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: const Center(child: Text('Guide Image: Tab Name', style: TextStyle(color: Colors.grey))),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            const AppleSectionHeader(title: '2. Verify column headers'),
            const SizedBox(height: 8),
            const Text(
              'Your Google Sheet must have these columns in order:',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _formType == null
                  ? 'Choose a form type above to see the columns it needs.'
                  : _formType == 'SAST-20'
                  ? '• Student ID, Instructor/Professor, Subject Taught, AY/Semester\n• M1 through M10 (10 columns)\n• P1 through P10 (10 columns)\n• Remarks & Suggestions, Date'
                  : '${_formType == 'SUP-15' ? '' : '• Student ID (only visible to the SAO office; the same student cannot evaluate the same instructor and subject twice)\n'}• Instructor/Professor, Subject Taught${_formType == 'SUP-15' ? ', Supervisor Email (the department head who filled the form), Academic Rank, Designation' : ''}\n• Section, Program Level, Program Year, Date (all optional)\n• Q1 through Q15 (15 columns, 5 to 1; leave empty if not answered)\n• Comments and Stamp No (both optional)\n• No student name: it is never stored\n• Start from the template file: ${_formType == 'SUP-15' ? 'Supervisors Evaluation of Faculty - import template.xlsx' : 'Student Evaluation of Teachers (SET) - import template.xlsx'}, then paste its share link',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/sast_sheet_guide.png',
                fit: BoxFit.cover,
                errorBuilder: (context, e, s) => Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: const Center(child: Text('Guide Image: Column Headers', style: TextStyle(color: Colors.grey))),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            const AppleSectionHeader(title: '3. Paste the share link'),
            const SizedBox(height: 12),
            TextField(
              controller: _linkController,
              decoration: InputDecoration(
                hintText: 'https://docs.google.com/spreadsheets/d/...',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.link, color: AppColors.primary),
              ),
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _formType == null ? null : () {
                  final link = _linkController.text.trim();
                  final form = _formType!;
                  if (link.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please paste the Google Sheet link first')),
                    );
                    return;
                  }
                  _confirmAndSubmit(link, form);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textInverted,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: const Text('START IMPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
