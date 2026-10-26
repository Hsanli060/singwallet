// lib/data/models/draft.dart

/// Model for the `drafts` table.
class Draft {
  final String id;
  final String captureId;
  final String candidateFields; // JSON encoded string
  final String fieldEvidence; // JSON encoded string
  final String validationIssues; // JSON encoded string array
  final String duplicateCandidates; // JSON encoded string array
  final String? savedTransactionId;
  final String createdAt;
  final String updatedAt;

  const Draft({
    required this.id,
    required this.captureId,
    required this.candidateFields,
    required this.fieldEvidence,
    required this.validationIssues,
    required this.duplicateCandidates,
    this.savedTransactionId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Draft.fromMap(Map<String, dynamic> map) {
    return Draft(
      id: map['id'] as String,
      captureId: map['capture_id'] as String,
      candidateFields: map['candidate_fields'] as String,
      fieldEvidence: map['field_evidence'] as String,
      validationIssues: map['validation_issues'] as String,
      duplicateCandidates: map['duplicate_candidates'] as String,
      savedTransactionId: map['saved_transaction_id'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'capture_id': captureId,
      'candidate_fields': candidateFields,
      'field_evidence': fieldEvidence,
      'validation_issues': validationIssues,
      'duplicate_candidates': duplicateCandidates,
      'saved_transaction_id': savedTransactionId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Draft copyWith({
    String? id,
    String? captureId,
    String? candidateFields,
    String? fieldEvidence,
    String? validationIssues,
    String? duplicateCandidates,
    String? savedTransactionId,
    String? createdAt,
    String? updatedAt,
  }) {
    return Draft(
      id: id ?? this.id,
      captureId: captureId ?? this.captureId,
      candidateFields: candidateFields ?? this.candidateFields,
      fieldEvidence: fieldEvidence ?? this.fieldEvidence,
      validationIssues: validationIssues ?? this.validationIssues,
      duplicateCandidates: duplicateCandidates ?? this.duplicateCandidates,
      savedTransactionId: savedTransactionId ?? this.savedTransactionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Draft &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          captureId == other.captureId &&
          candidateFields == other.candidateFields &&
          fieldEvidence == other.fieldEvidence &&
          validationIssues == other.validationIssues &&
          duplicateCandidates == other.duplicateCandidates &&
          savedTransactionId == other.savedTransactionId &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        captureId,
        candidateFields,
        fieldEvidence,
        validationIssues,
        duplicateCandidates,
        savedTransactionId,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'Draft(id: $id, captureId: $captureId, savedTransactionId: $savedTransactionId)';
}
