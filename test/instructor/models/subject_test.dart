import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/models/subject.dart';

void main() {
  group('Subject', () {
    test('toJson then fromJson is a round trip', () {
      final original = Subject(
        code: 'CS101',
        name: 'Intro to Programming',
        addedAt: DateTime.utc(2026, 5, 10, 12, 30),
      );

      final json = original.toJson();
      final restored = Subject.fromJson(json);

      expect(restored.code, original.code);
      expect(restored.name, original.name);
      expect(restored.addedAt, original.addedAt);
    });

    test('toJson uses ISO8601 for the addedAt timestamp', () {
      final s = Subject(
        code: 'IT305',
        name: 'Web Development',
        addedAt: DateTime.utc(2026, 5, 10, 12, 30),
      );

      expect(s.toJson()['addedAt'], '2026-05-10T12:30:00.000Z');
    });
  });
}
