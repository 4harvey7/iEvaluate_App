// eval_report_widgets.dart
// Shared widgets for the new 15-item reports (SET student form, SUP supervisor
// form): percent + verbal badge, A/B/C section bars, 15-item list, and the
// full report body used by the instructor and department head screens.
import 'package:flutter/material.dart';
import '../core/services/eval_results_service.dart';
import '../core/utils/sast_rating.dart';
import '../theme/app_colors.dart';
import 'apple_ui.dart';

/// "86.5%  Outstanding" pill.
class EvalPctBadge extends StatelessWidget {
  final double? pct;
  final String? label;
  final bool large;
  const EvalPctBadge({super.key, required this.pct, this.label, this.large = false});

  @override
  Widget build(BuildContext context) {
    final color = SastRating.colorPct(pct);
    final verbal = label ?? SastRating.verbalPct(pct);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 10 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(SastRating.formatPct(pct, empty: 'N/A'),
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: large ? 26 : 14)),
          Text(verbal, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: large ? 12 : 10)),
        ],
      ),
    );
  }
}

/// Horizontal % bar, one per section.
class EvalSectionBars extends StatelessWidget {
  final EvalScope scope;
  const EvalSectionBars({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    final codes = scope.sectionTitles.keys.toList()..sort();
    return Column(
      children: [
        for (final c in codes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('$c. ${scope.sectionTitles[c]}',
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    ),
                    Text(SastRating.formatPct(scope.sectionPct[c]),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: SastRating.colorPct(scope.sectionPct[c]))),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ((scope.sectionPct[c] ?? 0) / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation(SastRating.colorPct(scope.sectionPct[c])),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// All items grouped by section; the lowest [improveCount] are highlighted.
class EvalItemList extends StatelessWidget {
  final EvalScope scope;
  final int improveCount;
  const EvalItemList({super.key, required this.scope, this.improveCount = 3});

  @override
  Widget build(BuildContext context) {
    final scored = scope.items.where((i) => scope.itemMean[i.no] != null).toList()
      ..sort((a, b) => scope.itemMean[a.no]!.compareTo(scope.itemMean[b.no]!));
    final weak = {for (final i in scored.take(improveCount)) i.no};
    final codes = scope.sectionTitles.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in codes) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text('$c. ${scope.sectionTitles[c]}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
          for (final i in scope.items.where((x) => x.section == c)) _row(i, weak.contains(i.no)),
        ],
      ],
    );
  }

  Widget _row(EvalItemInfo i, bool isWeak) {
    final mean = scope.itemMean[i.no];
    final color = isWeak ? AppColors.warning : AppColors.textPrimary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isWeak ? AppColors.warning.withValues(alpha: 0.08) : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isWeak ? AppColors.warning.withValues(alpha: 0.4) : AppColors.borderHairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Text('${i.no}.', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.text, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                if (isWeak)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text('Area to improve',
                        style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(SastRating.format(mean), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// One instrument's card: badge, respondents, section bars and (optionally) items.
class EvalScopeCard extends StatelessWidget {
  final EvalScope scope;
  final String heading;
  final bool showItems;
  const EvalScopeCard({super.key, required this.scope, required this.heading, this.showItems = true});

  @override
  Widget build(BuildContext context) {
    final n = scope.respondents;
    final who = scope.evaluatorType == 'supervisor' ? 'evaluation' : 'respondent';
    return AppleSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(heading, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('$n $who${n == 1 ? '' : 's'}${scope.excluded > 0 ? ' (${scope.excluded} excluded: fewer than 5 answers)' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              EvalPctBadge(pct: scope.pct, label: scope.verbalLabel, large: true),
            ],
          ),
          const SizedBox(height: 16),
          EvalSectionBars(scope: scope),
          if (showItems) ...[
            const Divider(height: 24),
            const Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            EvalItemList(scope: scope),
          ],
        ],
      ),
    );
  }
}

/// Comments list (anonymous).
class EvalCommentsCard extends StatelessWidget {
  final String title;
  final List<String> comments;
  const EvalCommentsCard({super.key, required this.title, required this.comments});

  @override
  Widget build(BuildContext context) {
    return AppleSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          if (comments.isEmpty)
            const Text('No comments.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
          else
            for (final c in comments)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
                child: Text(c, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              ),
        ],
      ),
    );
  }
}

/// Full new-form report body: student SET card, comments, and a separate
/// supervisor card when SUP-15 results exist.
class EvalReportView extends StatelessWidget {
  final EvalReport report;
  const EvalReportView({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final s = report.student;
    final v = report.supervisor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s != null) ...[
          EvalScopeCard(scope: s, heading: 'Student evaluation (SET)'),
          const SizedBox(height: 16),
          EvalCommentsCard(title: 'Student comments (anonymous)', comments: report.studentComments),
        ] else
          const AppleEmptyState(
            icon: Icons.assessment_outlined,
            title: 'No student evaluation results yet',
            message: 'Student SET results will appear here once the forms have been processed.',
          ),
        if (v != null) ...[
          const SizedBox(height: 16),
          EvalScopeCard(scope: v, heading: "Supervisor's evaluation"),
          if (report.supervisorComments.isNotEmpty) ...[
            const SizedBox(height: 16),
            EvalCommentsCard(title: "Supervisor's comments", comments: report.supervisorComments),
          ],
        ],
      ],
    );
  }
}
