// lib/dept_head/faculty_roster_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class FacultyRosterScreen extends StatefulWidget {
  const FacultyRosterScreen({super.key});

  @override
  State<FacultyRosterScreen> createState() => _FacultyRosterScreenState();
}

class _FacultyRosterScreenState extends State<FacultyRosterScreen> {
  // --- UPDATED DUMMY DATA WITH SENTIMENT ---
  final List<Map<String, dynamic>> _facultyList = [
    {
      'name': 'Kirito (Kazuto Kirigaya)',
      'title': 'Senior Instructor',
      'score': 4.95,
      'trend': 'up',
      'evals': 142,
      'sentiment': {'pos': 0.85, 'neu': 0.10, 'neg': 0.05},
      'tags': ['Expert Knowledge', 'Engaging', 'Fast Responder']
    },
    {
      'name': 'Asuna Yuuki',
      'title': 'Associate Professor',
      'score': 4.88,
      'trend': 'up',
      'evals': 110,
      'sentiment': {'pos': 0.80, 'neu': 0.15, 'neg': 0.05},
      'tags': ['Approachable', 'Clear Rubrics', 'Patient']
    },
    {
      'name': 'Klein (Ryotaro Tsuboi)',
      'title': 'Adjunct Instructor',
      'score': 2.85,
      'trend': 'down',
      'evals': 105,
      'sentiment': {'pos': 0.20, 'neu': 0.30, 'neg': 0.50},
      'tags': ['Unclear Instructions', 'Slow Grading', 'Hard to Reach']
    },
    // ... add more as needed
  ];

  String _searchQuery = '';
  String _sortBy = 'Score (Highest to Lowest)';

  List<Map<String, dynamic>> get _filteredAndSortedFaculty {
    List<Map<String, dynamic>> filtered = _facultyList.where((faculty) {
      return faculty['name'].toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (_sortBy == 'Score (Highest to Lowest)') {
      filtered.sort((a, b) => b['score'].compareTo(a['score']));
    } else if (_sortBy == 'Score (Lowest to Highest)') {
      filtered.sort((a, b) => a['score'].compareTo(b['score']));
    } else if (_sortBy == 'Name (A-Z)') {
      filtered.sort((a, b) => a['name'].compareTo(b['name']));
    }
    return filtered;
  }

  void _showInstructorDetails(Map<String, dynamic> instructor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final sent = instructor['sentiment'] ?? {'pos': 0.0, 'neu': 0.0, 'neg': 0.0};
        final tags = instructor['tags'] ?? [];

        return Container(
          height: MediaQuery.of(context).size.height * 0.85, // Made taller for more info
          decoration: const BoxDecoration(
            color: AppColors.lightGray,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sticky Header (Same as before)
              _buildModalHeader(instructor),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuickStats(instructor),
                      const SizedBox(height: 32),

                      // ==========================================
                      // 📊 SENTIMENT ANALYSIS SECTION
                      // ==========================================
                      const Text('Sentiment Analysis', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Comment Polarity Distribution', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 16),
                            // Sentiment Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 12,
                                child: Row(
                                  children: [
                                    Expanded(flex: (sent['pos'] * 100).toInt(), child: Container(color: Colors.green)),
                                    Expanded(flex: (sent['neu'] * 100).toInt(), child: Container(color: Colors.orange)),
                                    Expanded(flex: (sent['neg'] * 100).toInt(), child: Container(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildSentimentLegend(sent),
                            const Divider(height: 32),
                            const Text('Key Sentiment Tags', style: TextStyle(color: AppColors.darkGray, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tags.map<Widget>((tag) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: instructor['score'] >= 3.0 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: instructor['score'] >= 3.0 ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
                                ),
                                child: Text(tag, style: TextStyle(fontSize: 12, color: instructor['score'] >= 3.0 ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600)),
                              )).toList(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                      // Action buttons for Dean
                      if (instructor['score'] < 3.0) _buildInterventionCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Helper UI Builders to keep code clean ---

  Widget _buildModalHeader(Map<String, dynamic> instructor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Row(
        children: [
          CircleAvatar(radius: 30, backgroundColor: AppColors.royalBlue.withOpacity(0.1), child: Text(instructor['name'][0], style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold, fontSize: 24))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(instructor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.darkGray)),
            Text(instructor['title'], style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  Widget _buildQuickStats(Map<String, dynamic> instructor) {
    return Row(
      children: [
        Expanded(child: _statCard('Overall Score', '${instructor['score']}', instructor['score'] >= 3.0 ? AppColors.deepBlue : Colors.red)),
        const SizedBox(width: 16),
        Expanded(child: _statCard('Total Evals', '${instructor['evals']}', AppColors.deepBlue)),
      ],
    );
  }

  Widget _statCard(String label, String val, Color valColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: valColor)),
      ]),
    );
  }

  Widget _buildSentimentLegend(Map<String, dynamic> sent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _legendItem('Positive', '${(sent['pos'] * 100).toInt()}%', Colors.green),
        _legendItem('Neutral', '${(sent['neu'] * 100).toInt()}%', Colors.orange),
        _legendItem('Negative', '${(sent['neg'] * 100).toInt()}%', Colors.red),
      ],
    );
  }

  Widget _legendItem(String label, String perc, Color color) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label: ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(perc, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.darkGray)),
    ]);
  }

  Widget _buildInterventionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.warning, color: Colors.red), SizedBox(width: 8), Text('Intervention Required', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () {}, child: const Text('Draft Intervention Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ]),
    );
  }
  @override
  Widget build(BuildContext context) {
    final roster = _filteredAndSortedFaculty;

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: const Text('Faculty Roster', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),

      ),
      body: SafeArea(
        child: Column(
          children: [
            // ==========================================
            // SEARCH & SORT HEADER
            // ==========================================
            Container(
              padding: const EdgeInsets.all(24.0),
              color: AppColors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search instructor name...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: AppColors.lightGray,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${roster.length} Instructors Found', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      DropdownButton<String>(
                        value: _sortBy,
                        icon: const Icon(Icons.sort, color: AppColors.royalBlue, size: 18),
                        style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold, fontSize: 13),
                        underline: const SizedBox(),
                        items: ['Score (Highest to Lowest)', 'Score (Lowest to Highest)', 'Name (A-Z)'].map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value));
                        }).toList(),
                        onChanged: (newValue) => setState(() => _sortBy = newValue!),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ==========================================
            // ROSTER LIST
            // ==========================================
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: roster.length,
                itemBuilder: (context, index) {
                  final faculty = roster[index];
                  // Flag low performers with a red border
                  bool isLowPerformer = faculty['score'] < 3.0;

                  return Card(
                    color: AppColors.white,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isLowPerformer ? Colors.red.withOpacity(0.5) : Colors.transparent, width: 2),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showInstructorDetails(faculty),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            // Rank / Status Indicator
                            SizedBox(
                              width: 30,
                              child: Text(
                                '#${index + 1}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: isLowPerformer ? Colors.red : Colors.grey.shade400, fontSize: 16),
                              ),
                            ),

                            // Profile Avatar
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.royalBlue.withOpacity(0.1),
                              child: Text(faculty['name'][0], style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 16),

                            // Name & Title
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(faculty['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGray, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(faculty['title'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),

                            // Score & Trend
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      faculty['trend'] == 'up' ? Icons.trending_up : (faculty['trend'] == 'down' ? Icons.trending_down : Icons.trending_flat),
                                      color: faculty['trend'] == 'up' ? Colors.green : (faculty['trend'] == 'down' ? Colors.red : Colors.orange),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${faculty['score']}',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isLowPerformer ? Colors.red : AppColors.deepBlue),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${faculty['evals']} evals', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}