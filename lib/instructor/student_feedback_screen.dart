// Screen where the instructor can read what the students actually wrote about them.
// Some will be nice. Some will be brutal. Dili ta makapili. Bahala na what they say.
// This screen also has AI insights, word cloud, sentiment stats — importente kaayo.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../widgets/apple_ui.dart';
import '../core/navigation/main_scaffold.dart';
import '../core/services/term_aware_state.dart';

// StatefulWidget — lots of dynamic data (feedback, AI analysis, word cloud, filters)
class StudentFeedbackScreen extends StatefulWidget {
  final String userId;
  final String? termId; // optional — if not provided, we fetch the current term
  const StudentFeedbackScreen({super.key, required this.userId, this.termId});

  @override
  State<StudentFeedbackScreen> createState() => _StudentFeedbackScreenState();
}

class _StudentFeedbackScreenState extends State<StudentFeedbackScreen>
    with TermAwareState<StudentFeedbackScreen> {
  final _supabase = Supabase.instance.client;

  // Filter for the feedback list — starts at 'All', can switch to Positive/Neutral/Critical
  String _selectedFilter = 'All';
  String _selectedSubjectFilter = 'All Subjects';
  List<String> _availableSubjects = ['All Subjects'];
  String _sortOrder = 'Date (Newest)';
  final List<String> _sortOptions = [
    'Date (Newest)',
    'Date (Oldest)',
    'Sentiment (Positive First)',
    'Sentiment (Critical First)',
  ];

  bool _isLoading = true;
  String _activeTermDisplay =
      ''; // shown in the AppBar subtitle — e.g. "First Semester 2024-2025"

  // Sentiment distribution counters — percentages of positive, neutral, critical
  Map<String, dynamic> _sentimentSummary = {
    'positive': 0,
    'neutral': 0,
    'negative': 0,
    'totalComments': 0,
  };

  // Word cloud items — words that appear often in feedback, with size and color
  List<Map<String, dynamic>> _wordCloud = [];
  // All feedback items loaded from database — filtered copy is shown in UI
  List<Map<String, dynamic>> _allFeedback = [];
  // AI-generated summary text — reads the feedback so you dont have to read 200 comments
  String _aiInsightSummary = "Analyzing your feedback...";
  // Positive themes extracted by AI — the good stuff students liked
  List<Map<String, String>> _positiveThemes = [];
  // Improvement areas flagged by AI — things to work on, ayaw ignore
  List<Map<String, String>> _improvementInsights = [];

  @override
  void initState() {
    super.initState();
    _fetchFeedbackData(); // start loading everything on screen open
  }

  // Reload when the SAO office switches the active term, instead of
  // showing the previous term's figures until this screen is rebuilt.
  @override
  void onTermChanged() {
    _fetchFeedbackData();
  }

  // The main data fetcher — grabs remarks, AI suggestions, and word cloud in parallel.
  // Also resolves the active term if not provided by the caller.
  Future<void> _fetchFeedbackData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      String? activeTermId = widget.termId;

      // If no termId is provided (e.g., dashboard still loading), fetch the current active term
      String activeTermName = "Current Term";
      if (activeTermId == null || activeTermId.isEmpty) {
        // No term provided — look it up from system_settings
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
        // Fetch term name for provided termId — just need the display label
        final termData = await _supabase
            .from('academic_terms')
            .select('semester, academic_year')
            .eq('id', activeTermId)
            .maybeSingle();
        if (termData != null) {
          activeTermName =
              "${termData['semester']} ${termData['academic_year']}";
        }
      }

      // If we still don't have a term ID, we can't filter correctly — show empty screen
      if (activeTermId == null || activeTermId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _allFeedback = []; // wala data, wala display
          });
        }
        return;
      }

      // Set the term display name in the AppBar subtitle
      if (mounted) {
        setState(() {
          _activeTermDisplay = activeTermName;
        });
      }

      // Query 1: Student remarks (the actual feedback text + tone + date + subject)
      var remarksQuery = _supabase
          .from('student_remarks')
          .select('remark, tone, created_at, subjects(subject_code)')
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      // Query 2: AI suggestion entry for this instructor+term — the ML-analyzed summary
      var aiQuery = _supabase
          .from('instructor_ai_suggestions')
          .select()
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      // Query 3: Word cloud data — most frequent words from feedback
      var wordCloudQuery = _supabase
          .from('instructor_wordcloud')
          .select('word, count')
          .eq('instructor_id', widget.userId)
          .eq('term_id', activeTermId);

      // Run all three queries at the same time — faster, no need wait one by one
      final responses = await Future.wait<dynamic>([
        remarksQuery,
        aiQuery
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle(), // only most recent AI entry
        wordCloudQuery
            .order('count', ascending: false)
            .limit(25), // top 25 words only
      ]);

      final remarks = responses[0] as List;
      final aiSuggestion = responses[1] as Map<String, dynamic>?;
      final words = responses[2] as List;

      if (mounted) {
        setState(() {
          // Map each remark row into a clean display-friendly map
          _allFeedback = remarks.map((r) {
            // Using subjects!inner ensures we get records where subjects are linked
            // We use standard Supabase relationship syntax
            String subjectCode = 'N/A'; // default if subject link is missing
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
              'sentiment':
                  r['tone'] ?? 'Neutral', // default to Neutral if tone is null
              'date': r['created_at'] != null
                  ? DateTime.parse(
                      r['created_at'],
                    ).toLocal().toString().split(' ')[0]
                  : 'Unknown',
            };
          }).toList();

          // Extract unique subjects for the filter dropdown
          final uniqueSubjects = _allFeedback
              .map((f) => f['course'] as String)
              .toSet()
              .toList();
          uniqueSubjects.sort();
          _availableSubjects = ['All Subjects', ...uniqueSubjects];
          if (!_availableSubjects.contains(_selectedSubjectFilter)) {
            _selectedSubjectFilter = 'All Subjects';
          }

          // Count each sentiment type — used for the bar chart and percentage display
          int pos = _allFeedback
              .where((f) => f['sentiment'] == 'Positive')
              .length;
          int neu = _allFeedback
              .where((f) => f['sentiment'] == 'Neutral')
              .length;
          int neg = _allFeedback
              .where((f) => f['sentiment'] == 'Critical')
              .length;
          int total = _allFeedback.length;

          // Only compute percentages if there is at least one comment
          if (total > 0) {
            _sentimentSummary = {
              'positive': ((pos / total) * 100).round(),
              'neutral': ((neu / total) * 100).round(),
              'negative': ((neg / total) * 100).round(),
              'totalComments': total,
            };
          }

          // Parse AI suggestion fields into usable lists.
          //
          // All three come from the same [instructor_ai_suggestions] row for
          // this instructor and term:
          //   "What Your Students Are Saying" -> ai_suggestion
          //   "Key Positive Themes"           -> positive_themes
          //   "Improvement Insights"          -> improvement_insights
          //
          // The summary used to prefer student_interpretation and fall back to
          // ai_suggestion, so this screen and the official evaluation report
          // could show two different paragraphs for the same term -- the report
          // has always read ai_suggestion. ai_suggestion is also NOT NULL in
          // the schema, so there is a value whenever the row exists.
          if (aiSuggestion != null) {
            final String summary =
                (aiSuggestion['ai_suggestion'] ?? '').toString().trim();
            _aiInsightSummary = summary.isNotEmpty
                ? summary
                : "No AI interpretation available yet.";
            _positiveThemes = _parseThemes(
              aiSuggestion['positive_themes'],
              '💡',
            );
            _improvementInsights = _parseImprovements(
              aiSuggestion['improvement_insights'],
            );
          }

          // Dense Word Cloud Logic — scale font size by frequency count
          _wordCloud = words.asMap().entries.map((entry) {
            int index = entry.key;
            var w = entry.value;
            return {
              'word': w['word'],
              // More aggressive scaling for visual impact — frequent words are BIG
              'weight': 14.0 + (w['count'] as num).toDouble() * 4.5,
              'color': _getWordColor(w['word']),
              // More organic rotation pattern — every 5th or 7th word gets rotated sideways
              'rotated': index % 5 == 0 || index % 7 == 0,
            };
          }).toList();
          _wordCloud
              .shuffle(); // Distribute high/low counts randomly for better density

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching feedback: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── AI insight text into bubbles ─────────────────────────────────────────
  //
  // The three AI columns hold free text written by the model, and the shape
  // varies: a Postgres text[] ({"a","b"}), a JSON array, a numbered or newline
  // list, or one plain paragraph. Whatever the shape, a bubble should hold ONE
  // SENTENCE - never half of one, and never a stray piece of punctuation.
  //
  // The previous splitter broke on two shapes. It split on commas whenever the
  // text contained no ". ", which shredded a single comma-rich sentence into
  // fragments, and it recognised quoted array elements by searching for the
  // literal '","', so an array holding ONE comma-rich element fell through to a
  // plain comma split. Both paths produced fragment bubbles, and a trailing or
  // doubled comma produced a bubble holding nothing but punctuation.

  /// The items to show as bubbles, one sentence each.
  List<String> _extractList(dynamic data) {
    // An array has already declared where its items begin and end, so its
    // elements are only ever split into SENTENCES, never on their commas.
    // Splitting a stored item further would contradict the row that produced
    // it: {"Approachable, fair in grading and well-prepared"} is one theme the
    // model wrote, not three.
    final bool structured = data is List || _looksLikeArrayLiteral(data);

    final List<String> out = [];
    for (final element in _unwrapContainer(data)) {
      out.addAll(_splitIntoSentences(element, allowCommaSplit: !structured));
    }
    return out.where(_isDisplayableItem).toList();
  }

  /// Is this a Postgres text[] or a JSON array, written as a string?
  bool _looksLikeArrayLiteral(dynamic data) {
    if (data is! String) return false;
    final raw = data.trim();
    return (raw.startsWith('{') && raw.endsWith('}')) ||
        (raw.startsWith('[') && raw.endsWith(']'));
  }

  /// Unwraps an array-shaped value into its elements. Anything else comes back
  /// whole, as a single element, to be split into sentences afterwards.
  List<String> _unwrapContainer(dynamic data) {
    if (data == null) return const [];
    if (data is List) {
      return data
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (data is! String) return const [];

    final raw = data.trim();
    if (raw.isEmpty) return const [];

    if (!_looksLikeArrayLiteral(raw)) return [raw];

    final inner = raw.substring(1, raw.length - 1).trim();
    if (inner.isEmpty) return const [];
    return _splitTopLevelCommas(inner);
  }

  /// Splits on the commas that sit OUTSIDE double quotes.
  ///
  /// This is the part the old code guessed at. A quoted element keeps its own
  /// commas, so {"Approachable, fair in grading and well-prepared"} stays one
  /// item instead of becoming three, while an unquoted array still splits.
  List<String> _splitTopLevelCommas(String value) {
    final items = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        continue; // quotes are packaging, never content
      }
      if (char == ',' && !inQuotes) {
        items.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    items.add(buffer.toString());

    return items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// One sentence per entry.
  ///
  /// Commas are split on ONLY when [allowCommaSplit] is set and the text is
  /// plainly a keyword list: no sentence punctuation anywhere, and every piece
  /// a few words at most. Prose is left to its full stops, which is what keeps
  /// a sentence in one bubble.
  List<String> _splitIntoSentences(String text, {bool allowCommaSplit = true}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    // A numbered or newline list already carries one item per line.
    final numbered = RegExp(r'\d+[.)]\s+');
    final List<String> chunks;
    if (trimmed.contains('\n')) {
      chunks = trimmed.split('\n');
    } else if (numbered.hasMatch(trimmed)) {
      chunks = trimmed.split(numbered);
    } else {
      chunks = [trimmed];
    }

    final sentences = <String>[];
    for (final chunk in chunks) {
      final piece = chunk.trim();
      if (piece.isEmpty) continue;

      if (allowCommaSplit &&
          !RegExp(r'[.!?]').hasMatch(piece) &&
          piece.contains(',')) {
        final parts = piece
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final bool isKeywordList =
            parts.length > 1 &&
            parts.every((e) => e.split(RegExp(r'\s+')).length <= 5);
        if (isKeywordList) {
          // "Approachable, fair in grading, and well-prepared" ends on a
          // conjunction that reads as noise on its own bubble.
          sentences.addAll(
            parts.map(
              (e) => e.replaceFirst(RegExp(r'^(and|or|but)\s+', caseSensitive: false), ''),
            ),
          );
          continue;
        }
      }

      // Each match is a sentence plus whatever ended it. Written without a
      // lookbehind so it behaves identically on every Dart version.
      for (final match in RegExp(r'[^.!?]+[.!?]*').allMatches(piece)) {
        final sentence = match.group(0)?.trim() ?? '';
        if (sentence.isNotEmpty) sentences.add(sentence);
      }
    }
    return sentences;
  }

  /// Is there anything here worth giving a bubble to?
  ///
  /// A bubble holding just "," or "-" is the thing this exists to stop: an item
  /// has to carry at least one letter and be long enough to read as something.
  bool _isDisplayableItem(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 3) return false;
    return RegExp(r'[A-Za-z]').hasMatch(trimmed);
  }

  // Parses a raw string of themes into a list of labeled items.
  // One bubble per sentence; _extractList has already dropped the fragments.
  List<Map<String, String>> _parseThemes(dynamic data, String defaultIcon) {
    return _extractList(data)
        .map((s) => {'icon': defaultIcon, 'label': s.endsWith('.') ? s : '$s.'})
        .toList();
  }

  // Same idea as _parseThemes but for improvement/critical areas.
  // Also extracts a short label (first 4 words) as the "title" of each insight.
  List<Map<String, String>> _parseImprovements(dynamic data) {
    final merged = _extractList(data);
    return merged
        .where((s) => s.length > 5) // skip very short fragments
        .map((s) {
          final sentence = s.endsWith('.') ? s : '$s.';
          // Extract a short label: first 3–5 words, capitalised
          final words = sentence.split(' ');
          final labelWords = words
              .take(words.length > 4 ? 4 : words.length)
              .join(' ');
          final label = labelWords.endsWith('.')
              ? labelWords
              : '$labelWords...';
          return {
            'icon': '⚠️',
            'label': label[0].toUpperCase() + label.substring(1),
            'detail':
                sentence, // full sentence shown as sub-detail below the label
          };
        })
        .toList();
  }

  // Maps a word to a color based on its length — simple but gives visual variety
  // Short words get one color, longer words get another. Murag random but consistent.
  Color _getWordColor(String word) {
    final colors = [
      AppColors.primary,
      AppColors.success,
      Colors.lightBlueAccent,
      AppColors.warning,
    ];
    return colors[word.length %
        colors.length]; // modulo gives predictable color per word
  }

  // Filter Logic — returns only the feedback items matching the selected sentiment filter
  List<Map<String, dynamic>> get _filteredFeedback {
    List<Map<String, dynamic>> filtered = List.from(_allFeedback);

    if (_selectedFilter != 'All') {
      filtered = filtered
          .where((f) => f['sentiment'] == _selectedFilter)
          .toList();
    }

    if (_selectedSubjectFilter != 'All Subjects') {
      filtered = filtered
          .where((f) => f['course'] == _selectedSubjectFilter)
          .toList();
    }

    filtered.sort((a, b) {
      if (_sortOrder == 'Date (Newest)') {
        return (b['date'] as String).compareTo(a['date'] as String);
      } else if (_sortOrder == 'Date (Oldest)') {
        return (a['date'] as String).compareTo(b['date'] as String);
      } else if (_sortOrder == 'Sentiment (Positive First)') {
        final weightA = _sentimentWeight(a['sentiment'] as String);
        final weightB = _sentimentWeight(b['sentiment'] as String);
        return weightB.compareTo(weightA); // Positive > Neutral > Critical
      } else if (_sortOrder == 'Sentiment (Critical First)') {
        final weightA = _sentimentWeight(a['sentiment'] as String);
        final weightB = _sentimentWeight(b['sentiment'] as String);
        return weightA.compareTo(weightB); // Critical > Neutral > Positive
      }
      return 0;
    });

    return filtered;
  }

  int _sentimentWeight(String sentiment) {
    if (sentiment == 'Positive') return 3;
    if (sentiment == 'Neutral') return 2;
    return 1; // Critical
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
          icon: const Icon(Icons.menu),
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        // Two-line title: screen name + active term below it
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Student Feedback',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (_activeTermDisplay.isNotEmpty)
              Text(
                _activeTermDisplay,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        actions: [
          // Manual refresh button — in case the AI analysis just came in and user wants fresh data
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            tooltip: 'Refresh',
            onPressed: _fetchFeedbackData,
          ),
        ],
      ),
      // Show spinner while loading, then the content once ready
      body: _isLoading
          ? const AppleLoadingState(label: 'Analyzing student feedback…')
          : RefreshIndicator(
              onRefresh:
                  _fetchFeedbackData, // pull-to-refresh triggers re-fetch
              color: AppColors.primary,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ApplePageHeader(
                        eyebrow: 'Student Voice',
                        title: 'Feedback Insights',
                        subtitle: 'Sentiment, recurring themes, and individual comments.',
                      ),
                      const SizedBox(height: 24),
                      // ==========================================
                      // SENTIMENT ANALYSIS DASHBOARD
                      // ==========================================
                      // Card showing the breakdown of positive/neutral/critical feedback percentages
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.textPrimary.withValues(
                                alpha: 0.05,
                              ),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.pie_chart, color: AppColors.primary),
                                SizedBox(width: 8),
                                Text(
                                  'Emotional Tone Overview',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Segmented Bar Chart — one colored segment per sentiment type
                            // flex values are the percentages (clamped to at least 1 to avoid 0-flex crash)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: (_sentimentSummary['positive'] as int)
                                        .clamp(1, 100),
                                    child: Container(
                                      height: 12,
                                      color: AppColors.success,
                                    ),
                                  ),
                                  Expanded(
                                    flex: (_sentimentSummary['neutral'] as int)
                                        .clamp(1, 100),
                                    child: Container(
                                      height: 12,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                  Expanded(
                                    flex: (_sentimentSummary['negative'] as int)
                                        .clamp(1, 100),
                                    child: Container(
                                      height: 12,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Legend & Stats — percentage labels below the bar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSentimentStat(
                                  'Positive',
                                  '${_sentimentSummary['positive']}%',
                                  AppColors.success,
                                ),
                                _buildSentimentStat(
                                  'Neutral',
                                  '${_sentimentSummary['neutral']}%',
                                  AppColors.textSecondary,
                                ),
                                _buildSentimentStat(
                                  'Critical',
                                  '${_sentimentSummary['negative']}%',
                                  AppColors.error,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ==========================================
                      // ✨ NEW: AI INSTRUCTOR INSIGHT SUMMARY
                      // ==========================================
                      // The AI reads all the feedback and writes a summary so the instructor
                      // doesnt have to read 200+ student comments manually. Importente feature.
                      const Text(
                        'AI Instructor Insights',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // --- Main Insight Card ---
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.textPrimary.withValues(
                                alpha: 0.05,
                              ),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row with AI icon and label
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.auto_awesome,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'What Your Students Are Saying',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'AI-generated interpretation',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(
                              height: 1,
                              color: AppColors.background,
                            ),
                            const SizedBox(height: 16),

                            // Summary Text — the paragraph the AI wrote about this instructor's feedback
                            Text(
                              _aiInsightSummary,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Analyzed comments pill — shows how many comments the AI based this on
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.comment_outlined,
                                        size: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Based on ${_sentimentSummary['totalComments']} comments',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                        ),
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
                      // Shows the things students consistently said good things about
                      if (_positiveThemes.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.15),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.04,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.thumb_up_alt_outlined,
                                    color: AppColors.success,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Key Positive Themes',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Consistently praised aspects of your teaching',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Each theme shown as a green chip/badge
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: _positiveThemes.map((theme) {
                                  return Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width -
                                          80,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withValues(
                                        alpha: 0.07,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.success.withValues(
                                          alpha: 0.2,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          theme['icon']!,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            theme['label']!,
                                            style: const TextStyle(
                                              color: AppColors.success,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                      // This only shows if students had complaints — the uncomfortable part
                      if (_improvementInsights.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.04,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.tips_and_updates_outlined,
                                    color: AppColors.warning,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Improvement Insights',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Areas flagged in student feedback worth reviewing',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Each insight shows an icon, short label, and full detail text
                              Column(
                                children: _improvementInsights.map((insight) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Warning icon in a colored box — makes it stand out
                                        Container(
                                          width: 36,
                                          height: 36,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            insight['icon']!,
                                            style: const TextStyle(
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Short title label in bold orange
                                              Text(
                                                insight['label']!,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: AppColors.warning,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              // Full detail text in smaller gray text
                                              Text(
                                                insight['detail']!,
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12,
                                                  height: 1.5,
                                                ),
                                              ),
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
                      // UPGRADED WORD CLOUD GENERATOR
                      // ==========================================
                      // Visual word cloud — words that students used most appear bigger.
                      // The cloud is random-shuffled so it looks more natural, less boring.
                      const Text(
                        'AI Word Cloud',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.textPrimary, Color(0xFF0F172A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.textPrimary.withValues(
                                alpha: 0.2,
                              ),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        // DEF-02: a word could run past the panel edge and be
                        // cut off mid-word, and because the cloud reshuffles on
                        // every load, WHICH word was clipped changed between
                        // refreshes. Rotated words were the ones at risk: their
                        // own text width becomes the vertical extent, and
                        // nothing bounded either extent to the panel.
                        //
                        // LayoutBuilder gives the panel's real inner width, and
                        // every word below is bounded to it and allowed to
                        // scale down rather than overflow. That holds for
                        // rotated words too -- inside a RotatedBox the
                        // constraints are swapped, so the same maxWidth caps
                        // what becomes the word's height. Clipping is now
                        // impossible by construction rather than by luck of the
                        // shuffle.
                        child: LayoutBuilder(
                          builder: (context, panelConstraints) {
                            final double maxWordExtent =
                                panelConstraints.maxWidth;
                            return Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8.0,
                          runSpacing: 6.0,
                          children: _wordCloud.map((wordData) {
                            // Scale font: weight 14–58 maps to 10–22px readable range
                            // High count words = bigger, rare words = smaller
                            final double rawWeight =
                                (wordData['weight'] as double).clamp(
                                  14.0,
                                  58.0,
                                );
                            final double fontSize =
                                10.0 + ((rawWeight - 14.0) / 44.0) * 12.0;

                            final Widget wordText = Text(
                              wordData['word'],
                              textAlign: TextAlign.center,
                              softWrap: false,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: fontSize > 18
                                    ? FontWeight.w800
                                    : FontWeight.w600, // bold if large
                                color: wordData['color'],
                                height: 1.1,
                                letterSpacing: -0.1,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    offset: const Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            );

                            // Bounded to the panel and allowed to shrink, so a
                            // long word renders smaller instead of running off
                            // the edge. scaleDown only ever reduces, so short
                            // words keep the size their count earned them.
                            final Widget boundedWord = ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxWordExtent,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: wordText,
                              ),
                            );

                            // Restore organic layout: every 5th or 7th word goes vertical (bottom→top)
                            if (wordData['rotated'] == true) {
                              return RotatedBox(
                                quarterTurns:
                                    3, // 270° = bottom-to-top rotation for visual variety
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  child: boundedWord,
                                ),
                              );
                            }
                            return boundedWord; // normal horizontal word
                          }).toList(),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ==========================================
                      // INDIVIDUAL FEEDBACK LIST & FILTERS
                      // ==========================================
                      // The raw list of actual student comments — filterable by sentiment type
                      // DEF-04: the counter had no give in this Row, so a wider
                      // value or a larger system font size pushed it hard
                      // against the edge and clipped it. Both sides are now
                      // Flexible with a gap between, so the heading yields
                      // before the number is ever cut.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              'Direct Quotes',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Show count of currently filtered results
                          Flexible(
                            child: Text(
                              '${_filteredFeedback.length} Comments',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Filter chips row — All, Positive, Neutral, Critical
                      _buildFilterRow(),
                      const SizedBox(height: 12),

                      // Dropdowns for Subject Filter and Sort Order
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedSubjectFilter,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: AppColors.surface,
                              ),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.primary,
                              ),
                              items: _availableSubjects.map((String subject) {
                                return DropdownMenuItem<String>(
                                  value: subject,
                                  child: Text(
                                    subject,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(
                                    () => _selectedSubjectFilter = value,
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _sortOrder,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: AppColors.surface,
                              ),
                              icon: const Icon(
                                Icons.sort,
                                color: AppColors.primary,
                              ),
                              items: _sortOptions.map((String option) {
                                return DropdownMenuItem<String>(
                                  value: option,
                                  child: Text(
                                    option,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _sortOrder = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // If filtered list is empty, show a simple message
                      _filteredFeedback.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Text(
                                  "No comments match this filter.",
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            )
                          // Otherwise show each feedback item as a colored card
                          : Column(
                              children: _filteredFeedback.map((feedback) {
                                // Determine visual style based on sentiment — color-coded for quick reading
                                Color sentimentColor =
                                    feedback['sentiment'] == 'Positive'
                                    ? AppColors.success
                                    : feedback['sentiment'] == 'Critical'
                                    ? AppColors.error
                                    : AppColors.textTertiary;
                                IconData sentimentIcon =
                                    feedback['sentiment'] == 'Positive'
                                    ? Icons.sentiment_very_satisfied
                                    : feedback['sentiment'] == 'Critical'
                                    ? Icons.sentiment_dissatisfied
                                    : Icons.sentiment_neutral;

                                return Card(
                                  color: AppColors.surface,
                                  elevation: 1,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: sentimentColor.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 1,
                                    ), // subtle colored border
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            // Subject code pill on the left
                                            Flexible(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.background,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  feedback['course'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: AppColors.primary,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Date on the right side
                                            Text(
                                              feedback['date'],
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        // The actual feedback text in italic — what the student wrote
                                        Text(
                                          '"${feedback['text']}"',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 14,
                                            fontStyle: FontStyle.italic,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // Sentiment icon and label at the bottom — green/gray/red
                                        Row(
                                          children: [
                                            Icon(
                                              sentimentIcon,
                                              color: sentimentColor,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              feedback['sentiment'],
                                              style: TextStyle(
                                                color: sentimentColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
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
            ),
    );
  }

  // Premium Filter Row with counts + icons — horizontally scrollable chips for each filter type
  Widget _buildFilterRow() {
    final filters = [
      {
        'label': 'All',
        'icon': Icons.all_inclusive_rounded,
        'count': _allFeedback.length, // total count regardless of sentiment
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
      scrollDirection:
          Axis.horizontal, // scroll if screen too small to fit all chips
      child: Row(
        children: filters.map((f) {
          final label = f['label'] as String;
          final icon = f['icon'] as IconData;
          final count = f['count'] as int;
          final color = f['color'] as Color;
          final selected =
              _selectedFilter == label; // is this the active filter?

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: 200,
              ), // smooth transition when selected
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: selected
                    ? color
                    : AppColors.surface, // filled when selected
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? color : color.withValues(alpha: 0.3),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: InkWell(
                onTap: () => setState(
                  () => _selectedFilter = label,
                ), // update active filter
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: selected ? Colors.white : color,
                      ), // white when selected
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
                      // Count badge inside each chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
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

  // Helper Widget for Sentiment Stats — shows percentage in big text with color-coded label
  Widget _buildSentimentStat(String label, String percentage, Color color) {
    return Column(
      children: [
        Text(
          percentage,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
