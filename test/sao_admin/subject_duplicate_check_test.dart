// Coverage for the subject duplicate rule, written against BUG-2026-TC-A07.
//
// The defect was not a wrong comparison -- the comparison was right -- it was a
// guard that asked which BUTTON opened the form ("is this a fresh add?") and
// skipped the check entirely for the edit and add-instructor forms, both of
// which could still retype the subject code. So the cases that matter most here
// are the ones carrying a non-null sheetSubjectId: those are the two forms that
// used to save a collision in silence and report success.
//
// Variant letters map to the "Affected Paths" table in the bug report.
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/sao_admin/subject_duplicate_check.dart';

void main() {
  // Two unrelated subjects, the shape of the data the screen loads.
  const pelec2 = <String, dynamic>{
    'id': 'sub-pelec2',
    'subject_code': 'PElec2',
    'subject_name': 'Human Computer Interaction',
    'department_id': 1,
  };
  const it101 = <String, dynamic>{
    'id': 'sub-it101',
    'subject_code': 'IT101',
    'subject_name': 'Computer Programming 1',
    'department_id': 1,
  };
  const all = [pelec2, it101];

  SubjectDuplicateVerdict check({
    required String code,
    required String name,
    String? sheetSubjectId,
    String? originalName,
    List<Map<String, dynamic>> subjects = all,
  }) =>
      checkSubjectDuplicates(
        subjects: subjects,
        code: code,
        name: name,
        sheetSubjectId: sheetSubjectId,
        originalName: originalName,
      );

  group('normalisation', () {
    test('code matches the DB index: upper(btrim(...))', () {
      // Must agree with subjects_one_per_code in migration 20240130000018,
      // or the app and the database disagree about what is taken.
      expect(normSubjectCode('  ias 301 '), 'IAS 301');
      expect(normSubjectCode('IAS 301'), 'IAS 301');
      expect(normSubjectCode(null), '');
    });

    test('name collapses internal whitespace, code does not', () {
      expect(normSubjectName('Programming  1'), 'programming 1');
      expect(normSubjectName('  PROGRAMMING 1  '), 'programming 1');
      // Deliberate asymmetry: the code rule mirrors a DB index that does not
      // collapse inner spaces, so it must not either.
      expect(normSubjectCode('IAS  301'), 'IAS  301');
    });
  });

  group('fresh add (no subject anchored)', () {
    test('a free code and free name are clear', () {
      expect(check(code: 'IT202', name: 'Data Structures').isClear, isTrue);
    });

    test('reusing a code is refused and names the holder', () {
      // UAT_SAO_Admin TC-A07 step 4.
      final v = check(code: 'PElec2', name: 'Something Else');
      expect(v.codeTakenBy?['id'], 'sub-pelec2');
      // The refusal outranks the warning -- nothing to ask about a save that
      // is not going to happen.
      expect(v.nameClashWith, isNull);
    });

    test('case and padding cannot smuggle a duplicate code past it', () {
      expect(check(code: '  pelec2 ', name: 'X').codeTakenBy?['id'],
          'sub-pelec2');
    });

    test('reusing a name under a free code warns but does not refuse', () {
      // UAT_SAO_Admin TC-A07 step 5 -- allowed, but only deliberately.
      final v = check(code: 'IT999', name: 'Human Computer Interaction');
      expect(v.codeTakenBy, isNull);
      expect(v.nameClashWith?['id'], 'sub-pelec2');
    });

    test('the name warning tolerates sloppy spacing', () {
      expect(
          check(code: 'IT999', name: 'human   computer  interaction')
              .nameClashWith?['id'],
          'sub-pelec2');
    });
  });

  group('variant A - add-instructor form, code retyped to another subject', () {
    test('is refused (was: silently attached the instructor to it)', () {
      // Opened against IT101, code retyped to PElec2, name retyped to match.
      // This exact input used to sail through and report
      // "Instructor assigned successfully".
      final v = check(
        code: 'PElec2',
        name: 'Human Computer Interaction',
        sheetSubjectId: 'sub-it101',
        originalName: 'Computer Programming 1',
      );
      expect(v.codeTakenBy?['id'], 'sub-pelec2');
    });
  });

  group('variant C - edit form, code changed to another subject', () {
    test('is refused (was: silently repointed the assignment)', () {
      final v = check(
        code: 'PElec2',
        name: 'Computer Programming 1',
        sheetSubjectId: 'sub-it101',
      );
      expect(v.codeTakenBy?['id'], 'sub-pelec2');
    });
  });

  group('variant D - edit form, name changed onto another subject', () {
    test('warns (was: rewrote the name with no warning at all)', () {
      // IT101 keeps its own code, so the code check must pass -- and the name
      // check must still fire against PElec2.
      final v = check(
        code: 'IT101',
        name: 'Human Computer Interaction',
        sheetSubjectId: 'sub-it101',
        originalName: 'Computer Programming 1',
      );
      expect(v.codeTakenBy, isNull);
      expect(v.nameClashWith?['id'], 'sub-pelec2');
    });
  });

  group('the legitimate paths must stay open', () {
    test('add-instructor with the code untouched is clear', () {
      // The normal, overwhelmingly common case: the fix must not block it.
      final v = check(
        code: 'PElec2',
        name: 'Human Computer Interaction',
        sheetSubjectId: 'sub-pelec2',
        originalName: 'Human Computer Interaction',
      );
      expect(v.isClear, isTrue,
          reason: 'a subject matching itself is not a duplicate');
    });

    test('an unchanged name never warns, even when it collides', () {
      // Two subjects share a name, legitimately, via "Create anyway". Opening
      // either of them and saving without touching the name must not warn:
      // the admin did not choose that collision here and cannot be expected
      // to answer for it on every save.
      const twin = <String, dynamic>{
        'id': 'sub-twin',
        'subject_code': 'IT999',
        'subject_name': 'Human Computer Interaction',
        'department_id': 2,
      };
      final v = check(
        code: 'PElec2',
        name: 'Human Computer Interaction',
        sheetSubjectId: 'sub-pelec2',
        originalName: 'Human Computer Interaction',
        subjects: const [pelec2, it101, twin],
      );
      expect(v.isClear, isTrue);
    });

    test('but changing the name onto a collision still warns', () {
      // Same data as above; this time the admin actually typed the other
      // subject's name, which is the case the warning exists for.
      const twin = <String, dynamic>{
        'id': 'sub-twin',
        'subject_code': 'IT999',
        'subject_name': 'Human Computer Interaction',
        'department_id': 2,
      };
      final v = check(
        code: 'IT101',
        name: 'Human Computer Interaction',
        sheetSubjectId: 'sub-it101',
        originalName: 'Computer Programming 1',
        subjects: const [pelec2, it101, twin],
      );
      expect(v.nameClashWith, isNotNull);
    });

    test('edit form re-saving a subject unchanged is clear', () {
      final v = check(
        code: 'IT101',
        name: 'Computer Programming 1',
        sheetSubjectId: 'sub-it101',
        originalName: 'Computer Programming 1',
      );
      expect(v.isClear, isTrue,
          reason: 'the form must not warn a subject about itself');
    });

    test('correcting a name to something nobody else uses is clear', () {
      final v = check(
        code: 'IT101',
        name: 'Computer Programming I',
        sheetSubjectId: 'sub-it101',
        originalName: 'Computer Programming 1',
      );
      expect(v.isClear, isTrue);
    });

    test('a name change that is only whitespace is treated as unchanged', () {
      // normSubjectName collapses runs of spaces, so this is the same name and
      // must not be re-litigated against other subjects.
      const twin = <String, dynamic>{
        'id': 'sub-twin',
        'subject_code': 'IT999',
        'subject_name': 'Computer  Programming 1',
      };
      final v = check(
        code: 'IT101',
        name: 'Computer   Programming   1',
        sheetSubjectId: 'sub-it101',
        originalName: 'Computer Programming 1',
        subjects: const [it101, twin],
      );
      expect(v.isClear, isTrue);
    });
  });

  group('edge cases', () {
    test('an empty subject list is clear', () {
      expect(check(code: 'IT101', name: 'Anything', subjects: const []).isClear,
          isTrue);
    });

    test('rows with a missing id are still matched on code', () {
      // Defensive: a malformed row must not be treated as "this is me" and
      // wave a real collision through.
      const noId = <String, dynamic>{
        'subject_code': 'PElec2',
        'subject_name': 'Human Computer Interaction',
      };
      final v = check(
          code: 'PElec2', name: 'X', sheetSubjectId: null, subjects: const [noId]);
      expect(v.codeTakenBy, isNotNull);
    });

    test('the first matching row wins, deterministically', () {
      // Two rows share a code only if the DB index is missing; the verdict
      // should still name one of them rather than throwing.
      const dupA = <String, dynamic>{
        'id': 'a',
        'subject_code': 'DUP1',
        'subject_name': 'First'
      };
      const dupB = <String, dynamic>{
        'id': 'b',
        'subject_code': 'dup1',
        'subject_name': 'Second'
      };
      expect(
          check(code: 'DUP1', name: 'X', subjects: const [dupA, dupB])
              .codeTakenBy?['id'],
          'a');
    });
  });
}
