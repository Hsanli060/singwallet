// lib/data/models/capture_job.dart

/// Model for the `capture_jobs` table.
class CaptureJob {
  final String id;
  final String contentHash;
  final String sourceKind;
  final String importedAt;
  final String privateImageRef;
  final String state;
  final int attemptCount;
  final int parserVersion;
  final String createdAt;
  final String updatedAt;

  const CaptureJob({
    required this.id,
    required this.contentHash,
    required this.sourceKind,
    required this.importedAt,
    required this.privateImageRef,
    required this.state,
    this.attemptCount = 0,
    this.parserVersion = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CaptureJob.fromMap(Map<String, dynamic> map) {
    return CaptureJob(
      id: map['id'] as String,
      contentHash: map['content_hash'] as String,
      sourceKind: map['source_kind'] as String,
      importedAt: map['imported_at'] as String,
      privateImageRef: map['private_image_ref'] as String,
      state: map['state'] as String,
      attemptCount: (map['attempt_count'] as int?) ?? 0,
      parserVersion: (map['parser_version'] as int?) ?? 1,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content_hash': contentHash,
      'source_kind': sourceKind,
      'imported_at': importedAt,
      'private_image_ref': privateImageRef,
      'state': state,
      'attempt_count': attemptCount,
      'parser_version': parserVersion,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  CaptureJob copyWith({
    String? id,
    String? contentHash,
    String? sourceKind,
    String? importedAt,
    String? privateImageRef,
    String? state,
    int? attemptCount,
    int? parserVersion,
    String? createdAt,
    String? updatedAt,
  }) {
    return CaptureJob(
      id: id ?? this.id,
      contentHash: contentHash ?? this.contentHash,
      sourceKind: sourceKind ?? this.sourceKind,
      importedAt: importedAt ?? this.importedAt,
      privateImageRef: privateImageRef ?? this.privateImageRef,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      parserVersion: parserVersion ?? this.parserVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptureJob &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          contentHash == other.contentHash &&
          sourceKind == other.sourceKind &&
          importedAt == other.importedAt &&
          privateImageRef == other.privateImageRef &&
          state == other.state &&
          attemptCount == other.attemptCount &&
          parserVersion == other.parserVersion &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        contentHash,
        sourceKind,
        importedAt,
        privateImageRef,
        state,
        attemptCount,
        parserVersion,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'CaptureJob(id: $id, contentHash: $contentHash, state: $state, attempts: $attemptCount)';
}
