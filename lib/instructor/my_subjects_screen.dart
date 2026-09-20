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
import '../widgets/apple_ui.dart';
import '../core/services/term_aware_state.dart';

// StatefulWidget because it needs to load term data before showing anything useful
class MySubjectsScreen extends StatefulWidget {
  final String userId;
  const MySubjectsScreen({super.key, required this.userId});

  @override
  State<MySubjectsScreen> createState() => _MySubjectsScreenState();
}

class _MySubjectsScreenState extends State<MySubjectsScreen>
    with TermAwareState<MySubjectsScreen> {
  // Service for getting system-wide settings like current term
  final _settingsService = SystemSettingsService();
  final _supabase = Supabase.instance.client;

  // Current term ID and display name — starts null/generic until loaded
  String? _currentTermId;
  String _termName = 'Current Semester'; // placeholder until real term is fetched

  @override
  void initState() {
    super.initState();
    _loadData(); // fetch term info and trigger subject loading
  }

  // Reload when the SAO office switches the active term, instead of
  // showing the previous term's figures until this screen is rebuilt.
  @override
  void onTermChanged() {
    _loadData();
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
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'My Subjects',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
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
          if (provider.trueTermAverage != null && provider.trueTermAverage! > 0) {
            termAverage = provider.trueTermAverage!;
          } else {
            double totalMean = 0;
            int count = 0;
            for (var s in subjects) {
              if (s.overallMean > 0) { // skip subjects with no score yet
                totalMean += s.overallMean;
                count++;
              }
            }
            termAverage = count > 0 ? totalMean / count : 0.0;
          }

          return RefreshIndicator(
            onRefresh: () => provider.load(termId: _currentTermId), // pull to reload subjects
            color: AppColors.primary,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              // +1 for the summary header row at the top
              itemCount: subjects.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  // First item is always the summary header card — not a subject card
                  return _buildSummaryHeader(termAverage, subjects.length);
                }
                // The rest are subject cards (offset by 1 because of the header)
                final subject = subjects[index - 1];
                return SubjectCard(
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
    final color = Subject.getScoreColor(average); // green = good, red = time to reflect
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.heroGradient),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
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
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Term Performance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Verbal description badge — "Outstanding", "Satisfactory", etc.
              // The score colours are deliberately dark (tuned for dark-text-on
              // -white), so they cannot be used as text on this dark hero
              // gradient. The Satisfactory band is #101828 on #0B3B68 — about
              // 1.5:1, unreadable. So the pill is filled white and the score
              // colour is used for the LABEL, which is what it was designed for.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  Subject.getVerbalDescription(average),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
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
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Overall Weighted Mean',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ),
              // Thin vertical divider between the two numbers
              Container(
                width: 1,
                height: 40,
                color: Colors.white12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Total number of assigned subjects
                    Text(
                      '$totalSubjects',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Assigned Subjects',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Shows when no subjects are assigned — center-aligned sad icon and message.
  // Dili ta makabuhat ug subject card kung wala subjects, so show this instead.
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: AppleEmptyState(
        icon: Icons.subject_rounded,
        title: 'No subjects assigned',
        message: 'Your assignments for $_termName will appear here.',
      ),
    );
  }
}
