enum SyncStatus { pending, uploading, success, failed, paused }

class ScanTask {
  final String id;
  final String localPath;
  SyncStatus status;
  int retryCount;
  String? errorMessage;

  /// True when the scanner could not find the SS Form 2 ruled table in this
  /// photo and the gatherer chose to send it anyway.
  ///
  /// Travels to n8n in the upload so the pipeline can hold a suspect scan back
  /// for review instead of aggregating whatever OCR makes of the wrong page.
  /// Never blocks the upload on its own — that call belongs to the gatherer,
  /// who is standing there holding the paper.
  final bool formSuspect;
  final String? termId;

  /// Set when n8n took the upload but discarded the form on its own, so it is
  /// not counted: 'duplicate_stamp' (this paper form was already scanned this
  /// term) or 'too_few_answers' (fewer than 5 of the 20 items answered). Null
  /// for a normal upload. The status stays success — there is nothing to retry.
  String? outcome;

  /// n8n's message for [outcome], shown in the sync queue.
  String? outcomeMessage;

  ScanTask({
    required this.id,
    required this.localPath,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.errorMessage,
    this.formSuspect = false,
    this.termId,
    this.outcome,
    this.outcomeMessage,
  });

  /// True when n8n discarded this upload as a form already scanned this term.
  bool get isAlreadyScanned => outcome == 'duplicate_stamp';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'localPath': localPath,
      'status': status.index,
      'retryCount': retryCount,
      'errorMessage': errorMessage,
      'formSuspect': formSuspect,
      'termId': termId,
      'outcome': outcome,
      'outcomeMessage': outcomeMessage,
    };
  }

  factory ScanTask.fromMap(Map<String, dynamic> map) {
    return ScanTask(
      id: map['id'] as String,
      localPath: map['localPath'] as String,
      // A stored index outside the enum -- a queue written by a newer build, or
      // a truncated write -- must not take the screen that loads the queue down
      // with it. An unreadable status means the scan's fate is unknown, and
      // pending is the answer that gets it retried rather than dropped.
      status: _statusFrom(map['status']),
      retryCount: map['retryCount'] as int? ?? 0,
      errorMessage: map['errorMessage'] as String?,
      // Queues written by an older build have no such key — those scans were
      // never checked, so the honest default is "not flagged".
      formSuspect: map['formSuspect'] as bool? ?? false,
      termId: map['termId'] as String?,
      // Older queues have neither key: a normal upload.
      outcome: map['outcome'] as String?,
      outcomeMessage: map['outcomeMessage'] as String?,
    );
  }

  static SyncStatus _statusFrom(Object? raw) {
    final idx = raw is int ? raw : 0;
    if (idx < 0 || idx >= SyncStatus.values.length) return SyncStatus.pending;
    return SyncStatus.values[idx];
  }
}
