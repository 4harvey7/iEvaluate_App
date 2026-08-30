// test/core/term_watcher_test.dart
//
// Covers classifyTermChange, the decision that drives every term-scoped reload
// in the app. Getting it wrong is expensive in both directions: too strict and
// a term switch never reaches the dashboards (the bug this whole mechanism
// exists to fix); too loose and every settings write triggers an app-wide
// "Updating term…" scrim and a reload storm.
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/system_settings_service.dart';
import 'package:ievaluateapp_final/core/services/term_watcher.dart';

SystemSettings settings({
  String? termId = 'term-a',
  String semester = '1st Semester',
  String academicYear = '2025-2026',
  bool autoSync = false,
}) {
  return SystemSettings(
    termId: termId,
    semester: semester,
    academicYear: academicYear,
    autoSync: autoSync,
  );
}

void main() {
  group('classifyTermChange', () {
    test('the first snapshot is not a change', () {
      // The screen that is mounting loads this term itself. Reporting it as a
      // change would make every screen load twice on startup.
      expect(
        classifyTermChange(null, settings()),
        TermTransition.firstSnapshot,
      );
    });

    test('the same term twice is unchanged', () {
      expect(
        classifyTermChange(settings(), settings()),
        TermTransition.unchanged,
      );
    });

    test('a different term id is a change', () {
      expect(
        classifyTermChange(settings(termId: 'term-a'), settings(termId: 'term-b')),
        TermTransition.changed,
      );
    });

    test('auto_sync flipping on its own is not a change', () {
      // auto_sync lives in the same row as current_term_id, so writing it
      // produces a Realtime event. Nothing is partitioned by it, and treating
      // it as a term change would clear every cache for nothing.
      expect(
        classifyTermChange(
          settings(autoSync: false),
          settings(autoSync: true),
        ),
        TermTransition.unchanged,
      );
    });

    test('renaming the current term counts as a change', () {
      // The SAO screen upserts academic_terms on (semester, academic_year), so
      // a corrected semester keeps the same term id while changing the label
      // every report is filed under. Comparing ids alone would leave every
      // screen showing the old label.
      expect(
        classifyTermChange(
          settings(semester: '1st Semester'),
          settings(semester: '2nd Semester'),
        ),
        TermTransition.changed,
      );
      expect(
        classifyTermChange(
          settings(academicYear: '2025-2026'),
          settings(academicYear: '2026-2027'),
        ),
        TermTransition.changed,
      );
    });

    test('arriving at a null term is a change, and leaving one is not', () {
      // A project with no term configured yet reports termId null. Going from a
      // real term to null means the pointer was cleared and nothing on screen
      // is valid any more, so it must reload.
      expect(
        classifyTermChange(settings(termId: 'term-a'), settings(termId: null)),
        TermTransition.changed,
      );
      // The reverse -- null to a real term -- is also a change, because screens
      // that rendered an empty state now have data to show.
      expect(
        classifyTermChange(settings(termId: null), settings(termId: 'term-a')),
        TermTransition.changed,
      );
    });

    test('two consecutive nulls do not loop', () {
      // Before the fix that seeded _current, a project with no configured term
      // could notify on every stream event forever. Guarding this explicitly
      // because the symptom (a permanent scrim) is severe.
      expect(
        classifyTermChange(settings(termId: null), settings(termId: null)),
        TermTransition.unchanged,
      );
    });
  });
}
