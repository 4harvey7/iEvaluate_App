// The screen that shows all subjects assigned to this instructor for the current term.
// If this list is empty, either the admin forgot to assign, or it is still early in the sem.
// Basin both. Wala ta kabalo.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/services/system_settings_service.dart';
import '../core/navigation/main_scaffold.dart';
import 'providers/subjects_provider.dart';
import 'models/subject.dart';
import 'subject_detail_screen.dart';
import 'widgets/subject_card.dart';
import '../widgets/motion.dart';

// StatefulWidget because it needs to load term data before showing anything useful
class MySubjectsScreen extends StatefulWidget {
  final String userId;
  const MySubjectsScreen({super.key, required this.userId});

  @override
  State<MySubjectsScreen> createState() => _MySubjectsScreenState();
}

class _MySubjectsScreenState extends State<MySubjectsScreen> {
  // Service for getting system-wide settings like current term
  final _settingsService = SystemSettingsService();
  final _supabase = Supabase.instance.client;

  // Current term ID and display name — starts null/generic until loaded
  String? _currentTermId;
  String _termName =
      'Current Semester'; // placeholder until real term is fetched

  @override
  void initState() {
    super.initState();
    _loadData(); // fetch term info and trigger subject loading
  }

  // Load the current term settings, then fetch term display name, then load subjects.
  // Order matters here — need term ID before we can do anything else.
  Future<void> _loadData() async {
    final provider = context.read<SubjectsProvider>();
    try {
      final settings = await _settingsService.getSettings();
      if (!mounted) return; // widget might be gone by the time this completes

      setState(() => _currentTermId = settings.termId); // save term ID to state

      // If we have a term ID, also fetch its human-readable name
      if (_currentTermId != null) {
        final termData = await _supabase
            .from('academic_terms')
            .select('semester, academic_year')
            .eq('id', _currentTermId!)
            .maybeSingle();

        if (termData != null && mounted) {
          setState(() {
            // Combine semester and year into a nice display name
            _termName = '${termData['semester']} ${termData['academic_year']}';
          });
        }
      }

      // Tell the subjects provider to load subjects for this term
      provider.load(termId: _currentTermId);
    } catch (e) {
      debugPrint('Error loading term data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: AppColors.textInverted,
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
          icon: const Icon(Icons.menu_rounded, color: AppColors.textInverted),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'My Subjects',
          style: TextStyle(
            color: AppColors.textInverted,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
      ),
      // Consumer rebuilds whenever SubjectsProvider changes — reactive, like a students feelings
      body: Consumer<SubjectsProvider>(
        builder: (context, provider, child) {
          final subjects = provider.subjects;

          if (subjects.isEmpty) {
            // Nothing assigned — show the empty state screen
            return _buildEmptyState();
          }

          // Use true term average if available, otherwise fallback to unweighted average
          double termAverage = 0.0;
          if (provider.trueTermAverage != null &&
              provider.trueTermAverage! > 0) {
            termAverage = provider.trueTermAverage!;
          } else {
            double totalMean = 0;
            int count = 0;
            for (var s in subjects) {
              if (s.overallMean > 0) {
                // skip subjects with no score yet
                totalMean += s.overallMean;
                count++;
              }
            }
            termAverage = count > 0 ? totalMean / count : 0.0;
          }

          return RefreshIndicator(
            onRefresh: () => provider.load(
              termId: _currentTermId,
            ), // pull to reload subjects
            color: AppColors.primary,
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              // +1 for the summary header row at the top
              itemCount: subjects.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  // First item is always the summary header card — not a subject card
                  return Entrance(
                    child: _buildSummaryHeader(termAverage, subjects.length),
                  );
                }
                // The rest are subject cards (offset by 1 because of the header)
                final subject = subjects[index - 1];
                return Entrance(
                  index: index.clamp(0, 8),
                  child: SubjectCard(
                    subject: subject,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SubjectDetailScreen(
                          subject: subject,
                          userId: widget.userId,
                          termId: _currentTermId,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // Builds the summary header card at the top of the list — shows term average and subject count.
  // The color of the verbal description badge changes based on the average score.
  Widget _buildSummaryHeader(double average, int totalSubjects) {
    final color = Subject.getScoreColor(
      average,
    ); // green = good, red = time to reflect

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1608), AppColors.textPrimary],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // soft orange glow, upper right — echoes the login hero
            Positioned(
              top: -60,
              right: -50,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.35),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: _buildSummaryContent(average, totalSubjects, color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryContent(double average, int totalSubjects, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Term name in small uppercase label — like a badge
                  Text(
                    _termName.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textInvertedDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Term Performance',
                    style: TextStyle(
                      color: AppColors.textInverted,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Verbal description badge — "Outstanding", "Satisfactory", etc.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                Subject.getVerbalDescription(average),
                style: TextStyle(
                  color: Color.lerp(color, Colors.white, 0.55),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Big average number — the main KPI of this screen
                  Text(
                    average > 0 ? average.toStringAsFixed(2) : 'N/A',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                  const Text(
                    'Overall Weighted Mean',
                    style: TextStyle(
                      color: AppColors.textInvertedDim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Thin vertical divider between the two numbers
            Container(width: 1, height: 40, color: AppColors.textInvertedFaint),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Total number of assigned subjects
                  Text(
                    '$totalSubjects',
                    style: const TextStyle(
                      color: AppColors.textInverted,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                  const Text(
                    'Assigned Subjects',
                    style: TextStyle(
                      color: AppColors.textInvertedDim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Shows when no subjects are assigned — center-aligned sad icon and message.
  // Dili ta makabuhat ug subject card kung wala subjects, so show this instead.
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.subject_rounded,
              size: 44,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No subjects assigned yet',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your assignments for $_termName will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
