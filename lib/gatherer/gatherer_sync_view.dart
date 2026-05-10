// lib/gatherer/gatherer_sync_view.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GathererSyncView extends StatelessWidget {
  final List<Map<String, dynamic>> queue;
  final bool isSyncing;
  final VoidCallback onSync;

  const GathererSyncView({super.key, required this.queue, required this.isSyncing, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline Queue', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
            const Text('Upload scanned forms to the N8n backend', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),

            Expanded(
              child: queue.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_done, color: AppColors.success, size: 64),
                    const SizedBox(height: 16),
                    const Text('All forms have been synced!', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: queue.length,
                itemBuilder: (context, index) {
                  final form = queue[index];
                  bool isProcessing = form['status'] == 'Processing...';
                  return Card(
                    color: AppColors.surface,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(isProcessing ? Icons.sync : Icons.description, color: isProcessing ? AppColors.primary : AppColors.textSecondary),
                      title: Text(form['id'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(form['status'], style: TextStyle(color: isProcessing ? AppColors.primary : AppColors.textSecondary, fontSize: 12)),
                      trailing: isProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle, color: AppColors.success),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: queue.isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: queue.isEmpty || isSyncing ? null : onSync,
                icon: isSyncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload, color: Colors.white),
                label: Text(
                  isSyncing ? 'Uploading to Server...' : 'Sync ${queue.length} Forms to Cloud',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}