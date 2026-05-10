import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/add_subject_screen.dart';
import 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpScreen(WidgetTester tester, SubjectsProvider provider) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SubjectsProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const AddSubjectScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Save button is disabled until both fields are filled',
      (WidgetTester tester) async {
    final provider = SubjectsProvider();
    await provider.load();
    await _pumpScreen(tester, provider);

    final saveFinder = find.widgetWithText(TextButton, 'Save');
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('codeField')), 'cs101');
    await tester.pump();
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('nameField')),
      'Intro to Programming',
    );
    await tester.pump();

    expect(tester.widget<TextButton>(saveFinder).onPressed, isNotNull);
  });

  testWidgets('Code field auto-uppercases input',
      (WidgetTester tester) async {
    final provider = SubjectsProvider();
    await provider.load();
    await _pumpScreen(tester, provider);

    await tester.enterText(find.byKey(const ValueKey('codeField')), 'cs101');
    await tester.pump();

    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('codeField')));
    expect(field.controller!.text, 'CS101');
  });

  testWidgets('Save persists to provider and pops the route',
      (WidgetTester tester) async {
    final provider = SubjectsProvider();
    await provider.load();
    await _pumpScreen(tester, provider);

    await tester.enterText(find.byKey(const ValueKey('codeField')), 'IT305');
    await tester.enterText(
      find.byKey(const ValueKey('nameField')),
      'Web Development',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(provider.subjects.length, 1);
    expect(provider.subjects.first.code, 'IT305');
    expect(provider.subjects.first.name, 'Web Development');
  });
}
