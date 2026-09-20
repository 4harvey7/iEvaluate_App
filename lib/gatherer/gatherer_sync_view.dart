// lib/gatherer/gatherer_sync_view.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'models/scan_task.dart';
import '../widgets/apple_ui.dart';
import 'scan_image_viewer.dart';

class GathererSyncView extends StatefulWidget {
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
  State<GathererSyncView> createState() => _GathererSyncViewState();
}

class _GathererSyncViewState extends State<GathererSyncView> {
  bool _isSelectMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      _selectedIds.clear();
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == widget.queue.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(widget.queue.map((t) => t.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove $count item${count > 1 ? 's' : ''}?'),
        content: Text('This will remove $count item${count > 1 ? 's' : ''} from the queue. Image files will remain on device.'),
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

    if (!confirmed) return;

    final toDelete = widget.queue.where((t) => _selectedIds.contains(t.id)).toList();
    for (final task in toDelete) {
      widget.onDelete(task);
    }
    setState(() {
      _isSelectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmSingleDelete(ScanTask task) async {
    final confirmed = await showDialog<bool>(
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

    if (confirmed) widget.onDelete(task);
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = widget.queue.where((t) => t.status == SyncStatus.pending || t.status == SyncStatus.failed).length;
    final successCount = widget.queue.where((t) => t.status == SyncStatus.success).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            ApplePageHeader(
              eyebrow: 'Upload Pipeline',
              title: 'Sync Queue',
              subtitle: 'Review and upload scanned forms.',
              trailing: widget.queue.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_isSelectMode ? Icons.close : Icons.checklist_rounded,
                              color: _isSelectMode ? AppColors.error : AppColors.textSecondary),
                          tooltip: _isSelectMode ? 'Cancel selection' : 'Select items',
                          onPressed: _toggleSelectMode,
                        ),
                        TextButton.icon(
                          onPressed: widget.isPaused ? widget.onResume : widget.onPause,
                          icon: Icon(widget.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                              color: widget.isPaused ? AppColors.success : AppColors.warning, size: 20),
                          label: Text(widget.isPaused ? 'Resume' : 'Pause',
                              style: TextStyle(color: widget.isPaused ? AppColors.success : AppColors.warning, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    )
                  : null,
            ),

            // Select mode action bar
            if (_isSelectMode) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: Icon(
                      _selectedIds.length == widget.queue.length ? Icons.deselect : Icons.select_all,
                      size: 18,
                    ),
                    label: Text(_selectedIds.length == widget.queue.length ? 'Deselect All' : 'Select All'),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      '${_selectedIds.length} selected',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedIds.isEmpty ? AppColors.textSecondary : AppColors.error,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                    label: const Text('Delete', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ],
              ),
            ],

            // Status summary chips
            if (widget.queue.isNotEmpty && !_isSelectMode) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _statusChip('$pendingCount pending', AppColors.warning),
                  const SizedBox(width: 8),
                  _statusChip('$successCount synced', AppColors.success),
                  if (widget.isPaused) ...[
                    const SizedBox(width: 8),
                    _statusChip('\u23f8 Paused', AppColors.textSecondary),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Queue List
            Expanded(
              child: widget.queue.isEmpty
                  ? const AppleEmptyState(
                      icon: Icons.cloud_done_outlined,
                      title: 'Everything is synced',
                      message: 'New scans will appear here before upload.',
                    )
                  : ListView.builder(
                      itemCount: widget.queue.length,
                      itemBuilder: (context, index) {
                        final task = widget.queue[index];
                        final isSelected = _selectedIds.contains(task.id);
                        return Dismissible(
                          key: Key(task.id),
                          direction: _isSelectMode ? DismissDirection.none : DismissDirection.endToStart,
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
                          onDismissed: (_) => widget.onDelete(task),
                          child: GestureDetector(
                            onTap: _isSelectMode
                                ? () => _toggleItem(task.id)
                                : () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => ScanImageViewer(
                                        task: task,
                                        onDelete: () {
                                          widget.onDelete(task);
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                    ));
                                  },
                            onLongPress: () {
                              if (!_isSelectMode) {
                                setState(() {
                                  _isSelectMode = true;
                                  _selectedIds.add(task.id);
                                });
                              }
                            },
                            child: Card(
                              color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: isSelected
                                    ? const BorderSide(color: AppColors.primary, width: 1.5)
                                    : BorderSide.none,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                leading: _isSelectMode
                                    ? Checkbox(
                                        value: isSelected,
                                        onChanged: (_) => _toggleItem(task.id),
                                        activeColor: AppColors.primary,
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.file(
                                          File(task.localPath),
                                          width: 40,
                                          height: 50,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: AppColors.textSecondary),
                                        ),
                                      ),
                                title: Text(task.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                                subtitle: _buildSubtitle(task),
                                trailing: _isSelectMode
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildStatusIcon(task),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                                            tooltip: 'Remove from queue',
                                            onPressed: () => _confirmSingleDelete(task),
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.only(left: 4),
                                          ),
                                        ],
                                      ),
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
                  backgroundColor: widget.isPaused
                      ? AppColors.textSecondary
                      : (widget.queue.any((t) => t.status != SyncStatus.success) ? AppColors.textPrimary : AppColors.textSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: widget.isSyncing || widget.isPaused || widget.queue.every((t) => t.status == SyncStatus.success) ? null : widget.onSync,
                icon: widget.isSyncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload, color: Colors.white),
                label: Text(
                  widget.isPaused ? 'Sync Paused' : (widget.isSyncing ? 'Syncing...' : 'Sync All Pending'),
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
          onPressed: () => widget.onRetry(task),
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
