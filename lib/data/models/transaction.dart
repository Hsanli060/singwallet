// lib/data/models/transaction.dart

/// Model for the `transactions` formal financial ledger table.
class TransactionEntry {
  final String id;
  final String? originDraftId;
  final String type; // 'expense', 'income', 'refund', 'transfer'
  final int amountMinor; // Stored in cents, strictly > 0
  final String currency; // Default 'CNY'
  final String merchantRaw;
  final String? merchantNormalized;
  final String occurredOn; // YYYY-MM-DD
  final String? occurredAt; // UTC ISO-8601
  final String eventTimezone; // Default 'Asia/Shanghai'
  final String eventTimeSource; // 'ocr_extracted', 'suggested_today', 'user_selected'
  final String eventTimePrecision; // 'second', 'minute', 'day'
  final String paymentChannel; // 'wechat', 'alipay', 'unionpay', 'cash', 'other'
  final String? accountId;
  final String? transferToAccountId;
  final String? categoryId;
  final String? projectId;
  final String? note;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  const TransactionEntry({
    required this.id,
    this.originDraftId,
    required this.type,
    required this.amountMinor,
    this.currency = 'CNY',
    required this.merchantRaw,
    this.merchantNormalized,
    required this.occurredOn,
    this.occurredAt,
    this.eventTimezone = 'Asia/Shanghai',
    required this.eventTimeSource,
    required this.eventTimePrecision,
    required this.paymentChannel,
    this.accountId,
    this.transferToAccountId,
    this.categoryId,
    this.projectId,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isInTrash => deletedAt != null;

  factory TransactionEntry.fromMap(Map<String, dynamic> map) {
    return TransactionEntry(
      id: map['id'] as String,
      originDraftId: map['origin_draft_id'] as String?,
      type: map['type'] as String,
      amountMinor: map['amount_minor'] as int,
      currency: (map['currency'] as String?) ?? 'CNY',
      merchantRaw: map['merchant_raw'] as String,
      merchantNormalized: map['merchant_normalized'] as String?,
      occurredOn: map['occurred_on'] as String,
      occurredAt: map['occurred_at'] as String?,
      eventTimezone: (map['event_timezone'] as String?) ?? 'Asia/Shanghai',
      eventTimeSource: map['event_time_source'] as String,
      eventTimePrecision: map['event_time_precision'] as String,
      paymentChannel: map['payment_channel'] as String,
      accountId: map['account_id'] as String?,
      transferToAccountId: map['transfer_to_account_id'] as String?,
      categoryId: map['category_id'] as String?,
      projectId: map['project_id'] as String?,
      note: map['note'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
      deletedAt: map['deleted_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'origin_draft_id': originDraftId,
      'type': type,
      'amount_minor': amountMinor,
      'currency': currency,
      'merchant_raw': merchantRaw,
      'merchant_normalized': merchantNormalized,
      'occurred_on': occurredOn,
      'occurred_at': occurredAt,
      'event_timezone': eventTimezone,
      'event_time_source': eventTimeSource,
      'event_time_precision': eventTimePrecision,
      'payment_channel': paymentChannel,
      'account_id': accountId,
      'transfer_to_account_id': transferToAccountId,
      'category_id': categoryId,
      'project_id': projectId,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  TransactionEntry copyWith({
    String? id,
    String? originDraftId,
    String? type,
    int? amountMinor,
    String? currency,
    String? merchantRaw,
    String? merchantNormalized,
    String? occurredOn,
    String? occurredAt,
    String? eventTimezone,
    String? eventTimeSource,
    String? eventTimePrecision,
    String? paymentChannel,
    String? accountId,
    String? transferToAccountId,
    String? categoryId,
    String? projectId,
    String? note,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
  }) {
    return TransactionEntry(
      id: id ?? this.id,
      originDraftId: originDraftId ?? this.originDraftId,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantNormalized: merchantNormalized ?? this.merchantNormalized,
      occurredOn: occurredOn ?? this.occurredOn,
      occurredAt: occurredAt ?? this.occurredAt,
      eventTimezone: eventTimezone ?? this.eventTimezone,
      eventTimeSource: eventTimeSource ?? this.eventTimeSource,
      eventTimePrecision: eventTimePrecision ?? this.eventTimePrecision,
      paymentChannel: paymentChannel ?? this.paymentChannel,
      accountId: accountId ?? this.accountId,
      transferToAccountId: transferToAccountId ?? this.transferToAccountId,
      categoryId: categoryId ?? this.categoryId,
      projectId: projectId ?? this.projectId,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          originDraftId == other.originDraftId &&
          type == other.type &&
          amountMinor == other.amountMinor &&
          currency == other.currency &&
          merchantRaw == other.merchantRaw &&
          merchantNormalized == other.merchantNormalized &&
          occurredOn == other.occurredOn &&
          occurredAt == other.occurredAt &&
          eventTimezone == other.eventTimezone &&
          eventTimeSource == other.eventTimeSource &&
          eventTimePrecision == other.eventTimePrecision &&
          paymentChannel == other.paymentChannel &&
          accountId == other.accountId &&
          transferToAccountId == other.transferToAccountId &&
          categoryId == other.categoryId &&
          projectId == other.projectId &&
          note == other.note &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          deletedAt == other.deletedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        originDraftId,
        type,
        amountMinor,
        currency,
        merchantRaw,
        merchantNormalized,
        occurredOn,
        occurredAt,
        eventTimezone,
        eventTimeSource,
        eventTimePrecision,
        paymentChannel,
        accountId,
        transferToAccountId,
        categoryId,
        projectId,
        note,
        createdAt,
        updatedAt,
        deletedAt,
      ]);

  @override
  String toString() =>
      'TransactionEntry(id: $id, type: $type, amountMinor: $amountMinor, merchant: $merchantRaw, date: $occurredOn)';
}
