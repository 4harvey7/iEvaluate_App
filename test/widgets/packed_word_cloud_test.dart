import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/widgets/packed_word_cloud.dart';

void main() {
  final freq = <String, int>{
    for (var i = 0; i < 80; i++) 'word${String.fromCharCode(97 + i % 26)}${i ~/ 26}': (80 / (i + 1)).ceil(),
    'instructor': 99,
  };

  Future<void> pump(WidgetTester t, double w, double h, {bool dark = false}) => t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(width: w, child: PackedWordCloud(frequencies: freq, height: h, onDarkBackground: dark)),
          ),
        ),
      );

  testWidgets('renders words with no overflow in a small box', (t) async {
    await pump(t, 180, 110);
    expect(tester(t), isNull);
    expect(find.text('instructor'), findsOneWidget);
    expect(find.byType(RotatedBox), findsWidgets);
  });

  testWidgets('renders on dark background at normal size', (t) async {
    await pump(t, 340, 240, dark: true);
    expect(t.takeException(), isNull);
    expect(find.text('instructor'), findsOneWidget);
  });

  testWidgets('empty frequencies render nothing and do not throw', (t) async {
    await t.pumpWidget(const MaterialApp(home: PackedWordCloud(frequencies: {})));
    expect(t.takeException(), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();
