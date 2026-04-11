// lib/instructor/student_feedback_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

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

  // --- 2. AI WORD CLOUD DATA ---
  // Weights dictate the font size. Colors represent sentiment of the word.
  final List<Map<String, dynamic>> _wordCloud = [
    {'word': 'Engaging', 'weight': 32.0, 'color': Colors.green},
    {'word': 'Fast-paced', 'weight': 24.0, 'color': Colors.orange},
    {'word': 'Helpful', 'weight': 28.0, 'color': Colors.green},
    {'word': 'Clear', 'weight': 22.0, 'color': AppColors.royalBlue},
    {'word': 'Examples', 'weight': 26.0, 'color': AppColors.deepBlue},
    {'word': 'Challenging', 'weight': 20.0, 'color': Colors.orange},
    {'word': 'Approachable', 'weight': 18.0, 'color': Colors.green},
    {'word': 'Projects', 'weight': 22.0, 'color': AppColors.royalBlue},
    {'word': 'Strict', 'weight': 16.0, 'color': Colors.redAccent},
    {'word': 'Inspiring', 'weight': 30.0, 'color': AppColors.gold},
    {'word': 'Rubrics', 'weight': 14.0, 'color': Colors.grey},
    {'word': 'Coding', 'weight': 24.0, 'color': AppColors.deepBlue},
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Student Feedback', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),

      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI Sentiment Analysis', style: TextStyle(color: AppColors.darkGray, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Our AI has read and categorized all written student comments from your evaluation forms.', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 24),

              // ==========================================
              // SENTIMENT ANALYSIS DASHBOARD
              // ==========================================
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.pie_chart, color: AppColors.royalBlue),
                        SizedBox(width: 8),
                        Text('Emotional Tone Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.deepBlue)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Segmented Bar Chart
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        children: [
                          Expanded(flex: _sentimentSummary['positive'], child: Container(height: 12, color: Colors.green)),
                          Expanded(flex: _sentimentSummary['neutral'], child: Container(height: 12, color: Colors.grey.shade400)),
                          Expanded(flex: _sentimentSummary['negative'], child: Container(height: 12, color: Colors.redAccent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Legend & Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSentimentStat('Positive', '${_sentimentSummary['positive']}%', Colors.green),
                        _buildSentimentStat('Neutral', '${_sentimentSummary['neutral']}%', Colors.grey.shade600),
                        _buildSentimentStat('Critical', '${_sentimentSummary['negative']}%', Colors.redAccent),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // WORD CLOUD GENERATOR
              // ==========================================
              const Text('AI Word Cloud', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.deepBlue,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.royalBlue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16.0, // Horizontal space between words
                  runSpacing: 12.0, // Vertical space between lines
                  children: _wordCloud.map((wordData) {
                    return Text(
                      wordData['word'],
                      style: TextStyle(
                        fontSize: wordData['weight'],
                        fontWeight: FontWeight.bold,
                        color: wordData['color'],
                        // Adds a tiny shadow to make words pop off the dark background
                        shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2, offset: const Offset(1, 1))],
                      ),
                    );
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
                  const Text('Direct Quotes', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('${_filteredFeedback.length} Comments', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
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
                        selectedColor: filter == 'Positive' ? Colors.green.withOpacity(0.2)
                            : filter == 'Critical' ? Colors.red.withOpacity(0.2)
                            : filter == 'Neutral' ? Colors.grey.withOpacity(0.2)
                            : AppColors.royalBlue.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? (filter == 'Positive' ? Colors.green.shade800 : filter == 'Critical' ? Colors.red.shade800 : AppColors.deepBlue)
                              : Colors.grey,
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
                  child: Text("No comments match this filter.", style: TextStyle(color: Colors.grey)),
                ),
              )
                  : Column(
                children: _filteredFeedback.map((feedback) {
                  // Determine visual style based on sentiment
                  Color sentimentColor = feedback['sentiment'] == 'Positive' ? Colors.green
                      : feedback['sentiment'] == 'Critical' ? Colors.red
                      : Colors.grey;
                  IconData sentimentIcon = feedback['sentiment'] == 'Positive' ? Icons.sentiment_very_satisfied
                      : feedback['sentiment'] == 'Critical' ? Icons.sentiment_dissatisfied
                      : Icons.sentiment_neutral;

                  return Card(
                    color: AppColors.white,
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
                                decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(6)),
                                child: Text(feedback['course'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.royalBlue)),
                              ),
                              Text(feedback['date'], style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '"${feedback['text']}"',
                            style: const TextStyle(color: AppColors.darkGray, fontSize: 14, fontStyle: FontStyle.italic, height: 1.4),
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
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}