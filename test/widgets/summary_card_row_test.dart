// Mirrors the three-across summary row on the instructor subject detail screen
// (subject_detail_screen.dart, "Summary Cards"). The builder there is a private
// method on the State, so the shape is reproduced here — three Expanded cards
// inside an IntrinsicHeight Row, with the longest real labels. What this guards
// is the thing that actually breaks: overflow when three boxes share one row on
// a narrow phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/models/subject.dart';
import 'package:ievaluateapp_final/theme/app_colors.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';

Widget summaryCard(
  String title,
  double score,
  Color color, {
  bool showDescription = false,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          score.toStringAsFixed(2),
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (showDescription) ...[
          const SizedBox(height: 2),
          Text(
            Subject.getVerbalDescription(score),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
        ],
      ],
    ),
  );
}

void main() {
  Future<void> pumpRow(WidgetTester tester, Size size, double score) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: summaryCard(
                      'Management',
                      score,
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: summaryCard(
                      'Performance',
                      score,
                      AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: summaryCard(
                      'Overall Weighted Mean',
                      score,
                      Subject.getScoreColor(score),
                      showDescription: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in <Size>[
    Size(320, 800), // very narrow phone
    Size(360, 800), // common Android width
    Size(390, 844), // iPhone 14
  ]) {
    testWidgets('three cards fit at ${size.width}dp', (tester) async {
      // 'Very Satisfactory' is the longest verbal description.
      await pumpRow(tester, size, 3.80);

      expect(tester.takeException(), isNull);
      expect(find.text('Management'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Overall Weighted Mean'), findsOneWidget);
      expect(find.text('Very Satisfactory'), findsOneWidget);
    });
  }

  testWidgets('all three cards share one height', (tester) async {
    await pumpRow(tester, const Size(360, 800), 3.80);

    final boxes = find.byType(Container).evaluate().toList();
    expect(boxes.length, greaterThanOrEqualTo(3));

    final heights = find
        .byType(Container)
        .evaluate()
        .take(3)
        .map((e) => tester.getSize(find.byWidget(e.widget)).height)
        .toSet();
    expect(
      heights.length,
      1,
      reason: 'IntrinsicHeight should equalise the three cards',
    );
  });

  testWidgets('every score band renders without overflow', (tester) async {
    for (final score in <double>[4.50, 3.80, 3.01, 2.00, 1.00]) {
      await pumpRow(tester, const Size(320, 800), score);
      expect(
        tester.takeException(),
        isNull,
        reason: 'score $score overflowed',
      );
    }
  });
}
