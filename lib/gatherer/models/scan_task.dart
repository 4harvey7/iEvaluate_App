enum SyncStatus { pending, uploading, success, failed, paused }

class ScanTask {
  final String id;
  final String localPath;
  SyncStatus status;
  int retryCount;
  String? errorMessage;

  ScanTask({
    required this.id,
    required this.localPath,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'localPath': localPath,
      'status': status.index,
      'retryCount': retryCount,
      'errorMessage': errorMessage,
    };
  }

  factory ScanTask.fromMap(Map<String, dynamic> map) {
    return ScanTask(
      id: map['id'] as String,
      localPath: map['localPath'] as String,
      status: SyncStatus.values[map['status'] as int? ?? 0],
      retryCount: map['retryCount'] as int? ?? 0,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}
