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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
                      Text('Sync Queue', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('Upload scanned forms to the n8n backend', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                // Pause / Resume button
                if (queue.isNotEmpty)
                  TextButton.icon(
                    onPressed: isPaused ? onResume : onPause,
                    icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: isPaused ? AppColors.success : AppColors.warning, size: 20),
                    label: Text(isPaused ? 'Resume' : 'Pause',
                        style: TextStyle(color: isPaused ? AppColors.success : AppColors.warning, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),

            // Status summary chips
            if (queue.isNotEmpty) ...[
              const SizedBox(height: 10),
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
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_done, color: AppColors.success, size: 64),
                          SizedBox(height: 16),
                          Text('All forms have been synced!', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
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
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete_outline, color: AppColors.error),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('Remove from queue?'),
                                content: const Text('This will remove the item from the queue. The image file will remain on device.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Remove', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            ) ?? false;
                          },
                          onDismissed: (_) => onDelete(task),
                          child: Card(
                            color: AppColors.surface,
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  File(task.localPath),
                                  width: 40,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.textSecondary),
                                ),
                              ),
                              title: Text(task.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                              subtitle: _buildSubtitle(task),
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
                                    padding: const EdgeInsets.only(left: 4),
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

            // Sync All Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPaused
                      ? AppColors.textSecondary
                      : (queue.any((t) => t.status != SyncStatus.success) ? AppColors.textPrimary : AppColors.textSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isSyncing || isPaused || queue.every((t) => t.status == SyncStatus.success) ? null : onSync,
                icon: isSyncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload, color: Colors.white),
                label: Text(
                  isPaused ? 'Sync Paused' : (isSyncing ? 'Syncing...' : 'Sync All Pending'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSubtitle(ScanTask task) {
    if (task.status == SyncStatus.failed) {
      return Text(task.errorMessage ?? 'Upload failed', style: const TextStyle(color: AppColors.error, fontSize: 11));
    }
    if (task.status == SyncStatus.paused) {
      return const Text('PAUSED', style: TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold));
    }
    return Text(
      task.status.name.toUpperCase(),
      style: TextStyle(
        color: task.status == SyncStatus.success ? AppColors.success : AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
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
        return const Icon(Icons.hourglass_empty, color: AppColors.textTertiary, size: 20);
    }
  }
}