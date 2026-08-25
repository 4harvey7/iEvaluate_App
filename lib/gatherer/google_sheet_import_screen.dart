import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';

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

  // numbered step chip + title — gives each card a clear identity
  Widget _stepHeader(int step, String title) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.primaryTint,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('$step',
                style: const TextStyle(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  // soft white card wrapper — the shared canvas for each step
  Widget _stepCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Entrance(
              index: 0,
              child: _stepCard(children: [
              _stepHeader(1, 'Step 1: Set Sheet Name'),
              const SizedBox(height: 12),
              const Text(
                'The tab at the bottom must be renamed exactly to:',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.drive_file_rename_outline, color: AppColors.warning),
                    SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'SAST Survey Data',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: -0.3,
                            color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/sast_tab_guide.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, e, s) => Container(
                    height: 80,
                    width: double.infinity,
                    color: AppColors.background,
                    child: const Center(child: Text('Guide Image: Tab Name', style: TextStyle(color: AppColors.textSecondary))),
                  ),
                ),
              ),
            ]),
            ),

            const SizedBox(height: 16),

            Entrance(
              index: 1,
              child: _stepCard(children: [
              _stepHeader(2, 'Step 2: Column Headers'),
              const SizedBox(height: 12),
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
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/sast_sheet_guide.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, e, s) => Container(
                    height: 120,
                    width: double.infinity,
                    color: AppColors.background,
                    child: const Center(child: Text('Guide Image: Column Headers', style: TextStyle(color: AppColors.textSecondary))),
                  ),
                ),
              ),
            ]),
            ),

            const SizedBox(height: 16),

            Entrance(
              index: 2,
              child: _stepCard(children: [
              _stepHeader(3, 'Step 3: Paste Link'),
              const SizedBox(height: 14),
              TextField(
                controller: _linkController,
                style: const TextStyle(fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'https://docs.google.com/spreadsheets/d/...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.link, color: AppColors.primaryText),
                ),
              ),
            ]),
            ),

            const SizedBox(height: 24),

            // gradient CTA — the one button that matters on this screen
            Entrance(
              index: 3,
              child: Pressable(
              child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDeep],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
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
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('START IMPORT',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 0.3)),
              ),
            ),
            ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
