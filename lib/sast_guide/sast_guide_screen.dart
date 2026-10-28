// lib/sast_guide/sast_guide_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/system_settings_service.dart';
import '../theme/app_colors.dart';
import 'sast_guide_content.dart';
import 'sast_guide_logic.dart';

class SastGuideGate {
  static bool _showing = false;

  /// Opens the guide from Settings (no acknowledge button).
  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SastGuideScreen()));

  /// Auto-shows once per semester. Never throws; does nothing if the term
  /// can't be loaded.
  static Future<void> maybeShow(BuildContext context) async {
    if (_showing) return;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final settings = await SystemSettingsService().getSettings();
      final termId = settings.termId?.toString();
      final prefs = await SharedPreferences.getInstance();
      if (termId == null ||
          !sastGuideShouldShow(prefs: prefs, userId: userId, termId: termId)) {
        return;
      }
      if (!context.mounted) return;
      _showing = true;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SastGuideScreen(
          onAcknowledge: () => sastGuideAcknowledge(
              prefs: prefs, userId: userId, termId: termId),
        ),
      ));
    } catch (e) {
      debugPrint('SAST guide auto-show skipped: $e');
    } finally {
      _showing = false;
    }
  }
}

class SastGuideScreen extends StatelessWidget {
  /// When set, a bottom "I have read this" button is shown.
  final Future<void> Function()? onAcknowledge;
  const SastGuideScreen({super.key, this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final sections = sastGuideSections();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(sastGuideTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(sastGuideSubtitle,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
                  const SizedBox(height: 16),
                  for (var i = 0; i < sections.length; i++)
                    _SectionCard(
                        section: sections[i], initiallyExpanded: i == 0),
                  const SizedBox(height: 8),
                  const Text(sastGuideFooter,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            if (onAcknowledge != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      try {
                        await onAcknowledge!();
                      } catch (_) {}
                      nav.pop();
                    },
                    child: const Text('I have read this'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final SastGuideSection section;
  final bool initiallyExpanded;
  const _SectionCard({required this.section, required this.initiallyExpanded});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Row(children: [
            Icon(section.icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(section.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ),
          ]),
          children: [
            _ListBlock(
                label: 'DO',
                color: AppColors.success,
                icon: Icons.check_circle_outline,
                items: section.dos),
            const SizedBox(height: 12),
            _ListBlock(
                label: "DON'T",
                color: AppColors.error,
                icon: Icons.cancel_outlined,
                items: section.donts),
          ],
        ),
      ),
    );
  }
}

class _ListBlock extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final List<SastItem> items;
  bool get isDo => icon == Icons.check_circle_outline;
  const _ListBlock(
      {required this.label,
      required this.color,
      required this.icon,
      required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
        const SizedBox(height: 6),
        for (final item in items)
          if (item.isSub)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 18),
              child: Text(item.text.trim(),
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(isDo ? Icons.check : Icons.close,
                        size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Icon(item.icon, size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(item.text,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                                height: 1.35)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
