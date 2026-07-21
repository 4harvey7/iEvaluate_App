import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';

class StudentFeedbackScreen extends StatefulWidget {
  final String userId;
  final String? termId;
  const StudentFeedbackScreen({super.key, required this.userId, this.termId});

  @override
  State<StudentFeedbackScreen> createState() => _StudentFeedbackScreenState();
}

class _StudentFeedbackScreenState extends State<StudentFeedbackScreen> {
  final _supabase = Supabase.instance.client;
  String _selectedFilter = 'All';
  bool _isLoading = true;
  String _activeTermDisplay = '';

  Map<String, dynamic> _sentimentSummary = {
    'positive': 0,
    'neutral': 0,
    'negative': 0,
    'totalComments': 0,
  };

  List<Map<String, dynamic>> _wordCloud = [];
  List<Map<String, dynamic>> _allFeedback = [];
  String _aiInsightSummary = "Analyzing your feedback...";
  List<Map<String, String>> _positiveThemes = [];
  List<Map<String, String>> _improvementInsights = [];

  @override
  void initState() {
    super.initState();
    _fetchFeedbackData();
  }

  Future<void> _fetchFeedbackData() async {
    try {
      String? activeTermId = widget.termId;

      // If no termId is provided (e.g., dashboard still loading), fetch the current active term
      String activeTermName = "Current Term";
      if (activeTermId == null || activeTermId.isEmpty) {
        final settings = await _supabase
            .from('system_settings')
            .select('current_term_id, academic_terms(semester, academic_year)')
            .maybeSingle();
        activeTermId = settings?['current_term_id'];
        if (settings?['academic_terms'] != null) {
          final term = settings!['academic_terms'];
          activeTermName = "${term['semester']} ${term['academic_year']}";
        }
      } else {
        // Fetch term name for provided termId
        final termData = await _supabase
            .from('academic_terms')
            .select('semester, academic_year')
            .eq('id', activeTermId)
            .maybeSingle();
        if (termData != null) {
          activeTermName = "${termData['semester']} ${termData['academic_year']}";
        }
      }

      // If we still don't have a term ID, we can't filter correctly
      if (activeTermId == null || activeTermId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _allFeedback = [];
          });
        }
        return;
      }
      
      if (mounted) {
        setState(() {
          _activeTermDisplay = activeTermName;
        });
      }

      var remarksQuery = _supabase
          .from('student_remarks')
          .select('remark, tone, created_at, subjects(subject_code)')
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      var aiQuery = _supabase
          .from('instructor_ai_suggestions')
          .select()
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      var wordCloudQuery = _supabase
          .from('instructor_wordcloud')
          .select('word, count')
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      final responses = await Future.wait<dynamic>([
        remarksQuery,
        aiQuery.order('updated_at', ascending: false).limit(1).maybeSingle(),
        wordCloudQuery.order('count', ascending: false).limit(25),
      ]);

      final remarks = responses[0] as List;
      final aiSuggestion = responses[1] as Map<String, dynamic>?;
      final words = responses[2] as List;

      if (mounted) {
        setState(() {
          _allFeedback = remarks.map((r) {
            // Using subjects!inner ensures we get records where subjects are linked
            // We use standard Supabase relationship syntax
            String subjectCode = 'N/A';
            if (r['subjects'] != null) {
              if (r['subjects'] is Map) {
                subjectCode = r['subjects']['subject_code'] ?? 'N/A';
              } else if (r['subjects'] is List && r['subjects'].isNotEmpty) {
                subjectCode = r['subjects'][0]['subject_code'] ?? 'N/A';
              }
            }

            return {
              'course': subjectCode,
              'text': r['remark'],
              'sentiment': r['tone'] ?? 'Neutral',
              'date': r['created_at'] != null ? DateTime.parse(r['created_at']).toLocal().toString().split(' ')[0] : 'Unknown',
            };
          }).toList();

          int pos = _allFeedback.where((f) => f['sentiment'] == 'Positive').length;
          int neu = _allFeedback.where((f) => f['sentiment'] == 'Neutral').length;
          int neg = _allFeedback.where((f) => f['sentiment'] == 'Critical').length;
          int total = _allFeedback.length;

          if (total > 0) {
            _sentimentSummary = {
              'positive': ((pos / total) * 100).round(),
              'neutral': ((neu / total) * 100).round(),
              'negative': ((neg / total) * 100).round(),
              'totalComments': total,
            };
          }

          if (aiSuggestion != null) {
            _aiInsightSummary = aiSuggestion['ai_suggestion'] ?? "";
            _positiveThemes = _parseThemes(aiSuggestion['positive_themes'], '💡');
            _improvementInsights = _parseImprovements(aiSuggestion['improvement_insights']);
          }

          // Dense Word Cloud Logic
          _wordCloud = words.asMap().entries.map((entry) {
            int index = entry.key;
            var w = entry.value;
            return {
              'word': w['word'],
              // More aggressive scaling for visual impact
              'weight': 14.0 + (w['count'] as num).toDouble() * 4.5,
              'color': _getWordColor(w['word']),
              // More organic rotation pattern
              'rotated': index % 5 == 0 || index % 7 == 0,
            };
          }).toList();
          _wordCloud.shuffle(); // Distribute high/low counts randomly for better density

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching feedback: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, String>> _parseThemes(dynamic data, String defaultIcon) {
    if (data == null) return [];
    if (data is! String || data.trim().isEmpty) return [];

    final raw = data.trim();
    List<String> parts;

    // 1. Try numbered list: "1. text 2. text"
    final numberedPattern = RegExp(r'\d+\.\s+');
    if (numberedPattern.hasMatch(raw)) {
      parts = raw.split(numberedPattern).where((s) => s.trim().isNotEmpty).toList();
    }
    // 2. Try newline-separated
    else if (raw.contains('\n')) {
      parts = raw.split('\n').where((s) => s.trim().isNotEmpty).toList();
    }
    // 3. Try sentence split (". " boundary)
    else {
      parts = raw.split(RegExp(r'\.\s+')).where((s) => s.trim().isNotEmpty).toList();
    }

    // Merge dangling fragments that start with a conjunction/preposition
    // back into the previous item so we don't get "and deep knowledge..."
    const _danglers = {'and', 'or', 'but', 'as', 'with', 'which', 'that',
                       'including', 'such', 'among', 'while', 'where'};
    final merged = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final firstWord = trimmed.split(' ').first.toLowerCase().replaceAll(',', '');
      if (merged.isNotEmpty && _danglers.contains(firstWord)) {
        merged[merged.length - 1] = '${merged.last}. $trimmed';
      } else {
        merged.add(trimmed);
      }
    }

    return merged
        .where((s) => s.length > 5) // skip garbage fragments
        .map((s) => {'icon': defaultIcon, 'label': s.endsWith('.') ? s : '$s.'})
        .toList();
  }

  List<Map<String, String>> _parseImprovements(dynamic data) {
    if (data == null) return [];
    if (data is! String || data.trim().isEmpty) return [];

    final raw = data.trim();
    List<String> parts;

    // 1. Numbered list
    final numberedPattern = RegExp(r'\d+\.\s+');
    if (numberedPattern.hasMatch(raw)) {
      parts = raw.split(numberedPattern).where((s) => s.trim().isNotEmpty).toList();
    }
    // 2. Newline-separated
    else if (raw.contains('\n')) {
      parts = raw.split('\n').where((s) => s.trim().isNotEmpty).toList();
    }
    // 3. Sentence split
    else {
      parts = raw.split(RegExp(r'\.\s+')).where((s) => s.trim().isNotEmpty).toList();
    }

    // Merge dangling fragments into previous item
    const _danglers = {'and', 'or', 'but', 'as', 'with', 'which', 'that',
                       'including', 'such', 'among', 'while', 'where', 'additional',
                       'more', 'further'};
    final merged = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final firstWord = trimmed.split(' ').first.toLowerCase().replaceAll(',', '');
      if (merged.isNotEmpty && _danglers.contains(firstWord)) {
        merged[merged.length - 1] = '${merged.last} $trimmed';
      } else {
        merged.add(trimmed);
      }
    }

    // Build label from first few words of each item as a title
    return merged
        .where((s) => s.length > 5)
        .map((s) {
          final sentence = s.endsWith('.') ? s : '$s.';
          // Extract a short label: first 3–5 words, capitalised
          final words = sentence.split(' ');
          final labelWords = words.take(words.length > 4 ? 4 : words.length).join(' ');
          final label = labelWords.endsWith('.') ? labelWords : '$labelWords...';
          return {
            'icon': '⚠️',
            'label': label[0].toUpperCase() + label.substring(1),
            'detail': sentence,
          };
        })
        .toList();
  }

  Color _getWordColor(String word) {
    final colors = [AppColors.primary, AppColors.success, Colors.lightBlueAccent, AppColors.warning];
    return colors[word.length % colors.length];
  }

  // Filter Logic
  List<Map<String, dynamic>> get _filteredFeedback {
    if (_selectedFilter == 'All') return _allFeedback;
    return _allFeedback.where((f) => f['sentiment'] == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Student Feedback', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold, fontSize: 18)),
            if (_activeTermDisplay.isNotEmpty)
              Text(_activeTermDisplay, style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12)),
          ],
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : SafeArea(
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
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
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
                          Expanded(flex: (_sentimentSummary['positive'] as int).clamp(1, 100), child: Container(height: 12, color: AppColors.success)),
                          Expanded(flex: (_sentimentSummary['neutral'] as int).clamp(1, 100), child: Container(height: 12, color: AppColors.textTertiary)),
                          Expanded(flex: (_sentimentSummary['negative'] as int).clamp(1, 100), child: Container(height: 12, color: AppColors.error)),
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
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
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
                            color: AppColors.primary.withValues(alpha: 0.1),
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
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.15), width: 1),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
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
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 80),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.2), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(theme['icon']!, style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    theme['label']!,
                                    style: const TextStyle(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600),
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

              // --- Improvement Insights Block (only when critical feedback exists) ---
              if (_improvementInsights.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.2), width: 1),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
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
                                    color: AppColors.warning.withValues(alpha: 0.1),
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
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.textPrimary, Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 6))
                  ],
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8.0,
                  runSpacing: 6.0,
                  children: _wordCloud.map((wordData) {
                    // Scale font: weight 14–58 maps to 10–22px readable range
                    final double rawWeight = (wordData['weight'] as double).clamp(14.0, 58.0);
                    final double fontSize = 10.0 + ((rawWeight - 14.0) / 44.0) * 12.0;

                    final Widget wordText = Text(
                      wordData['word'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: fontSize > 18 ? FontWeight.w800 : FontWeight.w600,
                        color: wordData['color'],
                        height: 1.1,
                        letterSpacing: -0.1,
                        shadows: [
                          Shadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(0, 1), blurRadius: 2),
                        ],
                      ),
                    );

                    // Restore organic layout: every 5th or 7th word goes vertical (bottom→top)
                    if (wordData['rotated'] == true) {
                      return RotatedBox(
                        quarterTurns: 3, // 270° = bottom-to-top
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: wordText,
                        ),
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

              // Filter chips
              _buildFilterRow(),
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
                        side: BorderSide(color: sentimentColor.withValues(alpha: 0.3), width: 1)
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

  // Premium Filter Row with counts + icons
  Widget _buildFilterRow() {
    final filters = [
      {
        'label': 'All',
        'icon': Icons.all_inclusive_rounded,
        'count': _allFeedback.length,
        'color': AppColors.primary,
      },
      {
        'label': 'Positive',
        'icon': Icons.sentiment_very_satisfied_rounded,
        'count': _allFeedback.where((f) => f['sentiment'] == 'Positive').length,
        'color': AppColors.success,
      },
      {
        'label': 'Neutral',
        'icon': Icons.sentiment_neutral_rounded,
        'count': _allFeedback.where((f) => f['sentiment'] == 'Neutral').length,
        'color': AppColors.textSecondary,
      },
      {
        'label': 'Critical',
        'icon': Icons.sentiment_dissatisfied_rounded,
        'count': _allFeedback.where((f) => f['sentiment'] == 'Critical').length,
        'color': AppColors.error,
      },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final label   = f['label']   as String;
          final icon    = f['icon']    as IconData;
          final count   = f['count']   as int;
          final color   = f['color']   as Color;
          final selected = _selectedFilter == label;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: selected ? color : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? color : color.withValues(alpha: 0.3),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))]
                    : [],
              ),
              child: InkWell(
                onTap: () => setState(() => _selectedFilter = label),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 16,
                          color: selected ? Colors.white : color),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.25)
                              : color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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