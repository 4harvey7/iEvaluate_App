// lib/data_validation_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
// Notice: We removed the gatherer_drawer.dart import because this screen doesn't need its own drawer anymore!

class DataValidationScreen extends StatefulWidget {
  const DataValidationScreen({super.key});

  @override
  State<DataValidationScreen> createState() => _DataValidationScreenState();
}

class _DataValidationScreenState extends State<DataValidationScreen> {
  // --- UPDATED SS FORM 2 FLAGGED DATA ---
  final List<Map<String, dynamic>> _flaggedForms = [
    {
      'id': 'FORM-2099',
      'instructor': 'Kazuto Kirigaya',
      'subject': 'CS202',
      'remarks': 'Great class and very helpful.',
      'confidence': 0.82,
      'issue': 'Multiple selections detected on Question 2.',
      'scores': [
        {'q': 'Gives reasonable course / subject assignments.', 'val': '5'},
        {'q': 'Earns appreciation and kind attention...', 'val': '?'},
        {'q': 'Shows deep interest and concern...', 'val': '4'},
      ]
    },
    {
      'id': 'FORM-2100',
      'instructor': 'Asuna Yuuki',
      'subject': 'IT305',
      'remarks': '',
      'confidence': 0.75,
      'issue': 'Missing Data: "Remarks and Suggestions" is required.',
      'scores': [
        {'q': 'Presents lesson clearly, methodically...', 'val': '5'},
        {'q': 'Motivates the students to learn.', 'val': '5'},
      ]
    }
  ];

  void _showValidationSheet(Map<String, dynamic> form) {
    final TextEditingController instructorController = TextEditingController(text: form['instructor']);
    final TextEditingController subjectController = TextEditingController(text: form['subject']);
    final TextEditingController remarksController = TextEditingController(text: form['remarks']);

    List<Map<String, dynamic>> scoreItems = List.from(form['scores']);
    List<TextEditingController> scoreControllers = scoreItems.map((item) {
      return TextEditingController(text: item['val']);
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.90,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HEADER & ALERT
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Itemized Data Validation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.warning.withOpacity(0.5))),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(child: Text('System Flag: ${form['issue']}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 13))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. SCROLLABLE MIDDLE SECTION
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Original Scanned Document', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                              color: AppColors.textPrimary,
                              borderRadius: BorderRadius.circular(12),
                              image: const DecorationImage(image: AssetImage('assets/images/CTU_logo.png'), fit: BoxFit.cover, opacity: 0.3)
                          ),
                          child: const Center(child: Text('Tap to zoom to error zone', style: TextStyle(color: Colors.white54))),
                        ),
                        const SizedBox(height: 24),

                        // General Info
                        const Text('Header Data', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildValidationInput(label: 'Instructor', controller: instructorController, hasError: RegExp(r'[0-9]').hasMatch(form['instructor']))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildValidationInput(label: 'Subject', controller: subjectController, hasError: false)),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Itemized Scores
                        const Text('Itemized Evaluation Scores (1-5)', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: scoreItems.length,
                            separatorBuilder: (context, index) => const Divider(height: 16),
                            itemBuilder: (context, index) {
                              String qText = scoreItems[index]['q'];
                              TextEditingController sCtrl = scoreControllers[index];
                              bool isError = double.tryParse(sCtrl.text) == null || double.parse(sCtrl.text) > 5 || double.parse(sCtrl.text) < 1;

                              return Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(qText, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: SizedBox(
                                      height: 45,
                                      child: TextField(
                                        controller: sCtrl,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: isError ? AppColors.error.withOpacity(0.1) : AppColors.background,
                                          contentPadding: EdgeInsets.zero,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isError ? AppColors.error : Colors.transparent)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isError ? AppColors.error : Colors.transparent)),
                                        ),
                                        style: TextStyle(fontWeight: FontWeight.bold, color: isError ? AppColors.error : AppColors.textPrimary),
                                      ),
                                    ),
                                  )
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Remarks Info
                        TextField(
                          controller: remarksController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Remarks & Suggestions (Required)',
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: form['remarks'].trim().isEmpty ? AppColors.error : Colors.transparent)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: form['remarks'].trim().isEmpty ? AppColors.error : Colors.transparent)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // 3. ACTION BUTTONS
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: AppColors.error), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form rejected.')));
                        },
                        child: const Text('Reject', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: AppColors.success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () {
                          setState(() => _flaggedForms.remove(form));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data approved!'), backgroundColor: AppColors.success));
                        },
                        child: const Text('Approve & Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildValidationInput({required String label, required TextEditingController controller, required bool hasError}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hasError ? AppColors.error : Colors.transparent)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hasError ? AppColors.error : Colors.transparent)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 👈 NEW: Scaffold, AppBar, and Drawer are completely removed!
    // This widget now simply returns a SafeArea so it fits perfectly inside the parent screen.
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Error Detection System', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('The AI requires human verification for the following scanned documents before they can be added to the database.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12)),
                      child: Text('${_flaggedForms.length} Pending Verifications', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _flaggedForms.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified, color: AppColors.success.shade200, size: 80),
                  const SizedBox(height: 16),
                  const Text('All Data Validated!', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Text('Database is clean and up to date.', style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _flaggedForms.length,
              itemBuilder: (context, index) {
                final form = _flaggedForms[index];
                return Card(
                  color: AppColors.surface,
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.warning.withOpacity(0.5), width: 1.5)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showValidationSheet(form),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(form['id'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              Text('Confidence: ${(form['confidence'] * 100).toInt()}%', style: TextStyle(fontWeight: FontWeight.bold, color: form['confidence'] < 0.7 ? AppColors.error : AppColors.warning, fontSize: 12)),
                            ],
                          ),
                          const Divider(),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.warning, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(form['issue'], style: const TextStyle(color: AppColors.textPrimary, fontSize: 14))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text('Tap to Resolve ➔', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                          )
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
    );
  }
}