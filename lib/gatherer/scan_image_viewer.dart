// lib/gatherer/scan_image_viewer.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'models/scan_task.dart';

/// Full-screen image viewer for scanned forms in the sync queue.
/// Supports pinch-to-zoom and shows scan metadata in the AppBar.
class ScanImageViewer extends StatelessWidget {
  final ScanTask task;
  final VoidCallback? onDelete;

  const ScanImageViewer({
    super.key,
    required this.task,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(task.localPath);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.id,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              task.status.name.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _statusColor(task.status),
              ),
            ),
          ],
        ),
        actions: [
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Delete scan',
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: Center(
        child: FutureBuilder<bool>(
          future: file.exists(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator(color: Colors.white);
            }

            if (snapshot.data != true) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Image file not found',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The scan image may have been deleted from device storage.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }

            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white54, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Could not load image',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _statusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.success:
        return AppColors.success;
      case SyncStatus.failed:
        return AppColors.error;
      case SyncStatus.uploading:
        return AppColors.primary;
      case SyncStatus.paused:
        return AppColors.warning;
      case SyncStatus.pending:
        return Colors.white54;
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this scan?'),
        content: const Text(
          'Are you sure you want to remove this scan from the queue? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      onDelete?.call();
      Navigator.pop(context); // close the viewer after deleting
    }
  }
}
