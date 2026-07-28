import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart';
import 'package:ievaluateapp_final/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App launches and renders the login portal title',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = SubjectsProvider();
    await provider.load();

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('iEvaluate Portal'), findsOneWidget);
  });
}
