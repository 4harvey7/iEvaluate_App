import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:ievaluateapp_final/widgets/apple_ui.dart';

/// AppleSectionHeader is a Row whose first child is Expanded. That means it
/// MUST be given a bounded width. Putting it inside another Row as a plain
/// (non-flex) child hands it unbounded width, and the resulting layout error
/// leaves the render object permanently NEEDS-LAYOUT — Flutter re-runs layout
/// every frame, pins the UI thread, and Android reports the app as not
/// responding. That is what happened on the instructor subject detail screen.
///
/// These tests lock in the safe shapes.
void main() {
  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [body],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lays out as a plain Column child', (tester) async {
    await pump(tester, const AppleSectionHeader(title: 'I. Management'));
    expect(tester.takeException(), isNull);
    expect(find.text('I. Management'), findsOneWidget);
  });

  testWidgets('lays out with a trailing action — the shape used for the '
      'Student Feedback count', (tester) async {
    await pump(
      tester,
      const AppleSectionHeader(
        title: 'Student Feedback',
        action: Text('2 of 2'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Student Feedback'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('lays out with a subtitle', (tester) async {
    await pump(
      tester,
      const AppleSectionHeader(title: 'Overview', subtitle: '5 subjects'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('5 subjects'), findsOneWidget);
  });

  testWidgets('a long title with an action does not overflow on a narrow '
      'phone', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: AppleSectionHeader(
              title: 'Per-Question Visualization Breakdown',
              action: Text('120 of 240'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('inside a Row it MUST be given bounded width', (tester) async {
    // Documents the failure mode. Deliberately a single pump(): the broken
    // shape never finishes layout, so pumpAndSettle() would spin forever -
    // which is precisely the ANR the instructor screen was hitting.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Row(
            children: [
              AppleSectionHeader(title: 'Student Feedback'),
              Text('2 of 2'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.takeException(),
      isNotNull,
      reason: 'unbounded width must surface as an error, not silent jank',
    );
  });

  testWidgets('inside a Row, wrapping in Expanded is the safe escape hatch', (
    tester,
  ) async {
    await pump(
      tester,
      Row(
        children: const [
          Expanded(child: AppleSectionHeader(title: 'Student Feedback')),
          Text('2 of 2'),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
