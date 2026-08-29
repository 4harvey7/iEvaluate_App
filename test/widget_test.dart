import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart';
import 'package:ievaluateapp_final/login_screen.dart';
import 'package:ievaluateapp_final/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('App launches and renders the login portal title', (
    WidgetTester tester,
  ) async {
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
    final provider = SubjectsProvider();
    await provider.load();

    await tester.pumpWidget(const MyApp(home: LoginScreen()));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('iEvaluate Portal'), findsOneWidget);
  });
}
