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

  // Text — all pre-baked as const Color so they can sit inside
  // `const TextStyle(...)`, `const Icon(...)`, `const DrawerHeader(...)`
  // and similar const contexts without breaking const-ness.
  static const Color textPrimary = Color(0xFF200F07); // Midnight Espresso
  static const Color textSecondary = Color(0x99200F07); // ~60% opacity
  static const Color textTertiary = Color(0x66200F07); // ~40% opacity
  static const Color textInverted = Color(0xFFFFF9EB);
  static const Color textInvertedDim = Color(0xB3FFF9EB); // ~70% opacity
  static const Color textInvertedFaint = Color(0x3DFFF9EB); // ~24% opacity

  // Borders / dividers
  static const Color borderHairline = Color(0x14200F07); // ~8% opacity
  static const Color borderSubtle = Color(0x1F200F07); // ~12% opacity

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
