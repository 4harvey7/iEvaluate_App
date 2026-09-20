import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:ievaluateapp_final/widgets/apple_ui.dart';

void main() {
  testWidgets('Apple loading state renders a reduced-motion phone skeleton', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: AppleLoadingState(label: 'Loading faculty roster…'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading faculty roster…'), findsOneWidget);
    expect(find.byType(FractionallySizedBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
