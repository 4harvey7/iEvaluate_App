// An upload n8n did not count keeps status success, so the full-image viewer
// must label it by its outcome, never as a green SUCCESS (UAT S17, DEF-R4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/models/scan_task.dart';
import 'package:ievaluateapp_final/gatherer/scan_image_viewer.dart';

void main() {
  Future<void> pumpViewer(WidgetTester tester, ScanTask task, {String? reason}) =>
      tester.pumpWidget(MaterialApp(home: ScanImageViewer(task: task, rejectionReason: reason)));

  ScanTask task(String? outcome) => ScanTask(
        id: 'SCAN-1',
        localPath: 'does-not-exist/SCAN-1.jpg',
        status: SyncStatus.success,
        outcome: outcome,
      );

  testWidgets('not a SAST form', (tester) async {
    await pumpViewer(tester, task('not_a_sast_form'), reason: 'Not a SAST form.');
    expect(find.text('NOT A SAST FORM - REJECTED'), findsOneWidget);
    expect(find.text('SUCCESS'), findsNothing);
  });

  testWidgets('other outcomes match the queue row', (tester) async {
    await pumpViewer(tester, task('duplicate_stamp'));
    expect(find.text('ALREADY SCANNED'), findsOneWidget);
    await pumpViewer(tester, task('too_few_answers'));
    expect(find.text('DISCARDED (FEWER THAN 5 ANSWERS)'), findsOneWidget);
    await pumpViewer(tester, task('needs_review'));
    expect(find.text('NEEDS REVIEW'), findsOneWidget);
  });

  testWidgets('a counted upload still reads SUCCESS', (tester) async {
    await pumpViewer(tester, task(null));
    expect(find.text('SUCCESS'), findsOneWidget);
  });
}
