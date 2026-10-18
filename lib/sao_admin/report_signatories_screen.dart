// lib/sao_admin/report_signatories_screen.dart
// Edits the single report_signatories row used for the report sign-off block.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/apple_ui.dart';

class ReportSignatoriesScreen extends StatefulWidget {
  const ReportSignatoriesScreen({super.key});

  @override
  State<ReportSignatoriesScreen> createState() =>
      _ReportSignatoriesScreenState();
}

class _ReportSignatoriesScreenState extends State<ReportSignatoriesScreen> {
  final _supabase = Supabase.instance.client;

  static const _roles = <({String key, String label})>[
    (key: 'prepared_by', label: 'Prepared by'),
    (key: 'checked_by', label: 'Checked and Verified'),
    (key: 'certified_by', label: 'Certified Proper and In Order'),
  ];

  final Map<String, TextEditingController> _c = {
    for (final r in _roles) ...{
      '${r.key}_name': TextEditingController(),
      '${r.key}_title': TextEditingController(),
    }
  };

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await _supabase
          .from('report_signatories')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row != null) {
        for (final e in _c.entries) {
          e.value.text = (row[e.key] ?? '').toString();
        }
      }
    } catch (e) {
      debugPrint('ReportSignatories load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _supabase.from('report_signatories').upsert({
        'id': 1,
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _snack('Signatories saved');
    } catch (e) {
      debugPrint('ReportSignatories save error: $e');
      _snack('Could not save signatories. Please try again.', isError: true);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      );

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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report Signatories',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
            Text('Names shown on printed reports',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
      body: _isLoading
          ? const AppleLoadingState(label: 'Loading signatories…')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in _roles) ...[
                    Text(r.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _c['${r.key}_name'], decoration: _dec('Name')),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _c['${r.key}_title'],
                        decoration: _dec('Title')),
                    const SizedBox(height: 20),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: Text(_isSaving ? 'Saving…' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
