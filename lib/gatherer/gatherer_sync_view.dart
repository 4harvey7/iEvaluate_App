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
  final Function(List<ScanTask>)? onDeleteMultiple;
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
    this.onDeleteMultiple,
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
        title: const Text('Delete selected scans?', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Are you sure you want to remove $count scan${count > 1 ? 's' : ''} from the queue? This cannot be undone.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (!confirmed) return;

    final toDelete = widget.queue.where((t) => _selectedIds.contains(t.id)).toList();
    if (widget.onDeleteMultiple != null) {
      widget.onDeleteMultiple!(toDelete);
    } else {
      for (final task in toDelete) {
        widget.onDelete(task);
      }
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
        title: const Text('Delete this scan?', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Are you sure you want to remove this scan from the queue? This cannot be undone.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (confirmed == true) widget.onDelete(task);
  }

  @override
  Widget build(BuildContext context) {
    final int pendingCount = widget.queue
        .where(
          (t) =>
              t.status == SyncStatus.pending || t.status == SyncStatus.failed,
        )
        .length;
    final int successCount = widget.queue
        .where((t) => t.status == SyncStatus.success)
        .length;

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
              subtitle: 'Review and upload\nscanned forms.',
              trailing: widget.queue.isNotEmpty
                  ? TextButton.icon(
                      onPressed: widget.isPaused
                          ? widget.onResume
                          : widget.onPause,
                      icon: Icon(
                          widget.isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: widget.isPaused
                              ? AppColors.success
                              : AppColors.warning,
                          size: 20),
                      label: Text(
                        widget.isPaused ? 'Resume' : 'Pause',
                        style: TextStyle(
                          color: widget.isPaused
                              ? AppColors.success
                              : AppColors.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
            ),

            const SizedBox(height: 16),

            // Status summary chips row matching reference screenshot
            if (widget.queue.isNotEmpty && !_isSelectMode) ...[
              Row(
                children: [
                  _statusChip('$pendingCount pending', AppColors.warning),
                  const SizedBox(width: 8),
                  _statusChip('$successCount synced', AppColors.success),
                  if (widget.isPaused) ...[
                    const SizedBox(width: 8),
                    _statusChip('\u23f8 Paused', AppColors.textSecondary),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary),
                    tooltip: 'Select multiple',
                    onPressed: _toggleSelectMode,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Select mode action bar
            if (_isSelectMode) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectedIds.length == widget.queue.length &&
                          widget.queue.isNotEmpty,
                      onChanged: (_) => _selectAll(),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${_selectedIds.length}/${widget.queue.length} selected',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedIds.isEmpty
                            ? AppColors.textSecondary
                            : AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed:
                          _selectedIds.isEmpty ? null : _deleteSelected,
                      icon: const Icon(Icons.delete_outline, size: 15),
                      label: Text('Delete (${_selectedIds.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _toggleSelectMode,
                      child: const Text('Done',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
                          direction: _isSelectMode
                              ? DismissDirection.none
                              : DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('Remove from queue?', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                content: Text('Are you sure you want to remove scan ${task.id}? This will discard the scan and cannot be undone.', style: const TextStyle(color: AppColors.textSecondary)),
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
                          child: Card(
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: isSelected
                                  ? const BorderSide(color: AppColors.primary, width: 1.5)
                                  : BorderSide(color: AppColors.borderSubtle.withValues(alpha: 0.6)),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                if (_isSelectMode) {
                                  _toggleItem(task.id);
                                } else {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ScanImageViewer(
                                      task: task,
                                      onDelete: () {
                                        widget.onDelete(task);
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ));
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectMode) {
                                  setState(() {
                                    _isSelectMode = true;
                                    _selectedIds.add(task.id);
                                  });
                                }
                              },
                              child: ListTile(
                                enabled: false,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                leading: _isSelectMode
                                    ? IgnorePointer(
                                        child: Checkbox(
                                          value: isSelected,
                                          onChanged: null,
                                          activeColor: AppColors.primary,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(
                                          File(task.localPath),
                                          width: 44,
                                          height: 52,
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
                                            padding: const EdgeInsets.only(left: 6),
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

            // Sync All Button matching screenshot (light grey when paused)
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isPaused
                      ? const Color(0xFFCFD8DC)
                      : (widget.queue.any((t) => t.status != SyncStatus.success) ? AppColors.textPrimary : AppColors.textSecondary),
                  disabledBackgroundColor: const Color(0xFFCFD8DC),
                  disabledForegroundColor: Colors.white,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: widget.isSyncing || widget.isPaused || widget.queue.every((t) => t.status == SyncStatus.success) ? null : widget.onSync,
                icon: widget.isSyncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                label: Text(
                  widget.isPaused ? 'Sync Paused' : (widget.isSyncing ? 'Syncing...' : 'Sync All Pending'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
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
