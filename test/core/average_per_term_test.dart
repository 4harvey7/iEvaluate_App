// Tests for averagePerTerm -- the rule that decides which results belong to a
// department in which term.
//
// This is the function the per-term snapshot exists for. The property worth
// protecting is that a closed term's number never moves: reassigning an
// instructor today must not change what last year's report said. That is
// testable here without a database, which is why the arithmetic was pulled out
// of getDepartmentHistory.
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/evaluation_service.dart';

/// One overall_total_survey row as PostgREST returns it, joined to its term.
Map<String, dynamic> row({
  required String term,
  required String instructor,
  double? combined,
  double? overall,
  String semester = '1st Semester',
  String year = '2025-2026',
}) {
  return {
    'term_id': term,
    'instructor_id': instructor,
    'combined_score_mean': combined,
    'overall_mean': overall,
    'academic_terms': {'semester': semester, 'academic_year': year},
  };
}

void main() {
  group('term attribution', () {
    test('a result counts only in the term the instructor was a member', () {
      // Ana was in this department for term A, then moved away. Her term-B
      // score belongs to whichever department she moved to, not this one.
      final rows = [
        row(term: 'A', instructor: 'ana', combined: 4.0),
        row(term: 'B', instructor: 'ana', combined: 2.0, semester: '2nd Semester'),
      ];

      final result = averagePerTerm(rows, membership: {'A|ana'});

      expect(result, hasLength(1));
      expect(result.single['score'], 4.0);
    });

    test('reassigning someone does not move a closed term', () {
      // The regression this table was built to prevent. Same result rows, and
      // the only change is that Ben has since been added to a later term --
      // exactly what happens when SAO moves an instructor in. Term A must be
      // byte-identical.
      final rows = [
        row(term: 'A', instructor: 'ana', combined: 4.0),
        row(term: 'A', instructor: 'ben', combined: 3.0),
      ];

      final before = averagePerTerm(rows, membership: {'A|ana', 'A|ben'});
      final after = averagePerTerm(rows, membership: {'A|ana', 'A|ben', 'B|ben'});

      expect(after, before);
      expect(before.single['score'], 3.5);
    });

    test('an instructor absent from the snapshot is left out entirely', () {
      final rows = [
        row(term: 'A', instructor: 'ana', combined: 4.0),
        row(term: 'A', instructor: 'stranger', combined: 1.0),
      ];

      final result = averagePerTerm(rows, membership: {'A|ana'});

      // 4.0 alone, not (4.0 + 1.0) / 2.
      expect(result.single['score'], 4.0);
    });

    test('an empty membership keeps every row', () {
      // No snapshot for this department yet: migration 10 not run, or no term
      // switch since. Degrade to the old behaviour rather than an empty chart.
      final rows = [
        row(term: 'A', instructor: 'ana', combined: 4.0),
        row(term: 'A', instructor: 'ben', combined: 2.0),
      ];

      final result = averagePerTerm(rows, membership: const {});

      expect(result.single['score'], 3.0);
    });

    test('a row with no instructor_id is dropped when a snapshot exists', () {
      final rows = [
        row(term: 'A', instructor: 'ana', combined: 4.0),
        {
          'term_id': 'A',
          'combined_score_mean': 1.0,
          'academic_terms': {'semester': '1st Semester', 'academic_year': '2025-2026'},
        },
      ];

      final result = averagePerTerm(rows, membership: {'A|ana'});

      expect(result.single['score'], 4.0);
    });
  });

  group('score selection', () {
    test('combined_score_mean wins over overall_mean', () {
      final result = averagePerTerm(
        [row(term: 'A', instructor: 'ana', combined: 4.2, overall: 1.1)],
        membership: {'A|ana'},
      );

      expect(result.single['score'], 4.2);
    });

    test('overall_mean is used when combined is null', () {
      final result = averagePerTerm(
        [row(term: 'A', instructor: 'ana', overall: 3.7)],
        membership: {'A|ana'},
      );

      expect(result.single['score'], 3.7);
    });

    test('both null reads as zero rather than throwing', () {
      final result = averagePerTerm(
        [row(term: 'A', instructor: 'ana')],
        membership: {'A|ana'},
      );

      expect(result.single['score'], 0.0);
    });

    test('scores are rounded to two decimals', () {
      final rows = [
        row(term: 'A', instructor: 'ana', combined: 4.0),
        row(term: 'A', instructor: 'ben', combined: 3.0),
        row(term: 'A', instructor: 'cid', combined: 3.0),
      ];

      final result = averagePerTerm(
        rows,
        membership: {'A|ana', 'A|ben', 'A|cid'},
      );

      // 10 / 3 = 3.3333...
      expect(result.single['score'], 3.33);
    });
  });

  group('ordering and labels', () {
    test('terms come back chronologically, 1st before 2nd', () {
      final rows = [
        row(term: 'C', instructor: 'ana', combined: 3.0,
            semester: '2nd Semester', year: '2025-2026'),
        row(term: 'A', instructor: 'ana', combined: 1.0,
            semester: '1st Semester', year: '2024-2025'),
        row(term: 'B', instructor: 'ana', combined: 2.0,
            semester: '1st Semester', year: '2025-2026'),
      ];

      final result = averagePerTerm(
        rows,
        membership: {'A|ana', 'B|ana', 'C|ana'},
      );

      expect(result.map((e) => e['score']).toList(), [1.0, 2.0, 3.0]);
    });

    test('the label is the chart axis form', () {
      final result = averagePerTerm(
        [row(term: 'A', instructor: 'ana', combined: 4.0,
            semester: '2nd Semester', year: '2025-2026')],
        membership: {'A|ana'},
      );

      expect(result.single['sem'], '2nd\n25-26');
    });

    test('rawTerm is not leaked to the caller', () {
      // The chart wants sem, score and year; rawTerm is sorting scaffolding.
      final result = averagePerTerm(
        [row(term: 'A', instructor: 'ana', combined: 4.0)],
        membership: {'A|ana'},
      );

      expect(result.single.keys, unorderedEquals(['sem', 'score', 'year']));
    });

    test('both semesters of one school year carry the same year key', () {
      final result = averagePerTerm(
        [
          row(term: 'A', instructor: 'ana', combined: 4.0,
              semester: '1st Semester', year: '2024-2025'),
          row(term: 'B', instructor: 'ana', combined: 3.0,
              semester: '2nd Semester', year: '2024-2025'),
          row(term: 'C', instructor: 'ana', combined: 3.5,
              semester: '1st Semester', year: '2025-2026'),
        ],
        membership: {'A|ana', 'B|ana', 'C|ana'},
      );

      expect(result.map((e) => e['year']).toList(),
          ['2024-2025', '2024-2025', '2025-2026']);
    });

    test('a malformed academic_year does not crash the label', () {
      final result = averagePerTerm(
        [
          {
            'term_id': 'A',
            'instructor_id': 'ana',
            'combined_score_mean': 4.0,
            'academic_terms': {'semester': 'Su', 'academic_year': '2025'},
          }
        ],
        membership: {'A|ana'},
      );

      expect(result.single['sem'], 'Su\n2025');
    });

    test('a missing term join still produces a row', () {
      final result = averagePerTerm(
        [
          {
            'term_id': 'A',
            'instructor_id': 'ana',
            'combined_score_mean': 4.0,
            'academic_terms': null,
          }
        ],
        membership: {'A|ana'},
      );

      expect(result.single['sem'], 'Sem');
      expect(result.single['score'], 4.0);
    });
  });

  group('empty input', () {
    test('no rows means no history', () {
      expect(averagePerTerm(const [], membership: {'A|ana'}), isEmpty);
    });

    test('rows that all fail membership mean no history', () {
      final result = averagePerTerm(
        [row(term: 'A', instructor: 'ana', combined: 4.0)],
        membership: {'B|ben'},
      );

      expect(result, isEmpty);
    });
  });
}
