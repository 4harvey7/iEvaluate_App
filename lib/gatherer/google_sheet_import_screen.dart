import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GoogleSheetImportScreen extends StatefulWidget {
  final String userId;
  final Function(String) onSubmit;

  const GoogleSheetImportScreen({
    super.key,
    required this.userId,
    required this.onSubmit,
  });

  @override
  State<GoogleSheetImportScreen> createState() => _GoogleSheetImportScreenState();
}

class _GoogleSheetImportScreenState extends State<GoogleSheetImportScreen> {
  final TextEditingController _linkController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 1: Set Sheet Name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
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
            
            const Text(
              'Step 2: Column Headers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your Google Sheet must have these columns in order:',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Student ID, Instructor/Professor, Subject Taught, AY/Semester\n• M1 through M10 (10 columns)\n• P1 through P10 (10 columns)\n• Remarks & Suggestions, Date',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
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
            
            const Text(
              'Step 3: Paste Link',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
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
                onPressed: () {
                  final link = _linkController.text.trim();
                  if (link.isNotEmpty) {
                    widget.onSubmit(link);  // Start processing
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please paste the Google Sheet link first')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
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
