import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/services/correction_pickers.dart';

const juan = 'bbbbbbbb-2222-4222-8222-111111111111';
const pedro = 'bbbbbbbb-2222-4222-8222-000000000002';
const maria = 'bbbbbbbb-2222-4222-8222-000000000003';
const mario = 'bbbbbbbb-2222-4222-8222-000000000005';
const it101 = 'cccccccc-3333-4333-8333-333333333333';
const it102 = 'cccccccc-3333-4333-8333-000000000002';
const it103 = 'cccccccc-3333-4333-8333-000000000005';
const ge104 = 'cccccccc-3333-4333-8333-000000000003';

const instructors = [
  PickerInstructor(id: juan, name: 'Juan Dela Cruz'),
  PickerInstructor(id: pedro, name: 'Pedro Reyes'),
  PickerInstructor(id: maria, name: 'Maria Santos'),
  PickerInstructor(id: mario, name: 'Mario Santos'),
];
const subjects = [
  PickerSubject(id: it101, code: 'IT 101', name: 'Introduction to Computing'),
  PickerSubject(id: it102, code: 'IT 102', name: 'Computer Programming 1'),
  PickerSubject(id: it103, code: 'IT 103', name: 'Computer Programming 2'),
  PickerSubject(id: ge104, code: 'GE 104', name: 'Mathematics in the Modern World'),
];

void main() {
  group('NameMatch (same rules as n8n name_match.js)', () {
    test('a clear instructor match despite titles and an OCR slip', () {
      final m = NameMatch.bestInstructor('Mr. Pedro Reyess', instructors);
      expect(m.isFound, isTrue);
      expect(m.pick!.id, pedro);
    });

    test('two close names are ambiguous, never guessed', () {
      final m = NameMatch.bestInstructor('Mari Santos', instructors);
      expect(m.match, 'ambiguous');
      expect(m.pick, isNull);
      expect(m.contenders.map((p) => p.id), containsAll([maria, mario]));
      final twins = [...instructors, const PickerInstructor(id: 'x', name: 'Juan Dela Cruz')];
      expect(NameMatch.bestInstructor('Juan Dela Cruz', twins).match, 'ambiguous');
    });

    test('nobody fits: none', () {
      expect(NameMatch.bestInstructor('Xyz Qwerty', instructors).match, 'none');
      expect(NameMatch.bestInstructor('', instructors).match, 'none');
    });

    test('subject by code (any spacing), by the old "CODE — Name" text, by title', () {
      expect(NameMatch.bestSubject('it-102', subjects).pick!.id, it102);
      expect(NameMatch.bestSubject('IT 101 — Introduction to Computing', subjects).pick!.id, it101);
      expect(NameMatch.bestSubject('Mathematics in the Modern World', subjects).pick!.id, ge104);
    });

    test('subject: equal titles are ambiguous; an unknown code never picks by title', () {
      final amb = NameMatch.bestSubject('Computer Programming', subjects);
      expect(amb.match, 'ambiguous');
      expect(amb.contenders.map((s) => s.id), containsAll([it102, it103]));
      expect(NameMatch.bestSubject('IT 109 Computer Programming 1', subjects).match, 'none');
    });
  });

  group('ScanIdentity pre-selection', () {
    test('website row: the suggested ids win', () {
      final id = ScanIdentity.fromPartial({
        'instructor': 'Juan Dela Cruz',
        'ocr_instructor': 'P. Reyes',
        'suggested_instructor_id': pedro.toUpperCase(),
        'suggested_instructor_name': 'Pedro Reyes',
        'suggested_subject_id': it102,
        'suggested_subject_code': 'IT 102',
        'subject': 'IT 101',
        'ocr_subject': 'IT1O2',
      });
      expect(id.pickInstructor(instructors)!.id, pedro);
      expect(id.pickSubject(subjects)!.id, it102);
      expect(id.instructorRead, 'P. Reyes');
      expect(id.subjectRead, 'IT1O2');
    });

    test('phone row: the read text, only when it is a clear match', () {
      final id = ScanIdentity.fromPartial({
        'instructor': 'Prof Pedro Reyes',
        'subject': 'IT 102',
        'instructor_match': {'match': 'found', 'score': 0.9, 'raw': 'Prof Pedro Reyes'},
      });
      expect(id.pickInstructor(instructors)!.id, pedro);
      expect(id.pickSubject(subjects)!.id, it102);
      expect(id.instructorRead, 'Prof Pedro Reyes');

      final unclear = ScanIdentity.fromPartial({'instructor': 'Mari Santos', 'subject': 'Computer Programming'});
      expect(unclear.pickInstructor(instructors), isNull);
      expect(unclear.pickSubject(subjects), isNull);
    });

    test('a suggested id that is not on the list falls back to the text', () {
      final id = ScanIdentity.fromPartial({
        'suggested_instructor_id': 'dddddddd-0000-4000-8000-000000000000',
        'instructor': 'Juan Dela Cruz',
        'subject': [null],
      });
      expect(id.pickInstructor(instructors)!.id, juan);
      expect(id.pickSubject(subjects), isNull);
    });
  });

  group('PickerSearch', () {
    test('filters by every typed word, code or title', () {
      expect(PickerSearch.instructors('santos', instructors).map((p) => p.id), [maria, mario]);
      expect(PickerSearch.instructors('', instructors).length, instructors.length);
      expect(PickerSearch.subjects('it102', subjects).first.id, it102);
      expect(PickerSearch.subjects('modern world', subjects).single.id, ge104);
    });

    test('a misread name still offers the closest people', () {
      expect(PickerSearch.instructors('Pedro Reyess', instructors).first.id, pedro);
    });
  });

  group('CorrectionNotFoundAnswer (n8n HTTP 422)', () {
    test('parses code, message and candidates', () {
      final a = CorrectionNotFoundAnswer.tryParse(422, {
        'success': false,
        'code': 'instructor_not_found',
        'message': 'Not saved: Several instructors fit "Mari Santos". Pick the instructor from the list and submit again.',
        'candidates': {
          'instructors': [
            {'id': maria, 'name': 'Maria Santos'},
            {'id': mario, 'name': 'Mario Santos'},
          ],
        },
      })!;
      expect(a.instructorMissing, isTrue);
      expect(a.subjectMissing, isFalse);
      expect(a.instructorCandidates.map((p) => p.id), [maria, mario]);
      expect(a.subjectCandidates, isEmpty);
      expect(a.message, contains('Mari Santos'));
    });

    test('both missing, list-wrapped body; other answers are not parsed', () {
      final a = CorrectionNotFoundAnswer.tryParse(422, [
        {'code': 'instructor_and_subject_not_found', 'candidates': {'subjects': [{'id': it102, 'code': 'IT 102', 'name': 'Computer Programming 1'}]}}
      ])!;
      expect(a.instructorMissing && a.subjectMissing, isTrue);
      expect(a.subjectCandidates.single.display, 'IT 102 — Computer Programming 1');
      expect(a.message, isNotEmpty);
      expect(CorrectionNotFoundAnswer.tryParse(409, {'code': 'duplicate_stamp'}), isNull);
      expect(CorrectionNotFoundAnswer.tryParse(200, {'success': true}), isNull);
      expect(CorrectionNotFoundAnswer.tryParse(500, 'oops'), isNull);
    });
  });

  group('CorrectionPickerData lists', () {
    test('only creditable instructors (approved + instructor role) and placeholders', () {
      final list = CorrectionPickerData.instructorsFrom([
        {'user_id': pedro, 'roles': {'Roles': 'FULL-TIME'}, 'user_info': {'id': pedro, 'first_name': 'Pedro', 'last_name': 'Reyes', 'account_status': 'approved'}},
        {'user_id': juan, 'roles': {'Roles': 'PART-TIME'}, 'user_info': {'id': juan, 'first_name': 'Juan', 'last_name': 'Dela Cruz', 'account_status': 'disabled'}},
        {'user_id': maria, 'roles': {'Roles': 'STUDENT'}, 'user_info': {'id': maria, 'first_name': 'Maria', 'last_name': 'Santos', 'account_status': 'approved'}},
      ], [
        {'id': mario, 'first_name': 'Mario', 'last_name': 'Santos'},
      ]);
      expect(list.map((p) => p.id), [mario, pedro]);
      expect(list.first.isPlaceholder, isTrue);
    });

    test('subjects sorted by code, blanks dropped', () {
      final list = CorrectionPickerData.subjectsFrom([
        {'id': it102, 'subject_code': 'IT 102', 'subject_name': 'Computer Programming 1'},
        {'id': it101, 'subject_code': 'IT 101', 'subject_name': 'Introduction to Computing'},
        {'id': 'z', 'subject_code': '', 'subject_name': ''},
      ]);
      expect(list.map((s) => s.id), [it101, it102]);
    });
  });
}
