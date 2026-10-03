// The one rating helper every screen and the PDF use. These pin the bands,
// the rounding rule, and that "no answers" (null) is never treated as 0.
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/utils/sast_rating.dart';

void main() {
  group('verbal description', () {
    test('band edges are 4.20 / 3.40 / 2.60 / 1.80 / 1.00', () {
      expect(SastRating.verbal(4.20), 'Outstanding');
      expect(SastRating.verbal(4.19), 'Very Satisfactory');
      expect(SastRating.verbal(3.40), 'Very Satisfactory');
      expect(SastRating.verbal(3.39), 'Satisfactory');
      expect(SastRating.verbal(2.60), 'Satisfactory');
      expect(SastRating.verbal(2.59), 'Fair');
      expect(SastRating.verbal(1.80), 'Fair');
      expect(SastRating.verbal(1.79), 'Unsatisfactory');
      expect(SastRating.verbal(1.00), 'Unsatisfactory');
    });

    test('compares on the value rounded to 2 decimals', () {
      // 4.196 shows as "4.20", so it must read Outstanding too.
      expect(SastRating.format(4.196), '4.20');
      expect(SastRating.verbal(4.196), 'Outstanding');
      expect(SastRating.code(4.196), 'O');
    });

    test('null is "No data", not Unsatisfactory', () {
      expect(SastRating.verbal(null), 'No data');
      expect(SastRating.code(null), '-');
      expect(SastRating.format(null), '—');
    });
  });

  group('combine', () {
    test('is ROUND((mgmt + perf) / 2, 2)', () {
      expect(SastRating.combine(4.50, 4.25), 4.38);
    });

    test('one null side means the other side', () {
      expect(SastRating.combine(4.5, null), 4.5);
      expect(SastRating.combine(null, 3.2), 3.2);
      expect(SastRating.combine(null, null), isNull);
    });
  });

  group('averageOfPresent', () {
    test('skips nulls instead of counting them as 0', () {
      expect(SastRating.averageOfPresent([4.0, null, 3.0]), 3.5);
      expect(SastRating.averageOfPresent([null, null]), isNull);
    });
  });

  test('answeredLabel is omitted when a count is unknown', () {
    expect(SastRating.answeredLabel(2, 3), '2 of 3 answered');
    expect(SastRating.answeredLabel(null, 3), isNull);
    expect(SastRating.answeredLabel(2, null), isNull);
  });
}
