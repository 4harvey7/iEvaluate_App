import 'package:flutter/material.dart';

/// Semantic colors for iEvaluate's calm, institutional Apple-inspired UI.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0066CC);
  static const Color primaryDeep = Color(0xFF004C99);
  static const Color primaryTint = Color(0xFFDDEEFF);
  static const Color accent = Color(0xFF5AC8FA);

  // Surfaces
  static const Color background = Color(0xFFF2F4F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF8FAFD);
  static const Color surfaceMuted = Color(0xFFE9EDF3);
  static const Color glass = Color(0xE8FFFFFF);

  // Text — all pre-baked as const Color so they can sit inside
  // `const TextStyle(...)`, `const Icon(...)`, `const DrawerHeader(...)`
  // and similar const contexts without breaking const-ness.
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xA34B5565);
  static const Color textTertiary = Color(0x995F6B7A);
  static const Color textInverted = Color(0xFFFFFFFF);
  static const Color textInvertedDim = Color(0xC7FFFFFF);
  static const Color textInvertedFaint = Color(0x52FFFFFF);

  // Borders / dividers
  static const Color borderHairline = Color(0x14212B3B);
  static const Color borderSubtle = Color(0x24212B3B);

  static const Color success = Color(0xFF248A4E);
  static const Color warning = Color(0xFFB85C00);
  static const Color error = Color(0xFFD92D20);

  // Convenience for hero gradients
  static const List<Color> heroGradient = [Color(0xFF0B3B68), primary];
}
