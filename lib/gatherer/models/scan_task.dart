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

  /// Set when n8n took the upload but it is not a plain counted form:
  /// 'duplicate_stamp' (this paper form was already scanned this term),
  /// 'too_few_answers' (fewer than 5 of the 20 items answered),
  /// 'needs_review' (held in the review queue until someone checks it) or
  /// 'not_a_sast_form' (the photo is not a SAST form). Null for a normal
  /// upload. The status stays success — there is nothing to retry.
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

  /// True while the upload sits in the review queue (failed_scan_queue or
  /// import_errors, status pending).
  bool get isNeedsReview => outcome == 'needs_review';

  /// True when n8n said the photo is not a SAST form.
  bool get isNotSast => outcome == 'not_a_sast_form';

  /// A copy with the given fields replaced and every other field kept --
  /// including [outcome], so a restored queue still shows DISCARDED.
  ScanTask copyWith({String? localPath, SyncStatus? status, String? termId}) {
    return ScanTask(
      id: id,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      retryCount: retryCount,
      errorMessage: errorMessage,
      formSuspect: formSuspect,
      termId: termId ?? this.termId,
      outcome: outcome,
      outcomeMessage: outcomeMessage,
    );
  }

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
