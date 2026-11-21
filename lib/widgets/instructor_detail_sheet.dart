// lib/widgets/instructor_detail_sheet.dart
// Shared instructor detail bottom sheet: dark header, SAST report button, score chips,
// historical bar chart (zoomable) and this-term subjects. Loads its own data.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/evaluation_service.dart';
import '../core/utils/sast_rating.dart';
import '../instructor/detailed_report_screen.dart';
import '../theme/app_colors.dart';
import 'apple_ui.dart';
import 'safe_button.dart';

/// Opens the sheet right away; [termId] null = system_settings.current_term_id.
/// Guarding against double-opening is the caller's job.
Future<void> showInstructorDetailSheet(
  BuildContext context, {
  required String instructorId,
  required String name,
  String roleLabel = '',
  String department = '',
  String? termId,
  Widget? extra,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InstructorDetailSheet(
      instructorId: instructorId,
      name: name,
      roleLabel: roleLabel,
      department: department,
      termId: termId,
      extra: extra,
    ),
  );
}

/// Merges instructor_subjects rows with management_results rows by subject_id.
/// Several result rows for one subject are averaged; no score -> null.
List<Map<String, dynamic>> mergeSubjectScores(
    List<Map<String, dynamic>> subjectRows,
    List<Map<String, dynamic>> resultRows) {
  final byId = <String, List<double>>{};
  for (final r in resultRows) {
    final v = SastRating.parse(r['overall_management_mean']);
    final id = r['subject_id']?.toString();
    if (v != null && id != null) byId.putIfAbsent(id, () => []).add(v);
  }
  return subjectRows.map((r) {
    final s = r['subjects'];
    final sub = s is List ? (s.isEmpty ? null : s.first) : s;
    final m = sub is Map ? sub : const {};
    final scores = byId[r['subject_id']?.toString()];
    return <String, dynamic>{
      'subject_id': r['subject_id'],
      'subject_code': m['subject_code']?.toString() ?? '',
      'subject_name': m['subject_name']?.toString() ?? '',
      'score': (scores == null || scores.isEmpty)
          ? null
          : scores.reduce((a, b) => a + b) / scores.length,
    };
  }).toList();
}

class _SheetData {
  final Map<String, dynamic>? term;
  final Map<String, dynamic>? overall;
  final List<Map<String, dynamic>> subjects;
  final List<Map<String, dynamic>> history;
  final String? termId;
  _SheetData(this.termId, this.term, this.overall, this.subjects, this.history);
}

class _InstructorDetailSheet extends StatefulWidget {
  final String instructorId, name, roleLabel, department;
  final String? termId;
  final Widget? extra;
  const _InstructorDetailSheet({
    required this.instructorId,
    required this.name,
    required this.roleLabel,
    required this.department,
    required this.termId,
    required this.extra,
  });

  @override
  State<_InstructorDetailSheet> createState() => _InstructorDetailSheetState();
}

class _InstructorDetailSheetState extends State<_InstructorDetailSheet> {
  late Future<_SheetData> _future = _load();
  double _chartScale = 1.0; // zoom level of the bar chart

  Future<_SheetData> _load() async {
    final db = Supabase.instance.client;
    var termId = widget.termId;
    if (termId == null) {
      final s = await db.from('system_settings').select('current_term_id').limit(1).maybeSingle();
      termId = s?['current_term_id']?.toString();
    }
    final history = EvaluationService().getInstructorHistory(widget.instructorId);
    if (termId == null) {
      return _SheetData(null, null, null, const [], await history);
    }
    final results = await Future.wait<dynamic>([
      db.from('academic_terms').select('semester, academic_year').eq('id', termId).maybeSingle(),
      db
          .from('overall_total_survey')
          .select('overall_mean, combined_score_mean, management_mean, performance_mean, total_responses')
          .eq('instructor_id', widget.instructorId)
          .eq('term_id', termId)
          .maybeSingle(),
      db
          .from('instructor_subjects')
          .select('subject_id, subjects(subject_code, subject_name)')
          .eq('instructor_id', widget.instructorId)
          .eq('term_id', termId),
      db
          .from('management_results')
          .select('subject_id, overall_management_mean')
          .eq('instructor_id', widget.instructorId)
          .eq('term_id', termId),
      history,
    ]);
    return _SheetData(
      termId,
      results[0] as Map<String, dynamic>?,
      results[1] as Map<String, dynamic>?,
      mergeSubjectScores(List<Map<String, dynamic>>.from(results[2] as List),
          List<Map<String, dynamic>>.from(results[3] as List)),
      List<Map<String, dynamic>>.from(results[4] as List),
    );
  }

  Future<void> _openReport(_SheetData d) async {
    final o = d.overall;
    final overall = o == null ? null : (SastRating.parse(o['combined_score_mean']) ?? SastRating.parse(o['overall_mean']));
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailedReportScreen(
        userId: widget.instructorId,
        termId: d.termId,
        instructorName: widget.name,
        department: widget.department,
        term: d.term?['semester']?.toString() ?? '',
        academicYear: d.term?['academic_year']?.toString() ?? '',
        managementScore: SastRating.parse(o?['management_mean']),
        performanceScore: SastRating.parse(o?['performance_mean']),
        overallScore: overall,
        totalEvaluations: SastRating.parseInt(o?['total_responses']) ?? 0,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.name.trim();
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
          decoration: const BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary.withValues(alpha: 0.3),
              child: Text(n.isEmpty ? '?' : String.fromCharCode(n.runes.first),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                if (widget.roleLabel.isNotEmpty)
                  Text(widget.roleLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12), overflow: TextOverflow.ellipsis),
                if (widget.department.isNotEmpty)
                  Text(widget.department, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11), overflow: TextOverflow.ellipsis),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<_SheetData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const AppleLoadingState();
              }
              if (snap.hasError) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Could not load instructor details.', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ]),
                );
              }
              return _content(snap.data!);
            },
          ),
        ),
      ]),
    );
  }

  Widget _content(_SheetData d) {
    final o = d.overall;
    final overall = o == null ? null : (SastRating.parse(o['combined_score_mean']) ?? SastRating.parse(o['overall_mean']));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: SafeElevatedButton(
            onPressed: () => _openReport(d),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.picture_as_pdf, size: 20),
              SizedBox(width: 8),
              Text('SAST Report', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        if (widget.extra != null) ...[widget.extra!, const SizedBox(height: 20)],
        const Text('Score Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _infoTile('Overall', SastRating.format(overall), AppColors.primary)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile('Management', SastRating.format(SastRating.parse(o?['management_mean'])), Colors.teal)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile('Performance', SastRating.format(SastRating.parse(o?['performance_mean'])), AppColors.success)),
        ]),
        const SizedBox(height: 6),
        Text('${SastRating.parseInt(o?['total_responses']) ?? 0} responses this term',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 24),
        _chart(d.history),
        const SizedBox(height: 24),
        Text('Subjects This Term (${d.subjects.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        if (d.subjects.isEmpty)
          const Text('No subjects assigned.', style: TextStyle(color: AppColors.textSecondary))
        else
          ...d.subjects.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.menu_book, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${s['subject_code']} — ${s['subject_name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(SastRating.format(s['score'] as double?),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                  ),
                ]),
              )),
      ]),
    );
  }

  // Bar chart moved unchanged from performance_analysis_screen.
  Widget _chart(List<Map<String, dynamic>> history) {
    // null-score terms are omitted
    final data = history.where((h) => h['score'] != null).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Expanded(
          child: Text('Historical Performance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.zoom_out, color: AppColors.primary),
            onPressed: () {
              if (_chartScale > 0.6) setState(() => _chartScale -= 0.2);
            },
          ),
          Text('${(_chartScale * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: AppColors.primary),
            onPressed: () {
              if (_chartScale < 2.5) setState(() => _chartScale += 0.2);
            },
          ),
        ]),
      ]),
      const SizedBox(height: 8),
      Container(
        height: 220,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: data.isEmpty
            ? const Center(child: Text('No historical data available', style: TextStyle(color: AppColors.textSecondary)))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 80),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: data.map<Widget>((h) {
                      final score = (h['score'] as num).toDouble();
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0 * _chartScale),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                          Text(SastRating.format(score), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 8),
                          Container(
                            width: 40 * _chartScale,
                            height: (score / 5.0) * 120,
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                          ),
                          const SizedBox(height: 8),
                          Text('${h['sem']}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _infoTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
