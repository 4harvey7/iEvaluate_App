// The sync queue lists every scan with a thumbnail of its photo. Each photo is
// a full-sensor still (13 MP on the Infinix X6525, ~52 MB decoded), so the
// thumbnails must be decoded small -- a full decode per row is what made the
// queue, and everything after a capture, crawl on a low-end phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/gatherer_sync_view.dart';
import 'package:ievaluateapp_final/gatherer/models/scan_task.dart';

void main() {
  testWidgets('queue thumbnails are decoded at thumbnail size', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GathererSyncView(
          queue: [
            ScanTask(id: 'SCAN-1', localPath: 'does-not-exist/SCAN-1_SHORT.jpg'),
            ScanTask(id: 'SCAN-2', localPath: 'does-not-exist/SCAN-2_LONG.jpg'),
          ],
          isSyncing: false,
          isPaused: false,
          onSync: () {},
          onRetry: (_) {},
          onDelete: (_) {},
          onPause: () {},
          onResume: () {},
        ),
      ),
    ));
    await tester.pump();

    final thumbs = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(thumbs, hasLength(2));
    for (final thumb in thumbs) {
      expect(thumb.image, isA<ResizeImage>());
      final width = (thumb.image as ResizeImage).width!;
      // 44 dp wide: a few device pixels per dp, never the photo's 3000+.
      expect(width, lessThanOrEqualTo(200));
    }
  });
}
