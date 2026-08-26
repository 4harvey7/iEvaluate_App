import 'package:flutter/material.dart';

/// Semantic colors for iEvaluate's calm, institutional Apple-inspired UI.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0066CC);
  static const Color primaryDeep = Color(0xFF004C99);
  static const Color primaryTint = Color(0xFFDDEEFF);
  static const Color accent = Color(0xFF5AC8FA);
  static const Color indigo = Color(0xFF5856D6);
  static const Color teal = Color(0xFF00A6A6);
  static const Color purple = Color(0xFF8A5CF6);
  static const Color rose = Color(0xFFE54872);

  // Surfaces
  // The page tint stays translucent so the ambient backdrop can softly show
  // through without exposing the previous route at full strength.
  static const Color background = Color(0xD9EDF4FC);
  // `surface` is intentionally translucent so legacy screen containers also
  // participate in the glass system. Use `solidSurface` only as an
  // accessibility fallback or where compositing would reduce legibility.
  static const Color solidSurface = Color(0xFFFFFFFF);
  static const Color surface = Color(0xD9FFFFFF);
  static const Color surfaceElevated = Color(0xD9F8FAFD);
  static const Color surfaceMuted = Color(0xB8E4ECF6);
  static const Color glass = Color(0xB8FFFFFF);
  static const Color glassStrong = Color(0xD9FFFFFF);
  static const Color glassSubtle = Color(0x8FFFFFFF);
  static const Color glassBorder = Color(0xD0FFFFFF);
  static const Color glassShadow = Color(0x1F173B63);

  static const List<Color> ambientGradient = [
    Color(0xFFF6FAFF),
    Color(0xFFE7F2FF),
    Color(0xFFF2EDFF),
  ];

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

  static const List<Color> chartPalette = [
    primary,
    teal,
    indigo,
    warning,
    rose,
    purple,
  ];

  // Convenience for hero gradients
  static const List<Color> heroGradient = [Color(0xFF0B3B68), primary];
}
