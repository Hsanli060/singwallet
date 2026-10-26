// lib/features/recognition/models/parsed_draft_result.dart
import 'dart:convert';
import '../../../data/models/draft.dart';
import '../../deduplication/deduplication_engine.dart';
import 'field_evidence.dart';
import 'validation_issue.dart';

/// Synthesized outcome of the OCR recognition and extraction pipeline
class ParsedDraftResult {
  final String captureId;
  final String type; // 'expense', 'refund', 'income', 'transfer'
  final int? amountMinor;
  final int? originalAmountMinor;
  final int? discountMinor;
  final int? feeMinor;
  final String currency;
  final String? merchantRaw;
  final String? merchantNormalized;
  final String occurredOn; // 'YYYY-MM-DD'
  final String? occurredAt; // UTC ISO-8601 string or null
  final String eventTimezone;
  final String eventTimeSource; // 'ocr_extracted', 'suggested_today', 'user_selected'
  final String eventTimePrecision; // 'second', 'minute', 'day'
  final String paymentChannel; // 'wechat', 'alipay', 'unionpay', 'bank_card', 'other'
  final String paymentStatus; // 'SUCCESS', 'PENDING', 'FAILED', 'REFUNDED'
  final String? paymentMethodLabel;
  final String? platformTransactionNo;
  final String? merchantOrderNo;
  final IdentifierCompleteness identifierCompleteness;
  final String? suggestedCategoryId;
  final String? suggestedProjectId;
  final List<String> suggestedTagIds;
  final Map<String, FieldEvidence> fieldEvidence;
  final List<ValidationIssue> validationIssues;
  final List<String> duplicateCandidates;
  final double confidenceScore;

  const ParsedDraftResult({
    required this.captureId,
    this.type = 'expense',
    this.amountMinor,
    this.originalAmountMinor,
    this.discountMinor,
    this.feeMinor,
    this.currency = 'CNY',
    this.merchantRaw,
    this.merchantNormalized,
    required this.occurredOn,
    this.occurredAt,
    this.eventTimezone = 'Asia/Shanghai',
    required this.eventTimeSource,
    required this.eventTimePrecision,
    required this.paymentChannel,
    this.paymentStatus = 'SUCCESS',
    this.paymentMethodLabel,
    this.platformTransactionNo,
    this.merchantOrderNo,
    this.identifierCompleteness = IdentifierCompleteness.none,
    this.suggestedCategoryId,
    this.suggestedProjectId,
    this.suggestedTagIds = const [],
    this.fieldEvidence = const {},
    this.validationIssues = const [],
    this.duplicateCandidates = const [],
    this.confidenceScore = 1.0,
  });

  bool get isConfident =>
      amountMinor != null &&
      amountMinor! > 0 &&
      merchantRaw != null &&
      merchantRaw!.trim().isNotEmpty &&
      occurredOn.isNotEmpty &&
      paymentStatus == 'SUCCESS' &&
      !validationIssues.any((i) => i.severity == IssueSeverity.error);

  /// Converts candidate fields into Map matching drafts table schema
  Map<String, dynamic> toCandidateFieldsMap() {
    return {
      'type': type,
      'amount_minor': amountMinor,
      'amountMinor': amountMinor,
      'currency': currency,
      'merchant_raw': merchantRaw,
      'merchantRaw': merchantRaw,
      'merchant_normalized': merchantNormalized,
      'merchantNormalized': merchantNormalized,
      'occurred_on': occurredOn,
      'occurredOn': occurredOn,
      'occurred_at': occurredAt,
      'occurredAt': occurredAt,
      'event_timezone': eventTimezone,
      'eventTimezone': eventTimezone,
      'event_time_source': eventTimeSource,
      'eventTimeSource': eventTimeSource,
      'event_time_precision': eventTimePrecision,
      'eventTimePrecision': eventTimePrecision,
      'payment_channel': paymentChannel,
      'paymentChannel': paymentChannel,
      'payment_status': paymentStatus,
      'paymentStatus': paymentStatus,
      'payment_method_label': paymentMethodLabel,
      'paymentMethodLabel': paymentMethodLabel,
      'platform_transaction_no': platformTransactionNo,
      'platformTransactionNo': platformTransactionNo,
      'merchant_order_no': merchantOrderNo,
      'merchantOrderNo': merchantOrderNo,
      'identifier_completeness': identifierCompleteness.toDbValue(),
      'identifierCompleteness': identifierCompleteness.toDbValue(),
      'original_amount_minor': originalAmountMinor,
      'originalAmountMinor': originalAmountMinor,
      'discount_minor': discountMinor,
      'discountMinor': discountMinor,
      'fee_minor': feeMinor,
      'feeMinor': feeMinor,
      'suggested_category_id': suggestedCategoryId,
      'suggestedCategoryId': suggestedCategoryId,
      'suggested_project_id': suggestedProjectId,
      'suggestedProjectId': suggestedProjectId,
      'suggested_tag_ids': suggestedTagIds,
      'suggestedTagIds': suggestedTagIds,
      'confidence_score': confidenceScore,
      'confidenceScore': confidenceScore,
    };
  }

  /// Serializes into candidate_fields JSON matching drafts table schema
  String toCandidateFieldsJson() => jsonEncode(toCandidateFieldsMap());

  /// Serializes fieldEvidence JSON matching drafts table schema
  String toFieldEvidenceJson() {
    return jsonEncode(fieldEvidence.map((k, v) => MapEntry(k, v.toMap())));
  }

  /// Serializes validationIssues JSON array matching drafts table schema
  String toValidationIssuesJson() {
    return jsonEncode(validationIssues.map((e) => e.code).toList());
  }

  /// Serializes duplicate candidates JSON array
  String toDuplicateCandidatesJson() {
    return jsonEncode(duplicateCandidates);
  }

  /// Synthesizes a Draft entity for persistence in SQLite `drafts` table
  Draft toDraftEntity({required String draftId, required String captureId}) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return Draft(
      id: draftId,
      captureId: captureId,
      candidateFields: toCandidateFieldsJson(),
      fieldEvidence: toFieldEvidenceJson(),
      validationIssues: toValidationIssuesJson(),
      duplicateCandidates: toDuplicateCandidatesJson(),
      savedTransactionId: null,
      createdAt: nowIso,
      updatedAt: nowIso,
    );
  }

  ParsedDraftResult copyWith({
    String? captureId,
    String? type,
    int? amountMinor,
    int? originalAmountMinor,
    int? discountMinor,
    int? feeMinor,
    String? currency,
    String? merchantRaw,
    String? merchantNormalized,
    String? occurredOn,
    String? occurredAt,
    String? eventTimezone,
    String? eventTimeSource,
    String? eventTimePrecision,
    String? paymentChannel,
    String? paymentStatus,
    String? paymentMethodLabel,
    String? platformTransactionNo,
    String? merchantOrderNo,
    IdentifierCompleteness? identifierCompleteness,
    String? suggestedCategoryId,
    String? suggestedProjectId,
    List<String>? suggestedTagIds,
    Map<String, FieldEvidence>? fieldEvidence,
    List<ValidationIssue>? validationIssues,
    List<String>? duplicateCandidates,
    double? confidenceScore,
  }) {
    return ParsedDraftResult(
      captureId: captureId ?? this.captureId,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      originalAmountMinor: originalAmountMinor ?? this.originalAmountMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      feeMinor: feeMinor ?? this.feeMinor,
      currency: currency ?? this.currency,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantNormalized: merchantNormalized ?? this.merchantNormalized,
      occurredOn: occurredOn ?? this.occurredOn,
      occurredAt: occurredAt ?? this.occurredAt,
      eventTimezone: eventTimezone ?? this.eventTimezone,
      eventTimeSource: eventTimeSource ?? this.eventTimeSource,
      eventTimePrecision: eventTimePrecision ?? this.eventTimePrecision,
      paymentChannel: paymentChannel ?? this.paymentChannel,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethodLabel: paymentMethodLabel ?? this.paymentMethodLabel,
      platformTransactionNo: platformTransactionNo ?? this.platformTransactionNo,
      merchantOrderNo: merchantOrderNo ?? this.merchantOrderNo,
      identifierCompleteness: identifierCompleteness ?? this.identifierCompleteness,
      suggestedCategoryId: suggestedCategoryId ?? this.suggestedCategoryId,
      suggestedProjectId: suggestedProjectId ?? this.suggestedProjectId,
      suggestedTagIds: suggestedTagIds ?? this.suggestedTagIds,
      fieldEvidence: fieldEvidence ?? this.fieldEvidence,
      validationIssues: validationIssues ?? this.validationIssues,
      duplicateCandidates: duplicateCandidates ?? this.duplicateCandidates,
      confidenceScore: confidenceScore ?? this.confidenceScore,
    );
  }
}
