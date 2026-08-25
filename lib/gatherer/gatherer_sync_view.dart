// lib/gatherer/gatherer_sync_view.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'models/scan_task.dart';

class GathererSyncView extends StatelessWidget {
  final List<ScanTask> queue;
  final bool isSyncing;
  final bool isPaused;
  final VoidCallback onSync;
  final Function(ScanTask) onRetry;
  final Function(ScanTask) onDelete;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const GathererSyncView({
    super.key,
    required this.queue,
    required this.isSyncing,
    required this.isPaused,
    required this.onSync,
    required this.onRetry,
    required this.onDelete,
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final pendingCount = queue.where((t) => t.status == SyncStatus.pending || t.status == SyncStatus.failed).length;
    final successCount = queue.where((t) => t.status == SyncStatus.success).length;
    // gradient CTA only lights up when there is actually something to sync
    final bool canSync = !isPaused && queue.any((t) => t.status != SyncStatus.success);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sync Queue',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                      Text('Upload scanned forms to the n8n backend',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                // Pause / Resume button — soft tinted pill
                if (queue.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: (isPaused ? AppColors.success : AppColors.warning)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TextButton.icon(
                      onPressed: isPaused ? onResume : onPause,
                      icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: isPaused ? AppColors.success : AppColors.warning, size: 20),
                      label: Text(isPaused ? 'Resume' : 'Pause',
                          style: TextStyle(
                              color: isPaused ? AppColors.success : AppColors.warning,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),

            // Status summary chips
            if (queue.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _statusChip('$pendingCount pending', AppColors.warning),
                  const SizedBox(width: 8),
                  _statusChip('$successCount synced', AppColors.success),
                  if (isPaused) ...[
                    const SizedBox(width: 8),
                    _statusChip('⏸ Paused', AppColors.textSecondary),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Queue List
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // soft icon in a tinted circle — friendly empty state
                          Container(
                            width: 88,
                            height: 88,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryTint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.cloud_done,
                                color: AppColors.primaryText, size: 40),
                          ),
                          const SizedBox(height: 18),
                          const Text('All forms have been synced!',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          const Text('New scans will appear here while they upload.',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final task = queue[index];
                        return Dismissible(
                          key: Key(task.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.delete_outline, color: AppColors.error),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: const Text('Remove from queue?'),
                                content: const Text('This will remove the item from the queue. The image file will remain on device.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.error,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12))),
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Remove', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            ) ?? false;
                          },
                          onDismissed: (_) => onDelete(task),
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
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(task.localPath),
                                  width: 40,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.textSecondary),
                                ),
                              ),
                              title: Text(task.id,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppColors.textPrimary)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: _buildSubtitle(task),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildStatusIcon(task),
                                  // Delete button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                                    tooltip: 'Remove from queue',
                                    onPressed: () => onDelete(task),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.only(left: 8),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 16),

            // Sync All Button — gradient CTA when there is work to do
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: canSync
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDeep],
                      )
                    : null,
                color: canSync ? null : AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(16),
                boxShadow: canSync
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: isSyncing || isPaused || queue.every((t) => t.status == SyncStatus.success) ? null : onSync,
                icon: isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: AppColors.textPrimary, strokeWidth: 2))
                    : Icon(Icons.cloud_upload,
                        color: canSync ? AppColors.textPrimary : AppColors.textSecondary),
                label: Text(
                  isPaused ? 'Sync Paused' : (isSyncing ? 'Syncing...' : 'Sync All Pending'),
                  style: TextStyle(
                      color: canSync ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // soft tinted pill chip — dark accessible label on a light fill
  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildSubtitle(ScanTask task) {
    if (task.status == SyncStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(task.errorMessage ?? 'Upload failed',
                  style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      );
    }
    if (task.status == SyncStatus.paused) {
      return _statusPill('PAUSED', AppColors.warning);
    }
    final color = task.status == SyncStatus.success
        ? AppColors.success
        : (task.status == SyncStatus.uploading
            ? AppColors.primaryText
            : AppColors.textSecondary);
    return _statusPill(task.status.name.toUpperCase(), color);
  }

  // small tinted pill for the sync state under each row
  Widget _statusPill(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(ScanTask task) {
    switch (task.status) {
      case SyncStatus.uploading:
        return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary));
      case SyncStatus.success:
        return const Icon(Icons.check_circle, color: AppColors.success, size: 20);
      case SyncStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh, color: AppColors.warning, size: 20),
          onPressed: () => onRetry(task),
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        );
      case SyncStatus.paused:
        return const Icon(Icons.pause_circle_outline, color: AppColors.warning, size: 20);
      case SyncStatus.pending:
        return const Icon(Icons.hourglass_empty, color: AppColors.textSecondary, size: 20);
    }
  }
}
