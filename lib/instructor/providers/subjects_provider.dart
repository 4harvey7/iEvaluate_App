import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subject.dart';

class SubjectsProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final List<Subject> _subjects = [];

  SubjectsProvider({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

  UnmodifiableListView<Subject> get subjects => UnmodifiableListView(_subjects);

  bool _isFetching = false;

  void clear() {
    _subjects.clear();
    notifyListeners();
  }

  Future<void> load({String? termId}) async {
    // If already fetching a specific term, don't interrupt.
    // If this is a background auto-load (termId is null) and we're already fetching, skip it.
    if (_isFetching && (termId == null || termId.isEmpty)) return;
    
    try {
      _isFetching = true;
      
      final userId = _supabase.auth.currentUser?.id;
      debugPrint('[SubjectsProvider] Loading subjects for User: $userId, Term: $termId');
      if (userId == null) {
        _subjects.clear();
        notifyListeners();
        return;
      }

      // 1. Resolve Term
      String? activeTermId = termId;
      if (activeTermId == null || activeTermId.isEmpty) {
        final settings = await _supabase.from('system_settings')
            .select('current_term_id')
            .limit(1)
            .maybeSingle();
        activeTermId = settings?['current_term_id'];
      }
      
      if (activeTermId == null || activeTermId.isEmpty) {
        debugPrint('SubjectsProvider: No active term ID found.');
        _subjects.clear();
        notifyListeners();
        return;
      }

      // 2. Multi-source Discovery
      final responses = await Future.wait<dynamic>([
        _supabase.from('subjects').select().eq('instructor_id', userId).eq('term_id', activeTermId),
        _supabase.from('management_results').select('subject_id, overall_management_mean, subjects(*)').eq('instructor_id', userId).eq('term_id', activeTermId),
        _supabase.from('performance_results').select('subject_id, overall_performance_mean, subjects(*)').eq('instructor_id', userId).eq('term_id', activeTermId),
        _supabase.from('raw_GoogleSheet_data_result').select('subject_id, subjects(*)').eq('instructor_ID', userId).eq('term_id', activeTermId),
      ]);

      debugPrint('[SubjectsProvider] Term Resolved: $activeTermId');
      debugPrint('[SubjectsProvider] Response counts: '
            'subjects=${(responses[0] as List).length}, '
            'mgmt=${(responses[1] as List).length}, '
            'perf=${(responses[2] as List).length}, '
            'raw=${(responses[3] as List).length}');

      // Group subjects by Code and Section to prevent duplicates
      Map<String, Map<String, dynamic>> uniqueSubjects = {};

      void register(dynamic item) {
        if (item == null) return;
        
        // Prefer metadata from the joined 'subjects' table if available
        final metadata = item['subjects'] != null 
            ? Map<String, dynamic>.from(item['subjects']) 
            : Map<String, dynamic>.from(item);
            
        final code = metadata['subject_code']?.toString();
        if (code == null) return;
        
        final section = metadata['section']?.toString() ?? '';
        final key = '${code}_$section'.toUpperCase();

        if (!uniqueSubjects.containsKey(key)) {
          uniqueSubjects[key] = metadata;
          uniqueSubjects[key]!['all_ids'] = <String>{};
        } else {
          // If this version has more data (like an ID from 'subjects' table), prefer it
          if (item.containsKey('instructor_id') && !uniqueSubjects[key]!.containsKey('instructor_id')) {
             uniqueSubjects[key] = metadata;
          }
        }
        
        // Collect all IDs that map to this subject code (across any term/record found)
        final sid = metadata['id']?.toString() ?? item['subject_id']?.toString();
        if (sid != null) {
          (uniqueSubjects[key]!['all_ids'] as Set<String>).add(sid);
        }
      }

      for (var response in responses) {
        if (response is List) {
          for (var item in response) register(item);
        }
      }

      List<Subject> newSubjects = [];
      for (var entry in uniqueSubjects.values) {
        final allRelatedIds = entry['all_ids'] as Set<String>;

        double mMean = 0.0, pMean = 0.0;
        
        // Aggregate scores from any matching ID
        for (var response in responses) {
          if (response is List) {
            for (var item in response) {
              final itemSid = item['subject_id']?.toString();
              if (allRelatedIds.contains(itemSid)) {
                if (item.containsKey('overall_management_mean')) mMean = (item['overall_management_mean'] as num?)?.toDouble() ?? mMean;
                if (item.containsKey('overall_performance_mean')) pMean = (item['overall_performance_mean'] as num?)?.toDouble() ?? pMean;
              }
            }
          }
        }

        if (mMean == 0.0 || pMean == 0.0) {
          // Try to find raw data for any of the linked IDs
          final rawData = await _supabase.from('raw_GoogleSheet_data_result')
              .select()
              .filter('subject_id', 'in', allRelatedIds.toList())
              .eq('instructor_ID', userId)
              .eq('term_id', activeTermId);

          if (rawData.isNotEmpty) {
            double mSum = 0, pSum = 0;
            for (var row in rawData) {
              for (int i = 1; i <= 10; i++) {
                mSum += (row['m$i'] as num?)?.toDouble() ?? 0.0;
                pSum += (row['p$i'] as num?)?.toDouble() ?? 0.0;
              }
            }
            if (mMean == 0.0) mMean = mSum / (rawData.length * 10);
            if (pMean == 0.0) pMean = pSum / (rawData.length * 10);
          }
        }

        newSubjects.add(Subject.fromJson({
          ...entry,
          'management_mean': mMean,
          'performance_mean': pMean,
        }));
      }

      newSubjects.sort((a, b) => a.code.compareTo(b.code));

      // Atomic Update: Only clear and replace when new data is ready
      _subjects.clear();
      _subjects.addAll(newSubjects);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading subjects in Provider: $e');
    } finally {
      _isFetching = false;
    }
  }
}
