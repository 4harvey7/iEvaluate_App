import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/sheet_import_job.dart';

void main() {
  test('job id only from the new workflow answer', () {
    expect(sheetImportJobId({'status': 'processing', 'job_id': 'abc'}), 'abc');
    expect(sheetImportJobId({'status': 'success', 'imported_count': 3}), isNull);
    expect(sheetImportJobId('text'), isNull);
  });

  test('parses a finished row; an error without finished_at is not the end', () {
    final done = SheetImportJob.fromRow({
      'status': 'done', 'rows': 5, 'imported_count': '4', 'error_count': 1,
      'ai_groups': 2, 'ai_failed': 0, 'finished_at': '2026-10-18T10:00:00Z',
    });
    expect(done.isFinished, isTrue);
    expect(done.importedCount, 4);
    expect(sheetImportSummary(done), contains('Imported: 4'));
    final running = SheetImportJob.fromRow(
        {'status': 'error', 'message': 'AI failed', 'failed_node': 'Unified AI Analysis1'});
    expect(running.isFinished, isFalse);
    expect(sheetImportErrorText(running), contains('Failed at step: Unified AI Analysis1.'));
  });

  test('polls every 4 s until finished, skipping failed reads', () async {
    var t = DateTime(2026);
    final waits = <Duration>[];
    var calls = 0;
    final r = await pollSheetImportJob(
      fetch: () async {
        calls++;
        if (calls == 2) throw Exception('network');
        return calls < 4
            ? {'status': 'processing'}
            : {'status': 'done', 'finished_at': '2026-10-18T10:00:00Z'};
      },
      sleep: (d) async { waits.add(d); t = t.add(d); },
      now: () => t,
    );
    expect(r.timedOut, isFalse);
    expect(r.job!.status, 'done');
    expect(waits, everyElement(const Duration(seconds: 4)));
    expect(calls, 4);
  });

  test('stops after 60 minutes still processing, never claims success', () async {
    var t = DateTime(2026);
    final r = await pollSheetImportJob(
      fetch: () async => {'status': 'processing'},
      sleep: (d) async => t = t.add(d),
      now: () => t,
    );
    expect(r.timedOut, isTrue);
    expect(r.job!.status, 'processing');
    expect(t.difference(DateTime(2026)), const Duration(minutes: 60));
  });
}
