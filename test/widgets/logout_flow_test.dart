import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/auth_service.dart';
import 'package:ievaluateapp_final/login_screen.dart';
import 'package:ievaluateapp_final/widgets/logout_confirmation_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuth extends AuthService {
  int signOutCount = 0;
  @override
  Future<void> signOut() async => signOutCount++;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
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

  // DEF-V11: settings screens live in a tab's nested Navigator; signing out
  // from there used to push Login inside the tab and leave the overlay up.
  testWidgets('sign-out from a nested navigator clears the overlay and shows Login', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (context) => TextButton(
              onPressed: () => confirmAndSignOut(context, auth),
              child: const Text('Sign Out Securely'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Sign Out Securely'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pump();
    expect(find.text('Signing you out…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(auth.signOutCount, 1);
    expect(find.text('Signing you out…'), findsNothing);
    expect(find.text('Sign Out Securely'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('Cancel keeps the user signed in', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => confirmAndSignOut(context, auth),
          child: const Text('Sign Out Securely'),
        ),
      ),
    ));
    await tester.tap(find.text('Sign Out Securely'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.signOutCount, 0);
    expect(find.text('Sign Out Securely'), findsOneWidget);
  });
}
