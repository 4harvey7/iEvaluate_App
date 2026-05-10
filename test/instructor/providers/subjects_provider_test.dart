import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/models/subject.dart';
import 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SubjectsProvider', () {
    test('starts empty when SharedPreferences has no entry', () async {
      final provider = SubjectsProvider();
      await provider.load();
      expect(provider.subjects, isEmpty);
    });

    test('hydrates persisted subjects on load', () async {
      final stored = jsonEncode([
        {
          'code': 'CS101',
          'name': 'Intro to Programming',
          'addedAt': '2026-05-01T00:00:00.000Z',
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'instructor_subjects_v1': stored,
      });

      final provider = SubjectsProvider();
      await provider.load();

      expect(provider.subjects.length, 1);
      expect(provider.subjects.first.code, 'CS101');
    });

    test('add appends, persists, and notifies listeners', () async {
      final provider = SubjectsProvider();
      await provider.load();

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.add(
        Subject(
          code: 'IT305',
          name: 'Web Development',
          addedAt: DateTime.utc(2026, 5, 10),
        ),
      );

      expect(provider.subjects.length, 1);
      expect(provider.subjects.first.code, 'IT305');
      expect(notifications, 1);

      // Re-hydrate a fresh provider to confirm persistence.
      final reloaded = SubjectsProvider();
      await reloaded.load();
      expect(reloaded.subjects.length, 1);
      expect(reloaded.subjects.first.code, 'IT305');
    });

    test('exists is case-insensitive', () async {
      final provider = SubjectsProvider();
      await provider.load();
      await provider.add(
        Subject(
          code: 'CS101',
          name: 'Intro',
          addedAt: DateTime.utc(2026, 5, 10),
        ),
      );

      expect(provider.exists('cs101'), isTrue);
      expect(provider.exists('CS101'), isTrue);
      expect(provider.exists('cs999'), isFalse);
    });
  });
}
