// The duplicate warning is a modal rather than a snackbar because "this person
// is already in the database" is not a typo the user can fix by reading faster.
// These tests hold that shape: the message is shown, the title names the field,
// and it cannot be dismissed by tapping past it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/identity_validator.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:ievaluateapp_final/widgets/duplicate_warning_dialog.dart';

void main() {
  /// Pumps a screen with one button that opens the dialog.
  Future<void> pumpAndOpen(
    WidgetTester tester,
    Future<void> Function(BuildContext) open, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the message', (tester) async {
    await pumpAndOpen(
      tester,
      (c) => showDuplicateWarningDialog(
        c,
        message: 'An account for "Juan Cruz" already exists.',
        field: IdentityField.name,
      ),
    );
    expect(find.text('An account for "Juan Cruz" already exists.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the title names which field clashed', (tester) async {
    final cases = <IdentityField?, String>{
      IdentityField.universityId: 'ID Already Used',
      IdentityField.email: 'Email Already Used',
      IdentityField.name: 'Name Already Used',
      null: 'Already In The Database',
    };

    for (final entry in cases.entries) {
      await pumpAndOpen(
        tester,
        (c) => showDuplicateWarningDialog(c, message: 'msg', field: entry.key),
      );
      expect(find.text(entry.value), findsOneWidget,
          reason: 'field ${entry.key} should be titled "${entry.value}"');
      // dismiss before the next iteration
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('OK dismisses it', (tester) async {
    await pumpAndOpen(
      tester,
      (c) => showDuplicateWarningDialog(c, message: 'already here'),
    );
    expect(find.text('already here'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('already here'), findsNothing);
  });

  testWidgets('tapping outside does NOT dismiss it', (tester) async {
    // barrierDismissible is false on purpose -- the admin has to acknowledge
    // that the person already exists, not swipe it away by accident.
    await pumpAndOpen(
      tester,
      (c) => showDuplicateWarningDialog(c, message: 'must be read'),
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('must be read'), findsOneWidget);
  });

  group('showConflictIfAny', () {
    testWidgets('shows nothing and reports false when available', (tester) async {
      bool? shown;
      await pumpAndOpen(tester, (c) async {
        shown = await showConflictIfAny(c, const IdentityCheckResult.ok());
      });
      expect(shown, isFalse);
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('shows the modal and reports true on a conflict', (tester) async {
      bool? shown;
      await pumpAndOpen(tester, (c) async {
        shown = await showConflictIfAny(
          c,
          const IdentityCheckResult.conflict(
            IdentityField.email,
            'That email is taken.',
          ),
        );
      });
      expect(find.text('That email is taken.'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(shown, isTrue);
    });
  });

  testWidgets('a long message does not overflow a narrow phone', (tester) async {
    await pumpAndOpen(
      tester,
      (c) => showDuplicateWarningDialog(
        c,
        message: 'An account for "Bartholomew Fitzgerald-Montgomery" already '
            'exists. A first name or a last name may be shared, but not both. '
            'Add a middle initial or suffix to tell the two people apart.',
        field: IdentityField.name,
      ),
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
  });

  group('isDuplicateMessage', () {
    test('recognises the server prefix', () {
      // describeConflict in _shared/identity_guard.ts always prefixes
      // 'Duplicate:'. That prefix is the contract between server and client.
      expect(
        isDuplicateMessage('Duplicate: this University ID already belongs to another account.'),
        isTrue,
      );
    });

    test('leaves ordinary failures alone', () {
      expect(isDuplicateMessage('Operation failed. Please try again.'), isFalse);
      expect(isDuplicateMessage('Unauthorized'), isFalse);
      expect(isDuplicateMessage(''), isFalse);
    });
  });
}
