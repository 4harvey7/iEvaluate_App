import 'package:flutter/material.dart';
import '../../core/utils/sast_rating.dart';

class Subject {
  final String? id; // UUID from database
  final String code;
  final String name;
  final DateTime addedAt;
  final double? managementMean;
  final double? performanceMean;

  /// New 15-item SET overall % for this subject (null for old-form terms).
  final double? setPct;

  /// All subject IDs that map to this subject code in the current term.
  /// Populated by SubjectsProvider to avoid cross-term ID contamination.
  final Set<String> allRelatedIds;

  const Subject({
    this.id,
    required this.code,
    required this.name,
    required this.addedAt,
    this.managementMean,
    this.performanceMean,
    this.setPct,
    Set<String>? allRelatedIds,
  }) : allRelatedIds = allRelatedIds ?? const {};

  Map<String, dynamic> toJson() => {
    'id': id,
    'subject_code': code,
    'subject_name': name,
    'created_at': addedAt.toUtc().toIso8601String(),
    // Keep the model-facing key for local caches and compatibility while
    // retaining `created_at`, which mirrors the database column.
    'addedAt': addedAt.toUtc().toIso8601String(),
    'management_mean': managementMean,
    'performance_mean': performanceMean,
  };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    id: json['id'] as String?,
    code: json['subject_code'] as String,
    name: json['subject_name'] as String,
    // tryParse: a null/blank created_at must not throw inside a build method.
    addedAt:
        DateTime.tryParse(
          (json['created_at'] ?? json['addedAt'] ?? '').toString(),
        ) ??
        DateTime.now(),
    managementMean: (json['management_mean'] as num?)?.toDouble(),
    performanceMean: (json['performance_mean'] as num?)?.toDouble(),
    setPct: (json['set_pct'] as num?)?.toDouble(),
    allRelatedIds: json['all_ids'] is Set<String>
        ? json['all_ids'] as Set<String>
        : (json['all_ids'] is Iterable
              ? Set<String>.from(
                  (json['all_ids'] as Iterable).map((e) => e.toString()),
                )
              : null),
  );

  /// Overall for this subject, from its two stored category means:
  /// ROUND((Management + Performance) / 2, 2), or whichever side exists.
  /// Null when the subject has no answers yet (never 0).
  double? get overallMean => SastRating.combine(managementMean, performanceMean);

  String get verbalDescription => getVerbalDescription(overallMean);

  // Thin wrappers kept so existing callers keep compiling; the thresholds
  // live in SastRating so the screens and the PDF can never disagree.
  static String getVerbalDescription(double? score) => SastRating.verbal(score);

  static String getVDCode(double? score) => SastRating.code(score);

  static Color getScoreColor(double? score) => SastRating.color(score);
}
