// Covers the SAO admin's "Activate account" dialog:
//
//   * the admin is asked for the real email ONLY -- no ID / address fields
//   * the email is validated before anything is sent
//   * a server error keeps the dialog open with the reason
//   * success switches to the instructions view; Done resolves true
//   * "already activated" disables the form and Close still asks for a refresh
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/account_activation_service.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:ievaluateapp_final/widgets/activate_account_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeActivationService extends AccountActivationService {
  FakeActivationService(this.result);

  AccountActivationResult result;
  final List<Map<String, String>> calls = [];

  @override
  Future<AccountActivationResult> activate({
    required String userId,
    required String email,
  }) async {
    calls.add({'userId': userId, 'email': email});
    return result;
  }
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

  final emailField = find.byKey(const Key('activateAccount.email'));
  final confirm = find.byKey(const Key('activateAccount.confirm'));
  final cancel = find.byKey(const Key('activateAccount.cancel'));

  /// Pumps a button that opens the dialog; returns a getter for its result.
  Future<bool? Function()> open(
    WidgetTester tester,
    FakeActivationService service,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showActivateAccountDialog(
                  context,
                  userId: 'user-1',
                  fullName: 'Juan Cruz',
                  subtitle: 'College of Technology',
                  service: service,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  const ok = AccountActivationResult.ok(
    email: 'juan.cruz@ctu.edu.ph',
    passwordSetupRequired: true,
  );

  testWidgets('asks for the real email only', (tester) async {
    await open(tester, FakeActivationService(ok));
    expect(find.text('Activate account'), findsOneWidget);
    expect(emailField, findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('activateAccount.id')), findsNothing);
    expect(find.byKey(const Key('activateAccount.street')), findsNothing);
    expect(tester.widget<TextField>(emailField).controller!.text, isEmpty);
  });

  testWidgets('invalid email is not sent', (tester) async {
    final service = FakeActivationService(ok);
    await open(tester, service);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Email is required'), findsWidgets);
    expect(service.calls, isEmpty);

    await tester.enterText(emailField, 'placeholder-x@ievaluate.internal');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('real email'), findsWidgets);
    expect(service.calls, isEmpty);
  });

  testWidgets('success shows instructions and Done resolves true', (tester) async {
    final service = FakeActivationService(ok);
    final result = await open(tester, service);

    await tester.enterText(emailField, 'juan.cruz@ctu.edu.ph');
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(service.calls.single, {'userId': 'user-1', 'email': 'juan.cruz@ctu.edu.ph'});
    expect(find.text('Account activated'), findsOneWidget);
    expect(find.textContaining('Forgot Password?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('activateAccount.done')));
    await tester.pumpAndSettle();
    expect(result(), isTrue);
  });

  testWidgets('email not sent is surfaced on success', (tester) async {
    final service = FakeActivationService(const AccountActivationResult.ok(
      email: 'juan.cruz@ctu.edu.ph',
      passwordSetupRequired: true,
      emailSent: false,
    ));
    await open(tester, service);
    await tester.enterText(emailField, 'juan.cruz@ctu.edu.ph');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be sent'), findsOneWidget);
  });

  testWidgets('server error keeps the dialog open; cancel resolves false', (tester) async {
    final service = FakeActivationService(const AccountActivationResult.failed(
      'This email address already belongs to another account. Use a different address.',
    ));
    final result = await open(tester, service);
    await tester.enterText(emailField, 'taken@ctu.edu.ph');
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.textContaining('already belongs to another account'), findsOneWidget);
    expect(find.text('Activate account'), findsOneWidget);

    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(result(), isFalse);
  });

  testWidgets('already activated: form locked, Close asks for refresh', (tester) async {
    final service = FakeActivationService(const AccountActivationResult.failed(
      'Already activated: this account already has its own login and is approved. Refresh the list.',
      alreadyActivated: true,
    ));
    final result = await open(tester, service);
    await tester.enterText(emailField, 'juan.cruz@ctu.edu.ph');
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(result(), isTrue);
  });
}
