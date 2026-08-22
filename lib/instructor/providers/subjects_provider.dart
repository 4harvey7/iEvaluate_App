import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subject.dart';

/// Loads subjects for the current instructor+term via the instructor_subjects
/// junction table (2NF schema). Scores come from management_results /
/// performance_results (pre-computed means).
class SubjectsProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final List<Subject> _subjects = [];
  double? _trueTermAverage;

  SubjectsProvider({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  UnmodifiableListView<Subject> get subjects => UnmodifiableListView(_subjects);
  double? get trueTermAverage => _trueTermAverage;

  bool _isFetching = false;

  void clear() {
    _subjects.clear();
    _trueTermAverage = null;
    notifyListeners();
  }

  Future<void> load({String? termId}) async {
    // Only skip if already fetching AND no new termId is being forced in.
    // If a real termId is provided (post-login call), always allow it through.
    if (_isFetching && (termId == null || termId.isEmpty)) return;

    try {
      _isFetching = true;

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _subjects.clear();
        _trueTermAverage = null;
        notifyListeners();
        return;
      }

      // Load cache instantly so the user doesn't wait for a blank screen
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('subjects_cache_$userId');
        if (cached != null && _subjects.isEmpty) {
          final data = jsonDecode(cached) as List;
          _subjects.clear();
          _subjects.addAll(data.map((x) => Subject.fromJson(Map<String, dynamic>.from(x))));
          notifyListeners();
          debugPrint('[SubjectsProvider] ⚡ Loaded cached subjects instantly.');
        }
      } catch (e) {
        debugPrint('[SubjectsProvider] Failed to load cache: $e');
      }

      // 1. Resolve active term
      String? activeTermId = termId;
      if (activeTermId == null || activeTermId.isEmpty) {
        final settings = await _supabase
            .from('system_settings')
            .select('current_term_id')
            .limit(1)
            .maybeSingle();
        activeTermId = settings?['current_term_id'];
      }

      if (activeTermId == null || activeTermId.isEmpty) {
        debugPrint('[SubjectsProvider] No active term found.');
        _subjects.clear();
        _trueTermAverage = null;
        notifyListeners();
        return;
      }

      // 2. Get subjects for this instructor+term via instructor_subjects junction table.
      final assignmentRows = await _supabase
          .from('instructor_subjects')
          .select('subject_id, subjects(id, subject_code, subject_name, created_at, department_id)')
          .eq('instructor_id', userId)
          .eq('term_id', activeTermId);

      debugPrint('[SubjectsProvider] Assignments found: ${(assignmentRows as List).length}');

      if ((assignmentRows as List).isEmpty) {
        _subjects.clear();
        _trueTermAverage = null;
        notifyListeners();
        return;
      }

      // Build id to metadata map (one row per unique subject_id)
      final Map<String, Map<String, dynamic>> subjectById = {};
      for (var row in assignmentRows) {
        final subjectData = row['subjects'];
        if (subjectData == null) continue;
        final meta = Map<String, dynamic>.from(
          subjectData is List ? subjectData[0] : subjectData,
        );
        final id = meta['id']?.toString();
        if (id == null) continue;
        subjectById.putIfAbsent(id, () => meta);
      }

      if (subjectById.isEmpty) {
        _subjects.clear();
        _trueTermAverage = null;
        notifyListeners();
        return;
      }

      final validSubjectIds = subjectById.keys.toList();

      // 3. Fetch pre-computed results for this instructor+term.
      final results = await Future.wait([
        _supabase
            .from('management_results')
            .select('subject_id, overall_management_mean, total_responses, created_at')
            .eq('instructor_id', userId)
            .eq('term_id', activeTermId)
            .filter('subject_id', 'in', validSubjectIds)
            .order('created_at', ascending: false),
        _supabase
            .from('performance_results')
            .select('subject_id, overall_performance_mean, total_responses, created_at')
            .eq('instructor_id', userId)
            .eq('term_id', activeTermId)
            .filter('subject_id', 'in', validSubjectIds)
            .order('created_at', ascending: false),
        _supabase
            .from('overall_total_survey')
            .select('overall_mean, combined_score_mean')
            .eq('instructor_id', userId)
            .eq('term_id', activeTermId)
            .maybeSingle(),
      ]);

      final mgmtRows = (results[0] as List);
      final perfRows = (results[1] as List);
      final overallAnalytics = results[2] as Map<String, dynamic>?;

      if (overallAnalytics != null) {
        _trueTermAverage = (overallAnalytics['combined_score_mean'] as num?)?.toDouble() ?? (overallAnalytics['overall_mean'] as num?)?.toDouble();
      } else {
        _trueTermAverage = null;
      }

      final Map<String, Map<String, dynamic>> mgmtBySubjectId = {};
      for (var row in mgmtRows) {
        final sid = row['subject_id']?.toString();
        if (sid != null && !mgmtBySubjectId.containsKey(sid)) {
          mgmtBySubjectId[sid] = Map<String, dynamic>.from(row);
        }
      }

      final Map<String, Map<String, dynamic>> perfBySubjectId = {};
      for (var row in perfRows) {
        final sid = row['subject_id']?.toString();
        if (sid != null && !perfBySubjectId.containsKey(sid)) {
          perfBySubjectId[sid] = Map<String, dynamic>.from(row);
        }
      }

      // 4. Build Subject objects
      final List<Subject> newSubjects = [];

      for (var entry in subjectById.entries) {
        final id = entry.key;
        final meta = entry.value;
        final code = meta['subject_code']?.toString() ?? id;

        final mgmt = mgmtBySubjectId[id];
        final perf = perfBySubjectId[id];

        double mMean = (mgmt?['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
        double pMean = (perf?['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
        int totalResponses = (mgmt?['total_responses'] as num?)?.toInt() ??
            (perf?['total_responses'] as num?)?.toInt() ?? 0;

        // Fallback to raw data if no pre-computed results
        if (mMean == 0.0 && pMean == 0.0) {
          try {
            final rawRows = await _supabase
                .from('sast_all_raw_data_survey')
                .select('m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10')
                .eq('subject_id', id)
                .eq('instructor_ID', userId)
                .eq('term_id', activeTermId);

            if ((rawRows as List).isNotEmpty) {
              double mSum = 0, pSum = 0;
              for (var row in rawRows) {
                for (int i = 1; i <= 10; i++) {
                  mSum += (row['m${i}'] as num?)?.toDouble() ?? 0.0;
                  pSum += (row['p${i}'] as num?)?.toDouble() ?? 0.0;
                }
              }
              mMean = mSum / (rawRows.length * 10);
              pMean = pSum / (rawRows.length * 10);
              totalResponses = rawRows.length;
            }
          } catch (e) {
            debugPrint('[SubjectsProvider] Raw fallback error for $code: $e');
          }
        }

        debugPrint('[SubjectsProvider] $code mgmt=$mMean perf=$pMean n=$totalResponses');

        try {
          newSubjects.add(Subject.fromJson({
            ...meta,
            'management_mean': mMean,
            'performance_mean': pMean,
            'all_ids': <String>{id},
          }));
        } catch (e) {
          debugPrint('[SubjectsProvider] Error building Subject $code: $e');
        }
      }

      newSubjects.sort((a, b) => a.code.compareTo(b.code));
      _subjects.clear();
      _subjects.addAll(newSubjects);
      notifyListeners();

      // Save to cache for the next time
      try {
        if (userId != null) {
          final prefs = await SharedPreferences.getInstance();
          final encoded = jsonEncode(_subjects.map((s) => s.toJson()).toList());
          await prefs.setString('subjects_cache_$userId', encoded);
        }
      } catch (e) {
        debugPrint('[SubjectsProvider] Failed to save cache: $e');
      }
    } catch (e) {
      debugPrint('[SubjectsProvider] Error: $e');
    } finally {
      _isFetching = false;
    }
  }
}
