// lib/features/recognition/models/validation_issue.dart

enum IssueSeverity { info, warning, error }

/// Structured validation issue generated during OCR receipt parsing
class ValidationIssue {
  final String code;
  final String message;
  final String? field;
  final IssueSeverity severity;

  const ValidationIssue({
    required this.code,
    required this.message,
    this.field,
    this.severity = IssueSeverity.warning,
  });

  // Standard issue codes
  static const String missingAmount = 'MISSING_AMOUNT';
  static const String multipleAmounts = 'MULTIPLE_AMOUNTS';
  static const String zeroAmountNotPermitted = 'ZERO_AMOUNT_NOT_PERMITTED';
  static const String zeroAmount = 'ZERO_AMOUNT';
  static const String missingMerchant = 'MISSING_MERCHANT';
  static const String missingDate = 'MISSING_DATE';
  static const String paymentNotSuccess = 'PAYMENT_NOT_SUCCESS';
  static const String nonSuccessStatus = 'NON_SUCCESS_STATUS';
  static const String maskedOrderId = 'MASKED_ORDER_ID';
  static const String truncatedOrderId = 'TRUNCATED_ORDER_ID';
  static const String incompleteOrderId = 'INCOMPLETE_ORDER_ID';
  static const String foreignCurrencyDetected = 'FOREIGN_CURRENCY_DETECTED';
  static const String lowConfidence = 'LOW_CONFIDENCE';
  static const String suspectedDuplicate = 'SUSPECTED_DUPLICATE';

  // Factory constructors for convenience
  factory ValidationIssue.missingAmountIssue() => const ValidationIssue(
        code: missingAmount,
        message: '未识别到支付金额，请手动填写。',
        field: 'amount',
        severity: IssueSeverity.error,
      );

  factory ValidationIssue.zeroAmountIssue() => const ValidationIssue(
        code: zeroAmountNotPermitted,
        message: '实付金额为 0 元，不可作为正式记账交易保存。',
        field: 'amount',
        severity: IssueSeverity.error,
      );

  factory ValidationIssue.multipleAmountsIssue() => const ValidationIssue(
        code: multipleAmounts,
        message: '识别到多个冲突金额，请确认最终实付金额。',
        field: 'amount',
        severity: IssueSeverity.warning,
      );

  factory ValidationIssue.missingMerchantIssue() => const ValidationIssue(
        code: missingMerchant,
        message: '未识别到商户名称，请核对。',
        field: 'merchant',
        severity: IssueSeverity.warning,
      );

  factory ValidationIssue.missingDateIssue() => const ValidationIssue(
        code: missingDate,
        message: '未识别到交易时间，已自动回退至今天。',
        field: 'date',
        severity: IssueSeverity.warning,
      );

  factory ValidationIssue.nonSuccessStatusIssue(String status) => ValidationIssue(
        code: paymentNotSuccess,
        message: '交易状态非已支付 ($status)，请确认是否记账。',
        field: 'status',
        severity: IssueSeverity.warning,
      );

  factory ValidationIssue.maskedOrderIdIssue() => const ValidationIssue(
        code: maskedOrderId,
        message: '订单号存在脱敏遮蔽字符，无法参与强唯一性防重。',
        field: 'order_id',
        severity: IssueSeverity.info,
      );

  factory ValidationIssue.truncatedOrderIdIssue() => const ValidationIssue(
        code: truncatedOrderId,
        message: '订单号长度不全或被截断。',
        field: 'order_id',
        severity: IssueSeverity.info,
      );

  Map<String, dynamic> toMap() => {
        'code': code,
        'message': message,
        'field': field,
        'severity': severity.name,
      };

  Map<String, dynamic> toJson() => toMap();

  factory ValidationIssue.fromMap(Map<String, dynamic> map) {
    final sevStr = map['severity'] as String?;
    final sev = IssueSeverity.values.firstWhere(
      (e) => e.name == sevStr,
      orElse: () => IssueSeverity.warning,
    );
    return ValidationIssue(
      code: (map['code'] ?? '') as String,
      message: (map['message'] ?? '') as String,
      field: map['field'] as String?,
      severity: sev,
    );
  }

  factory ValidationIssue.fromJson(Map<String, dynamic> json) =>
      ValidationIssue.fromMap(json);

  @override
  String toString() => 'ValidationIssue(code: $code, message: "$message")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationIssue &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          field == other.field &&
          severity == other.severity;

  @override
  int get hashCode => Object.hash(code, message, field, severity);
}
