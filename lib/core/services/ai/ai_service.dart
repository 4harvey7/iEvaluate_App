import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InstructorAISuggestion {
  final String suggestion;
  final List<String> positiveThemes;
  final List<String> improvementInsights;
  final DateTime updatedAt;

  InstructorAISuggestion({
    required this.suggestion,
    required this.positiveThemes,
    required this.improvementInsights,
    required this.updatedAt,
  });
}

class AIService {
  final _supabase = Supabase.instance.client;

  Future<InstructorAISuggestion?> getInstructorSuggestions(String instructorId, {String? termId}) async {
    try {
      var query = _supabase
          .from('instructor_ai_suggestions')
          .select()
          .eq('instructor_id', instructorId);
      
      if (termId != null) {
        query = query.eq('term_id', termId);
      }

      final data = await query.order('updated_at', ascending: false).limit(1).maybeSingle();

      if (data == null) return null;

      return InstructorAISuggestion(
        suggestion: data['ai_suggestion'] ?? '',
        positiveThemes: _parseList(data['positive_themes']),
        improvementInsights: _parseList(data['improvement_insights']),
        updatedAt: DateTime.parse(data['updated_at']),
      );
    } catch (e) {
      debugPrint('Error fetching AI suggestions: $e');
      return null;
    }
  }

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.map((e) => e.toString()).toList();
    if (data is String) {
      // Handle potential comma separated string or JSON string
      if (data.startsWith('[') && data.endsWith(']')) {
         // basic json list parsing if needed, but supabase usually handles this if it's jsonb
      }
      return data.split(',').map((e) => e.trim()).toList();
    }
    return [];
  }
}
