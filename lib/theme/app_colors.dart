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
  // Fully opaque background so the previous route never bleeds through on
  // lower-end Android devices (Impeller / Vulkan path, no compositing layer).
  static const Color background = Color(0xFFEDF4FC);    // was 0xD9 (85%) → now FF (100%)
  // Surfaces are now fully opaque — legibility first, glass feel via gradient.
  static const Color solidSurface = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);        // was 0xD9 → FF
  static const Color surfaceElevated = Color(0xFFF8FAFD); // was 0xD9 → FF
  static const Color surfaceMuted = Color(0xFFE4ECF6);   // was 0xB8 → FF
  // Glass tints — kept slightly transparent for cards but strong enough to be
  // opaque in practice; backdrop blur still fires but nothing shows through.
  static const Color glass = Color(0xF5FFFFFF);          // was 0xB8 → F5 (96%)
  static const Color glassStrong = Color(0xF8FFFFFF);    // was 0xD9 → F8 (97%)
  static const Color glassSubtle = Color(0xEBFFFFFF);    // was 0x8F → EB (92%)
  static const Color glassBorder = Color(0xD0FFFFFF);    // unchanged
  static const Color glassShadow = Color(0x1F173B63);    // unchanged

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

  // ── Score bands ON the hero gradient ───────────────────────────────────────
  // success / warning / error and textPrimary are tuned for white surfaces. On
  // heroGradient they fail: textPrimary (0xFF101828) is near-black on dark blue
  // and effectively invisible, and `primary` IS the gradient's own end stop, so
  // painting a number in it hides it in the background it sits on. These are
  // the same five semantics, lightened to stay legible there.
  static const Color onHeroOutstanding = Color(0xFF7BE8A8);
  static const Color onHeroGood        = Color(0xFFB3DBFF);
  static const Color onHeroNeutral     = Color(0xFFFFFFFF);
  static const Color onHeroFair        = Color(0xFFFFC46B);
  static const Color onHeroPoor        = Color(0xFFFF9E94);
}
