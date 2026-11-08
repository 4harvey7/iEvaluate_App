// lib/widgets/update_tile.dart
// "About" card for every settings screen: real installed version, a
// "Check for updates" button, and the download/install flow. The startup
// dialog (showUpdateDialog) reuses the same panel.
import 'package:flutter/material.dart';
import '../core/services/update_service.dart';
import '../theme/app_colors.dart';
import 'apple_ui.dart';

class UpdateTile extends StatefulWidget {
  const UpdateTile({super.key});

  @override
  State<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<UpdateTile> {
  String _versionLabel = 'iEvaluate';
  bool _checking = false;
  bool _checked = false;
  AppRelease? _release;
  String? _error;

  @override
  void initState() {
    super.initState();
    UpdateService.installedVersionLabel().then((label) {
      if (mounted) setState(() => _versionLabel = label);
    });
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await UpdateService.check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = true;
      _release = result.release;
      _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppleSectionHeader(title: 'About'),
        const SizedBox(height: 12),
        Card(
          color: AppColors.surface,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.info_outline, color: AppColors.primary),
                ),
                title: const Text('App Version', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                subtitle: Text(_versionLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
              const Divider(height: 1, indent: 56),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _release != null
                    ? UpdatePanel(release: _release!)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) _ErrorText(_error!),
                          if (_checked && _error == null && !_checking)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text('You have the latest version.', style: TextStyle(color: AppColors.success, fontSize: 13)),
                            ),
                          OutlinedButton.icon(
                            onPressed: _checking ? null : _check,
                            icon: _checking
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh, color: AppColors.primary),
                            label: Text(_checking ? 'Checking…' : 'Check for updates',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              minimumSize: const Size.fromHeight(46),
                            ),
                          ),
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

/// Release notes + "Update to vX" button + progress bar + error text.
class UpdatePanel extends StatefulWidget {
  const UpdatePanel({super.key, required this.release});
  final AppRelease release;

  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  bool _downloading = false;
  double? _progress;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await UpdateService.downloadAndInstall(widget.release, (p) {
        if (mounted) setState(() => _progress = p);
      });
    } on UpdateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final notes = r.notes?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Version ${r.versionName} is available',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        if (_error != null) _ErrorText(_error!),
        if (_downloading) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _progress, minHeight: 6, color: AppColors.primary, backgroundColor: AppColors.primaryTint),
          ),
          const SizedBox(height: 6),
          Text(_progress == null ? 'Downloading…' : 'Downloading… ${(_progress! * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ] else
          ElevatedButton.icon(
            onPressed: _update,
            icon: const Icon(Icons.system_update, color: AppColors.textInverted),
            label: Text('Update to v${r.versionName}',
                style: const TextStyle(color: AppColors.textInverted, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size.fromHeight(46),
            ),
          ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: AppColors.error, fontSize: 13))),
          ],
        ),
      );
}

/// "Update available" dialog. A forced release cannot be dismissed.
Future<void> showUpdateDialog(BuildContext context, AppRelease release) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !release.force,
    builder: (ctx) => PopScope(
      canPop: !release.force,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(release.force ? 'Update required' : 'Update available',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        content: SingleChildScrollView(child: UpdatePanel(release: release)),
        actions: [
          if (!release.force)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later', style: TextStyle(color: AppColors.textSecondary)),
            ),
        ],
      ),
    ),
  );
}

/// Wraps the first screen after login and checks for an update once per app
/// start. A failed check is silent; the settings tile shows errors instead.
class UpdateCheckGate extends StatefulWidget {
  const UpdateCheckGate({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends State<UpdateCheckGate> {
  @override
  void initState() {
    super.initState();
    if (UpdateService.startupCheckDone) return;
    UpdateService.startupCheckDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await UpdateService.check();
      final release = result.release;
      if (release != null && mounted) showUpdateDialog(context, release);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
