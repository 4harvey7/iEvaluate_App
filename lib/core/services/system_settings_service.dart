// system_settings_service.dart
// handles fetching and streaming the system-wide settings like active term, semester, etc.
// importente kaayo -- if active term is wrong, all evaluation data show for wrong period.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// data class that holds the current system settings.
// one row in the system_settings table becomes one of these, murag its snapshot in time
class SystemSettings {
  final String? termId;       // the active academic term ID, null if not set yet
  final String semester;      // semester label like "1st Semester" or "2nd Semester"
  final String academicYear;  // academic year like "2025-2026"
  final bool autoSync;        // whether auto sync is enabled, importente for realtime

  SystemSettings({
    this.termId,              // optional, can be null if no active term configured
    required this.semester,
    required this.academicYear,
    required this.autoSync,
  });

  // factory constructor that returns a safe default when database has nothing.
  // better to show a sensible default than crash with null pointer, wala choice
  factory SystemSettings.defaultSettings() {
    return SystemSettings(
      termId: null,                    // no active term, bahala na who set it
      semester: '1st Semester',        // default to first semester
      academicYear: '2025-2026',       // default academic year, update this every year
      autoSync: true,                  // auto sync on by default, dili ta turn it off
    );
  }
}

// service class for fetching and streaming system settings from supabase.
// the app use this to know which academic term is currently active.
class SystemSettingsService {
  final _supabase = Supabase.instance.client; // our supabase connection

  // fetch the current system settings one time.
  // does a joined query to also get the term label (semester and year) from academic_terms.
  // returns defaultSettings() if anything go wrong or data is missing, pray lang it work
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
          ''') // join academic_terms using the foreign key so we get semester and year too
          .eq('id', 1)       // always row with id=1, single settings row, wala need filter more
          .maybeSingle();    // maybeSingle so it dont crash if row missing

      if (data != null) {
        final termData = data['academic_terms']; // the joined term info, might be null
        return SystemSettings(
          termId: data['current_term_id'],
          semester: termData?['semester'] ?? '1st Semester',         // fallback if join is null
          academicYear: termData?['academic_year'] ?? '2025-2026',   // fallback too, just in case
          autoSync: data['auto_sync'] ?? true,                       // default true if column null
        );
      }
    } catch (e) {
      debugPrint('Error fetching system settings: $e'); // log the error, dili ta silently fail
    }
    return SystemSettings.defaultSettings(); // something went wrong, return safe defaults
  }

  // stream the system settings so the app update in real-time when admin change the active term.
  // uses supabase Realtime under the hood to push updates when the row changes.
  // We stream the base table and fetch term details to ensure Realtime works perfectly
  // because joining directly in stream() is tricky with supabase, so we do it manually
  Stream<SystemSettings> streamSettings() {
    return _supabase
        .from('system_settings')
        .stream(primaryKey: ['id']) // listen to changes on this table
        .limit(1)                   // only care about the one settings row
        .asyncMap((data) async {
          if (data.isEmpty) return SystemSettings.defaultSettings(); // no data, use defaults
          
          final settings = data.first; // grab the single settings row
          final termId = settings['current_term_id']; // get the current active term ID
          
          if (termId == null) return SystemSettings.defaultSettings(); // no active term set, return defaults

          // Fetch the term details for the ID
          // we do this separately because stream() cant join async in supabase
          // wala choice, separate fetch is the way to go here
          final termData = await _supabase
              .from('academic_terms')
              .select('semester, academic_year')
              .eq('id', termId)
              .maybeSingle(); // maybeSingle in case the termId points to deleted term

          return SystemSettings(
            termId: termId,
            semester: termData?['semester'] ?? '1st Semester',         // fallback if term row missing
            academicYear: termData?['academic_year'] ?? '2025-2026',   // fallback for safety
            autoSync: settings['auto_sync'] ?? true,                   // use value from settings row
          );
        });
  }
}
