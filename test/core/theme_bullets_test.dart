import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/utils/theme_list_parser.dart';

void main() {
  group('themeBullets', () {
    test('one sentence per line becomes one bullet each', () {
      expect(
        themeBullets('Explains clearly.\nGrades fairly.\n\n- Is approachable'),
        ['Explains clearly.', 'Grades fairly.', 'Is approachable'],
      );
    });

    test('old run-on paragraph stays ONE item, never split on commas', () {
      const old = 'Clear and patient explanation of difficult topics, strong '
          'preparedness and organization, fair and consistent grading, '
          'high approachability and supportiveness toward students, '
          'teaching quality';
      expect(themeBullets(old), ['$old.']);
      expect(themeBullets('Clear, patient, and fair. Very good.'),
          ['Clear, patient, and fair. Very good.']);
    });

    test('arrays and array literals give one bullet per element', () {
      expect(themeBullets(['teaching clarity', 'Examples.']),
          ['Teaching clarity.', 'Examples.']);
      expect(themeBullets('{"Teaching clarity",Examples}'),
          ['Teaching clarity.', 'Examples.']);
    });

    test('empty values give no bullets', () {
      expect(themeBullets(null), isEmpty);
      expect(themeBullets('  '), isEmpty);
      expect(themeBullets('NULL'), isEmpty);
    });

    test('lines are deduplicated', () {
      expect(themeBullets('A good.\na good.\nB.'), ['A good.', 'B.']);
    });
  });
}
