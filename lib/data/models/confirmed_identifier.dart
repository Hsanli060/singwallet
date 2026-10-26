// lib/data/models/confirmed_identifier.dart

/// Model for the `confirmed_identifiers` hard deduplication table.
class ConfirmedIdentifier {
  final String namespace; // e.g. 'wechat_pay', 'alipay', 'unionpay'
  final String identifierType; // e.g. 'platform_transaction_no'
  final String completeValue; // Complete unmasked platform order ID
  final String stableEventKind; // 'payment' or 'refund'
  final String transactionId;

  const ConfirmedIdentifier({
    required this.namespace,
    required this.identifierType,
    required this.completeValue,
    required this.stableEventKind,
    required this.transactionId,
  });

  factory ConfirmedIdentifier.fromMap(Map<String, dynamic> map) {
    return ConfirmedIdentifier(
      namespace: map['namespace'] as String,
      identifierType: map['identifier_type'] as String,
      completeValue: map['complete_value'] as String,
      stableEventKind: map['stable_event_kind'] as String,
      transactionId: map['transaction_id'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'namespace': namespace,
      'identifier_type': identifierType,
      'complete_value': completeValue,
      'stable_event_kind': stableEventKind,
      'transaction_id': transactionId,
    };
  }

  ConfirmedIdentifier copyWith({
    String? namespace,
    String? identifierType,
    String? completeValue,
    String? stableEventKind,
    String? transactionId,
  }) {
    return ConfirmedIdentifier(
      namespace: namespace ?? this.namespace,
      identifierType: identifierType ?? this.identifierType,
      completeValue: completeValue ?? this.completeValue,
      stableEventKind: stableEventKind ?? this.stableEventKind,
      transactionId: transactionId ?? this.transactionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfirmedIdentifier &&
          runtimeType == other.runtimeType &&
          namespace == other.namespace &&
          identifierType == other.identifierType &&
          completeValue == other.completeValue &&
          stableEventKind == other.stableEventKind &&
          transactionId == other.transactionId;

  @override
  int get hashCode => Object.hash(
        namespace,
        identifierType,
        completeValue,
        stableEventKind,
        transactionId,
      );

  @override
  String toString() =>
      'ConfirmedIdentifier(ns: $namespace, val: $completeValue, kind: $stableEventKind, txId: $transactionId)';
}
