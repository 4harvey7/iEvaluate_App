// lib/dept_head/faculty_roster_screen.dart
import 'package:flutter/material.dart';
import '../app_colors.dart';

class FacultyRosterScreen extends StatefulWidget {
  const FacultyRosterScreen({super.key});

  @override
  State<FacultyRosterScreen> createState() => _FacultyRosterScreenState();
}

class _FacultyRosterScreenState extends State<FacultyRosterScreen> {
  // --- DUMMY FACULTY DATA ---
  final List<Map<String, dynamic>> _facultyList = [
    {
      'name': 'Kirito (Kazuto Kirigaya)',
      'title': 'Senior Instructor',
      'score': 4.95,
      'trend': 'up',
      'evals': 142,
    },
    {
      'name': 'Asuna Yuuki',
      'title': 'Associate Professor',
      'score': 4.88,
      'trend': 'up',
      'evals': 110,
    },
    {
      'name': 'Eugeo',
      'title': 'Instructor',
      'score': 4.75,
      'trend': 'same',
      'evals': 95,
    },
    {
      'name': 'Alice Zuberg',
      'title': 'Assistant Professor',
      'score': 4.60,
      'trend': 'up',
      'evals': 120,
    },
    {
      'name': 'Sinon (Shino Asada)',
      'title': 'Instructor',
      'score': 4.30,
      'trend': 'down',
      'evals': 88,
    },
    {
      'name': 'Klein (Ryotaro Tsuboi)',
      'title': 'Adjunct Instructor',
      'score': 2.85, // 👈 The low performer flagged on the dashboard
      'trend': 'down',
      'evals': 105,
    },
  ];

  String _searchQuery = '';
  String _sortBy = 'Score (Highest to Lowest)';

  // Logic to filter and sort the roster
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

  // ==========================================
  // INSTRUCTOR DEEP-DIVE POPUP
  // ==========================================
  void _showInstructorDetails(Map<String, dynamic> instructor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: AppColors.lightGray,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sticky Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.royalBlue.withOpacity(0.1),
                      child: Text(instructor['name'][0], style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.bold, fontSize: 24)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(instructor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.darkGray)),
                          Text(instructor['title'], style: const TextStyle(color: Colors.grey, fontSize: 14)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
              ),

              // Content Area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quick Stats
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                children: [
                                  const Text('Overall Score', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  Text('${instructor['score']}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: instructor['score'] >= 3.0 ? AppColors.deepBlue : Colors.red)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                children: [
                                  const Text('Total Evals', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  Text('${instructor['evals']}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.deepBlue)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Interventions Action (Only shows if score is low)
                      if (instructor['score'] < 3.0) ...[
                        const Text('Dean Actions', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.warning, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Intervention Required', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('This instructor has fallen below the acceptable threshold. Administrative action is advised.', style: TextStyle(color: AppColors.darkGray, fontSize: 13)),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention report drafted.')));
                                  },
                                  child: const Text('Draft Intervention Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
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