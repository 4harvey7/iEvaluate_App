import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Inter / Inter Tight typography scale tuned to feel iOS-premium.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get displayLarge => GoogleFonts.interTight(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: AppColors.textPrimary,
        height: 1.1,
      );

  static TextStyle get displayMedium => GoogleFonts.interTight(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: AppColors.textPrimary,
        height: 1.15,
      );

  static TextStyle get displaySmall => GoogleFonts.interTight(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get titleLarge => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
        height: 1.25,
      );

  static TextStyle get titleMedium => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get titleSmall => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.35,
      );

  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.45,
      );

  static TextStyle get bodySmall => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.45,
      );

  static TextStyle get labelLarge => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get labelMedium => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  /// Small uppercase metadata, iOS-style ALL-CAPS captions.
  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppColors.textSecondary,
      );
}
