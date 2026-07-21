import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SystemSettings {
  final String? termId;
  final String semester;
  final String academicYear;
  final bool autoSync;

  SystemSettings({
    this.termId,
    required this.semester,
    required this.academicYear,
    required this.autoSync,
  });

  factory SystemSettings.defaultSettings() {
    return SystemSettings(
      termId: null,
      semester: '1st Semester',
      academicYear: '2025-2026',
      autoSync: true,
    );
  }
}

class SystemSettingsService {
  final _supabase = Supabase.instance.client;

  Future<SystemSettings> getSettings() async {
    try {
      final data = await _supabase
          .from('system_settings')
          .select('''
            current_term_id,
            auto_sync,
            academic_terms!current_term_id (
              semester,
              academic_year
            )
          ''')
          .eq('id', 1)
          .maybeSingle();

      if (data != null) {
        final termData = data['academic_terms'];
        return SystemSettings(
          termId: data['current_term_id'],
          semester: termData?['semester'] ?? '1st Semester',
          academicYear: termData?['academic_year'] ?? '2025-2026',
          autoSync: data['auto_sync'] ?? true,
        );
      }
    } catch (e) {
      debugPrint('Error fetching system settings: $e');
    }
    return SystemSettings.defaultSettings();
  }

  Stream<SystemSettings> streamSettings() {
    // We stream the base table and fetch term details to ensure Realtime works perfectly
    return _supabase
        .from('system_settings')
        .stream(primaryKey: ['id'])
        .limit(1)
        .asyncMap((data) async {
          if (data.isEmpty) return SystemSettings.defaultSettings();
          
          final settings = data.first;
          final termId = settings['current_term_id'];
          
          if (termId == null) return SystemSettings.defaultSettings();

          // Fetch the term details for the ID
          final termData = await _supabase
              .from('academic_terms')
              .select('semester, academic_year')
              .eq('id', termId)
              .maybeSingle();

          return SystemSettings(
            termId: termId,
            semester: termData?['semester'] ?? '1st Semester',
            academicYear: termData?['academic_year'] ?? '2025-2026',
            autoSync: settings['auto_sync'] ?? true,
          );
        });
  }
}
