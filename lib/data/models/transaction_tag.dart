// lib/data/models/transaction_tag.dart

/// Model for the `transaction_tags` join table.
class TransactionTag {
  final String transactionId;
  final String tagId;

  const TransactionTag({
    required this.transactionId,
    required this.tagId,
  });

  factory TransactionTag.fromMap(Map<String, dynamic> map) {
    return TransactionTag(
      transactionId: map['transaction_id'] as String,
      tagId: map['tag_id'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'transaction_id': transactionId,
      'tag_id': tagId,
    };
  }

  TransactionTag copyWith({
    String? transactionId,
    String? tagId,
  }) {
    return TransactionTag(
      transactionId: transactionId ?? this.transactionId,
      tagId: tagId ?? this.tagId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionTag &&
          runtimeType == other.runtimeType &&
          transactionId == other.transactionId &&
          tagId == other.tagId;

  @override
  int get hashCode => Object.hash(transactionId, tagId);

  @override
  String toString() => 'TransactionTag(txId: $transactionId, tagId: $tagId)';
}
