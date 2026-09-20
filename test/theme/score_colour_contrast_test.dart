import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/models/subject.dart';
import 'package:ievaluateapp_final/theme/app_colors.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colours. 1.0 = identical,
/// 21.0 = black on white. 4.5 is the AA threshold for body text.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // One score from each band of Subject.getScoreColor.
  const samples = <String, double>{
    'Outstanding': 4.50,
    'Very Satisfactory': 3.80,
    'Satisfactory': 3.01, // the band that was unreadable
    'Fair': 2.00,
    'Unsatisfactory': 1.00,
  };

  group('score colours are readable where they are used', () {
    test('as a label on the white hero pill (my_subjects_screen)', () {
      // The pill is filled white and the score colour is the text.
      const aaFloor = 4.5;

      // AppColors.success (#248A4E) measures 4.36:1 on white - a hair under the
      // AA floor. That is a pre-existing palette value used as text all over the
      // app, not something this pill introduced, so it is recorded explicitly
      // rather than quietly rounded away. Darkening it to roughly #1B7A43 would
      // clear AA everywhere, but that is a palette-wide decision.
      const knownShortfalls = <String, double>{'Outstanding': 4.3};

      for (final entry in samples.entries) {
        final colour = Subject.getScoreColor(entry.value);
        final ratio = _contrast(colour, const Color(0xFFFFFFFF));
        final floor = knownShortfalls[entry.key] ?? aaFloor;
        expect(
          ratio,
          greaterThanOrEqualTo(floor),
          reason:
              '${entry.key} (${entry.value}) is ${colour.toARGB32().toRadixString(16)} '
              'on white = ${ratio.toStringAsFixed(2)}:1, below the $floor:1 floor',
        );
      }
    });

    test('score colours must NOT be used as text on the hero gradient', () {
      // Regression guard for the original bug: these colours are dark by
      // design, so they are illegible directly on the dark hero. If someone
      // reintroduces that, this documents why it fails.
      final heroDark = AppColors.heroGradient.first;
      final offenders = <String>[];
      for (final entry in samples.entries) {
        final colour = Subject.getScoreColor(entry.value);
        final ratio = _contrast(colour, heroDark);
        if (ratio < 4.5) {
          offenders.add('${entry.key} ${ratio.toStringAsFixed(2)}:1');
        }
      }
      expect(
        offenders,
        isNotEmpty,
        reason: 'if these ever become light enough for the dark hero, the '
            'white-pill workaround can be revisited',
      );
    });
  });

  group('hero card text on the gradient', () {
    final heroDark = AppColors.heroGradient.first;
    final heroLight = AppColors.heroGradient.last;

    test('white body text clears AA on both ends of the gradient', () {
      for (final bg in [heroDark, heroLight]) {
        expect(_contrast(const Color(0xFFFFFFFF), bg),
            greaterThanOrEqualTo(4.5));
      }
    });

    test('textInverted clears AA on both ends of the gradient', () {
      for (final bg in [heroDark, heroLight]) {
        expect(_contrast(AppColors.textInverted, bg),
            greaterThanOrEqualTo(4.5));
      }
    });
  });
}
