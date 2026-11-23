import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/widgets/apple_ui.dart';

/// DEF-V6: the Users / Personnel tabs remove the search field while loading
/// and build a new one afterwards. With a screen-owned controller the new
/// field must show the text that is still filtering the list.
void main() {
  testWidgets('a remounted field keeps the text of a shared controller',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    Widget host({required bool loading}) => MaterialApp(
          home: Scaffold(
            body: loading
                ? const SizedBox()
                : AppleSearchField(controller: controller),
          ),
        );

    await tester.pumpWidget(host(loading: false));
    await tester.enterText(find.byType(TextField), 'Throwaway');

    await tester.pumpWidget(host(loading: true)); // auto-refresh starts
    await tester.pumpWidget(host(loading: false)); // and finishes

    expect(find.text('Throwaway'), findsOneWidget);
  });
}
