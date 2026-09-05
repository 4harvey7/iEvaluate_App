// evaluation_service.dart
// this is the big boy service. handles all the evaluation data fetching.
// talks to supabase, crunches numbers, returns summaries. importente kaayo.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// holds the summary stats for a whole department -- overall score, means, totals, etc.
// murag the final report card of the department, but for deans to look at
class EvaluationSummary {
  final double averageScore;     // overall average score across all faculty in dept
  final double managementMean;   // average management category score
  final double performanceMean;  // average performance category score
  final int totalEvaluations;    // responses already folded into the scores
  final double completionRate;   // how many students actually submitted, 0.0 to 1.0
  /// Faculty shown on the Overview headcount this term.
  ///
  /// NOT "approved accounts only" any more. It is kept equal to
  /// FacultyRosterScreen's own rule -- active, OR still holding a result for
  /// this term -- on purpose: this number and the row count on the Faculty tab
  /// used to disagree the moment someone was deactivated, because this one
  /// dropped immediately while the roster kept showing the person (correctly)
  /// until their last term with results ended. A dean deactivating someone
  /// mid-term would open the Faculty tab to 5 rows under an Overview card that
  /// had already dropped to 4.
  ///
  /// So [facultyCount] now falls by one only once [activeFacultyCount] does
  /// AND that person's last-recorded term has passed -- the same moment the
  /// roster stops listing them. See [activeFacultyCount] for the account-status
  /// count this is built from.
  final int facultyCount;
  final int evaluatedCount;      // how many of [facultyCount] actually have results yet

  /// Currently active (account_status = 'approved') faculty, independent of
  /// term data. This is the number [facultyCount] used to be. Exists
  /// separately so the UI can say WHY the two headcounts differ -- "5 total,
  /// 1 deactivated" -- instead of just changing the number with no explanation.
  final int activeFacultyCount;

  /// Forms actually scanned for this department this term, counted from the
  /// raw uploads rather than from the aggregates.
  ///
  /// Deliberately separate from [totalEvaluations]: n8n folds a scan into
  /// overall_total_survey some time after the SAO staff uploads it, so this is
  /// the larger, earlier number. The difference is the backlog.
  final int formsScanned;

  EvaluationSummary({
    required this.averageScore,
    required this.managementMean,
    required this.performanceMean,
    required this.totalEvaluations,
    required this.completionRate,
    required this.facultyCount,
    int? activeFacultyCount,
    this.evaluatedCount = 0,
    this.formsScanned = 0,
  })  // Every call site already knew its active count before this field existed
      // except the zero-data fallbacks, where active and total are the same
      // number anyway (nobody has data to be a deactivated exception to).
      : activeFacultyCount = activeFacultyCount ?? facultyCount;

  /// Forms collected but not yet reflected in any score.
  int get formsAwaitingProcessing =>
      formsScanned > totalEvaluations ? formsScanned - totalEvaluations : 0;

  /// True when the term has started but nothing has been scanned yet.
  ///
  /// The dashboards need this to say "no evaluations yet" instead of printing
  /// 0.00, which reads as a department that scored nothing.
  bool get hasNoData => evaluatedCount == 0;

  /// True when only some of the faculty have been scanned, so every average
  /// here describes [evaluatedCount] people rather than the whole department.
  bool get isPartial => evaluatedCount > 0 && evaluatedCount < facultyCount;

  /// How many of [facultyCount] are a deactivated account kept only because it
  /// still holds a result this term. Zero once nobody on the roster is in that
  /// state -- in particular, always zero once the term rolls past their last
  /// recorded one, which is what makes [facultyCount] fall to match.
  int get deactivatedWithResults =>
      (facultyCount - activeFacultyCount).clamp(0, facultyCount);
}

// holds performance data for a single instructor -- name, dept, score, trend
// this is what shows up in the top instructors leaderboard, basin they proud of it
class InstructorPerformance {
  final String id;             // instructor user id
  final String name;           // full name of the instructor
  final String department;     // what department they belong to
  final double overallScore;   // their overall evaluation score
  final int subjectCount;      // how many subjects they teaching this term
  final String trend;          // "up", "down", or "stable" -- currently hardcoded to "up", bahala na

  InstructorPerformance({
    required this.id,
    required this.name,
    required this.department,
    required this.overallScore,
    required this.subjectCount,
    required this.trend,
  });
}

// holds analytics data for a specific subject -- avg score, dept avg, difficulty level, sentiment
// also contains instructor breakdown so dean can see who teaching that subject and how good they are
class SubjectAnalytic {
  final String code;            // subject code like "CS101"
  final String name;            // full subject name
  final double avgScore;        // average score across all instructors teaching this subject
  final double deptAvg;         // department-wide average for comparison
  final String difficulty;      // "High", "Moderate", or "Low" difficulty based on score
  final String sentiment;       // "Critical", "Neutral", or "Positive" based on score
  final String trend;           // trend direction -- currently hardcoded "stable"
  final int sections;           // how many sections this subject has
  final String? aiNote;         // optional AI-generated note if score is significantly below dept avg
  final List<SubjectInstructorPerformance> instructorBreakdown; // per-instructor performance for this subject

  SubjectAnalytic({
    required this.code,
    required this.name,
    required this.avgScore,
    required this.deptAvg,
    required this.difficulty,
    required this.sentiment,
    required this.trend,
    required this.sections,
    this.aiNote,
    this.instructorBreakdown = const [],
  });
}

// holds the performance of one instructor for one specific subject
// used inside SubjectAnalytic as a breakdown list
class SubjectInstructorPerformance {
  final String instructorId;    // instructor user id
  final String instructorName;  // instructor full name
  final double avgScore;        // their average score for this subject
  final int sections;           // number of sections they teach for this subject
  final int totalResponses;     // total student responses they received

  SubjectInstructorPerformance({
    required this.instructorId,
    required this.instructorName,
    required this.avgScore,
    required this.sections,
    this.totalResponses = 0, // defaults to 0 if server give nothing
  });
}

// an alert for when an instructor score is dangerously low
// dean use this to know who need intervention asap, dili ta ignore these
class ActionAlert {
  final String type;            // alert type, currently always "Performance"
  final String title;           // short title of the alert
  final String desc;            // longer description with the actual score info
  final String? instructorId;   // who the alert is about
  final String? instructorName; // their name, for display
  final String? subjectCode;    // related subject, if applicable
  final DateTime dateFlagged;   // when this alert was generated

  ActionAlert({
    required this.type,
    required this.title,
    required this.desc,
    this.instructorId,
    this.instructorName,
    this.subjectCode,
    required this.dateFlagged,
  });
}

// a formal intervention report created by a dean for an underperforming instructor
// gets saved to the database and optionally triggers an email notification
class InterventionReport {
  final String id;              // unique ID of this report
  final String instructorId;   // who the intervention is for
  final String instructorName; // their name stored in the report
  final String deanId;         // which dean created this report
  final String actionType;     // what kind of action is being taken
  final String notes;          // written notes from the dean
  final String status;         // "Pending", "Resolved", etc.
  final String termId;         // which academic term this belongs to
  final DateTime createdAt;    // when the report was created

  InterventionReport({
    required this.id,
    required this.instructorId,
    required this.instructorName,
    required this.deanId,
    required this.actionType,
    required this.notes,
    required this.status,
    required this.termId,
    required this.createdAt,
  });
}

/// Averages [resultRows] per academic term, counting a result only when the
/// instructor belonged to the department in that term.
///
/// [membership] holds `'termId|instructorId'` pairs read from
/// instructor_department_terms. That snapshot is the whole point: department
/// membership has no term dimension of its own, so without it a past term's
/// average is rebuilt from *today's* membership and moving one instructor
/// silently rewrites numbers that were already reported.
///
/// An empty [membership] means no snapshot exists for this department yet, and
/// every row is kept -- the pre-snapshot behaviour, so a chart degrades to
/// slightly-wrong rather than empty.
///
/// Lives outside EvaluationService so the rule can be tested without a
/// database; a closed term's number never moving is a property of this
/// function, not of Supabase.
List<Map<String, dynamic>> averagePerTerm(
  List<Map<String, dynamic>> resultRows, {
  required Set<String> membership,
}) {
  final grouped = <String, Map<String, dynamic>>{};

  for (final row in resultRows) {
    final termId = row['term_id']?.toString() ?? 'unknown';
    final instructorId = row['instructor_id']?.toString();

    // Earned while the instructor was somewhere else -- not this department's
    // number to report.
    if (membership.isNotEmpty &&
        (instructorId == null ||
            !membership.contains('$termId|$instructorId'))) {
      continue;
    }

    final overall = (row['combined_score_mean'] as num?)?.toDouble() ??
        (row['overall_mean'] as num?)?.toDouble() ??
        0.0;

    final bucket = grouped.putIfAbsent(
      termId,
      () => {'sum': 0.0, 'count': 0, 'term': row['academic_terms']},
    );
    bucket['sum'] = (bucket['sum'] as double) + overall;
    bucket['count'] = (bucket['count'] as int) + 1;
  }

  final history = <Map<String, dynamic>>[];
  grouped.forEach((termId, data) {
    final count = data['count'] as int;
    if (count == 0) return;
    final term = data['term'];

    // Label reads like "1st\n25-26" on the chart axis.
    String label = 'Sem';
    if (term != null) {
      final ay = term['academic_year'].toString();
      final parts = ay.split('-');
      final yearShort = parts.length == 2
          ? '${parts[0].length >= 2 ? parts[0].substring(parts[0].length - 2) : parts[0]}-'
              '${parts[1].length >= 2 ? parts[1].substring(parts[1].length - 2) : parts[1]}'
          : ay;
      final sem = term['semester'].toString();
      label = '${sem.length >= 3 ? sem.substring(0, 3) : sem}\n$yearShort';
    }

    history.add({
      'sem': label,
      'score':
          double.parse(((data['sum'] as double) / count).toStringAsFixed(2)),
      // Kept so the chart can colour both semesters of one school year alike.
      'year': term?['academic_year']?.toString() ?? '',
      'rawTerm': term,
    });
  });

  // Chronological, then 1st / 2nd / Summer within a year.
  const semOrder = {'1st': 0, '2nd': 1, 'Summer': 2};
  history.sort((a, b) {
    final aTerm = a['rawTerm'];
    final bTerm = b['rawTerm'];
    final aYear = int.tryParse(
            aTerm?['academic_year']?.toString().split('-').first ?? '0') ??
        0;
    final bYear = int.tryParse(
            bTerm?['academic_year']?.toString().split('-').first ?? '0') ??
        0;
    if (aYear != bYear) return aYear.compareTo(bYear);
    final aSem = aTerm?['semester']?.toString() ?? '';
    final bSem = bTerm?['semester']?.toString() ?? '';
    final aKey =
        semOrder.keys.firstWhere((k) => aSem.startsWith(k), orElse: () => '');
    final bKey =
        semOrder.keys.firstWhere((k) => bSem.startsWith(k), orElse: () => '');
    return (semOrder[aKey] ?? 99).compareTo(semOrder[bKey] ?? 99);
  });

  return history
      .map((e) => {'sem': e['sem'], 'score': e['score'], 'year': e['year']})
      .toList();
}

// the main service class -- all database calls live here, not in the widgets
// dili ta put fetch logic in the UI, importente kaayo to keep this separate
class EvaluationService {
  final _supabase = Supabase.instance.client; // the supabase client, our connection to the cloud

  // fetch the currently active academic term ID from system_settings table.
  // almost every other method need this, so it get called a lot. wala choice.
  // returns null if no active term found or something go wrong
  Future<String?> _getActiveTermId() async {
    try {
      final settings = await _supabase
          .from('system_settings')
          .select('current_term_id')
          .maybeSingle(); // maybeSingle so it dont crash if no row found
      
      final termId = settings?['current_term_id'];
      debugPrint('EvaluationService - Active Term ID: $termId');
      return termId; // could be null if nobody set the active term yet
    } catch (e) {
      debugPrint('EvaluationService - Error fetching active term: $e');
      return null; // something broke, return null, caller will handle it
    }
  }

  // get the summary stats for the dean's department.
  // finds the dept, gets all faculty IDs, fetches their scores from overall_total_survey,
  // then calculates averages for display on the dashboard.
  // returns empty summary (all zeros) if anything is missing, bahala na the UI show zeros
  Future<EvaluationSummary> getDepartmentSummary(String userId) async {
    try {
      debugPrint('EvaluationService - Fetching summary for Dean: $userId');
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle(); // find what department this dean belongs to

      if (deptData == null) {
        debugPrint('EvaluationService - No department found for Dean: $userId');
        return _emptySummary(); // dean has no dept?? return zeros, dili ta crash
      }
      final deptId = deptData['Department_name_ID']; // the department ID we need
      debugPrint('EvaluationService - Dean belongs to Dept ID: $deptId');

      final termId = await _getActiveTermId(); // need active term for filtering
      if (termId == null) {
        debugPrint('EvaluationService - No active term ID found.');
        return _emptySummary(); // no active term, nothing to show
      }

      // get all instructors in the dept via instructor_departments
      final facultyRows = await _supabase
          .from('instructor_departments')
          .select('instructor_id')
          .eq('department_id', deptId)
          .eq('is_primary', true);
      
      // Every instructor linked to this dept EXCEPT the head reading the card.
      //
      // Heads do teach and do get evaluated, so their results were counted here
      // for a long time. The problem is that faculty_roster_screen ends its
      // query with `.neq('id', deanId)` -- a head is not on their own roster.
      // So the card was built from one more person than the list underneath it,
      // and the head had no row to attribute the difference to: the forms total
      // read 250 against a roster that added up to less, which is exactly the
      // reconciliation this card exists to support.
      //
      // A head's own teaching results are still theirs to see -- the instructor
      // dashboard shows them -- they just don't fold into the department
      // numbers the head is reporting on. Keep this rule and the roster's
      // `.neq` together: whichever way they point, they must point the same way.
      final facultyIds = (facultyRows as List)
          .where((row) => row['instructor_id'] != null)
          .map((row) => row['instructor_id'].toString())
          .where((id) => id != userId)
          .toList();

      debugPrint('EvaluationService - Found ${facultyIds.length} instructors for Dept $deptId (head excluded)');

      // Staff headcount excludes accounts that are no longer active. Their
      // already-collected results still aggregate below: a fired instructor
      // leaves the roster, but the evaluations students submitted while he was
      // teaching are not deleted from the term's numbers.
      var activeFacultyIds = facultyIds;
      if (facultyIds.isNotEmpty) {
        try {
          final statusRows = await _supabase
              .from('user_info')
              .select('id')
              .filter('id', 'in', facultyIds)
              .eq('account_status', 'approved');
          activeFacultyIds = (statusRows as List)
              .where((row) => row['id'] != null)
              .map((row) => row['id'].toString())
              .toList();
        } catch (e) {
          // Non-fatal: fall back to the linked count rather than lose the
          // whole dashboard over a headcount.
          debugPrint('EvaluationService - Could not filter faculty by status: $e');
        }
      }
      final activeFacultyCount = activeFacultyIds.length;

      if (facultyIds.isEmpty) return _emptySummary(); // no faculty found, show zeros

      // Forms actually collected, counted from the raw scans rather than by
      // summing overall_total_survey.total_responses.
      //
      // Those are not the same number, and the gap is the whole point: n8n
      // aggregates an upload into overall_total_survey some time after the SAO
      // staff scans it, so an instructor with scans but no aggregate row yet
      // contributed NOTHING to the old total. One department read "101 forms
      // this semester" against 152 actually scanned -- 51 forms collected,
      // stored, and invisible to the head who has to chase them.
      //
      // Counted over the SAME people the faculty roster lists, so the card and
      // the list underneath it can be reconciled. Counting every id ever linked
      // to the department made the card read 250 for a roster adding up to 203,
      // because forms belonging to accounts nobody could see were still in the
      // total -- deactivated accounts, and the head themselves, who is dropped
      // from `facultyIds` above for the same reason.
      //
      // That set is no longer "active accounts only". The roster now also keeps
      // a deactivated instructor for as long as their results are still in this
      // term's numbers -- because the average below has always included them,
      // and hiding them from the list while counting their scores is what the
      // head could not reconcile. So the roster's rule is: active, OR still
      // holding results this term. This count follows the same rule, which is
      // why the aggregate fetch now happens first: `stats` is what says who
      // still holds results.
      //
      // Scores continue to include those accounts on purpose -- an evaluation a
      // student submitted is not deleted when the instructor leaves -- and the
      // formsScanned floor at the end of this method still keeps the card from
      // ever claiming fewer forms collected than it has scored.
      //
      // fetch overall survey results for all faculty in this dept for the active term
      final stats = await _supabase
          .from('overall_total_survey')
          .select('''
            overall_mean,
            combined_score_mean,
            management_mean,
            performance_mean,
            total_responses,
            instructor_id
          ''')
          .eq('term_id', termId)
          .filter('instructor_id', 'in', facultyIds); // only get rows for our faculty

      debugPrint('EvaluationService - Found ${(stats as List).length} overall_total_survey records for faculty: $facultyIds');

      // Active faculty, plus anyone still carrying results this term. Exactly
      // the roster's set. When nothing has been aggregated yet this collapses
      // to activeFacultyIds, which is what it used to be in every case.
      final rosterFacultyIds = <String>{
        ...activeFacultyIds,
        for (final row in (stats as List))
          if (row['instructor_id'] != null) row['instructor_id'].toString(),
      }.toList();

      // Forms actually collected, counted from the raw scans.
      //
      // Counted before the "no results yet" early return below on purpose, so
      // that path can still report the forms sitting in the n8n queue.
      var formsScanned = 0;
      if (rosterFacultyIds.isNotEmpty) {
        try {
          final rawRows = await _supabase
              .from('sast_all_raw_data_survey')
              .select('id')
              .eq('term_id', termId)
              .filter('instructor_ID', 'in', rosterFacultyIds);
          formsScanned = (rawRows as List).length;
        } catch (e) {
          // Non-fatal, and it fails low rather than high: fall back to the
          // aggregated count so the card never claims more than it can show.
          debugPrint('EvaluationService - Could not count raw forms: $e');
        }
      }
      debugPrint(
          'EvaluationService - $formsScanned raw forms this term across ${rosterFacultyIds.length} rostered faculty '
          '(${activeFacultyIds.length} active, ${facultyIds.length} linked)');

      if ((stats as List).isEmpty) {
        debugPrint('EvaluationService - No records in overall_total_survey for faculty in term $termId. Dashboard will show 0.0.');
        // Scores are genuinely unknown, but forms may still have been
        // collected and be waiting on n8n. Returning _emptySummary() here told
        // the head nothing had arrived when it had.
        return EvaluationSummary(
          averageScore: 0,
          managementMean: 0,
          performanceMean: 0,
          totalEvaluations: 0,
          completionRate: 0,
          // rosterFacultyIds, not activeFacultyIds -- stats is empty on this
          // path so the two happen to be equal today, but the rule these two
          // numbers state should always be the same one FacultyRosterScreen
          // uses, not "whichever is equal right now."
          facultyCount: rosterFacultyIds.length,
          activeFacultyCount: activeFacultyCount,
          evaluatedCount: 0,
          formsScanned: formsScanned,
        );
      }

      final list = stats as List;
      double totalOverall = 0;
      double totalMgmt = 0;
      double totalPerf = 0;
      int totalResponses = 0;

      // loop through each faculty record and accumulate the totals
      for (var row in list) {
        double mgmt = (row['management_mean'] as num?)?.toDouble() ?? 0.0;
        double perf = (row['performance_mean'] as num?)?.toDouble() ?? 0.0;
        double overall = (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0;

        // Fallback logic if the generated column is 0.0 but component means exist
        if (overall == 0.0 && (mgmt > 0 || perf > 0)) {
          overall = double.parse(((mgmt + perf) / 2).toStringAsFixed(2)); // average of two components
        }

        totalOverall += overall;
        totalMgmt += mgmt;
        totalPerf += perf;
        totalResponses += (row['total_responses'] as int?) ?? 0;
      }

      final count = list.length; // faculty who actually have results this term

      // Completion is measured against the whole roster, not against the
      // people already scanned. Dividing by `count` meant one instructor with
      // 25 responses read as 100% complete for a department of twenty.
      // 25 responses is the assumed full class -- dili guarantee accurate.
      final expectedResponses =
          (activeFacultyCount > 0 ? activeFacultyCount : count) * 25.0;
      final calculatedRate = expectedResponses > 0
          ? (totalResponses / expectedResponses).clamp(0.0, 1.0)
          : 0.0;

      // The means stay averaged over `count`. Treating an unscanned instructor
      // as a zero would be worse than leaving them out -- but evaluatedCount
      // travels with the result so the dashboard can say which it is.
      return EvaluationSummary(
        averageScore: double.parse((totalOverall / count).toStringAsFixed(2)),
        managementMean: double.parse((totalMgmt / count).toStringAsFixed(2)),
        performanceMean: double.parse((totalPerf / count).toStringAsFixed(2)),
        totalEvaluations: totalResponses,
        completionRate: double.parse(calculatedRate.toStringAsFixed(2)),
        // rosterFacultyIds -- active accounts, plus anyone deactivated who still
        // holds a result this term. Kept equal to activeFacultyCount by
        // construction is what let the Overview card read "5 Active Faculty"
        // against a Faculty tab that already, correctly, listed only 4 the
        // moment someone was deactivated mid-term. This is the same number the
        // roster counts its rows by, so the two screens can no longer disagree.
        // `count` (evaluatedCount, below) is always <= this, because every id in
        // `stats` was added into rosterFacultyIds above -- so "Based on X of Y"
        // stays a true subset relationship instead of quietly counting a
        // deactivated account in X while that same account is excluded from Y.
        facultyCount: rosterFacultyIds.length,
        activeFacultyCount: activeFacultyCount,
        evaluatedCount: count,
        formsScanned: formsScanned > totalResponses ? formsScanned : totalResponses,
      );
    } catch (e) {
      debugPrint('Error fetching department summary: $e');
      return _emptySummary(); // something broke badly, return zeros so app dont crash
    }
  }

  // Historical average for the department across past terms.
  //
  // Reads membership from the per-term snapshot, not from current membership,
  // so reassigning an instructor today cannot change a closed term's average.
  // See snapshot_term_departments in migration 10.
  Future<List<Map<String, dynamic>>> getDepartmentHistory(String userId) async {
    try {
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle();

      if (deptData == null) return [];
      final deptId = deptData['Department_name_ID'];

      final membership = <String>{};       // 'termId|instructorId'
      final instructorIds = <String>{};

      // Who belonged to this department in which term.
      //
      // Its own try/catch on purpose: until migration 10 has been applied the
      // table does not exist, and letting that reach the outer catch would
      // return an empty chart instead of falling through to the live-membership
      // path below.
      try {
        final snapshotRows = await _supabase
            .from('instructor_department_terms')
            .select('term_id, instructor_id')
            .eq('department_id', deptId)
            .eq('is_primary', true);

        for (final row in (snapshotRows as List)) {
          final termId = row['term_id']?.toString();
          final instructorId = row['instructor_id']?.toString();
          if (termId == null || instructorId == null) continue;
          membership.add('$termId|$instructorId');
          instructorIds.add(instructorId);
        }
      } catch (e) {
        debugPrint('EvaluationService - Term snapshot unavailable ($e), '
            'using current membership');
        membership.clear();
        instructorIds.clear();
      }

      // No snapshot yet -- migration 10 has not been run, or no term switch has
      // happened since. Fall back to current membership so the chart shows the
      // old (slightly wrong) numbers rather than nothing at all.
      if (membership.isEmpty) {
        debugPrint('EvaluationService - No term snapshot for dept $deptId, '
            'falling back to current membership');
        final liveRows = await _supabase
            .from('instructor_departments')
            .select('instructor_id')
            .eq('department_id', deptId)
            .eq('is_primary', true);
        instructorIds.addAll((liveRows as List)
            .where((row) => row['instructor_id'] != null)
            .map((row) => row['instructor_id'].toString()));
      }

      if (instructorIds.isEmpty) return [];

      final historyData = await _supabase
          .from('overall_total_survey')
          .select('overall_mean, combined_score_mean, instructor_id, term_id, '
              'academic_terms(semester, academic_year)')
          .filter('instructor_id', 'in', instructorIds.toList())
          .order('created_at', ascending: true);

      return averagePerTerm(
        (historyData as List).cast<Map<String, dynamic>>(),
        membership: membership,
      );
    } catch (e) {
      debugPrint('Error fetching dept history: $e');
      return [];
    }
  }

  // get school-wide global stats: overall avg score, total instructors, total responses.
  // used by SAO/admin for the big picture view of the whole university
  // optionally accepts a termId, otherwise uses the active term
  Future<Map<String, dynamic>> getGlobalStats({String? termId}) async {
    final resolvedTermId = termId ?? await _getActiveTermId(); // use provided or fetch active
    if (resolvedTermId == null) return {}; // no term, no data, return empty map

    final data = await _supabase
        .from('overall_total_survey')
        .select('overall_mean, combined_score_mean, total_responses')
        .eq('term_id', resolvedTermId); // get all records for this term
    
    if ((data as List).isEmpty) return {}; // nothing in db, return empty

    final list = data as List;
    double sum = 0;
    int totalResp = 0;
    for (var row in list) {
      sum += (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0;    // accumulate score
      totalResp += (row['total_responses'] as int?) ?? 0;          // accumulate responses
    }

    return {
      'avgScore': sum / list.length,       // average score across all instructors
      'totalInstructors': list.length,     // how many instructors have data
      'totalResponses': totalResp,         // total student responses school-wide
    };
  }

  // get average scores grouped by department name.
  // used for charts that compare departments against each other, murag ranking
  // returns list of maps with 'dept' and 'score' keys
  Future<List<Map<String, dynamic>>> getDepartmentAverages({String? termId}) async {
    final resolvedTermId = termId ?? await _getActiveTermId();
    if (resolvedTermId == null) return []; // no term, return empty list

    // big join query -- goes from survey results up to department name through multiple tables
    final data = await _supabase
        .from('overall_total_survey')
        .select('''
          overall_mean,
          combined_score_mean,
          user_info!instructor_id(
            department_table!user_id(
              department_name!Department_name_ID(d_name)
            )
          )
        ''')
        .eq('term_id', resolvedTermId);

    final Map<String, List<double>> deptScores = {}; // accumulate scores per dept name
    for (var row in (data as List)) {
      final userInfo = row['user_info'];
      if (userInfo == null) continue; // skip if no user info, bahala na
      
      // handle both List and Map response shapes from supabase joins
      final List deptTables = userInfo['department_table'] is List 
          ? userInfo['department_table'] 
          : [userInfo['department_table']];
      
      if (deptTables.isEmpty || deptTables[0] == null) continue; // skip if dept data missing

      final deptTable = deptTables[0];
      final deptNameData = deptTable['department_name'];
      
      String deptName = 'Unknown'; // fallback if dept name missing, murag mystery dept
      if (deptNameData != null) {
        deptName = deptNameData['d_name'] ?? 'Unknown';
      }
      
      final score = (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0;
      deptScores.putIfAbsent(deptName, () => []).add(score); // add score to that dept's list
    }

    // compute average for each dept and return as list of maps
    return deptScores.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return {
        'dept': e.key,
        'score': double.parse(avg.toStringAsFixed(2)), // round to 2 decimal places
      };
    }).toList();
  }

  // get the top 10 instructors by overall score for the active term.
  // sorted descending so the best comes first. deans like to see who on top.
  Future<List<InstructorPerformance>> getTopInstructors({String? termId}) async {
    final resolvedTermId = termId ?? await _getActiveTermId();
    if (resolvedTermId == null) return []; // no term, nobody on top today

    // ── Find the previous term so we can compute a real trend ───────────────
    // Same approach as faculty_roster_screen.dart — order terms by created_at,
    // find the one immediately before the active term.
    final allTerms = await _supabase
        .from('academic_terms')
        .select('id, created_at')
        .order('created_at', ascending: true);

    final termIds = (allTerms as List).map((t) => t['id'] as String).toList();
    final currentTermIndex = termIds.indexOf(resolvedTermId);
    final previousTermId = currentTermIndex > 0 ? termIds[currentTermIndex - 1] : null;

    // big join to get instructor name, dept, and subject count all in one query
    final data = await _supabase
        .from('overall_total_survey')
        .select('''
          instructor_id,
          overall_mean,
          combined_score_mean,
          user_info!instructor_id(\n            first_name, \n            last_name,
            department_table!user_id(
              department_name!Department_name_ID(d_name)
            ),
            instructor_subjects!instructor_id(id, term_id)
          )
        ''')
        .eq('term_id', resolvedTermId)
        .order('overall_mean', ascending: false) // highest score first
        .limit(10); // top 10 only, dili need all of them

    // ── Batch-fetch previous term scores for trend comparison ────────────────
    // One extra query for all top-10 IDs at once — avoids N+1 per instructor.
    final Map<String, double> prevScores = {};
    if (previousTermId != null) {
      final instructorIds = (data as List)
          .map((row) => row['instructor_id'] as String)
          .toList();

      if (instructorIds.isNotEmpty) {
        final prevData = await _supabase
            .from('overall_total_survey')
            .select('instructor_id, overall_mean, combined_score_mean')
            .eq('term_id', previousTermId)
            .filter('instructor_id', 'in', instructorIds);

        for (final row in prevData as List) {
          final id = row['instructor_id'] as String?;
          final score = (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0;
          if (id != null) prevScores[id] = score;
        }
      }
    }

    return (data as List).map((row) {
      final userInfo = row['user_info'];
      if (userInfo == null) return null; // no user info, skip this row

      // handle supabase returning dept as List or Map
      final List deptTables = userInfo['department_table'] is List 
          ? userInfo['department_table'] 
          : [userInfo['department_table']];
      
      // Defensive: department_table should hold one row per user. More than one
      // is a data fault, so name it rather than silently picking the first.
      String deptName = 'Unknown'; // default if we cant find the dept name
      if (deptTables.length > 1) {
        deptName = 'Multiple Departments';
      } else if (deptTables.isNotEmpty && deptTables[0] != null) {
        final deptNameData = deptTables[0]['department_name'];
        if (deptNameData != null) {
          deptName = deptNameData['d_name'] ?? 'Unknown';
        }
      }
      final allSubjects = userInfo['instructor_subjects'] as List? ?? [];
      final subjects = allSubjects.where((s) => s['term_id'] == resolvedTermId).toList(); // only count for selected term

      // ── Real trend: compare current score vs previous term ─────────────────
      // Threshold of 0.1 — anything smaller is noise, not a real change.
      final currentScore = (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0;
      final prevScore = prevScores[row['instructor_id'] as String] ?? 0.0;
      final String trend;
      if (prevScore == 0.0) {
        trend = 'flat'; // no previous term data to compare — dont guess
      } else if (currentScore - prevScore > 0.1) {
        trend = 'up'; // improved by more than 0.1 — genuine increase
      } else if (prevScore - currentScore > 0.1) {
        trend = 'down'; // dropped by more than 0.1 — dean should notice
      } else {
        trend = 'flat'; // within noise threshold — status quo
      }

      return InstructorPerformance(
        id: row['instructor_id'],
        name: '${userInfo['first_name']} ${userInfo['last_name']}', // combine first and last name
        department: deptName,
        overallScore: currentScore,
        subjectCount: subjects.length, // number of subjects they have assigned
        trend: trend, // real term-over-term trend, not hardcoded
      );
    }).whereType<InstructorPerformance>().toList(); // filter out the nulls we skipped
  }

  // get historical score data for a single instructor across all past terms.
  // used for trend charts -- shows if instructor improving or declining over time
  Future<List<Map<String, dynamic>>> getInstructorHistory(String instructorId) async {
    final data = await _supabase
        .from('overall_total_survey')
        .select('overall_mean, combined_score_mean, academic_terms(semester, academic_year)') // join to get term label
        .eq('instructor_id', instructorId);

    final rows = List<Map<String, dynamic>>.from(data as List);

    // Sort semantically: oldest year first, then 1st → 2nd → Summer within year
    const semOrder = {'1st': 0, '2nd': 1, 'Summer': 2};
    rows.sort((a, b) {
      final aTerm = a['academic_terms'] as Map?;
      final bTerm = b['academic_terms'] as Map?;
      final aYear = int.tryParse(aTerm?['academic_year']?.toString().split('-').first ?? '0') ?? 0;
      final bYear = int.tryParse(bTerm?['academic_year']?.toString().split('-').first ?? '0') ?? 0;
      if (aYear != bYear) return aYear.compareTo(bYear);
      final aSem = aTerm?['semester']?.toString() ?? '';
      final bSem = bTerm?['semester']?.toString() ?? '';
      final aSemKey = semOrder.keys.firstWhere((k) => aSem.startsWith(k), orElse: () => '');
      final bSemKey = semOrder.keys.firstWhere((k) => bSem.startsWith(k), orElse: () => '');
      return (semOrder[aSemKey] ?? 99).compareTo(semOrder[bSemKey] ?? 99);
    });

    return rows.map((row) {
      final term = row['academic_terms'] as Map?;
      // Build compact label: "1st\n25-26"
      String label = 'Term';
      if (term != null) {
        final sem = term['semester']?.toString() ?? '';
        final ay = term['academic_year']?.toString() ?? '';
        final ayParts = ay.split('-');
        final yearShort = ayParts.length == 2
            ? '${ayParts[0].length >= 2 ? ayParts[0].substring(ayParts[0].length - 2) : ayParts[0]}-'
              '${ayParts[1].length >= 2 ? ayParts[1].substring(ayParts[1].length - 2) : ayParts[1]}'
            : ay;
        final ordinal = sem.split(' ').isNotEmpty ? sem.split(' ').first : sem; // "1st"
        label = '$ordinal\n$yearShort'; // "1st\n25-26"
      }
      return {
        'sem': label,
        'score': (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();
  }

  // get the subjects taught by an instructor in the current active term with their scores.
  // used in instructor detail views -- shows per-subject performance breakdown
  Future<List<Map<String, dynamic>>> getInstructorSubjects(String instructorId) async {
    final termId = await _getActiveTermId();
    if (termId == null) return []; // no active term, nothing to show

    final data = await _supabase
        .from('management_results')
        .select('overall_management_mean, subjects!subject_id(subject_code, subject_name)')
        .eq('instructor_id', instructorId)
        .eq('term_id', termId); // only get subjects for the active term

    return (data as List).map((row) {
      final subjectRaw = row['subjects'];
      Map<String, dynamic>? subject;
      // supabase sometimes return as List, sometimes as Map -- handle both, wala choice
      if (subjectRaw is List && subjectRaw.isNotEmpty) {
        subject = subjectRaw[0]; // take first element if it's a list
      } else if (subjectRaw is Map<String, dynamic>) {
        subject = subjectRaw; // already a map, use directly
      }
      
      if (subject == null) return null; // no subject data, skip

      return {
        'name': '${subject['subject_code']} - ${subject['subject_name']}', // formatted subject label
        'score': (row['overall_management_mean'] as num?)?.toDouble() ?? 0.0,
      };
    }).whereType<Map<String, dynamic>>().toList(); // remove nulls
  }

  // get subject-level analytics for the dean's department.
  // groups management_results by subject, computes scores per instructor per subject,
  // and produces SubjectAnalytic objects for each subject. this method is the big one, pray lang it run fast.
  Future<List<SubjectAnalytic>> getSubjectAnalyticsForDept(String userId) async {
    try {
      debugPrint('SubjectAnalytics - Start for user: $userId');
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle(); // find the dean's dept

      if (deptData == null) {
        debugPrint('SubjectAnalytics - No department found for user.');
        return []; // dean has no dept, return empty
      }
      final deptId = deptData['Department_name_ID'];
      final termId = await _getActiveTermId();
      if (termId == null) return []; // no active term, nothing to analyze

      final summary = await getDepartmentSummary(userId); // get dept avg for comparison
      final deptAvg = summary.averageScore; // will be used later to compute AI note

      // Which subjects this department owns.
      //
      // Attribution here is by SUBJECT, deliberately different from the
      // department average above. A department's subject analytics are about
      // its own classes, so a visiting instructor teaching one of them still
      // appears -- otherwise a dean gets no feedback at all on subjects their
      // own department runs.
      //
      // The department *average* stays per-instructor and primary-only,
      // because there is exactly one authoritative score per instructor per
      // term (overall_total_survey -- the same figure the instructor sees on
      // their own dashboard) and recomputing it per department would produce a
      // second, conflicting number for the same person.
      final subjectRows = await _supabase
          .from('subjects')
          .select('id')
          .eq('department_id', deptId);

      final subjectIds = (subjectRows as List)
          .where((row) => row['id'] != null)
          .map((row) => row['id'].toString())
          .toSet()
          .toList();

      if (subjectIds.isEmpty) {
        debugPrint('SubjectAnalytics - No subjects registered for Dept $deptId.');
        return []; // department owns no subjects, nothing to analyze
      }

      // fetch management results for all faculty -- includes subject and instructor info
      final mgmtResults = await _supabase
          .from('management_results')
          .select('''
            overall_management_mean,
            total_responses,
            instructor_id,
            subject_id,
            instructor:user_info!instructor_id(first_name, last_name),
            subject:subjects!subject_id(subject_code, subject_name)
          ''')
          .eq('term_id', termId)
          .filter('subject_id', 'in', subjectIds)
          .neq('instructor_id', userId); // dept head's own classes excluded

      final perfResults = await _supabase
          .from('performance_results')
          .select('overall_performance_mean, instructor_id, subject_id')
          .eq('term_id', termId)
          .filter('subject_id', 'in', subjectIds)
          .neq('instructor_id', userId); // dept head's own classes excluded

      // fetch remarks to calculate sentiment based on tones
      final remarkResults = await _supabase
          .from('student_remarks')
          .select('subject_id, tone')
          .eq('term_id', termId)
          .filter('subject_id', 'in', subjectIds)
          .neq('instructor_id', userId); // dept head's own classes excluded

      if ((mgmtResults as List).isEmpty) return []; // no data at all

      final Map<String, Map<String, int>> remarksBySubject = {};
      for (var r in (remarkResults as List)) {
        final subId = r['subject_id'] as String?;
        final tone = r['tone'] as String?;
        if (subId != null && tone != null) {
          remarksBySubject.putIfAbsent(subId, () => {'Positive': 0, 'Neutral': 0, 'Critical': 0});
          if (remarksBySubject[subId]!.containsKey(tone)) {
            remarksBySubject[subId]![tone] = remarksBySubject[subId]![tone]! + 1;
          }
        }
      }

      // Create a map for quick performance lookup: "instructorId_subjectId" -> mean
      // key combines instructor and subject so we can find it fast by two IDs
      final Map<String, double> perfMap = {};
      for (var p in (perfResults as List)) {
        perfMap['${p['instructor_id']}_${p['subject_id']}'] = 
            (p['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
      }

      final Map<String, List<Map<String, dynamic>>> groupedBySubject = {}; // group rows by subject code
      final Map<String, String> subjectNames = {}; // subject code -> subject name

      // loop through management results and group them by subject code
      for (var row in (mgmtResults as List)) {
        final subjectDataRaw = row['subject'];
        Map<String, dynamic>? subjectData;
        // handle both List and Map response from supabase join, same old story
        if (subjectDataRaw is List && subjectDataRaw.isNotEmpty) {
          subjectData = subjectDataRaw[0];
        } else if (subjectDataRaw is Map<String, dynamic>) {
          subjectData = subjectDataRaw;
        }

        if (subjectData == null) continue; // no subject info, skip this row
        
        final code = subjectData['subject_code'];
        final name = subjectData['subject_name'];
        subjectNames[code] = name; // store name for later use
        
        groupedBySubject.putIfAbsent(code, () => []).add(row); // group by subject code
      }

      List<SubjectAnalytic> analytics = []; // final output list

      // now process each subject group
      for (var entry in groupedBySubject.entries) {
        final code = entry.key;
        final rows = entry.value;
        final name = subjectNames[code]!;

        // per-instructor data containers for this subject
        final Map<String, List<double>> instructorScores = {};
        final Map<String, String> instructorNames = {};
        final Map<String, Set<String>> instructorSections = {};
        final Map<String, int> instructorResponses = {};
        final Set<String> processedSubIds = {};
        int posTone = 0;
        int neuTone = 0;
        int critTone = 0;

        for (var row in rows) {
          final instId = row['instructor_id'] as String;
          final subId = row['subject_id'] as String;
          
          if (!processedSubIds.contains(subId) && remarksBySubject.containsKey(subId)) {
            posTone += remarksBySubject[subId]!['Positive']!;
            neuTone += remarksBySubject[subId]!['Neutral']!;
            critTone += remarksBySubject[subId]!['Critical']!;
            processedSubIds.add(subId);
          }

          double mgmt = (row['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
          double perf = perfMap['${instId}_$subId'] ?? 0.0; // look up perf from our map

          // combine mgmt and perf into one score; if no perf data just use mgmt alone
          double combinedScore = double.parse(((mgmt + perf) / 2).toStringAsFixed(2));
          if (perf == 0.0) combinedScore = mgmt; // fallback: no perf data so use mgmt only

          // handle instructor name from join -- same List/Map handling, again
          final userInfoRaw = row['instructor'];
          Map<String, dynamic>? userInfo;
          if (userInfoRaw is List && userInfoRaw.isNotEmpty) {
            userInfo = userInfoRaw[0];
          } else if (userInfoRaw is Map<String, dynamic>) {
            userInfo = userInfoRaw;
          }

          final iName = userInfo != null ? '${userInfo['first_name']} ${userInfo['last_name']}' : 'Unknown';
          
          // Accumulate student survey responses
          final responses = (row['total_responses'] as int?) ?? 0;

          instructorNames[instId] = iName; // store name for this instructor
          instructorScores.putIfAbsent(instId, () => []).add(combinedScore);
          instructorSections.putIfAbsent(instId, () => <String>{});
          instructorResponses[instId] = (instructorResponses[instId] ?? 0) + responses;
        }

        // build the per-instructor breakdown objects for this subject
        final List<SubjectInstructorPerformance> breakdowns = instructorScores.entries.map((e) {
          final avg = e.value.reduce((a, b) => a + b) / e.value.length; // average scores for this instructor
          final distinctSections = instructorSections[e.key]?.length ?? 0;
          final sectionCount = distinctSections > 0 ? distinctSections : e.value.length; // fallback to row count if sections unknown
          return SubjectInstructorPerformance(
            instructorId: e.key,
            instructorName: instructorNames[e.key]!,
            avgScore: double.parse(avg.toStringAsFixed(2)),
            sections: sectionCount,
            totalResponses: instructorResponses[e.key] ?? 0,
          );
        }).toList();

        // compute average score for the whole subject across all instructors
        final totalScore = breakdowns.map((b) => b.avgScore).reduce((a, b) => a + b);
        final avgScore = totalScore / breakdowns.length;

        // Calculate dominant sentiment from remarks
        String dominantSentiment = 'Neutral';
        if (posTone == 0 && neuTone == 0 && critTone == 0) {
           dominantSentiment = avgScore < 3.0 ? 'Critical' : (avgScore < 4.0 ? 'Neutral' : 'Positive'); // fallback to score
        } else {
           if (posTone > neuTone && posTone > critTone) {
             dominantSentiment = 'Positive';
           } else if (critTone > posTone && critTone > neuTone) {
             dominantSentiment = 'Critical';
           } else {
             // if tied or neutral is highest, consider it neutral
             dominantSentiment = 'Neutral';
           }
        }

        analytics.add(SubjectAnalytic(
          code: code,
          name: name,
          avgScore: double.parse(avgScore.toStringAsFixed(2)),
          deptAvg: double.parse(deptAvg.toStringAsFixed(2)),
          difficulty: avgScore < 3.5 ? 'High' : (avgScore < 4.5 ? 'Moderate' : 'Low'), // lower score = harder to do well
          sentiment: dominantSentiment, // sentiment based on student remarks tone
          // Trend: compare subject avg to dept avg — no extra query needed.
          // >0.1 above dept avg = up (subject doing well), >0.1 below = down (needs attention).
          trend: avgScore - deptAvg > 0.1
              ? 'up'
              : deptAvg - avgScore > 0.1
                  ? 'down'
                  : 'stable',
          sections: rows.length,
          instructorBreakdown: breakdowns,
          aiNote: (deptAvg - avgScore) > 0.5 ? "AI Note: Significant performance gap vs. department average." : null, // flag if subject is notably below dept avg
        ));
      }

      return analytics;
    } catch (e) {
      debugPrint('Error fetching subject analytics: $e');
      return []; // something went wrong, return empty list, bahala na
    }
  }

  // get all instructors in the dean's dept whose overall score is below the threshold.
  // threshold default is 3.0 -- below that is considered low performance.
  // returns a list of ActionAlert objects, one per underperforming instructor
  Future<List<ActionAlert>> getDepartmentAlerts(String userId, {double threshold = 3.0}) async {
    try {
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle();

      if (deptData == null) return []; // no dept found, no alerts possible
      final deptId = deptData['Department_name_ID'];
      final termId = await _getActiveTermId();
      if (termId == null) return []; // no active term, no alerts

      final facultyRows = await _supabase
          .from('department_table')
          .select('user_id')
          .eq('Department_name_ID', deptId);
      
      // Exclude the dept head themselves -- only flag instructors
      // dean flagging themselves would be awkward, dili pwede
      final facultyIds = (facultyRows as List)
          .where((row) => row['user_id'] != null && row['user_id'] != userId)
          .map((row) => row['user_id'] as String)
          .toSet()
          .toList();

      if (facultyIds.isEmpty) {
        debugPrint('Subject Analytics - No faculty found in department $deptId');
        return []; // no faculty, no alerts
      }

      // fetch only records where overall_mean is below the threshold -- these are the problem ones
      final stats = await _supabase
          .from('overall_total_survey')
          .select('''
            overall_mean,
            combined_score_mean,
            instructor_id,
            user_info!instructor_id(first_name, last_name)
          ''')
          .eq('term_id', termId)
          .filter('instructor_id', 'in', facultyIds)
          ; // Filtering moved to Dart below

      final List<ActionAlert> alerts = [];
        for (var row in (stats as List)) {
          final userInfo = row['user_info'];
          final name = userInfo != null ? '${userInfo['first_name']} ${userInfo['last_name']}' : 'Unknown';
          final score = (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0;
          
          // Strict filter: only flag if strictly below threshold (3.0) and > 0
          if (score > 0 && score < threshold) {
            alerts.add(ActionAlert(
              type: 'Performance',
              title: 'Low Performance Alert',
              desc: "Instructor scored ${score.toStringAsFixed(2)}, which is below the strict 3.0 benchmark.",
              instructorId: row['instructor_id'],
              instructorName: name,
              dateFlagged: DateTime.now(),
            ));
          }
        }

        // --- ADD NEGATIVE SENTIMENT FLAGS (> 50% Critical) ---
      // 1. Get instructor names safely without relying on Foreign Keys
      final usersData = await _supabase
          .from('user_info')
          .select('id, first_name, last_name')
          .filter('id', 'in', facultyIds);
          
      final Map<String, String> instructorNames = {};
      for (var u in (usersData as List)) {
         instructorNames[u['id']] = '${u['first_name']} ${u['last_name']}';
      }

      // 2. Fetch ALL remarks for the department's faculty in the current term
      final sentimentData = await _supabase
          .from('student_remarks')
          .select('instructor_id, tone') // Removed user_info join to prevent PGRST200 foreign key crash
          .eq('term_id', termId)
          .filter('instructor_id', 'in', facultyIds);
      
      // Group them by instructor id
      final Map<String, int> totalReviewCounts = {};
      final Map<String, int> badReviewCounts = {};
      
      for (var row in (sentimentData as List)) {
        final iId = row['instructor_id'] as String;
        final tone = row['tone'] as String?;
        
        totalReviewCounts[iId] = (totalReviewCounts[iId] ?? 0) + 1;
        
        if (tone == 'Critical') {
          badReviewCounts[iId] = (badReviewCounts[iId] ?? 0) + 1;
        }
      }

      // Generate alert only if Critical > 50% (and there's at least 2 remarks total)
      for (final entry in totalReviewCounts.entries) {
        final instructorId = entry.key;
        final total = entry.value;
        final badCount = badReviewCounts[instructorId] ?? 0;
        final name = instructorNames[instructorId] ?? 'Unknown';

        if (total >= 2 && (badCount / total) > 0.50) {
          alerts.add(ActionAlert(
            type: 'Sentiment',
            title: 'Highly Negative Feedback Detected',
            desc: "$badCount out of $total remarks (>50%) are highly negative.",
            instructorId: instructorId,
            instructorName: name,
            dateFlagged: DateTime.now(),
          ));
        }
      }

      // --- ADD 3-STRIKE TERMINATION FLAGS ---
      // Fetch entire history for these faculty members, ordered by newest first
      final historyData = await _supabase
          .from('overall_total_survey')
          .select('''
            instructor_id,
            overall_mean,
            combined_score_mean,
            created_at,
            user_info!instructor_id(first_name, last_name)
          ''')
          .filter('instructor_id', 'in', facultyIds)
          .order('created_at', ascending: false); // newest first!
      
      // Group historical scores by instructor
      final Map<String, List<double>> instructorHistory = {};
      final Map<String, String> instructorNamesForHistory = {};
      
      for (var row in (historyData as List)) {
        final iId = row['instructor_id'] as String;
        final score = (row['combined_score_mean'] as num?)?.toDouble() ?? (row['overall_mean'] as num?)?.toDouble() ?? 0.0;
        
        instructorHistory.putIfAbsent(iId, () => []).add(score);
        
        if (!instructorNamesForHistory.containsKey(iId)) {
          final userInfo = row['user_info'];
          instructorNamesForHistory[iId] = userInfo != null ? '${userInfo['first_name']} ${userInfo['last_name']}' : 'Unknown';
        }
      }
      
      // Evaluate the 3-strike rule
      for (final entry in instructorHistory.entries) {
        final iId = entry.key;
        final scores = entry.value;
        
        // Ensure they have at least 3 active semesters
        if (scores.length >= 3) {
          // Check the 3 most recent semesters (which are the first 3 in the list since we ordered descending)
          final last3 = scores.sublist(0, 3);
          
          // If ALL 3 are below the threshold (usually 3.0), strike 3!
          if (last3.every((score) => score < threshold)) {
             alerts.add(ActionAlert(
               type: 'Termination',
               title: '3-Strike Alert: Termination Review',
               desc: 'Instructor has scored below ${threshold.toStringAsFixed(1)} for 3 consecutive active semesters. Immediate intervention or deactivation required.',
               instructorId: iId,
               instructorName: instructorNamesForHistory[iId] ?? 'Unknown',
               dateFlagged: DateTime.now(),
             ));
          }
        }
      }

              // Filter out duplicate Performance alerts if they already have a Termination alert
        final Set<String> terminationIds = alerts.where((a) => a.type == 'Termination').map((a) => a.instructorId!).toSet();
        alerts.removeWhere((a) => a.type == 'Performance' && terminationIds.contains(a.instructorId));

        // Drop alerts the head has already acted on THIS term.
        //
        // The dashboard rendered this list raw while the Interventions screen
        // filtered the same list against the log, so the two disagreed on the
        // same data: "1 Alerts" and a 3-Strike card on the dashboard, next to
        // "All caught up / 0 Pending Action Required" on Interventions. The
        // rule belongs here, once, so every caller sees the same set.
        //
        // Scoped to the active term deliberately. A report closes the loop for
        // the semester it was filed in; if the scores are still below the line
        // next term that is a new signal and the head should see it again --
        // which is the entire point of a 3-strike rule. status is not checked:
        // Pending or Resolved, an action was taken for the term.
        try {
          final handled = await _supabase
              .from('intervention_reports')
              .select('instructor_id')
              .eq('term_id', termId)
              .filter('instructor_id', 'in', facultyIds);
          final handledIds = (handled as List)
              .map((r) => r['instructor_id']?.toString())
              .whereType<String>()
              .toSet();
          if (handledIds.isNotEmpty) {
            alerts.removeWhere((a) => handledIds.contains(a.instructorId));
          }
        } catch (e) {
          // Non-fatal: a stale alert is better than a missing one, so a failed
          // read leaves the list exactly as it was.
          debugPrint('Could not read intervention reports for alert filtering: $e');
        }

        return alerts;
    } catch (e) {
      debugPrint('Error fetching alerts: $e');
      return []; // error occurred, return empty list
    }
  }

  // fetch all intervention reports created by this dean, sorted newest first.
  // shows the dean's action history -- who they flagged and what they did about it
  Future<List<InterventionReport>> getInterventionLog(String userId) async {
    try {
      final data = await _supabase
          .from('intervention_reports')
          .select('*, user_info!instructor_id(first_name, last_name)') // join to get instructor name
          .eq('dean_id', userId) // only get this dean's reports
          .order('created_at', ascending: false); // newest first

      return (data as List).map((row) {
        // Prefer stored name; fall back to joined user_info
        // stored name is more reliable in case user info changes later
        String instructorName = row['instructor_name'] ?? '';
        if (instructorName.isEmpty) {
          final ui = row['user_info'];
          if (ui is Map) {
            instructorName = '${ui['first_name'] ?? ''} ${ui['last_name'] ?? ''}'.trim(); // combine from join
          }
        }
        return InterventionReport(
          id: row['id'].toString(),
          instructorId: row['instructor_id'],
          instructorName: instructorName.isEmpty ? 'Unknown Instructor' : instructorName, // fallback if both sources empty
          deanId: row['dean_id'],
          actionType: row['action_type'],
          notes: row['notes'] ?? '', // empty string if notes column is null
          status: row['status'] ?? 'Active Tracking', // default status if missing
          termId: row['term_id'] ?? '',
          createdAt: DateTime.parse(row['created_at']), // parse the datetime string
        );
      }).toList();
    } catch (e) {
      debugPrint('Error fetching intervention log: $e');
      return []; // something went wrong, return empty, dili ta crash the screen
    }
  }

  // create a new intervention report for an underperforming instructor.
  // saves to db then tries to send an email notification to the instructor.
  // email failure is non-critical -- the report still save even if email fail, wala choice
  Future<void> createIntervention({
    required String instructorId,
    required String deanId,
    required String actionType,
    required String notes,
  }) async {
    final termId = await _getActiveTermId();
    if (termId == null) return; // no active term, cannot create report, ayaw proceed

    // fetch instructor name so we can store it in the report denormalized
    final instructorData = await _supabase
        .from('user_info')
        .select('first_name, last_name')
        .eq('id', instructorId)
        .single(); // must exist, crash if not found
    
    final instructorName = '${instructorData['first_name']} ${instructorData['last_name']}'; // combine names

    // insert the intervention report into the database
    await _supabase.from('intervention_reports').insert({
      'instructor_id': instructorId,
      'instructor_name': instructorName,  // store name denormalized so it persist even if user renamed
      'dean_id': deanId,
      'action_type': actionType,
      'notes': notes,
      'status': 'Pending', // starts as Pending, dean can resolve later
      'term_id': termId,
    });

    // Trigger email notification to the instructor via the Edge Function.
    // Non-critical: wrapped in try/catch so a failed email does not block the report.
    // basin email server down, dili ta let it ruin the whole thing
    try {
      await _supabase.functions.invoke(
        'send-intervention-email',
        body: {
          'record': {
            'instructor_id': instructorId,
            'dean_id': deanId,
            'action_type': actionType,
            'notes': notes,
            'status': 'Pending',
          },
        },
      );
      debugPrint('[createIntervention] Email notification sent to instructor.');
    } catch (e) {
      debugPrint('[createIntervention] Email notification failed (non-critical): $e'); // log it but dont crash
    }
  }

  // mark an intervention report as resolved. simple update, no email needed.
  // called when the dean decide the problem is fixed, good job everyone
  Future<void> resolveIntervention(String id) async {
    await _supabase
        .from('intervention_reports')
        .update({'status': 'Resolved'}) // flip status to Resolved
        .eq('id', id); // only update the one with this specific id
  }

  /// Fetches aggregated word cloud data for the dept head's department
  /// using the dept_word_cloud view created in Supabase.
  /// returns top 60 words sorted by frequency -- most common first.
  /// used to show what students say most often in their text feedback
  Future<List<Map<String, dynamic>>> getDeptWordCloud(String userId) async {
    try {
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle(); // find the dept for this dean
      if (deptData == null) return []; // no dept, no word cloud
      final deptId = deptData['Department_name_ID'];

      final termId = await _getActiveTermId();
      if (termId == null) return []; // no active term, no words to show

      // query the word cloud view -- already aggregated in supabase, we just fetch
      final words = await _supabase
          .from('dept_word_cloud')
          .select('word, total_count')
          .eq('department_id', deptId)
          .eq('term_id', termId)
          .order('total_count', ascending: false) // most used words first
          .limit(60); // limit to 60 so the cloud dont get too crowded, enough na

      return (words as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('getDeptWordCloud error: $e');
      return []; // word cloud failed, return empty list
    }
  }

  // return an EvaluationSummary with all fields set to zero.
  // used as a safe fallback when data is missing or something went wrong.
  // better to show zeros than crash the app, bahala na the numbers look sad
  EvaluationSummary _emptySummary() {
    return EvaluationSummary(
      averageScore: 0, managementMean: 0, performanceMean: 0,
      totalEvaluations: 0, completionRate: 0, facultyCount: 0,
    );
  }
}
