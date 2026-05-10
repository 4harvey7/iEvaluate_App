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

  // Surfaces
  static const Color background = Color(0xFFFFF9EB); // Vanilla Custard
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFEF8);

  // Text
  static const Color textPrimary = Color(0xFF200F07); // Midnight Espresso
  static Color get textSecondary => textPrimary.withOpacity(0.60);
  static Color get textTertiary => textPrimary.withOpacity(0.40);
  static const Color textInverted = Color(0xFFFFF9EB);

  /// Pre-baked alpha variants of [textInverted] for use in const contexts
  /// (e.g. `const TextStyle(color: AppColors.textInvertedDim)`), where
  /// `.withOpacity()` would break const-ness.
  static const Color textInvertedDim = Color(0xB3FFF9EB); // ~70% opacity
  static const Color textInvertedFaint = Color(0x3DFFF9EB); // ~24% opacity

  // Borders / dividers
  static Color get borderHairline => textPrimary.withOpacity(0.08);
  static Color get borderSubtle => textPrimary.withOpacity(0.12);

  // Status (warm-paired so they sit next to the orange without clashing)
  static const Color success = Color(0xFF2E7D5A);
  static const Color warning = Color(0xFFC97419);
  static const Color error = Color(0xFFC2410C);

  // Convenience for hero gradients
  static List<Color> get heroGradient => [
        textPrimary,
        textPrimary.withOpacity(0.85),
      ];
}
