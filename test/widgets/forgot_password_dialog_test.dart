import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/auth_service.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:ievaluateapp_final/widgets/forgot_password_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stands in for the real service so the three steps can be driven without a
/// network round-trip. Records what the dialog asked for.
class FakeAuthService extends AuthService {
  FakeAuthService({
    this.sendResult = const AuthResult(success: true),
    this.verifyResult = const AuthResult(success: true, userId: 'u1'),
    this.updateResult = const AuthResult(success: true),
  });

  final AuthResult sendResult;
  final AuthResult verifyResult;
  final AuthResult updateResult;

  final List<String> sentTo = [];
  final List<({String email, String code})> verified = [];
  final List<String> updated = [];
  int signOutCount = 0;

  @override
  Future<AuthResult> sendPasswordResetCode(String email) async {
    sentTo.add(email);
    return sendResult;
  }

  @override
  Future<AuthResult> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    verified.add((email: email, code: code));
    return verifyResult;
  }

  @override
  Future<AuthResult> updatePassword(String newPassword) async {
    updated.add(newPassword);
    return updateResult;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
  }
}

Future<bool?> pumpDialog(WidgetTester tester, FakeAuthService fake) async {
  bool? outcome;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                outcome = await showForgotPasswordDialog(
                  context,
                  authService: fake,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return outcome;
}

/// Reads the value back out after the dialog has closed.
bool? lastOutcome;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // AuthService touches Supabase.instance in its field initialiser, so the
    // client has to exist even though the fake never calls out.
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });

  testWidgets('opens on the email step', (tester) async {
    await pumpDialog(tester, FakeAuthService());

    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Send Code'), findsOneWidget);
    // No code or password fields yet.
    expect(find.text('8-digit code'), findsNothing);
    expect(find.text('New Password'), findsNothing);
  });

  testWidgets('rejects an email with no @ and does not call the service', (
    tester,
  ) async {
    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    expect(fake.sentTo, isEmpty);
    expect(find.text('Reset Password'), findsOneWidget); // still step 1
  });

  testWidgets('surfaces a send failure and stays on the email step', (
    tester,
  ) async {
    final fake = FakeAuthService(
      sendResult: const AuthResult(
        success: false,
        error: 'No internet connection.',
      ),
    );
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Reset Password'), findsOneWidget);
  });

  testWidgets('advances to the code step and shows the target address', (
    tester,
  ) async {
    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    expect(fake.sentTo, ['teacher@ctu.edu.ph']);
    expect(find.text('Enter Code'), findsOneWidget);
    expect(
      find.textContaining('teacher@ctu.edu.ph'),
      findsOneWidget,
      reason: 'the blurb should name the address the code went to',
    );
    expect(find.widgetWithText(ElevatedButton, 'Verify Code'), findsOneWidget);
  });

  testWidgets('a wrong code keeps the user on the code step', (tester) async {
    final fake = FakeAuthService(
      verifyResult: const AuthResult(
        success: false,
        error: 'Incorrect code. Please check the email and try again.',
      ),
    );
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '00000000');
    await tester.pumpAndSettle();

    expect(fake.verified.single.code, '00000000');
    expect(
      find.text('Incorrect code. Please check the email and try again.'),
      findsOneWidget,
    );
    expect(find.text('Enter Code'), findsOneWidget);
  });

  testWidgets('resend re-sends to the same address', (tester) async {
    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();

    expect(fake.sentTo, ['teacher@ctu.edu.ph', 'teacher@ctu.edu.ph']);
  });

  testWidgets('full happy path: email -> code -> new password', (tester) async {
    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    // step 1
    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    // step 2 — a full-length code auto-submits
    await tester.enterText(find.byType(TextField).first, '12345678');
    await tester.pumpAndSettle();
    expect(
      fake.verified.single,
      (email: 'teacher@ctu.edu.ph', code: '12345678'),
    );

    // step 3
    expect(find.text('Set New Password'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget); // field label
    expect(find.text('Confirm Password'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), r'NewPass1!');
    await tester.enterText(fields.at(1), r'NewPass1!');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Password'));
    await tester.pumpAndSettle();

    expect(fake.updated, [r'NewPass1!']);
    expect(fake.signOutCount, 1, reason: 'recovery session must be cleared');
    // dialog closed
    expect(find.text('Set New Password'), findsNothing);
  });

  testWidgets('mismatched confirmation blocks the update', (tester) async {
    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12345678');
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), r'NewPass1!');
    await tester.enterText(fields.at(1), r'Different1!');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Password'));
    await tester.pumpAndSettle();

    expect(find.text('The two passwords do not match.'), findsOneWidget);
    expect(fake.updated, isEmpty);
  });

  testWidgets('a weak password blocks the update', (tester) async {
    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12345678');
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'weakpass');
    await tester.enterText(fields.at(1), 'weakpass');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('at least 8 characters'), findsWidgets);
    expect(fake.updated, isEmpty);
  });

  testWidgets('a code shorter than the full length is rejected locally', (
    tester,
  ) async {
    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    // 6 digits when the project issues 8 — must not reach the service.
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Verify Code'));
    await tester.pumpAndSettle();

    expect(fake.verified, isEmpty);
    expect(find.textContaining('8-digit code'), findsWidgets);
  });

  testWidgets('the code field fits on a narrow phone without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakeAuthService();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'teacher@ctu.edu.ph');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '88888888');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
