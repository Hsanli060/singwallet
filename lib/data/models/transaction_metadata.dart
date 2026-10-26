// lib/data/models/transaction_metadata.dart

/// Model for the `transaction_metadata` table.
class TransactionMetadata {
  final String transactionId;
  final int? originalAmountMinor;
  final int? discountMinor;
  final int? feeMinor;
  final String paymentStatus; // 'SUCCESS', 'REFUNDED', 'PARTIAL_REFUNDED'
  final String? platformTransactionNo;
  final String? merchantOrderNo;
  final String identifierCompleteness; // 'NONE', 'COMPLETE', 'MASKED', 'TRUNCATED', 'UNRELIABLE'
  final String? paymentMethodLabel;

  const TransactionMetadata({
    required this.transactionId,
    this.originalAmountMinor,
    this.discountMinor,
    this.feeMinor,
    this.paymentStatus = 'SUCCESS',
    this.platformTransactionNo,
    this.merchantOrderNo,
    this.identifierCompleteness = 'NONE',
    this.paymentMethodLabel,
  });

  factory TransactionMetadata.fromMap(Map<String, dynamic> map) {
    return TransactionMetadata(
      transactionId: map['transaction_id'] as String,
      originalAmountMinor: map['original_amount_minor'] as int?,
      discountMinor: map['discount_minor'] as int?,
      feeMinor: map['fee_minor'] as int?,
      paymentStatus: (map['payment_status'] as String?) ?? 'SUCCESS',
      platformTransactionNo: map['platform_transaction_no'] as String?,
      merchantOrderNo: map['merchant_order_no'] as String?,
      identifierCompleteness:
          (map['identifier_completeness'] as String?) ?? 'NONE',
      paymentMethodLabel: map['payment_method_label'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'transaction_id': transactionId,
      'original_amount_minor': originalAmountMinor,
      'discount_minor': discountMinor,
      'fee_minor': feeMinor,
      'payment_status': paymentStatus,
      'platform_transaction_no': platformTransactionNo,
      'merchant_order_no': merchantOrderNo,
      'identifier_completeness': identifierCompleteness,
      'payment_method_label': paymentMethodLabel,
    };
  }

  TransactionMetadata copyWith({
    String? transactionId,
    int? originalAmountMinor,
    int? discountMinor,
    int? feeMinor,
    String? paymentStatus,
    String? platformTransactionNo,
    String? merchantOrderNo,
    String? identifierCompleteness,
    String? paymentMethodLabel,
  }) {
    return TransactionMetadata(
      transactionId: transactionId ?? this.transactionId,
      originalAmountMinor: originalAmountMinor ?? this.originalAmountMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      feeMinor: feeMinor ?? this.feeMinor,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      platformTransactionNo:
          platformTransactionNo ?? this.platformTransactionNo,
      merchantOrderNo: merchantOrderNo ?? this.merchantOrderNo,
      identifierCompleteness:
          identifierCompleteness ?? this.identifierCompleteness,
      paymentMethodLabel: paymentMethodLabel ?? this.paymentMethodLabel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionMetadata &&
          runtimeType == other.runtimeType &&
          transactionId == other.transactionId &&
          originalAmountMinor == other.originalAmountMinor &&
          discountMinor == other.discountMinor &&
          feeMinor == other.feeMinor &&
          paymentStatus == other.paymentStatus &&
          platformTransactionNo == other.platformTransactionNo &&
          merchantOrderNo == other.merchantOrderNo &&
          identifierCompleteness == other.identifierCompleteness &&
          paymentMethodLabel == other.paymentMethodLabel;

  @override
  int get hashCode => Object.hash(
        transactionId,
        originalAmountMinor,
        discountMinor,
        feeMinor,
        paymentStatus,
        platformTransactionNo,
        merchantOrderNo,
        identifierCompleteness,
        paymentMethodLabel,
      );

  @override
  String toString() =>
      'TransactionMetadata(txId: $transactionId, status: $paymentStatus, platformNo: $platformTransactionNo)';
}
