// lib/data/models/refund_link.dart

/// Model for the `refund_links` table.
class RefundLink {
  final String refundTransactionId;
  final String originalExpenseId;
  final String createdAt;

  const RefundLink({
    required this.refundTransactionId,
    required this.originalExpenseId,
    required this.createdAt,
  });

  factory RefundLink.fromMap(Map<String, dynamic> map) {
    return RefundLink(
      refundTransactionId: map['refund_transaction_id'] as String,
      originalExpenseId: map['original_expense_id'] as String,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'refund_transaction_id': refundTransactionId,
      'original_expense_id': originalExpenseId,
      'created_at': createdAt,
    };
  }

  RefundLink copyWith({
    String? refundTransactionId,
    String? originalExpenseId,
    String? createdAt,
  }) {
    return RefundLink(
      refundTransactionId: refundTransactionId ?? this.refundTransactionId,
      originalExpenseId: originalExpenseId ?? this.originalExpenseId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RefundLink &&
          runtimeType == other.runtimeType &&
          refundTransactionId == other.refundTransactionId &&
          originalExpenseId == other.originalExpenseId &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        refundTransactionId,
        originalExpenseId,
        createdAt,
      );

  @override
  String toString() =>
      'RefundLink(refundId: $refundTransactionId, originalExpenseId: $originalExpenseId)';
}
