// Google Sheet import job (n8n + website migration 018_sheet_import_jobs.sql).
//
// n8n answers the sheet link early (to avoid the proxy's 504) with
// {status: 'processing', job_id, rows, ...} and keeps saving rows and running
// the AI remark analysis. It writes the real end into sheet_import_jobs:
// finished_at + counts, status 'done' or 'error' (message + failed_node).
// The app polls that row by id until finished_at is set.

import 'dart:async';
import 'dart:convert';

class SheetImportJob {
  final String status; // processing | done | error
  final int? rows;
  final int? matched;
  final int? unmatched;
  final int? importedCount;
  final int? errorCount;
  final int? aiGroups;
  final int? aiFailed;
  final String? message;
  final String? failedNode;
  final DateTime? finishedAt;
  // Migration 021: {form_type, term_label, rows, new, already_imported,
  // excluded_under_5, rejected, reasons:[{reason, plain_text, count, rows}]}.
  // Null on an old DB (no column) or an old workflow.
  final Map<String, dynamic>? details;

  const SheetImportJob({
    required this.status,
    this.rows,
    this.matched,
    this.unmatched,
    this.importedCount,
    this.errorCount,
    this.aiGroups,
    this.aiFailed,
    this.message,
    this.failedNode,
    this.finishedAt,
    this.details,
  });

  static int? _int(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  static String? _str(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory SheetImportJob.fromRow(Map<String, dynamic> row) => SheetImportJob(
        status: _str(row['status']) ?? 'processing',
        rows: _int(row['rows']),
        matched: _int(row['matched']),
        unmatched: _int(row['unmatched']),
        importedCount: _int(row['imported_count']),
        errorCount: _int(row['error_count']),
        aiGroups: _int(row['ai_groups']),
        aiFailed: _int(row['ai_failed']),
        message: _str(row['message']),
        failedNode: _str(row['failed_node']),
        finishedAt: DateTime.tryParse('${row['finished_at'] ?? ''}'),
        details: _details(row['details']),
      );

  static Map<String, dynamic>? _details(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.trim().startsWith('{')) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }

  /// The flow has really ended. An 'error' recorded while n8n is still
  /// running (finished_at not set yet) is not the end: keep polling.
  bool get isFinished => finishedAt != null;

  bool get isError => status == 'error';
}

/// The job id in the webhook answer, or null (old workflow: no job).
String? sheetImportJobId(dynamic data) {
  if (data is! Map) return null;
  final id = data['job_id']?.toString().trim();
  return (id == null || id.isEmpty) ? null : id;
}

class SheetImportPollResult {
  final SheetImportJob? job; // last row read (null if never read)
  final bool timedOut;
  const SheetImportPollResult(this.job, {this.timedOut = false});
}

/// Reads the job every [interval] until it is finished or [timeout] passes.
/// A failed read (network, RLS) is skipped and retried on the next tick.
Future<SheetImportPollResult> pollSheetImportJob({
  required Future<Map<String, dynamic>?> Function() fetch,
  void Function(SheetImportJob job)? onUpdate,
  Duration interval = const Duration(seconds: 4),
  Duration timeout = const Duration(minutes: 60),
  Future<void> Function(Duration)? sleep,
  DateTime Function()? now,
  bool Function()? cancelled,
}) async {
  final clock = now ?? DateTime.now;
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  final deadline = clock().add(timeout);
  SheetImportJob? last;
  while (true) {
    if (cancelled?.call() ?? false) return SheetImportPollResult(last);
    try {
      final row = await fetch();
      if (row != null) {
        last = SheetImportJob.fromRow(row);
        onUpdate?.call(last);
        if (last.isFinished) return SheetImportPollResult(last);
      }
    } catch (_) {
      // transient read failure: try again next tick
    }
    if (!clock().isBefore(deadline)) {
      return SheetImportPollResult(last, timedOut: true);
    }
    await wait(interval);
  }
}

/// Plain-language text for staff.
String sheetImportSummary(SheetImportJob job) {
  final lines = <String>[];
  if (job.rows != null) lines.add('• Rows in the sheet: ${job.rows}');
  if (job.importedCount != null) lines.add('• Imported: ${job.importedCount}');
  if (job.errorCount != null) {
    lines.add('• Not imported (see Import Errors): ${job.errorCount}');
  }
  if (job.aiGroups != null && job.aiGroups! > 0) {
    final ok = job.aiGroups! - (job.aiFailed ?? 0);
    lines.add('• AI comment analysis: $ok of ${job.aiGroups} instructors');
  }
  return lines.join('\n');
}

String sheetImportErrorText(SheetImportJob job) {
  final parts = <String>[
    job.message ?? 'The import reported a problem.',
    if (job.failedNode != null) 'Failed at step: ${job.failedNode}.',
  ];
  final counts = sheetImportSummary(job);
  if (counts.isNotEmpty) parts.add(counts);
  return parts.join('\n\n');
}

/// What the final dialog shows.
class SheetImportOutcome {
  final String title;
  final String message;
  final bool isSuccess;
  const SheetImportOutcome(this.title, this.message, this.isSuccess);
}

/// Title, text and tone for a finished job. Uses `details` when present,
/// else the older counts. Never throws on a missing or odd key.
SheetImportOutcome sheetImportOutcome(SheetImportJob job) {
  final d = job.details;
  if (job.isError) {
    final msg = job.message ?? 'The import reported a problem.';
    return SheetImportOutcome('Import failed', msg, false);
  }
  if (d == null) {
    final counts = sheetImportSummary(job);
    return SheetImportOutcome(
      'Import finished',
      counts.isEmpty ? (job.message ?? 'Import completed.') : 'Import completed.\n$counts',
      true,
    );
  }
  int n(String k) => SheetImportJob._int(d[k]) ?? 0;
  final rejected = n('rejected');
  final lines = <String>[
    'New: ${n('new')}',
    'Already imported earlier (skipped): ${n('already_imported')}',
    'Saved but not counted (fewer than 5 answers): ${n('excluded_under_5')}',
    'Not imported: $rejected',
  ];
  final reasons = d['reasons'];
  if (reasons is List && reasons.isNotEmpty) {
    lines.add('');
    for (final r in reasons.take(5)) {
      if (r is! Map) continue;
      final text = SheetImportJob._str(r['plain_text']) ?? SheetImportJob._str(r['reason']) ?? 'Unknown reason';
      final count = SheetImportJob._int(r['count']);
      final rows = r['rows'] is List ? (r['rows'] as List).map((e) => '$e').toList() : const <String>[];
      var line = text;
      if (count != null) line += ' - $count';
      if (rows.isNotEmpty) line += ' (rows ${rows.join(', ')})';
      lines.add(line);
    }
  }
  return SheetImportOutcome(
    rejected > 0 ? 'Import finished - some rows need attention' : 'Import finished',
    lines.join('\n'),
    rejected == 0,
  );
}
