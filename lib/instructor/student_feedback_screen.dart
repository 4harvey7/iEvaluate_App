// lib/instructor/student_feedback_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StudentFeedbackScreen extends StatefulWidget {
  const StudentFeedbackScreen({super.key});

  @override
  State<StudentFeedbackScreen> createState() => _StudentFeedbackScreenState();
}

class _StudentFeedbackScreenState extends State<StudentFeedbackScreen> {
  String _selectedFilter = 'All';

  // --- 1. AI SENTIMENT ANALYSIS DATA ---
  final Map<String, dynamic> _sentimentSummary = {
    'positive': 75,
    'neutral': 15,
    'negative': 10,
    'totalComments': 142,
  };

  // --- 2. 👈 UPGRADED AI WORD CLOUD DATA ---
  // Added a 'rotated' boolean to flip some words vertically!
  // Tweaked colors to be brighter against the dark background.
  final List<Map<String, dynamic>> _wordCloud = [
    {'word': 'Engaging', 'weight': 36.0, 'color': AppColors.primary, 'rotated': false},
    {'word': 'Fast-paced', 'weight': 20.0, 'color': AppColors.warning, 'rotated': false},
    {'word': 'Helpful', 'weight': 28.0, 'color': AppColors.success, 'rotated': false},
    {'word': 'Clear', 'weight': 24.0, 'color': Colors.white, 'rotated': true},
    {'word': 'Examples', 'weight': 32.0, 'color': Colors.lightBlueAccent, 'rotated': false},
    {'word': 'Challenging', 'weight': 20.0, 'color': AppColors.warning, 'rotated': true},
    {'word': 'Approachable', 'weight': 26.0, 'color': AppColors.success, 'rotated': false},
    {'word': 'Projects', 'weight': 22.0, 'color': Colors.white70, 'rotated': false},
    {'word': 'Strict', 'weight': 16.0, 'color': AppColors.error, 'rotated': false},
    {'word': 'Inspiring', 'weight': 34.0, 'color': AppColors.primary, 'rotated': false},
    {'word': 'Rubrics', 'weight': 14.0, 'color': Colors.white54, 'rotated': true},
    {'word': 'Coding', 'weight': 28.0, 'color': Colors.lightBlue, 'rotated': false},
  ];

  // --- 3. RAW STUDENT FEEDBACK ---
  final List<Map<String, dynamic>> _allFeedback = [
    {
      'course': 'CS101',
      'text': 'The examples used in class are really helpful for understanding the code. Very inspiring lectures!',
      'sentiment': 'Positive',
      'date': 'Oct 12, 2026'
    },
    {
      'course': 'CS202',
      'text': 'Pacing is a bit fast during the Data Structures lectures. Sometimes hard to keep up.',
      'sentiment': 'Critical',
      'date': 'Oct 10, 2026'
    },
    {
      'course': 'IT305',
      'text': 'Always willing to answer questions after class. Great and approachable instructor!',
      'sentiment': 'Positive',
      'date': 'Oct 08, 2026'
    },
    {
      'course': 'CS101',
      'text': 'The grading rubrics are clear, but the exams are very strict.',
      'sentiment': 'Neutral',
      'date': 'Oct 05, 2026'
    },
    {
      'course': 'IT305',
      'text': 'The group projects were challenging but I learned a lot about real-world coding.',
      'sentiment': 'Positive',
      'date': 'Oct 01, 2026'
    },
  ];

  // Filter Logic
  List<Map<String, dynamic>> get _filteredFeedback {
    if (_selectedFilter == 'All') return _allFeedback;
    return _allFeedback.where((f) => f['sentiment'] == _selectedFilter).toList();
  }

  // ============================================================
  // AI INTERPRETATION LAYER — derived from _allFeedback &
  // _sentimentSummary. No external APIs or backend logic.
  // ============================================================

  /// Builds a human-readable summary sentence from the sentiment numbers
  /// and a quick keyword scan of the raw feedback texts.
  String get _aiInsightSummary {
    final positive = _sentimentSummary['positive'] as int;
    final positiveFeedbacks = _allFeedback.where((f) => f['sentiment'] == 'Positive').toList();
    final hasClear = positiveFeedbacks.any((f) => (f['text'] as String).toLowerCase().contains('clear') ||
        (f['text'] as String).toLowerCase().contains('rubric'));
    final hasApproachable = positiveFeedbacks.any((f) => (f['text'] as String).toLowerCase().contains('approachable') ||
        (f['text'] as String).toLowerCase().contains('question'));
    final hasInspiring = positiveFeedbacks.any((f) => (f['text'] as String).toLowerCase().contains('inspir') ||
        (f['text'] as String).toLowerCase().contains('engag'));

    if (positive >= 70) {
      final traits = <String>[];
      if (hasInspiring) traits.add('inspiring');
      if (hasApproachable) traits.add('approachable');
      if (hasClear) traits.add('organized');
      final traitString = traits.isNotEmpty ? traits.join(', ') : 'effective';
      return 'The majority of your students ($positive%) view you as a $traitString instructor. '
          'Your teaching is making a strong positive impression across multiple courses.';
    } else if (positive >= 50) {
      return 'Most students ($positive%) feel positively about your teaching. '
          'There are clear strengths to build on alongside some areas to address.';
    } else {
      return 'Student sentiment is mixed. Consider reviewing feedback carefully '
          'to identify recurring concerns alongside your teaching strengths.';
    }
  }

  /// Extracts positive theme tags from the positive feedback texts.
  List<Map<String, String>> get _positiveThemes {
    final themes = <Map<String, String>>[];
    final texts = _allFeedback
        .where((f) => f['sentiment'] == 'Positive')
        .map((f) => (f['text'] as String).toLowerCase())
        .join(' ');

    if (texts.contains('example') || texts.contains('helpful')) {
      themes.add({'icon': '💡', 'label': 'Helpful Examples'});
    }
    if (texts.contains('approachable') || texts.contains('question')) {
      themes.add({'icon': '🤝', 'label': 'Approachable Style'});
    }
    if (texts.contains('inspir') || texts.contains('engag')) {
      themes.add({'icon': '🌟', 'label': 'Inspiring Lectures'});
    }
    if (texts.contains('coding') || texts.contains('real-world') || texts.contains('project')) {
      themes.add({'icon': '🛠️', 'label': 'Practical Projects'});
    }
    return themes;
  }

  /// Extracts improvement points only when critical feedback exists.
  List<Map<String, String>> get _improvementInsights {
    final criticalFeedbacks = _allFeedback.where((f) => f['sentiment'] == 'Critical').toList();
    if (criticalFeedbacks.isEmpty) return [];

    final insights = <Map<String, String>>[];
    final texts = criticalFeedbacks.map((f) => (f['text'] as String).toLowerCase()).join(' ');

    if (texts.contains('pacing') || texts.contains('fast') || texts.contains('keep up')) {
      insights.add({
        'icon': '⏱️',
        'label': 'Lecture Pacing',
        'detail': 'Some students find the pace too fast — consider adding recap checkpoints.',
      });
    }
    if (texts.contains('strict') || texts.contains('exam')) {
      insights.add({
        'icon': '📋',
        'label': 'Assessment Strictness',
        'detail': 'A few students feel exams are strict relative to the rubrics provided.',
      });
    }
    if (texts.contains('example') && texts.contains('more')) {
      insights.add({
        'icon': '📖',
        'label': 'More Examples Needed',
        'detail': 'Students are requesting more worked examples during instruction.',
      });
    }
    // Always surface at least one general insight when critical feedback exists
    if (insights.isEmpty) {
      insights.add({
        'icon': '💬',
        'label': 'Student Concerns Noted',
        'detail': 'Review critical comments individually to identify specific improvement areas.',
      });
    }
    return insights;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Student Feedback', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),

      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [


              // ==========================================
              // SENTIMENT ANALYSIS DASHBOARD
              // ==========================================
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.pie_chart, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Emotional Tone Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Segmented Bar Chart
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        children: [
                          Expanded(flex: _sentimentSummary['positive'], child: Container(height: 12, color: AppColors.success)),
                          Expanded(flex: _sentimentSummary['neutral'], child: Container(height: 12, color: AppColors.textTertiary)),
                          Expanded(flex: _sentimentSummary['negative'], child: Container(height: 12, color: AppColors.error)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Legend & Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSentimentStat('Positive', '${_sentimentSummary['positive']}%', AppColors.success),
                        _buildSentimentStat('Neutral', '${_sentimentSummary['neutral']}%', AppColors.textSecondary),
                        _buildSentimentStat('Critical', '${_sentimentSummary['negative']}%', AppColors.error),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // ✨ NEW: AI INSTRUCTOR INSIGHT SUMMARY
              // ==========================================
              const Text('AI Instructor Insights', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // --- Main Insight Card ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('What Your Students Are Saying', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                            Text('AI-generated interpretation', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: AppColors.background),
                    const SizedBox(height: 16),

                    // Summary Text
                    Text(
                      _aiInsightSummary,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.6),
                    ),
                    const SizedBox(height: 16),

                    // Analyzed comments pill
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.comment_outlined, size: 12, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                'Based on ${_sentimentSummary['totalComments']} comments',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Positive Themes Block ---
              if (_positiveThemes.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.success.withOpacity(0.15), width: 1),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.thumb_up_alt_outlined, color: AppColors.success, size: 18),
                          SizedBox(width: 8),
                          Text('Key Positive Themes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('Consistently praised aspects of your teaching', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _positiveThemes.map((theme) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.success.withOpacity(0.2), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(theme['icon']!, style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Text(
                                  theme['label']!,
                                  style: TextStyle(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // --- Improvement Insights Block (only when critical feedback exists) ---
              if (_improvementInsights.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.warning.withOpacity(0.2), width: 1),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tips_and_updates_outlined, color: AppColors.warning, size: 18),
                          SizedBox(width: 8),
                          Text('Improvement Insights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('Areas flagged in student feedback worth reviewing', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 16),
                      Column(
                        children: _improvementInsights.map((insight) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(insight['icon']!, style: const TextStyle(fontSize: 16)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(insight['label']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.warning)),
                                      const SizedBox(height: 2),
                                      Text(insight['detail']!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),
              // ==========================================
              // END: AI INSTRUCTOR INSIGHT SUMMARY
              // ==========================================

              // ==========================================
              // 👈 UPGRADED WORD CLOUD GENERATOR
              // ==========================================
              const Text('AI Word Cloud', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                decoration: BoxDecoration(
                  // Added a sleek gradient background
                  gradient: const LinearGradient(
                    colors: [AppColors.textPrimary, Color(0xFF0B192C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12.0, // Reduced to pack words tighter
                  runSpacing: 4.0, // Squeezed vertical lines together
                  children: _wordCloud.map((wordData) {

                    // Build the text widget
                    Widget wordText = Text(
                      wordData['word'],
                      style: TextStyle(
                        fontSize: wordData['weight'],
                        // Bigger words get thicker fonts, smaller words get thinner fonts
                        fontWeight: wordData['weight'] > 26 ? FontWeight.w900 : FontWeight.w600,
                        color: wordData['color'],
                        height: 1.0, // Removes extra line spacing around the text
                        letterSpacing: -0.5,
                      ),
                    );

                    // If it's flagged as rotated, wrap it in a RotatedBox!
                    if (wordData['rotated'] == true) {
                      return RotatedBox(
                        quarterTurns: 3, // Rotates it 90 degrees upward
                        child: wordText,
                      );
                    }

                    return wordText;
                  }).toList(),
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // INDIVIDUAL FEEDBACK LIST & FILTERS
              // ==========================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Direct Quotes', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('${_filteredFeedback.length} Comments', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Positive', 'Neutral', 'Critical'].map((filter) {
                    bool isSelected = _selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(filter, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        selected: isSelected,
                        selectedColor: filter == 'Positive' ? AppColors.success.withOpacity(0.2)
                            : filter == 'Critical' ? AppColors.error.withOpacity(0.2)
                            : filter == 'Neutral' ? AppColors.textTertiary.withOpacity(0.2)
                            : AppColors.primary.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? (filter == 'Positive' ? AppColors.success : filter == 'Critical' ? AppColors.error : AppColors.textPrimary)
                              : AppColors.textSecondary,
                        ),
                        onSelected: (bool selected) {
                          if (selected) setState(() => _selectedFilter = filter);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Feedback List
              _filteredFeedback.isEmpty
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text("No comments match this filter.", style: TextStyle(color: AppColors.textSecondary)),
                ),
              )
                  : Column(
                children: _filteredFeedback.map((feedback) {
                  // Determine visual style based on sentiment
                  Color sentimentColor = feedback['sentiment'] == 'Positive' ? AppColors.success
                      : feedback['sentiment'] == 'Critical' ? AppColors.error
                      : AppColors.textTertiary;
                  IconData sentimentIcon = feedback['sentiment'] == 'Positive' ? Icons.sentiment_very_satisfied
                      : feedback['sentiment'] == 'Critical' ? Icons.sentiment_dissatisfied
                      : Icons.sentiment_neutral;

                  return Card(
                    color: AppColors.surface,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: sentimentColor.withOpacity(0.3), width: 1)
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(6)),
                                child: Text(feedback['course'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary)),
                              ),
                              Text(feedback['date'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '"${feedback['text']}"',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontStyle: FontStyle.italic, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(sentimentIcon, color: sentimentColor, size: 16),
                              const SizedBox(width: 4),
                              Text(feedback['sentiment'], style: TextStyle(color: sentimentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
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

  // Helper Widget for Sentiment Stats
  Widget _buildSentimentStat(String label, String percentage, Color color) {
    return Column(
      children: [
        Text(percentage, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}