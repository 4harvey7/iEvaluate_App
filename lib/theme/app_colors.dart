import 'package:flutter/material.dart';

/// iEvaluate brand palette: Vanilla Custard / Vivid Orange / Midnight Espresso.
///
/// Colours are exposed as semantic tokens, not raw names, so theming and
/// repaletting can happen without touching the rest of the app.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFFF77331); // Vivid Orange
  static const Color primaryDeep = Color(0xFFD85A1A);
  static const Color primaryTint = Color(0xFFFFE4D2);

  /// Accessible orange for TEXT, LINKS and informative ICONS on light
  /// surfaces. `primary` (#F77331) only reaches ~2.8:1 contrast on white —
  /// below the WCAG/HIG 4.5:1 minimum for body text — so text must use this
  /// darker shade (5.4:1 on white, 5.2:1 on vanilla) while fills, gradients,
  /// indicators and other large decorative shapes keep the vivid `primary`.
  static const Color primaryText = Color(0xFFB54708);

  // Surfaces
  static const Color background = Color(0xFFFFF9EB); // Vanilla Custard
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFEF8);

  // Text — all pre-baked as const Color so they can sit inside
  // `const TextStyle(...)`, `const Icon(...)`, `const DrawerHeader(...)`
  // and similar const contexts without breaking const-ness.
  static const Color textPrimary = Color(0xFF200F07); // Midnight Espresso
  static const Color textSecondary = Color(0x99200F07); // ~60% opacity
  /// Decorative / disabled ONLY (2.6:1 — below the 4.5:1 minimum).
  /// Never use for text that carries information; use [textSecondary].
  static const Color textTertiary = Color(0x66200F07); // ~40% opacity
  static const Color textInverted = Color(0xFFFFF9EB);
  static const Color textInvertedDim = Color(0xB3FFF9EB); // ~70% opacity
  static const Color textInvertedFaint = Color(0x3DFFF9EB); // ~24% opacity

  // Borders / dividers
  static const Color borderHairline = Color(0x14200F07); // ~8% opacity
  static const Color borderSubtle = Color(0x1F200F07); // ~12% opacity

  // Status (warm-paired so they sit next to the orange without clashing)
  static const Color success = Color(0xFF2E7D5A);
  static const Color warning = Color(0xFF9A5B00); // 5.4:1 on white (was #C97419, 3.5:1)
  static const Color error = Color(0xFFC2410C);

  // Convenience for hero gradients
  static List<Color> get heroGradient => [
        textPrimary,
        textPrimary.withValues(alpha: 0.85),
      ];
}
