// Covers the registration UX changes:
//
//   * a taken name / ID / email is reported on the step that owns the field,
//     not at the final Register press after the agreements have been read
//   * the review step actually shows what was entered
//   * per-field errors appear only once the field has been typed in
//   * the password special-character rule accepts characters people use
//
// The duplicate rules themselves live in identity_validator_test.dart; this
// file is about when and where the user finds out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/address_service.dart';
import 'package:ievaluateapp_final/widgets/agreement_reader_page.dart';
import 'package:ievaluateapp_final/core/services/auth_service.dart';
import 'package:ievaluateapp_final/core/services/identity_validator.dart';
import 'package:ievaluateapp_final/signup_screen.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Answers availability lookups from a fixed set of "already taken" values so
/// no network is involved.
class FakeAuthService extends AuthService {
  FakeAuthService({
    this.takenNames = const {},
    this.takenIds = const {},
    this.takenEmails = const {},
  });

  final Set<String> takenNames; // 'first last', lower case
  final Set<String> takenIds;
  final Set<String> takenEmails;

  int checkCalls = 0;

  @override
  Future<List<String>> getDepartments() async => ['College of Technology'];

  // The real table holds these raw strings. FULL-TIME and PART-TIME are the
  // two instructor roles; there is no INSTRUCTOR row.
  @override
  Future<List<String>> getRoles() async =>
      ['DEPARTMENT_HEAD', 'FULL-TIME', 'PART-TIME', 'SAO_ADMIN', 'SAO_STAFF'];

  @override
  Future<IdentityCheckResult> checkIdentityAvailable({
    String? firstName,
    String? lastName,
    String? email,
    String? universityId,
  }) async {
    checkCalls++;
    final id = IdentityValidator.normalise(universityId);
    if (id.isNotEmpty && takenIds.contains(id)) {
      return const IdentityCheckResult.conflict(
        IdentityField.universityId,
        'This University ID is already registered to another account.',
      );
    }
    final mail = IdentityValidator.normalise(email);
    if (mail.isNotEmpty && takenEmails.contains(mail)) {
      return const IdentityCheckResult.conflict(
        IdentityField.email,
        'This email address is already registered to another account.',
      );
    }
    final name =
        '${IdentityValidator.normalise(firstName)} ${IdentityValidator.normalise(lastName)}'.trim();
    if (name.isNotEmpty && takenNames.contains(name)) {
      return const IdentityCheckResult.conflict(
        IdentityField.name,
        'An account for that name already exists.',
      );
    }
    return const IdentityCheckResult.ok();
  }
}

/// Serves a fixed barangay list so the picker has options without a database.
class FakeAddressService extends AddressService {
  FakeAddressService({this.locations = _defaultLocations});

  static const _defaultLocations = <AddressLocation>[
    AddressLocation(
        barangay: 'Poblacion', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
    AddressLocation(
        barangay: 'Lamacan', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
    AddressLocation(
        barangay: 'Langtad', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
  ];

  final List<AddressLocation> locations;

  @override
  Future<List<AddressLocation>> fetchLocations() async => locations;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  Future<void> pumpSignUp(WidgetTester tester, FakeAuthService fake,
      {Size size = const Size(400, 900), FakeAddressService? addresses}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SignUpScreen(
          authService: fake,
          addressService: addresses ?? FakeAddressService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldWithHint(String hint) => find.ancestor(
        of: find.text(hint),
        matching: find.byType(TextField),
      );

  /// Taps Continue, scrolling it into view first -- on a short screen the
  /// button sits below the fold and a blind tap misses it.
  Future<void> tapContinue(WidgetTester tester) async {
    final button = find.text('Continue');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Types into the field carrying [hint] and lets the 600ms debounce fire.
  Future<void> typeAndSettle(
    WidgetTester tester,
    String hint,
    String value,
  ) async {
    await tester.enterText(fieldWithHint(hint), value);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  /// Picks a role from the step-1 dropdown. [label] is the friendly wording,
  /// e.g. 'SAO Staff (Data Gatherer)'.
  Future<void> pickRole(WidgetTester tester, String label) async {
    // Tap the field, not the hint Text inside it: the hint's RenderParagraph
    // is not the hit-test target -- the InputDecorator above it is -- so
    // tapping the text warns about a missed hit even when it happens to work.
    await tester.tap(find.ancestor(
      of: find.text('I am registering as'),
      matching: find.byType(DropdownButtonFormField<String>),
    ).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Fills every field on step 1: role, name, and the two address inputs.
  /// Role lives here now because it decides what step 2 contains.
  Future<void> fillStep1(
    WidgetTester tester, {
    String first = 'Juan',
    String last = 'Cruz',
    String street = 'Purok 3',
    String barangay = 'Lamacan, Argao, Cebu',
    String role = 'SAO Staff (Data Gatherer)',
  }) async {
    await pickRole(tester, role);
    await typeAndSettle(tester, 'First Name', first);
    await typeAndSettle(tester, 'Last Name', last);
    await tester.enterText(fieldWithHint('House No. / Street / Purok'), street);
    await tester.pump();
    await tester.enterText(
        fieldWithHint('Barangay, Municipality, Province'), barangay);
    await tester.pumpAndSettle();
  }

  group('name availability on step 1', () {
    testWidgets('a free name is confirmed inline', (tester) async {
      final fake = FakeAuthService();
      await pumpSignUp(tester, fake);

      await typeAndSettle(tester, 'First Name', 'Juan');
      await typeAndSettle(tester, 'Last Name', 'Cruz');

      expect(find.text('Juan Cruz is available'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a taken name is reported on step 1, not at the end',
        (tester) async {
      final fake = FakeAuthService(takenNames: {'juan cruz'});
      await pumpSignUp(tester, fake);

      await typeAndSettle(tester, 'First Name', 'Juan');
      await typeAndSettle(tester, 'Last Name', 'Cruz');

      expect(
        find.text('Someone is already registered with this exact name'),
        findsOneWidget,
      );
      // Still on step 1 -- the whole point is not to walk them through three
      // more steps and two legal agreements before saying this.
      expect(find.text('Personal Information'), findsOneWidget);
    });

    testWidgets('Continue is disabled while the name is known to be taken',
        (tester) async {
      final fake = FakeAuthService(takenNames: {'juan cruz'});
      await pumpSignUp(tester, fake);

      await typeAndSettle(tester, 'First Name', 'Juan');
      await typeAndSettle(tester, 'Last Name', 'Cruz');

      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('only the pair is checked, so one half alone asks nothing',
        (tester) async {
      // Sharing a first OR a last name is allowed, so there is nothing to ask
      // the server until both halves are present.
      final fake = FakeAuthService();
      await pumpSignUp(tester, fake);

      await typeAndSettle(tester, 'First Name', 'Juan');
      expect(fake.checkCalls, 0);

      await typeAndSettle(tester, 'Last Name', 'Cruz');
      expect(fake.checkCalls, 1);
    });

    testWidgets('editing the name drops the previous answer', (tester) async {
      final fake = FakeAuthService();
      await pumpSignUp(tester, fake);

      await typeAndSettle(tester, 'First Name', 'Juan');
      await typeAndSettle(tester, 'Last Name', 'Cruz');
      expect(find.text('Juan Cruz is available'), findsOneWidget);

      // A stale green tick under a name that has since changed would be a lie.
      await tester.enterText(fieldWithHint('Last Name'), 'Cruzz');
      await tester.pump();
      expect(find.text('Juan Cruz is available'), findsNothing);
    });
  });

  group('per-field errors', () {
    testWidgets('nothing is red before the user types', (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      expect(find.text('First name is required'), findsNothing);
      expect(find.text('Last name is required'), findsNothing);
    });

    testWidgets('a bad value is flagged on the field itself', (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      // Digits in a name field -- previously only surfaced after Continue, in a
      // banner at the bottom of the screen.
      await typeAndSettle(tester, 'First Name', 'Juan2');
      expect(
        find.textContaining('may only contain letters'),
        findsOneWidget,
      );
    });

    testWidgets('an empty required field is still caught by Continue',
        (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      // Role is validated before the name, so choose one to get past it.
      await pickRole(tester, 'SAO Staff (Data Gatherer)');
      await tapContinue(tester);
      expect(find.text('First name is required'), findsOneWidget);
    });
  });

  group('the review step shows what was entered', () {
    Future<void> fillToReview(WidgetTester tester, FakeAuthService fake) async {
      await pumpSignUp(tester, fake);

      await fillStep1(tester);
      await tapContinue(tester);

      await typeAndSettle(tester, 'Staff ID', 'CTU-1234');
      await typeAndSettle(tester, 'Institutional Email', 'juan@ctu.edu.ph');
      await tapContinue(tester);

      // password step
      await tester.enterText(fieldWithHint('Password'), 'Passw0rd_');
      await tester.pump();
      await tester.enterText(fieldWithHint('Confirm Password'), 'Passw0rd_');
      await tester.pumpAndSettle();
      await tapContinue(tester);
    }

    testWidgets('name, ID and email are read back before submitting',
        (tester) async {
      await fillToReview(tester, FakeAuthService());

      expect(find.text('Review & Terms'), findsOneWidget);
      // The email is the field that matters most: a typo there produces an
      // account that can never receive its approval notice or a reset.
      expect(find.text('juan@ctu.edu.ph'), findsOneWidget);
      expect(find.text('CTU-1234'), findsOneWidget);
      expect(find.text('Juan Cruz'), findsOneWidget);
    });

    testWidgets('tapping a summary row jumps back to fix it', (tester) async {
      await fillToReview(tester, FakeAuthService());

      await tester.tap(find.text('juan@ctu.edu.ph'));
      await tester.pumpAndSettle();
      expect(find.text('Personnel Details'), findsOneWidget);
    });

    testWidgets('the summary collapses so the agreements are readable',
        (tester) async {
      // The summary and the NDA share one screen. On a phone that left the
      // agreements about two lines tall -- unreadable, and nobody can
      // meaningfully consent to text they cannot see.
      await fillToReview(tester, FakeAuthService());

      // Expanded by default: every row is there.
      expect(find.text('Registering as'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();

      // Detail rows gone, and the toggle now offers to bring them back.
      expect(find.text('Registering as'), findsNothing);
      expect(find.text('Address'), findsNothing);
      expect(find.text('Show'), findsOneWidget);
    });

    testWidgets('collapsing keeps name and email in view', (tester) async {
      // Hiding the details must not hide what was entered -- a wrong email is
      // the one typo that produces an unrecoverable account.
      await fillToReview(tester, FakeAuthService());

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Juan Cruz'), findsOneWidget);
      expect(find.textContaining('juan@ctu.edu.ph'), findsOneWidget);
    });

    testWidgets('the collapsed strip taps back open', (tester) async {
      await fillToReview(tester, FakeAuthService());

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(find.text('Address'), findsNothing);

      await tester.tap(find.byIcon(Icons.unfold_more_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
    });

    testWidgets('the agreements are a tile, not a cramped inline box',
        (tester) async {
      // They used to render in a box on this step, about two lines tall on a
      // phone. Now the step only links to them.
      await fillToReview(tester, FakeAuthService());

      expect(find.text('NDA and Data Privacy Agreement'), findsOneWidget);
      expect(find.text('Tap to read. Required before you can agree.'),
          findsOneWidget);
      expect(find.byType(AgreementReaderPage), findsNothing);
    });

    testWidgets('agreeing is locked until the agreement has been read',
        (tester) async {
      await fillToReview(tester, FakeAuthService());

      expect(find.text('Read the agreement above first'), findsOneWidget);
      final box = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile));
      expect(box.onChanged, isNull);
    });
  });

  group('the agreement reader', () {
    Future<void> fillToReview(WidgetTester tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await fillStep1(tester);
      await tapContinue(tester);
      await typeAndSettle(tester, 'Staff ID', 'CTU-1234');
      await typeAndSettle(tester, 'Institutional Email', 'juan@ctu.edu.ph');
      await tapContinue(tester);
      await tester.enterText(fieldWithHint('Password'), 'Passw0rd_');
      await tester.pump();
      await tester.enterText(fieldWithHint('Confirm Password'), 'Passw0rd_');
      await tester.pumpAndSettle();
      await tapContinue(tester);
    }

    Finder confirmButton() => find.widgetWithText(
        ElevatedButton, 'I have read the NDA and DPA');

    /// Drags the reader to the bottom. The agreements are long, so one drag
    /// will not do it; bounded so a broken gate fails instead of hanging.
    Future<void> readToEnd(WidgetTester tester) async {
      final view = find.descendant(
        of: find.byType(AgreementReaderPage),
        matching: find.byType(SingleChildScrollView),
      );
      for (var i = 0; i < 60; i++) {
        if (tester.widget<ElevatedButton>(confirmButton()).onPressed != null) {
          return;
        }
        await tester.drag(view, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      fail('never reached the end of the agreements after 60 drags');
    }

    testWidgets('tapping the tile opens it full screen', (tester) async {
      await fillToReview(tester);

      await tester.tap(find.text('NDA and Data Privacy Agreement'));
      await tester.pumpAndSettle();

      expect(find.byType(AgreementReaderPage), findsOneWidget);
      expect(find.text('NDA & Data Privacy'), findsOneWidget);
      expect(find.textContaining('Non-Disclosure Agreement'), findsWidgets);
    });

    testWidgets('the confirm button is dead until the end is reached',
        (tester) async {
      await fillToReview(tester);
      await tester.tap(find.text('NDA and Data Privacy Agreement'));
      await tester.pumpAndSettle();

      expect(tester.widget<ElevatedButton>(confirmButton()).onPressed, isNull);
      expect(find.text('Scroll to the end to continue'), findsOneWidget);
    });

    testWidgets('reading to the end unlocks agreeing on the review step',
        (tester) async {
      await fillToReview(tester);
      await tester.tap(find.text('NDA and Data Privacy Agreement'));
      await tester.pumpAndSettle();

      await readToEnd(tester);
      expect(find.text('Scroll to the end to continue'), findsNothing);

      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      // Back on the review step, and the checkbox is now live.
      expect(find.byType(AgreementReaderPage), findsNothing);
      expect(find.text('Read the agreement above first'), findsNothing);
      expect(find.text('Read — tap to view again'), findsOneWidget);

      final box = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile));
      expect(box.onChanged, isNotNull);
    });

    testWidgets('closing early does not count as read', (tester) async {
      await fillToReview(tester);
      await tester.tap(find.text('NDA and Data Privacy Agreement'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Read the agreement above first'), findsOneWidget);
    });

    testWidgets('reopening keeps the read state', (tester) async {
      // Someone going back to re-check a clause must not lose their progress.
      await fillToReview(tester);
      await tester.tap(find.text('NDA and Data Privacy Agreement'));
      await tester.pumpAndSettle();
      await readToEnd(tester);
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      await tester.tap(find.text('NDA and Data Privacy Agreement'));
      await tester.pumpAndSettle();

      // Enabled immediately, without scrolling the whole thing again.
      expect(tester.widget<ElevatedButton>(confirmButton()).onPressed,
          isNotNull);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Read — tap to view again'), findsOneWidget);
    });
  });

  group('password rules', () {
    testWidgets('an underscore counts as a special character', (tester) async {
      // The old character class left out - _ + = ; [ ] ~ / so "Passw0rd_" was
      // told it had no special character, with no hint as to why.
      await pumpSignUp(tester, FakeAuthService());
      await fillStep1(tester);
      await tapContinue(tester);

      await typeAndSettle(tester, 'Staff ID', 'CTU-1234');
      await typeAndSettle(tester, 'Institutional Email', 'juan@ctu.edu.ph');
      await tapContinue(tester);

      await tester.enterText(fieldWithHint('Password'), 'Passw0rd_');
      await tester.enterText(fieldWithHint('Confirm Password'), 'Passw0rd_');
      await tester.pumpAndSettle();

      // All four rules met means Continue is live.
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('role', () {
    testWidgets('is asked on step 1, before anything it decides',
        (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      expect(find.text('I am registering as'), findsOneWidget);
      expect(find.text('Personal Information'), findsOneWidget);
    });

    testWidgets('raw table values are shown in readable wording',
        (tester) async {
      // The picker used to list DEPARTMENT_HEAD, FULL-TIME, PART-TIME,
      // SAO_ADMIN, SAO_STAFF -- raw column values, alphabetical, with
      // FULL-TIME telling nobody what they were registering as.
      await pumpSignUp(tester, FakeAuthService());
      await tester.tap(find.ancestor(
        of: find.text('I am registering as'),
        matching: find.byType(DropdownButtonFormField<String>),
      ).first);
      await tester.pumpAndSettle();

      expect(find.text('Instructor — Resident (Full-Time)'), findsOneWidget);
      expect(find.text('Instructor — Non-Resident (Part-Time)'), findsOneWidget);
      expect(find.text('Department Head'), findsOneWidget);
      expect(find.text('SAO Administrator'), findsOneWidget);
      expect(find.text('FULL-TIME'), findsNothing);
      expect(find.text('SAO_ADMIN'), findsNothing);
    });

    testWidgets('cannot leave step 1 without choosing one', (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await tapContinue(tester);
      expect(find.text('Please choose what you are registering as'),
          findsOneWidget);
    });
  });

  group('step 2 shows only what the role needs', () {
    testWidgets('SAO staff get a Staff ID and no department', (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await fillStep1(tester, role: 'SAO Staff (Data Gatherer)');
      await tapContinue(tester);

      expect(find.text('Personnel Details'), findsOneWidget);
      expect(find.text('Staff ID'), findsOneWidget);
      expect(find.text('University ID'), findsNothing);
      // SAO office staff have no department and no employment question.
      expect(find.text('Select Department'), findsNothing);
      expect(find.text('Employment Status'), findsNothing);
    });

    testWidgets('instructors get a University ID and a department',
        (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await fillStep1(tester, role: 'Instructor — Non-Resident (Part-Time)');
      await tapContinue(tester);

      expect(find.text('Academic Information'), findsOneWidget);
      expect(find.text('University ID'), findsOneWidget);
      expect(find.text('Select Department'), findsOneWidget);
      // Part-Time already states the employment status, so asking again would
      // let the two disagree.
      expect(find.text('Employment Status'), findsNothing);
    });

    testWidgets('department heads are still asked their employment status',
        (tester) async {
      // Their role name does not state it, so it stays a real question.
      await pumpSignUp(tester, FakeAuthService());
      await fillStep1(tester, role: 'Department Head');
      await tapContinue(tester);

      expect(find.text('Select Department'), findsOneWidget);
      expect(find.text('Employment Status'), findsOneWidget);
    });

    testWidgets('the step names the role back to you', (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await fillStep1(tester, role: 'Instructor — Resident (Full-Time)');
      await tapContinue(tester);

      expect(
        find.text('Registering as Instructor — Resident (Full-Time).'),
        findsOneWidget,
      );
    });
  });

  testWidgets('step 1 and 2 survive a narrow screen', (tester) async {
    await pumpSignUp(tester, FakeAuthService(), size: const Size(320, 640));
    expect(tester.takeException(), isNull);

    await fillStep1(tester);
    await tapContinue(tester);
    expect(tester.takeException(), isNull);
  });

  group('address picker', () {
    testWidgets('suggestions appear as you type', (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await tester.enterText(
          fieldWithHint('Barangay, Municipality, Province'), 'lam');
      await tester.pumpAndSettle();

      expect(find.text('Lamacan, Argao, Cebu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking one fills in the full canonical label',
        (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await tester.enterText(
          fieldWithHint('Barangay, Municipality, Province'), 'lam');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lamacan, Argao, Cebu'));
      await tester.pumpAndSettle();

      // Typing three letters yields the whole address, spelt consistently.
      final field = tester.widget<TextField>(
          fieldWithHint('Barangay, Municipality, Province'));
      expect(field.controller!.text, 'Lamacan, Argao, Cebu');
    });

    testWidgets('the composed address reaches the review step', (tester) async {
      final fake = FakeAuthService();
      await pumpSignUp(tester, fake);
      await fillStep1(tester, street: 'Purok 3');
      await tapContinue(tester);

      await typeAndSettle(tester, 'Staff ID', 'CTU-1234');
      await typeAndSettle(tester, 'Institutional Email', 'juan@ctu.edu.ph');
      await tapContinue(tester);

      await tester.enterText(fieldWithHint('Password'), 'Passw0rd_');
      await tester.enterText(fieldWithHint('Confirm Password'), 'Passw0rd_');
      await tester.pumpAndSettle();
      await tapContinue(tester);

      // Street and barangay joined into the one string user_info.address holds.
      expect(find.text('Purok 3, Lamacan, Argao, Cebu'), findsOneWidget);
    });

    testWidgets('a barangay that is not on the list is still accepted',
        (tester) async {
      // Nobody from an unseeded town may be blocked -- the list is a
      // convenience, not a gate.
      await pumpSignUp(tester, FakeAuthService());
      await fillStep1(tester, barangay: 'Tagbilaran, Bohol');
      await tapContinue(tester);

      expect(find.text('Personnel Details'), findsOneWidget);
    });

    testWidgets('an empty list degrades to plain free text', (tester) async {
      // The fetch failed, or the migration has not been applied.
      await pumpSignUp(tester, FakeAuthService(),
          addresses: FakeAddressService(locations: const []));

      expect(find.text('Type your barangay, municipality and province.'),
          findsOneWidget);

      await fillStep1(tester, barangay: 'Somewhere, Somewhere');
      await tapContinue(tester);
      expect(find.text('Personnel Details'), findsOneWidget);
    });

    testWidgets('both halves of the address are required', (tester) async {
      await pumpSignUp(tester, FakeAuthService());
      await pickRole(tester, 'SAO Staff (Data Gatherer)');
      await typeAndSettle(tester, 'First Name', 'Juan');
      await typeAndSettle(tester, 'Last Name', 'Cruz');

      await tapContinue(tester);
      expect(find.text('House number / street is required'), findsOneWidget);

      await tester.enterText(fieldWithHint('House No. / Street / Purok'), 'Purok 3');
      await tester.pumpAndSettle();
      await tapContinue(tester);
      expect(find.text('Barangay is required'), findsOneWidget);
    });
  });
}
