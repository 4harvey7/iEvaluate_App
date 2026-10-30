// eval_results_service.dart
// Read side of the new 15-item evaluations (SET-15 student, SUP-15 supervisor).
// The database stores every mean / percent (migration 019); this file only
// loads and groups them. Item texts and section titles come from the
// eval_instrument_* registry, never from the app. Student SET and supervisor
// results are always kept apart.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/sast_rating.dart';

class EvalItemInfo {
  final int no;
  final String section;
  final String text;
  const EvalItemInfo(this.no, this.section, this.text);
}

/// One scored scope (instrument + instructor + term + subject or pooled).
class EvalScope {
  final String code; // SET-15 / SUP-15
  final String title;
  final String evaluatorType; // student | supervisor
  final Map<String, String> sectionTitles; // A -> title
  final List<EvalItemInfo> items;
  double? pct;
  double? mean;
  String? verbal;
  int respondents = 0;
  int excluded = 0;
  final Map<String, double?> sectionPct = {};
  final Map<int, double?> itemMean = {};
  final Map<int, double?> itemPct = {};
  final Map<int, int> itemAnswered = {};

  EvalScope(this.code, this.title, this.evaluatorType, this.sectionTitles, this.items);

  String get verbalLabel => (verbal != null && verbal!.isNotEmpty) ? verbal! : SastRating.verbalPct(pct);
}

class EvalReport {
  final EvalScope? student;
  final EvalScope? supervisor;
  final List<String> studentComments;
  final List<String> supervisorComments;
  const EvalReport({this.student, this.supervisor, this.studentComments = const [], this.supervisorComments = const []});
}

class EvalResultsService {
  EvalResultsService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Registry cache: instrument id -> (code, title, evaluator_type, sections, items).
  static Map<int, Map<String, dynamic>>? _registry;

  static Future<Map<int, Map<String, dynamic>>> _loadRegistry() async {
    final cached = _registry;
    if (cached != null) return cached;
    final res = await Future.wait<dynamic>([
      _db.from('eval_instruments').select('id, code, title, evaluator_type, is_legacy'),
      _db.from('eval_instrument_sections').select('instrument_id, section_code, title, sort_order'),
      _db.from('eval_instrument_items').select('instrument_id, item_no, section_code, text').order('item_no', ascending: true),
    ]);
    final reg = <int, Map<String, dynamic>>{};
    for (final r in res[0] as List) {
      reg[(r['id'] as num).toInt()] = {
        'code': r['code'], 'title': r['title'], 'type': r['evaluator_type'],
        'legacy': r['is_legacy'] == true,
        'sections': <String, String>{}, 'items': <EvalItemInfo>[],
      };
    }
    for (final r in res[1] as List) {
      final e = reg[(r['instrument_id'] as num).toInt()];
      if (e != null) (e['sections'] as Map<String, String>)[r['section_code'].toString()] = r['title'].toString();
    }
    for (final r in res[2] as List) {
      final e = reg[(r['instrument_id'] as num).toInt()];
      if (e != null) {
        (e['items'] as List<EvalItemInfo>).add(EvalItemInfo(
            (r['item_no'] as num).toInt(), r['section_code'].toString(), r['text'].toString()));
      }
    }
    return _registry = reg;
  }

  static Set<int> _idsOfType(Map<int, Map<String, dynamic>> reg, String type) => {
        for (final e in reg.entries)
          if (e.value['type'] == type && e.value['legacy'] != true) e.key
      };

  /// Scores for an instructor + term. [subjectId] null = all subjects pooled.
  /// The student scope uses [subjectId]; the supervisor scope is always pooled.
  /// Returns null when there are no eval_results rows at all (old-form term).
  static Future<EvalReport?> load({
    required String instructorId,
    required String termId,
    String? subjectId,
  }) async {
    try {
      final reg = await _loadRegistry();
      final rows = await _db
          .from('eval_results')
          .select('instrument_id, subject_id, level, section_code, item_no, respondents, excluded_responses, answered_count, mean, pct, verbal_label')
          .eq('instructor_id', instructorId)
          .eq('term_id', termId);
      final all = (rows as List).cast<Map<String, dynamic>>();
      if (all.isEmpty) return null;

      EvalScope? build(String type, String? sid) {
        final ids = _idsOfType(reg, type);
        final mine = all.where((r) {
          if (!ids.contains((r['instrument_id'] as num).toInt())) return false;
          final rs = r['subject_id']?.toString();
          return sid == null ? rs == null : rs == sid;
        }).toList();
        if (mine.isEmpty) return null;
        final info = reg[(mine.first['instrument_id'] as num).toInt()]!;
        final s = EvalScope(info['code'], info['title'], type, info['sections'], info['items']);
        for (final r in mine) {
          switch (r['level']) {
            case 'overall':
              s.pct = SastRating.parse(r['pct']);
              s.mean = SastRating.parse(r['mean']);
              s.verbal = r['verbal_label']?.toString();
              s.respondents = SastRating.parseInt(r['respondents']) ?? 0;
              s.excluded = SastRating.parseInt(r['excluded_responses']) ?? 0;
            case 'section':
              s.sectionPct[r['section_code'].toString()] = SastRating.parse(r['pct']);
            case 'item':
              final n = (r['item_no'] as num).toInt();
              s.itemMean[n] = SastRating.parse(r['mean']);
              s.itemPct[n] = SastRating.parse(r['pct']);
              s.itemAnswered[n] = SastRating.parseInt(r['answered_count']) ?? 0;
          }
        }
        return s;
      }

      final student = build('student', subjectId);
      final supervisor = build('supervisor', null);
      if (student == null && supervisor == null) return null;

      var q = _db.from('eval_response_comments').select('evaluator_type, subject_id, comments')
          .eq('instructor_id', instructorId).eq('term_id', termId);
      if (subjectId != null) q = q.eq('subject_id', subjectId);
      final cRows = (await q as List).cast<Map<String, dynamic>>();
      List<String> pick(String type) => [
            for (final c in cRows)
              if (c['evaluator_type'] == type && (c['comments']?.toString().trim().isNotEmpty ?? false))
                c['comments'].toString().trim()
          ];
      // Supervisor comments are pooled: they are not tied to the subject filter.
      var supComments = pick('supervisor');
      if (subjectId != null) {
        final sc = await _db.from('eval_response_comments').select('comments')
            .eq('instructor_id', instructorId).eq('term_id', termId).eq('evaluator_type', 'supervisor');
        supComments = [for (final c in sc as List) if (c['comments']?.toString().trim().isNotEmpty ?? false) c['comments'].toString().trim()];
      }
      return EvalReport(student: student, supervisor: supervisor,
          studentComments: pick('student'), supervisorComments: supComments);
    } catch (e) {
      debugPrint('[EvalResultsService] load failed: $e');
      return null;
    }
  }

  /// SET overall % per subject for one instructor + term.
  static Future<Map<String, double>> subjectPcts(String instructorId, String termId) async {
    try {
      final ids = _idsOfType(await _loadRegistry(), 'student');
      final rows = await _db.from('eval_results').select('instrument_id, subject_id, pct')
          .eq('instructor_id', instructorId).eq('term_id', termId).eq('level', 'overall').not('subject_id', 'is', null);
      return {
        for (final r in rows as List)
          if (ids.contains((r['instrument_id'] as num).toInt()) && SastRating.parse(r['pct']) != null)
            r['subject_id'].toString(): SastRating.parse(r['pct'])!
      };
    } catch (e) {
      debugPrint('[EvalResultsService] subjectPcts failed: $e');
      return {};
    }
  }

  /// Pooled SET overall % per term for one instructor (trend across semesters).
  static Future<Map<String, double>> termPcts(String instructorId) async {
    try {
      final ids = _idsOfType(await _loadRegistry(), 'student');
      final rows = await _db.from('eval_results').select('instrument_id, term_id, pct')
          .eq('instructor_id', instructorId).eq('level', 'overall').isFilter('subject_id', null);
      return {
        for (final r in rows as List)
          if (ids.contains((r['instrument_id'] as num).toInt()) && SastRating.parse(r['pct']) != null)
            r['term_id'].toString(): SastRating.parse(r['pct'])!
      };
    } catch (e) {
      debugPrint('[EvalResultsService] termPcts failed: $e');
      return {};
    }
  }

  /// Pooled SET overall % per instructor per term, for a set of instructors:
  /// instructor id -> (term id -> pct). Empty on failure (callers fall back to means).
  static Future<Map<String, Map<String, double>>> pooledPctsFor(List<String> instructorIds) async {
    if (instructorIds.isEmpty) return {};
    try {
      final ids = _idsOfType(await _loadRegistry(), 'student');
      final rows = await _db.from('eval_results').select('instrument_id, instructor_id, term_id, pct')
          .filter('instructor_id', 'in', instructorIds).eq('level', 'overall').isFilter('subject_id', null);
      final out = <String, Map<String, double>>{};
      for (final r in rows as List) {
        final pct = SastRating.parse(r['pct']);
        if (pct == null || !ids.contains((r['instrument_id'] as num).toInt())) continue;
        (out[r['instructor_id'].toString()] ??= {})[r['term_id'].toString()] = pct;
      }
      return out;
    } catch (e) {
      debugPrint('[EvalResultsService] pooledPctsFor failed: $e');
      return {};
    }
  }

  /// Pooled SET overall % + respondents per instructor for one term.
  /// RLS limits the rows to what the caller may read.
  static Future<Map<String, ({double pct, int respondents})>> instructorPcts(String termId) async {
    try {
      final ids = _idsOfType(await _loadRegistry(), 'student');
      final rows = await _db.from('eval_results').select('instrument_id, instructor_id, pct, respondents')
          .eq('term_id', termId).eq('level', 'overall').isFilter('subject_id', null);
      final out = <String, ({double pct, int respondents})>{};
      for (final r in rows as List) {
        final pct = SastRating.parse(r['pct']);
        if (pct == null || !ids.contains((r['instrument_id'] as num).toInt())) continue;
        out[r['instructor_id'].toString()] = (pct: pct, respondents: SastRating.parseInt(r['respondents']) ?? 0);
      }
      return out;
    } catch (e) {
      debugPrint('[EvalResultsService] instructorPcts failed: $e');
      return {};
    }
  }

  /// Instructors and subjects with SET results in a term, plus the average of
  /// the pooled instructor percents. Null when the term has no new results.
  static Future<({int instructors, int subjects, double? avgPct})?> termSummary(String termId) async {
    try {
      final ids = _idsOfType(await _loadRegistry(), 'student');
      final rows = await _db.from('eval_results').select('instrument_id, instructor_id, subject_id, pct')
          .eq('term_id', termId).eq('level', 'overall');
      final instr = <String>{};
      final subj = <String>{};
      final pooled = <double?>[];
      for (final r in rows as List) {
        if (!ids.contains((r['instrument_id'] as num).toInt())) continue;
        if (r['subject_id'] == null) {
          instr.add(r['instructor_id'].toString());
          pooled.add(SastRating.parse(r['pct']));
        } else {
          subj.add(r['subject_id'].toString());
        }
      }
      if (instr.isEmpty && subj.isEmpty) return null;
      return (instructors: instr.length, subjects: subj.length, avgPct: SastRating.averageOfPresent(pooled));
    } catch (e) {
      debugPrint('[EvalResultsService] termSummary failed: $e');
      return null;
    }
  }

  /// Ids of instructors this user has already evaluated as a supervisor in a term.
  static Future<Set<String>> evaluatedBy(String evaluatorUserId, String termId) async {
    try {
      final rows = await _db.from('eval_responses').select('instructor_id')
          .eq('evaluator_user_id', evaluatorUserId).eq('term_id', termId).eq('status', 'submitted');
      return {for (final r in rows as List) r['instructor_id'].toString()};
    } catch (e) {
      debugPrint('[EvalResultsService] evaluatedBy failed: $e');
      return {};
    }
  }

  /// Dept-head view: SET (student only, never SUP-15) overall rows of a term,
  /// one per instructor + subject. RLS limits the rows to the head's own
  /// department. Empty = the term has no SET-15 results (old-form term).
  static Future<List<({String subjectId, String instructorId, double pct, int respondents})>> deptSubjectRows(String termId) async {
    try {
      final ids = _idsOfType(await _loadRegistry(), 'student');
      final rows = await _db.from('eval_results').select('instrument_id, instructor_id, subject_id, pct, respondents')
          .eq('term_id', termId).eq('level', 'overall').not('subject_id', 'is', null);
      return [
        for (final r in rows as List)
          if (ids.contains((r['instrument_id'] as num).toInt()) && SastRating.parse(r['pct']) != null)
            (
              subjectId: r['subject_id'].toString(),
              instructorId: r['instructor_id'].toString(),
              pct: SastRating.parse(r['pct'])!,
              respondents: SastRating.parseInt(r['respondents']) ?? 0,
            )
      ];
    } catch (e) {
      debugPrint('[EvalResultsService] deptSubjectRows failed: $e');
      return [];
    }
  }
}
