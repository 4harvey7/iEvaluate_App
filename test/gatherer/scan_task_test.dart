import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/models/scan_task.dart';

void main() {
  group('ScanTask outcome survives a restart', () {
    test('toMap -> JSON -> fromMap -> copyWith keeps the discard', () {
      final task = ScanTask(
        id: 'SCAN-1',
        localPath: '/old/SCAN-1_A4.jpg',
        status: SyncStatus.success,
        termId: 'term-1',
        outcome: 'too_few_answers',
        outcomeMessage: 'Discarded automatically: fewer than 5 of the 20 '
            'items were answered (only 3), so this form is not counted.',
      );

      // what _saveQueueToStorage / _loadQueueFromStorage do
      final stored = jsonEncode(task.toMap());
      final restored = ScanTask.fromMap(
        jsonDecode(stored) as Map<String, dynamic>,
      ).copyWith(localPath: '/new/SCAN-1_A4.jpg');

      expect(restored.localPath, '/new/SCAN-1_A4.jpg');
      expect(restored.status, SyncStatus.success);
      expect(restored.termId, 'term-1');
      expect(restored.outcome, 'too_few_answers');
      expect(restored.outcomeMessage, task.outcomeMessage);
      expect(restored.isAlreadyScanned, isFalse);
    });

    test('already-scanned outcome is kept too', () {
      final t = ScanTask(
        id: 'SCAN-2',
        localPath: '/a.jpg',
        status: SyncStatus.success,
        outcome: 'duplicate_stamp',
      ).copyWith(status: SyncStatus.success);
      expect(t.isAlreadyScanned, isTrue);
    });

    test('normal upload has no outcome', () {
      final t = ScanTask.fromMap({'id': 'SCAN-3', 'localPath': '/b.jpg'});
      expect(t.copyWith().outcome, isNull);
    });
  });
}
