// sast_rating.dart
// One place for how a SAST mean is rounded, labelled, coloured and printed.
//
// The database computes every mean (blank answers excluded, ROUND(..., 2)).
// The app only DISPLAYS those stored values, so a teacher can check them by
// hand: Management mean = average of the M1-M10 means shown, and
// Overall = (Management + Performance) / 2. Nothing here re-averages raw
// answers. A null mean means "nobody answered", which is not the same as 0.
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class SastRating {
  SastRating._();

  /// Shown in place of a mean that has no answers behind it.
  static const String emptyValue = '—';

  /// Verbal description for a missing mean.
  static const String noData = 'No data';

  /// Round to 2 decimals, the same precision the database stores.
  /// Null (or a non-finite value) stays null.
  static double? round2(num? value) {
    if (value == null) return null;
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) return null;
    return (d * 100).round() / 100;
  }

  /// Read a numeric column that PostgREST may hand back as num or String.
  /// Null, blank or unparseable stays null (never 0).
  static double? parse(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString().trim());
  }

  /// Same as [parse] for count columns.
  static int? parseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim());
  }

  /// A mean is usable for a rating only when it is on the 1..5 scale.
  static double? _rated(double? score) {
    final r = round2(score);
    if (r == null || r < 1.0) return null;
    return r;
  }

  /// >= 4.20 Outstanding, >= 3.40 Very Satisfactory, >= 2.60 Satisfactory,
  /// >= 1.80 Fair, >= 1.00 Unsatisfactory, otherwise "No data".
  /// Compared on the value rounded to 2 decimals.
  static String verbal(double? score) {
    final r = _rated(score);
    if (r == null) return noData;
    if (r >= 4.20) return 'Outstanding';
    if (r >= 3.40) return 'Very Satisfactory';
    if (r >= 2.60) return 'Satisfactory';
    if (r >= 1.80) return 'Fair';
    return 'Unsatisfactory';
  }

  /// Short code used in the report tables: O / VS / S / F / US, or "-".
  static String code(double? score) {
    final r = _rated(score);
    if (r == null) return '-';
    if (r >= 4.20) return 'O';
    if (r >= 3.40) return 'VS';
    if (r >= 2.60) return 'S';
    if (r >= 1.80) return 'F';
    return 'US';
  }

  static Color color(double? score) {
    final r = _rated(score);
    if (r == null) return AppColors.textSecondary;
    if (r >= 4.20) return AppColors.success;
    if (r >= 3.40) return AppColors.primary;
    if (r >= 2.60) return AppColors.textPrimary;
    if (r >= 1.80) return AppColors.warning;
    return AppColors.error;
  }

  /// "4.50", or [empty] when the mean is null.
  static String format(double? score, {String empty = emptyValue}) {
    final r = round2(score);
    return r == null ? empty : r.toStringAsFixed(2);
  }

  /// Overall for one subject from its two stored category means, using the
  /// same rule as overall_total_survey: ROUND((mgmt + perf) / 2, 2), and when
  /// one side is null the other side is the overall. Both null -> null.
  /// Only for places that have no stored combined value (per-subject views);
  /// instructor-level screens read combined_score_mean instead.
  static double? combine(double? management, double? performance) {
    if (management == null) return round2(performance);
    if (performance == null) return round2(management);
    return round2((management + performance) / 2);
  }

  /// "2 of 3 answered", or null when either count is unknown (older rows
  /// written before the *_count columns existed).
  static String? answeredLabel(int? answered, int? total) {
    if (answered == null || total == null || total <= 0) return null;
    return '$answered of $total answered';
  }

  /// Average of the non-null values, rounded to 2 decimals; null if none.
  /// Only for aggregates ACROSS instructors (department / school averages),
  /// where no stored value exists. Missing values are skipped, never zero.
  static double? averageOfPresent(Iterable<double?> values) {
    var sum = 0.0;
    var n = 0;
    for (final v in values) {
      if (v == null) continue;
      sum += v;
      n++;
    }
    return n == 0 ? null : round2(sum / n);
  }

  // ---- Percent scale (new 15-item SET / SUP forms) -------------------------

  /// Old SAST mean (1..5) shown on the percent scale: mean / 5 * 100.
  static double? meanToPct(double? mean) => mean == null ? null : round2(mean / 5 * 100);

  /// >= 84 Outstanding, >= 68 Very Satisfactory, >= 52 Satisfactory,
  /// >= 36 Fair, otherwise Unsatisfactory.
  static String verbalPct(double? pct) {
    if (pct == null) return noData;
    if (pct >= 84) return 'Outstanding';
    if (pct >= 68) return 'Very Satisfactory';
    if (pct >= 52) return 'Satisfactory';
    if (pct >= 36) return 'Fair';
    return 'Unsatisfactory';
  }

  static Color colorPct(double? pct) => color(pct == null ? null : pct / 20);

  /// "86.5%", or [empty] when there is no value.
  static String formatPct(double? pct, {String empty = emptyValue}) {
    final r = round2(pct);
    if (r == null) return empty;
    return '${r.toStringAsFixed(r == r.roundToDouble() ? 0 : 1)}%';
  }
}
