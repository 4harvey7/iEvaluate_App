import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../models/subject.dart';
import '../../widgets/pressable.dart';

class SubjectCard extends StatelessWidget {
  final Subject subject;
  final VoidCallback onTap;
  final bool showMetrics;

  const SubjectCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.showMetrics = true,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Subject code badge — tinted brand pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                subject.code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryText,
                                  fontSize: 12,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              subject.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                letterSpacing: -0.3,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildScoreBadge(subject.overallMean),
                    ],
                  ),
                  if (showMetrics) ...[
                    const SizedBox(height: 14),
                    Container(height: 1, color: AppColors.borderHairline),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildMiniMetric(
                          Icons.settings_suggest_outlined,
                          'Mgmt: ${subject.managementMean?.toStringAsFixed(2) ?? "N/A"}',
                          AppColors.primaryText,
                        ),
                        const SizedBox(width: 8),
                        _buildMiniMetric(
                          Icons.psychology_outlined,
                          'Perf: ${subject.performanceMean?.toStringAsFixed(2) ?? "N/A"}',
                          AppColors.success,
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBadge(double score) {
    Color color = Subject.getScoreColor(score);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            score > 0 ? score.toStringAsFixed(2) : 'N/A',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 15,
            ),
          ),
          if (score > 0)
            Text(
              Subject.getVDCode(score),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
