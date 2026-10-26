// lib/features/recognition/order_id_parser.dart
import '../../core/native/native_bridge.g.dart';
import '../deduplication/deduplication_engine.dart';
import 'models/field_evidence.dart';
import 'models/validation_issue.dart';

class OrderIdParseResult {
  final String? platformTransactionNo;
  final String? merchantOrderNo;
  final IdentifierCompleteness completeness;
  final FieldEvidence? platformEvidence;
  final FieldEvidence? merchantEvidence;
  final List<ValidationIssue> issues;

  const OrderIdParseResult({
    this.platformTransactionNo,
    this.merchantOrderNo,
    required this.completeness,
    this.platformEvidence,
    this.merchantEvidence,
    this.issues = const [],
  });
}

/// Extracts platform transaction numbers and merchant order IDs and grades completeness
class OrderIdParser {
  static final RegExp _merchantOrderRegex = RegExp(
    r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );

  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );

  static String cleanOrderId(String id) {
    return id
        .replaceAll(' ', '')
        .replaceAll('驯', '31')
        .replaceAll('引', '3')
        .replaceAll('叾', '3')
        .replaceAll('巧', '3')
        .replaceAll('×', 'X');
  }

  /// Analyzes lines and extracts platform and merchant identifiers
  static OrderIdParseResult parse(List<OcrTextLine> lines, {String? channel}) {
    String? merchantOrderNo;
    FieldEvidence? merchantEvidence;
    String? platformTransactionNo;
    FieldEvidence? platformEvidence;
    final issues = <ValidationIssue>[];

    // 1. First pass: look for merchant order no
    for (final line in lines) {
      final text = cleanOrderId(line.text);
      final m = _merchantOrderRegex.firstMatch(text);
      if (m != null) {
        final rawId = m.group(1)?.trim();
        if (rawId != null && rawId.isNotEmpty) {
          merchantOrderNo = rawId;
          merchantEvidence = FieldEvidence(
            rawText: line.text,
            matchedSubstring: rawId,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
            source: 'ocr_extracted',
          );
          break;
        }
      }
    }

    // 2. Look for platform transaction no
    for (final line in lines) {
      final text = cleanOrderId(line.text);
      // If this line was already consumed by merchantOrderNo, skip
      if (_merchantOrderRegex.hasMatch(text)) continue;

      final m = _platformNoRegex.firstMatch(text);
      if (m != null) {
        final rawId = m.group(1)?.trim();
        if (rawId != null && rawId.isNotEmpty) {
          platformTransactionNo = rawId;
          platformEvidence = FieldEvidence(
            rawText: line.text,
            matchedSubstring: rawId,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
            source: 'ocr_extracted',
          );
          break;
        }
      }
    }

    // 3. Fallback: if no platform number matched by label, check for standalone long ID strings
    if (platformTransactionNo == null) {
      for (final line in lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        // Check for long numeric string matching WeChat (420000...) or Alipay (2026... / 2088...)
        final wechatMatch = RegExp(r'\b(420000\d{18,26})\b').firstMatch(text);
        if (wechatMatch != null) {
          platformTransactionNo = wechatMatch.group(1);
          platformEvidence = FieldEvidence(
            rawText: text,
            matchedSubstring: platformTransactionNo!,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
            source: 'ocr_extracted',
          );
          break;
        }

        final alipayMatch = RegExp(r'\b(20\d{26,30})\b').firstMatch(text);
        if (alipayMatch != null) {
          platformTransactionNo = alipayMatch.group(1);
          platformEvidence = FieldEvidence(
            rawText: text,
            matchedSubstring: platformTransactionNo!,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
            source: 'ocr_extracted',
          );
          break;
        }
      }
    }

    // 4. Determine completeness of platform order ID
    IdentifierCompleteness completeness = IdentifierCompleteness.none;

    if (platformTransactionNo != null) {
      final id = platformTransactionNo;
      final hasMaskChars = id.contains('*') ||
          id.contains('＊') ||
          id.contains('...') ||
          id.contains('…') ||
          id.toLowerCase().contains('x');

      if (hasMaskChars) {
        completeness = IdentifierCompleteness.masked;
        issues.add(ValidationIssue.maskedOrderIdIssue());
      } else if (id.length < 16 || id.endsWith('.')) {
        completeness = IdentifierCompleteness.truncated;
        issues.add(ValidationIssue.truncatedOrderIdIssue());
      } else if (platformEvidence?.confidence != null &&
          platformEvidence!.confidence! < 0.60) {
        completeness = IdentifierCompleteness.unreliable;
      } else {
        completeness = IdentifierCompleteness.complete;
      }
    }

    return OrderIdParseResult(
      platformTransactionNo: platformTransactionNo,
      merchantOrderNo: merchantOrderNo,
      completeness: completeness,
      platformEvidence: platformEvidence,
      merchantEvidence: merchantEvidence,
      issues: issues,
    );
  }
}
