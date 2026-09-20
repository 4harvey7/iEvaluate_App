// Locks in the identity rules that stop duplicate accounts:
//
//   university_id  unique across active accounts (case-insensitive)
//   email          unique across active accounts (case-insensitive)
//   first + last   unique TOGETHER -- sharing one half is allowed
//
// The "sharing one half is allowed" half of that rule is the easy one to break
// by accident, so it is tested as an explicit matrix below.
//
// The enforcement itself lives in the database (unique indexes in migration
// 20240130000008). What is testable here without a live Supabase is everything
// that decides WHICH values count as the same value, plus the wording the user
// ends up seeing -- and a wrong normalisation is exactly how "Juan  Cruz" gets
// in alongside "Juan Cruz".
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/identity_validator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The composite key the database indexes on. Mirrors
/// `(norm_identity(first_name), norm_identity(last_name))`.
String nameKey(String first, String last) =>
    '${IdentityValidator.normalise(first)}|${IdentityValidator.normalise(last)}';

void main() {
  group('normalise', () {
    test('folds case', () {
      expect(IdentityValidator.normalise('JUAN'), 'juan');
    });

    test('trims the ends', () {
      expect(IdentityValidator.normalise('  juan  '), 'juan');
    });

    test('collapses inner whitespace', () {
      // Without this, "Juan  Cruz" and "Juan Cruz" are two different people.
      expect(IdentityValidator.normalise('Juan   Cruz'), 'juan cruz');
      expect(IdentityValidator.normalise('Juan\tCruz'), 'juan cruz');
    });

    test('null and blank collapse to empty', () {
      expect(IdentityValidator.normalise(null), '');
      expect(IdentityValidator.normalise('   '), '');
    });
  });

  group('clean keeps the name as the person writes it', () {
    test('capitalisation survives', () {
      expect(IdentityValidator.clean('  Juan  Dela Cruz '), 'Juan Dela Cruz');
    });

    test('email is lower-cased for storage', () {
      expect(
        IdentityValidator.cleanEmail('  Rodz.Harvey@CTU.EDU.PH '),
        'rodz.harvey@ctu.edu.ph',
      );
    });
  });

  group('the full-name rule', () {
    test('same first AND same last is the same person -> blocked', () {
      expect(nameKey('Juan', 'Cruz'), nameKey('Juan', 'Cruz'));
    });

    test('same first name, different last name -> allowed', () {
      expect(nameKey('Juan', 'Cruz'), isNot(nameKey('Juan', 'Santos')));
    });

    test('different first name, same last name -> allowed', () {
      expect(nameKey('Juan', 'Cruz'), isNot(nameKey('Maria', 'Cruz')));
    });

    test('casing and stray spacing do not create a second person', () {
      expect(nameKey('  juan ', 'CRUZ'), nameKey('Juan', 'Cruz'));
      expect(nameKey('Juan', 'Dela  Cruz'), nameKey('juan', 'dela cruz'));
    });

    test('swapping first and last is two different people', () {
      // The key is ordered, so "Juan Cruz" and "Cruz Juan" do not collide.
      expect(nameKey('Juan', 'Cruz'), isNot(nameKey('Cruz', 'Juan')));
    });
  });

  group('validateName', () {
    test('accepts ordinary names', () {
      for (final n in ['Juan', 'Dela Cruz', "O'Brien", 'Maria-Clara', 'Cruz Jr.']) {
        expect(IdentityValidator.validateName(n, 'First name'), isNull,
            reason: '$n should be accepted');
      }
    });

    test('accepts Filipino and accented characters', () {
      // A name rule that rejects ñ is unusable at a Philippine university.
      for (final n in ['Peñaflor', 'Muñoz', 'Sánchez', 'Núñez']) {
        expect(IdentityValidator.validateName(n, 'Last name'), isNull,
            reason: '$n should be accepted');
      }
    });

    test('rejects blank', () {
      expect(IdentityValidator.validateName('   ', 'First name'),
          'First name is required');
      expect(IdentityValidator.validateName(null, 'Last name'),
          'Last name is required');
    });

    test('rejects digits, so an ID cannot be typed into a name field', () {
      expect(IdentityValidator.validateName('Juan2', 'First name'), isNotNull);
      expect(IdentityValidator.validateName('12345', 'Last name'), isNotNull);
    });

    test('rejects a single character', () {
      expect(IdentityValidator.validateName('J', 'First name'), isNotNull);
    });

    test('rejects something absurdly long', () {
      expect(IdentityValidator.validateName('a' * 61, 'First name'), isNotNull);
    });

    test('the label appears in the message', () {
      expect(IdentityValidator.validateName('', 'First name'), contains('First name'));
      expect(IdentityValidator.validateName('', 'Last name'), contains('Last name'));
    });
  });

  group('validateUniversityId', () {
    test('accepts letters, digits and hyphens', () {
      expect(IdentityValidator.validateUniversityId('CTU-2024-0001'), isNull);
      expect(IdentityValidator.validateUniversityId('12345678'), isNull);
    });

    test('rejects too short', () {
      expect(IdentityValidator.validateUniversityId('123'), isNotNull);
    });

    test('rejects spaces and symbols', () {
      expect(IdentityValidator.validateUniversityId('CTU 2024'), isNotNull);
      expect(IdentityValidator.validateUniversityId('CTU_2024'), isNotNull);
    });

    test('rejects LIKE wildcards', () {
      // Sign-in resolves an ID with ilike. A bare '%' would otherwise match
      // every row in the table and hand back somebody else's email address.
      expect(IdentityValidator.validateUniversityId('%'), isNotNull);
      expect(IdentityValidator.validateUniversityId('12%4'), isNotNull);
      expect(IdentityValidator.validateUniversityId('12_4'), isNotNull);
    });

    test('surrounding spaces do not make a second ID', () {
      expect(IdentityValidator.validateUniversityId('  12345  '), isNull);
      expect(
        IdentityValidator.normalise('  12345  '),
        IdentityValidator.normalise('12345'),
      );
    });
  });

  group('validateEmail', () {
    test('accepts ordinary addresses', () {
      expect(IdentityValidator.validateEmail('rodz@ctu.edu.ph'), isNull);
      expect(IdentityValidator.validateEmail('first.last-x@mail.ctu.edu.ph'), isNull);
    });

    test('accepts an underscore, which is legal in a mailbox name', () {
      expect(IdentityValidator.validateEmail('rodz_harvey@ctu.edu.ph'), isNull);
    });

    test('accepts a long TLD', () {
      // The old regex capped the TLD at 4 characters, so this was rejected.
      expect(IdentityValidator.validateEmail('staff@university.education'), isNull);
    });

    test('rejects malformed addresses', () {
      for (final e in ['nope', 'nope@', '@nope.com', 'a b@c.com', 'a@b']) {
        expect(IdentityValidator.validateEmail(e), isNotNull, reason: '$e should fail');
      }
    });

    test('case and spacing do not make a second address', () {
      expect(
        IdentityValidator.cleanEmail(' RODZ@CTU.EDU.PH '),
        IdentityValidator.cleanEmail('rodz@ctu.edu.ph'),
      );
    });
  });

  group('validateFormat reports the first problem only', () {
    test('all valid', () {
      expect(
        IdentityValidator.validateFormat(
          firstName: 'Juan',
          lastName: 'Cruz',
          email: 'juan@ctu.edu.ph',
          universityId: 'CTU-1234',
        ),
        isNull,
      );
    });

    test('skips fields that were not supplied', () {
      // The edit dialogs collect a name and nothing else.
      expect(
        IdentityValidator.validateFormat(firstName: 'Juan', lastName: 'Cruz'),
        isNull,
      );
    });

    test('first name is reported before the email', () {
      expect(
        IdentityValidator.validateFormat(firstName: '', email: 'bad'),
        contains('First name'),
      );
    });
  });

  group('the ID field is named after the screen asking', () {
    // SAO Personnel Management labels the field "Staff ID". A field labelled
    // one thing whose error names another is how people conclude the app is
    // broken, so the label has to reach every message.
    test('format errors use the supplied label', () {
      expect(
        IdentityValidator.validateUniversityId('12', label: IdentityValidator.staffIdLabel),
        'Staff ID must be at least 4 characters',
      );
      expect(
        IdentityValidator.validateUniversityId('12'),
        'University ID must be at least 4 characters',
      );
    });

    test('validateFormat passes idLabel through', () {
      expect(
        IdentityValidator.validateFormat(
          universityId: 'CTU 1234',
          idLabel: IdentityValidator.staffIdLabel,
        ),
        contains('Staff ID'),
      );
    });

    test('duplicate messages use the supplied label', () {
      final msg = IdentityValidator.mapDatabaseError(
        PostgrestException(
          message: 'duplicate key value violates unique constraint '
              '"user_info_university_id_unique_idx"',
          code: '23505',
        ),
        idLabel: IdentityValidator.staffIdLabel,
      );
      expect(msg, contains('Staff ID'));
      expect(msg, isNot(contains('University ID')));
    });

    test('the default is still University ID', () {
      expect(IdentityValidator.defaultIdLabel, 'University ID');
      expect(
        IdentityValidator.validateUniversityId(''),
        'University ID is required',
      );
    });
  });

  group('mapDatabaseError turns a unique violation into the right message', () {
    PostgrestException unique(String index) => PostgrestException(
          message: 'duplicate key value violates unique constraint "$index"',
          code: '23505',
        );

    test('university ID index', () {
      expect(
        IdentityValidator.mapDatabaseError(unique('user_info_university_id_unique_idx')),
        contains('University ID'),
      );
    });

    test('email index', () {
      expect(
        IdentityValidator.mapDatabaseError(unique('user_info_email_unique_idx')),
        contains('email'),
      );
    });

    test('full-name index names the person and explains the rule', () {
      final msg = IdentityValidator.mapDatabaseError(
        unique('user_info_full_name_unique_idx'),
        firstName: 'Juan',
        lastName: 'Cruz',
      );
      expect(msg, contains('Juan Cruz'));
      // The admin has to be told that sharing ONE name is fine, otherwise the
      // message reads as "this person cannot be added" and they give up.
      expect(msg, contains('not both'));
    });

    test('returns null for anything that is not a duplicate', () {
      expect(
        IdentityValidator.mapDatabaseError(
          PostgrestException(message: 'permission denied', code: '42501'),
        ),
        isNull,
      );
      expect(IdentityValidator.mapDatabaseError('some network blip'), isNull);
    });

    test('returns null for a unique violation on an unrelated index', () {
      // Do not claim a duplicate person when some other table complained.
      expect(
        IdentityValidator.mapDatabaseError(
          unique('overall_total_survey_instructor_term_unique'),
        ),
        isNull,
      );
    });
  });

  group('describeEdgeFunctionError', () {
    test("pulls out the server's message", () {
      // Without this the admin sees the whole FunctionException toString.
      expect(
        IdentityValidator.describeEdgeFunctionError(
          const FunctionException(
            status: 400,
            details: {'error': 'Duplicate: this University ID already belongs to another account.'},
          ),
        ),
        'Duplicate: this University ID already belongs to another account.',
      );
    });

    test('falls back when details carry nothing usable', () {
      expect(
        IdentityValidator.describeEdgeFunctionError(
          const FunctionException(status: 500, details: null),
          fallback: 'Update failed. Please try again.',
        ),
        'Update failed. Please try again.',
      );
    });

    test('a thrown string passes through', () {
      // Some call sites `throw response.data['error']` directly.
      expect(
        IdentityValidator.describeEdgeFunctionError('Duplicate: already exists.'),
        'Duplicate: already exists.',
      );
    });

    test('never leaks a raw exception to the user', () {
      final msg = IdentityValidator.describeEdgeFunctionError(
        Exception('PostgrestException(schema "auth" does not exist)'),
        fallback: 'Could not create the user. Please try again.',
      );
      expect(msg, 'Could not create the user. Please try again.');
      expect(msg, isNot(contains('Postgrest')));
    });
  });
}
