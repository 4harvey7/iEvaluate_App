// lib/instructor/add_subject_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import 'models/subject.dart';
import 'providers/subjects_provider.dart';

class AddSubjectScreen extends StatefulWidget {
  const AddSubjectScreen({super.key});

  @override
  State<AddSubjectScreen> createState() => _AddSubjectScreenState();
}

class _AddSubjectScreenState extends State<AddSubjectScreen> {
  static final _recommendedCodePattern = RegExp(r'^[A-Z]{2,5}\d{2,4}$');

  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onChange);
    _nameController.addListener(_onChange);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  bool get _isFormValid =>
      _codeController.text.trim().isNotEmpty &&
      _nameController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = context.read<SubjectsProvider>();

    if (provider.exists(code)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Already in your list'),
          content: Text('"$code" is already in your subjects. Save anyway?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await provider.add(
      Subject(
        code: code,
        name: name,
        addedAt: DateTime.now(),
      ),
    );

    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Subject added')),
    );
  }

  String? get _codeHelperText {
    final code = _codeController.text.trim();
    if (code.isEmpty) return null;
    if (!_recommendedCodePattern.hasMatch(code)) {
      return 'Heads up: codes usually look like CS101 or IT305.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        title: const Text('Add Subject'),
        actions: [
          TextButton(
            onPressed: _isFormValid ? _save : null,
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('codeField'),
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(8),
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    return newValue.copyWith(text: newValue.text.toUpperCase());
                  }),
                ],
                decoration: InputDecoration(
                  labelText: 'Subject Code',
                  hintText: 'e.g. CS101',
                  helperText: _codeHelperText,
                  helperStyle: const TextStyle(color: AppColors.warning),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('nameField'),
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(60),
                ],
                decoration: const InputDecoration(
                  labelText: 'Subject Name',
                  hintText: 'e.g. Intro to Programming',
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Subject codes auto-capitalize. You can edit and delete subjects in a later update.',
                        style: TextStyle(
                          color: AppColors.textPrimary.withOpacity(0.8),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
