import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../models/subject.dart';
import '../../widgets/apple_ui.dart';

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppleSurface(
        onTap: onTap,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.code.toUpperCase(),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subject.name,
                        style: AppTextStyles.titleMedium,
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildMiniMetric(
                    Icons.settings_suggest_outlined,
                    'Management ${subject.managementMean?.toStringAsFixed(2) ?? "N/A"}',
                    AppColors.primary,
                  ),
                  _buildMiniMetric(
                    Icons.psychology_outlined,
                    'Performance ${subject.performanceMean?.toStringAsFixed(2) ?? "N/A"}',
                    AppColors.success,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBadge(double score) {
    Color color = Subject.getScoreColor(score);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            score > 0 ? score.toStringAsFixed(2) : 'N/A',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
          if (score > 0)
            Text(
              Subject.getVDCode(score),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
