// Which evaluation form the CURRENT term uses (writes eval_term_instruments).
// SET-15 + SUP-15 (new forms) or the old SAST-20. Only the SAO office can
// write the table (RLS); a refused write is shown, not worked around.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';

class TermFormSettingCard extends StatefulWidget {
  const TermFormSettingCard({super.key});

  @override
  State<TermFormSettingCard> createState() => _TermFormSettingCardState();
}

class _TermFormSettingCardState extends State<TermFormSettingCard> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  String? _termId;
  String _termLabel = '';
  String? _current; // 'NEW' | 'OLD' | null (not set)
  String? _picked;
  Map<String, int> _ids = {}; // code -> instrument id

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _db
          .from('system_settings')
          .select('current_term_id, academic_terms(semester, academic_year)')
          .limit(1)
          .maybeSingle();
      final termId = s?['current_term_id']?.toString();
      final t = s?['academic_terms'];
      final instruments = await _db.from('eval_instruments').select('id, code');
      final ids = {for (final r in instruments as List) r['code'].toString(): (r['id'] as num).toInt()};
      String? current;
      if (termId != null) {
        final rows = await _db
            .from('eval_term_instruments')
            .select('evaluator_type, instrument_id')
            .eq('term_id', termId);
        final byType = {for (final r in rows as List) r['evaluator_type'].toString(): (r['instrument_id'] as num).toInt()};
        final student = byType['student'];
        if (student != null) current = student == ids['SAST-20'] ? 'OLD' : 'NEW';
      }
      if (!mounted) return;
      setState(() {
        _termId = termId;
        _termLabel = t is Map ? '${t['semester']} ${t['academic_year']}' : '';
        _ids = ids;
        _current = current;
        _picked = current;
        _loading = false;
      });
    } catch (e) {
      debugPrint('TermFormSettingCard load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final termId = _termId;
    final picked = _picked;
    if (termId == null || picked == null) return;
    final uid = _db.auth.currentUser?.id;
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() => _saving = true);
    try {
      Map<String, dynamic> row(String type, int id) =>
          {'term_id': termId, 'evaluator_type': type, 'instrument_id': id, 'set_by': uid, 'set_at': now};
      if (picked == 'NEW') {
        final set = _ids['SET-15'];
        final sup = _ids['SUP-15'];
        if (set == null || sup == null) throw 'SET-15 / SUP-15 are not registered in the database.';
        await _db.from('eval_term_instruments').upsert(
            [row('student', set), row('supervisor', sup)],
            onConflict: 'term_id,evaluator_type');
      } else {
        final old = _ids['SAST-20'];
        if (old == null) throw 'SAST-20 is not registered in the database.';
        await _db.from('eval_term_instruments').upsert([row('student', old)], onConflict: 'term_id,evaluator_type');
        // The old form has no supervisor evaluation.
        await _db.from('eval_term_instruments').delete().eq('term_id', termId).eq('evaluator_type', 'supervisor');
      }
      if (!mounted) return;
      setState(() {
        _current = picked;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form for this semester saved.'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      debugPrint('TermFormSettingCard save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      final denied = e is PostgrestException && (e.code == '42501' || e.message.toLowerCase().contains('row-level'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(denied
              ? 'Not allowed: the database refused this change for your account.'
              : 'Could not save the form choice. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            : _termId == null
                ? const Text('No current semester is set yet.', style: TextStyle(color: AppColors.textSecondary))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Form used by $_termLabel',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                        _current == null
                            ? 'Not set yet. Pick the form for this semester.'
                            : 'Saved: ${_current == 'NEW' ? 'new forms (SET-15 + SUP-15)' : 'old SAST-20 form'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        emptySelectionAllowed: true,
                        segments: const [
                          ButtonSegment(value: 'NEW', label: Text('New: SET-15 + SUP-15')),
                          ButtonSegment(value: 'OLD', label: Text('Old: SAST-20')),
                        ],
                        selected: {?_picked},
                        onSelectionChanged: (v) => setState(() => _picked = v.isEmpty ? null : v.first),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: (_saving || _picked == null || _picked == _current) ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save form for this semester'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
