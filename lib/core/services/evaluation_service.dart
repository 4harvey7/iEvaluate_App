import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EvaluationSummary {
  final double averageScore;
  final double managementMean;
  final double performanceMean;
  final int totalEvaluations;
  final double completionRate;
  final int facultyCount;

  EvaluationSummary({
    required this.averageScore,
    required this.managementMean,
    required this.performanceMean,
    required this.totalEvaluations,
    required this.completionRate,
    required this.facultyCount,
  });
}

class InstructorPerformance {
  final String id;
  final String name;
  final String department;
  final double overallScore;
  final int subjectCount;
  final String trend;

  InstructorPerformance({
    required this.id,
    required this.name,
    required this.department,
    required this.overallScore,
    required this.subjectCount,
    required this.trend,
  });
}

class SubjectAnalytic {
  final String code;
  final String name;
  final double avgScore;
  final double deptAvg;
  final String difficulty;
  final String sentiment;
  final String trend;
  final int sections;
  final String? aiNote;
  final List<SubjectInstructorPerformance> instructorBreakdown;

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

class SubjectInstructorPerformance {
  final String instructorId;
  final String instructorName;
  final double avgScore;
  final int sections;
  final int totalResponses;

  SubjectInstructorPerformance({
    required this.instructorId,
    required this.instructorName,
    required this.avgScore,
    required this.sections,
    this.totalResponses = 0,
  });
}

class ActionAlert {
  final String type;
  final String title;
  final String desc;
  final String? instructorId;
  final String? instructorName;
  final String? subjectCode;
  final DateTime dateFlagged;

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

class InterventionReport {
  final String id;
  final String instructorId;
  final String instructorName;
  final String deanId;
  final String actionType;
  final String notes;
  final String status;
  final String termId;
  final DateTime createdAt;

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

class EvaluationService {
  final _supabase = Supabase.instance.client;

  Future<String?> _getActiveTermId() async {
    try {
      final settings = await _supabase
          .from('system_settings')
          .select('current_term_id')
          .maybeSingle();
      
      final termId = settings?['current_term_id'];
      debugPrint('EvaluationService - Active Term ID: $termId');
      return termId;
    } catch (e) {
      debugPrint('EvaluationService - Error fetching active term: $e');
      return null;
    }
  }

  Future<EvaluationSummary> getDepartmentSummary(String userId) async {
    try {
      debugPrint('EvaluationService - Fetching summary for Dean: $userId');
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle();

      if (deptData == null) {
        debugPrint('EvaluationService - No department found for Dean: $userId');
        return _emptySummary();
      }
      final deptId = deptData['Department_name_ID'];
      debugPrint('EvaluationService - Dean belongs to Dept ID: $deptId');

      final termId = await _getActiveTermId();
      if (termId == null) {
        debugPrint('EvaluationService - No active term ID found.');
        return _emptySummary();
      }

      final facultyRows = await _supabase
          .from('department_table')
          .select('user_id')
          .eq('Department_name_ID', deptId);
      
      final facultyIds = (facultyRows as List)
          .where((row) => row['user_id'] != null)
          .map((row) => row['user_id'] as String)
          .toSet()
          .toList();

      debugPrint('EvaluationService - Found ${facultyIds.length} unique faculty IDs for Dept $deptId');

      if (facultyIds.isEmpty) return _emptySummary();

      final stats = await _supabase
          .from('overall_total_survey')
          .select('''
            overall_mean, 
            management_mean, 
            performance_mean, 
            total_responses,
            instructor_id
          ''')
          .eq('term_id', termId)
          .filter('instructor_id', 'in', facultyIds);
      
      debugPrint('EvaluationService - Found ${stats?.length ?? 0} overall_total_survey records for faculty: $facultyIds');

      if (stats == null || (stats as List).isEmpty) {
        debugPrint('EvaluationService - No records in overall_total_survey for faculty in term $termId. Dashboard will show 0.0.');
        return _emptySummary();
      }

      final list = stats as List;
      double totalOverall = 0;
      double totalMgmt = 0;
      double totalPerf = 0;
      int totalResponses = 0;

      for (var row in list) {
        double mgmt = (row['management_mean'] as num?)?.toDouble() ?? 0.0;
        double perf = (row['performance_mean'] as num?)?.toDouble() ?? 0.0;
        double overall = (row['overall_mean'] as num?)?.toDouble() ?? 0.0;

        // Fallback logic if the generated column is 0.0 but component means exist
        if (overall == 0.0 && (mgmt > 0 || perf > 0)) {
          overall = double.parse(((mgmt + perf) / 2).toStringAsFixed(2));
        }

        totalOverall += overall;
        totalMgmt += mgmt;
        totalPerf += perf;
        totalResponses += (row['total_responses'] as int?) ?? 0;
      }

      final count = list.length;
      // Calculate rough completion rate: avg responses per faculty / expected max (25 responses = 100%)
      final avgResponses = count > 0 ? totalResponses / count : 0;
      final calculatedRate = (avgResponses / 25.0).clamp(0.0, 1.0);
      return EvaluationSummary(
        averageScore: double.parse((totalOverall / count).toStringAsFixed(2)),
        managementMean: double.parse((totalMgmt / count).toStringAsFixed(2)),
        performanceMean: double.parse((totalPerf / count).toStringAsFixed(2)),
        totalEvaluations: totalResponses,
        completionRate: double.parse(calculatedRate.toStringAsFixed(2)),
        facultyCount: facultyIds.length,
      );
    } catch (e) {
      debugPrint('Error fetching department summary: $e');
      return _emptySummary();
    }
  }

  Future<Map<String, dynamic>> getGlobalStats({String? termId}) async {
    final resolvedTermId = termId ?? await _getActiveTermId();
    if (resolvedTermId == null) return {};

    final data = await _supabase
        .from('overall_total_survey')
        .select('overall_mean, total_responses')
        .eq('term_id', resolvedTermId);
    
    if (data == null || (data as List).isEmpty) return {};

    final list = data as List;
    double sum = 0;
    int totalResp = 0;
    for (var row in list) {
      sum += (row['overall_mean'] as num?)?.toDouble() ?? 0.0;
      totalResp += (row['total_responses'] as int?) ?? 0;
    }

    return {
      'avgScore': sum / list.length,
      'totalInstructors': list.length,
      'totalResponses': totalResp,
    };
  }

  Future<List<Map<String, dynamic>>> getDepartmentAverages({String? termId}) async {
    final resolvedTermId = termId ?? await _getActiveTermId();
    if (resolvedTermId == null) return [];

    final data = await _supabase
        .from('overall_total_survey')
        .select('''
          overall_mean,
          user_info!instructor_id(
            department_table!user_id(
              department_name!Department_name_ID(d_name)
            )
          )
        ''')
        .eq('term_id', resolvedTermId);
    
    if (data == null) return [];

    final Map<String, List<double>> deptScores = {};
    for (var row in (data as List)) {
      final userInfo = row['user_info'];
      if (userInfo == null) continue;
      
      final List deptTables = userInfo['department_table'] is List 
          ? userInfo['department_table'] 
          : [userInfo['department_table']];
      
      if (deptTables.isEmpty || deptTables[0] == null) continue;

      final deptTable = deptTables[0];
      final deptNameData = deptTable['department_name'];
      
      String deptName = 'Unknown';
      if (deptNameData != null) {
        deptName = deptNameData['d_name'] ?? 'Unknown';
      }
      
      final score = (row['overall_mean'] as num?)?.toDouble() ?? 0.0;
      deptScores.putIfAbsent(deptName, () => []).add(score);
    }

    return deptScores.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return {
        'dept': e.key,
        'score': double.parse(avg.toStringAsFixed(2)),
      };
    }).toList();
  }

  Future<List<InstructorPerformance>> getTopInstructors({String? termId}) async {
    final resolvedTermId = termId ?? await _getActiveTermId();
    if (resolvedTermId == null) return [];

    final data = await _supabase
        .from('overall_total_survey')
        .select('''
          instructor_id,
          overall_mean,
          user_info!instructor_id(
            first_name, 
            last_name,
            department_table!user_id(
              department_name!Department_name_ID(d_name)
            ),
            subjects!instructor_id(id)
          )
        ''')
        .eq('term_id', resolvedTermId)
        .order('overall_mean', ascending: false)
        .limit(10);

    if (data == null) return [];

    return (data as List).map((row) {
      final userInfo = row['user_info'];
      if (userInfo == null) return null;
      
      final List deptTables = userInfo['department_table'] is List 
          ? userInfo['department_table'] 
          : [userInfo['department_table']];
      
      String deptName = 'Unknown';
      if (deptTables.isNotEmpty && deptTables[0] != null) {
        final deptNameData = deptTables[0]['department_name'];
        if (deptNameData != null) {
          deptName = deptNameData['d_name'] ?? 'Unknown';
        }
      }
      
      final subjects = userInfo['subjects'] as List? ?? [];

      return InstructorPerformance(
        id: row['instructor_id'],
        name: '${userInfo['first_name']} ${userInfo['last_name']}',
        department: deptName,
        overallScore: (row['overall_mean'] as num?)?.toDouble() ?? 0.0,
        subjectCount: subjects.length,
        trend: 'up',
      );
    }).whereType<InstructorPerformance>().toList();
  }

  Future<List<Map<String, dynamic>>> getInstructorHistory(String instructorId) async {
    final data = await _supabase
        .from('overall_total_survey')
        .select('overall_mean, academic_terms(semester, academic_year)')
        .eq('instructor_id', instructorId)
        .order('created_at', ascending: true);

    if (data == null) return [];

    return (data as List).map((row) {
      final term = row['academic_terms'];
      return {
        'sem': '${term['semester']} ${term['academic_year']}',
        'score': (row['overall_mean'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getInstructorSubjects(String instructorId) async {
    final termId = await _getActiveTermId();
    if (termId == null) return [];

    final data = await _supabase
        .from('management_results')
        .select('overall_management_mean, subjects!subject_id(subject_code, subject_name)')
        .eq('instructor_id', instructorId)
        .eq('term_id', termId);

    if (data == null) return [];

    return (data as List).map((row) {
      final subjectRaw = row['subjects'];
      Map<String, dynamic>? subject;
      if (subjectRaw is List && subjectRaw.isNotEmpty) {
        subject = subjectRaw[0];
      } else if (subjectRaw is Map<String, dynamic>) {
        subject = subjectRaw;
      }
      
      if (subject == null) return null;

      return {
        'name': '${subject['subject_code']} - ${subject['subject_name']}',
        'score': (row['overall_management_mean'] as num?)?.toDouble() ?? 0.0,
      };
    }).whereType<Map<String, dynamic>>().toList();
  }

  Future<List<SubjectAnalytic>> getSubjectAnalyticsForDept(String userId) async {
    try {
      debugPrint('SubjectAnalytics - Start for user: $userId');
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle();

      if (deptData == null) {
        debugPrint('SubjectAnalytics - No department found for user.');
        return [];
      }
      final deptId = deptData['Department_name_ID'];
      final termId = await _getActiveTermId();
      if (termId == null) return [];

      final summary = await getDepartmentSummary(userId);
      final deptAvg = summary.averageScore;

      final facultyRows = await _supabase
          .from('department_table')
          .select('user_id')
          .eq('Department_name_ID', deptId);
      
      final facultyIds = (facultyRows as List)
          .where((row) => row['user_id'] != null)
          .map((row) => row['user_id'] as String)
          .toSet()
          .toList();

      if (facultyIds.isEmpty) {
        debugPrint('SubjectAnalytics - No faculty found.');
        return [];
      }

      final mgmtResults = await _supabase
          .from('management_results')
          .select('''
            overall_management_mean,
            total_responses,
            instructor_id,
            subject_id,
            instructor:user_info!instructor_id(first_name, last_name),
            subject:subjects!subject_id(subject_code, subject_name, section)
          ''')
          .eq('term_id', termId)
          .filter('instructor_id', 'in', facultyIds);

      final perfResults = await _supabase
          .from('performance_results')
          .select('overall_performance_mean, instructor_id, subject_id')
          .eq('term_id', termId)
          .filter('instructor_id', 'in', facultyIds);

      if (mgmtResults == null || (mgmtResults as List).isEmpty) return [];

      // Create a map for quick performance lookup: "instructorId_subjectId" -> mean
      final Map<String, double> perfMap = {};
      for (var p in (perfResults as List)) {
        perfMap['${p['instructor_id']}_${p['subject_id']}'] = 
            (p['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
      }

      final Map<String, List<Map<String, dynamic>>> groupedBySubject = {};
      final Map<String, String> subjectNames = {};

      for (var row in (mgmtResults as List)) {
        final subjectDataRaw = row['subject'];
        Map<String, dynamic>? subjectData;
        if (subjectDataRaw is List && subjectDataRaw.isNotEmpty) {
          subjectData = subjectDataRaw[0];
        } else if (subjectDataRaw is Map<String, dynamic>) {
          subjectData = subjectDataRaw;
        }

        if (subjectData == null) continue;
        
        final code = subjectData['subject_code'];
        final name = subjectData['subject_name'];
        subjectNames[code] = name;
        
        groupedBySubject.putIfAbsent(code, () => []).add(row);
      }

      List<SubjectAnalytic> analytics = [];

      for (var entry in groupedBySubject.entries) {
        final code = entry.key;
        final rows = entry.value;
        final name = subjectNames[code]!;

        final Map<String, List<double>> instructorScores = {};
        final Map<String, String> instructorNames = {};
        final Map<String, Set<String>> instructorSections = {};
        final Map<String, int> instructorResponses = {};

        for (var row in rows) {
          final instId = row['instructor_id'] as String;
          final subId = row['subject_id'] as String;
          
          double mgmt = (row['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
          double perf = perfMap['${instId}_${subId}'] ?? 0.0;

          double combinedScore = double.parse(((mgmt + perf) / 2).toStringAsFixed(2));
          if (perf == 0.0) combinedScore = mgmt;
          
          final userInfoRaw = row['instructor'];
          Map<String, dynamic>? userInfo;
          if (userInfoRaw is List && userInfoRaw.isNotEmpty) {
            userInfo = userInfoRaw[0];
          } else if (userInfoRaw is Map<String, dynamic>) {
            userInfo = userInfoRaw;
          }

          final iName = userInfo != null ? '${userInfo['first_name']} ${userInfo['last_name']}' : 'Unknown';
          
          // Collect distinct section labels per instructor
          final subjectRaw = row['subject'];
          final subjectMap = subjectRaw is Map<String, dynamic>
              ? subjectRaw
              : (subjectRaw is List && subjectRaw.isNotEmpty ? subjectRaw[0] as Map<String, dynamic> : null);
          final sectionLabel = (subjectMap?['section'] as String?)?.trim() ?? '';
          // Accumulate student survey responses
          final responses = (row['total_responses'] as int?) ?? 0;

          instructorNames[instId] = iName;
          instructorScores.putIfAbsent(instId, () => []).add(combinedScore);
          instructorSections.putIfAbsent(instId, () => <String>{});
          if (sectionLabel.isNotEmpty) instructorSections[instId]!.add(sectionLabel);
          instructorResponses[instId] = (instructorResponses[instId] ?? 0) + responses;
        }

        final List<SubjectInstructorPerformance> breakdowns = instructorScores.entries.map((e) {
          final avg = e.value.reduce((a, b) => a + b) / e.value.length;
          final distinctSections = instructorSections[e.key]?.length ?? 0;
          final sectionCount = distinctSections > 0 ? distinctSections : e.value.length;
          return SubjectInstructorPerformance(
            instructorId: e.key,
            instructorName: instructorNames[e.key]!,
            avgScore: double.parse(avg.toStringAsFixed(2)),
            sections: sectionCount,
            totalResponses: instructorResponses[e.key] ?? 0,
          );
        }).toList();

        final totalScore = breakdowns.map((b) => b.avgScore).reduce((a, b) => a + b);
        final avgScore = totalScore / breakdowns.length;

        analytics.add(SubjectAnalytic(
          code: code,
          name: name,
          avgScore: double.parse(avgScore.toStringAsFixed(2)),
          deptAvg: double.parse(deptAvg.toStringAsFixed(2)),
          difficulty: avgScore < 3.5 ? 'High' : (avgScore < 4.5 ? 'Moderate' : 'Low'),
          sentiment: avgScore < 3.0 ? 'Critical' : (avgScore < 4.0 ? 'Neutral' : 'Positive'),
          trend: 'stable',
          sections: rows.length,
          instructorBreakdown: breakdowns,
          aiNote: (deptAvg - avgScore) > 0.5 ? "AI Note: Significant performance gap vs. department average." : null,
        ));
      }

      return analytics;
    } catch (e) {
      debugPrint('Error fetching subject analytics: $e');
      return [];
    }
  }

  Future<List<ActionAlert>> getDepartmentAlerts(String userId, {double threshold = 3.0}) async {
    try {
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle();

      if (deptData == null) return [];
      final deptId = deptData['Department_name_ID'];
      final termId = await _getActiveTermId();
      if (termId == null) return [];

      final facultyRows = await _supabase
          .from('department_table')
          .select('user_id')
          .eq('Department_name_ID', deptId);
      
      final facultyIds = (facultyRows as List)
          .where((row) => row['user_id'] != null)
          .map((row) => row['user_id'] as String)
          .toSet()
          .toList();

      if (facultyIds.isEmpty) {
        debugPrint('Subject Analytics - No faculty found in department $deptId');
        return [];
      }

      final stats = await _supabase
          .from('overall_total_survey')
          .select('''
            overall_mean,
            instructor_id,
            user_info!instructor_id(first_name, last_name)
          ''')
          .eq('term_id', termId)
          .filter('instructor_id', 'in', facultyIds)
          .lt('overall_mean', threshold);
      
      if (stats == null) return [];

      final List<ActionAlert> alerts = [];
      for (var row in (stats as List)) {
        final userInfo = row['user_info'];
        final name = userInfo != null ? '${userInfo['first_name']} ${userInfo['last_name']}' : 'Unknown';
        
        alerts.add(ActionAlert(
          type: 'Performance',
          title: 'Low Performance Alert',
          desc: "Score (${(row['overall_mean'] as num?)?.toStringAsFixed(2) ?? '?'}) is below the department average of ${threshold.toStringAsFixed(2)}.",
          instructorId: row['instructor_id'],
          instructorName: name,
          dateFlagged: DateTime.now(),
        ));
      }

      return alerts;
    } catch (e) {
      debugPrint('Error fetching alerts: $e');
      return [];
    }
  }

  Future<List<InterventionReport>> getInterventionLog(String userId) async {
    try {
      final data = await _supabase
          .from('intervention_reports')
          .select('*, user_info!instructor_id(first_name, last_name)')
          .eq('dean_id', userId)
          .order('created_at', ascending: false);
      
      if (data == null) return [];

      return (data as List).map((row) {
        // Prefer stored name; fall back to joined user_info
        String instructorName = row['instructor_name'] ?? '';
        if (instructorName.isEmpty) {
          final ui = row['user_info'];
          if (ui is Map) {
            instructorName = '${ui['first_name'] ?? ''} ${ui['last_name'] ?? ''}'.trim();
          }
        }
        return InterventionReport(
          id: row['id'].toString(),
          instructorId: row['instructor_id'],
          instructorName: instructorName.isEmpty ? 'Unknown Instructor' : instructorName,
          deanId: row['dean_id'],
          actionType: row['action_type'],
          notes: row['notes'] ?? '',
          status: row['status'] ?? 'Active Tracking',
          termId: row['term_id'] ?? '',
          createdAt: DateTime.parse(row['created_at']),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error fetching intervention log: $e');
      return [];
    }
  }

  Future<void> createIntervention({
    required String instructorId,
    required String deanId,
    required String actionType,
    required String notes,
  }) async {
    final termId = await _getActiveTermId();
    if (termId == null) return;

    final instructorData = await _supabase
        .from('user_info')
        .select('first_name, last_name')
        .eq('id', instructorId)
        .single();
    
    final instructorName = '${instructorData['first_name']} ${instructorData['last_name']}';

    await _supabase.from('intervention_reports').insert({
      'instructor_id': instructorId,
      'instructor_name': instructorName,
      'dean_id': deanId,
      'action_type': actionType,
      'notes': notes,
      'status': 'Pending',
      'term_id': termId,
    });
  }

  Future<void> resolveIntervention(String id) async {
    await _supabase
        .from('intervention_reports')
        .update({'status': 'Resolved'})
        .eq('id', id);
  }

  /// Fetches aggregated word cloud data for the dept head's department
  /// using the dept_word_cloud view created in Supabase.
  Future<List<Map<String, dynamic>>> getDeptWordCloud(String userId) async {
    try {
      final deptData = await _supabase
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', userId)
          .maybeSingle();
      if (deptData == null) return [];
      final deptId = deptData['Department_name_ID'];

      final termId = await _getActiveTermId();
      if (termId == null) return [];

      final words = await _supabase
          .from('dept_word_cloud')
          .select('word, total_count')
          .eq('department_id', deptId)
          .eq('term_id', termId)
          .order('total_count', ascending: false)
          .limit(60);

      return (words as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('getDeptWordCloud error: $e');
      return [];
    }
  }

  EvaluationSummary _emptySummary() {
    return EvaluationSummary(
      averageScore: 0, managementMean: 0, performanceMean: 0,
      totalEvaluations: 0, completionRate: 0, facultyCount: 0,
    );
  }
}
