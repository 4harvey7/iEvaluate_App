import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class Subject {
  final String? id; // UUID from database
  final String code;
  final String name;
  final String? section;
  final DateTime addedAt;
  final double? managementMean;
  final double? performanceMean;
  /// All subject IDs that map to this subject code in the current term.
  /// Populated by SubjectsProvider to avoid cross-term ID contamination.
  final Set<String> allRelatedIds;

  const Subject({
    this.id,
    required this.code,
    required this.name,
    this.section,
    required this.addedAt,
    this.managementMean,
    this.performanceMean,
    Set<String>? allRelatedIds,
  }) : allRelatedIds = allRelatedIds ?? const {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject_code': code,
        'subject_name': name,
        'section': section,
        'created_at': addedAt.toUtc().toIso8601String(),
        'management_mean': managementMean,
        'performance_mean': performanceMean,
      };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        id: json['id'] as String?,
        code: json['subject_code'] as String,
        name: json['subject_name'] as String,
        section: json['section'] as String?,
        addedAt: DateTime.parse(json['created_at'] as String),
        managementMean: (json['management_mean'] as num?)?.toDouble(),
        performanceMean: (json['performance_mean'] as num?)?.toDouble(),
        allRelatedIds: json['all_ids'] is Set<String>
            ? json['all_ids'] as Set<String>
            : (json['all_ids'] is Iterable
                ? Set<String>.from((json['all_ids'] as Iterable).map((e) => e.toString()))
                : null),
      );

  double get overallMean {
    if (managementMean != null && performanceMean != null) {
      return (managementMean! + performanceMean!) / 2;
    }
    return managementMean ?? performanceMean ?? 0.0;
  }

  String get verbalDescription => getVerbalDescription(overallMean);

  static String getVerbalDescription(double score) {
    if (score >= 4.20) return 'Outstanding';
    if (score >= 3.40) return 'Very Satisfactory';
    if (score >= 2.60) return 'Satisfactory';
    if (score >= 1.80) return 'Fair';
    if (score > 0) return 'Unsatisfactory';
    return 'N/A';
  }

  static String getVDCode(double score) {
    if (score >= 4.20) return 'O';
    if (score >= 3.40) return 'VS';
    if (score >= 2.60) return 'S';
    if (score >= 1.80) return 'F';
    if (score > 0) return 'US';
    return '-';
  }

  static Color getScoreColor(double score) {
    if (score >= 4.20) return AppColors.success;
    if (score >= 3.40) return AppColors.primary;
    if (score >= 2.60) return AppColors.textPrimary;
    if (score >= 1.80) return AppColors.warning;
    if (score > 0) return AppColors.error;
    return AppColors.textPrimary;
  }
}
