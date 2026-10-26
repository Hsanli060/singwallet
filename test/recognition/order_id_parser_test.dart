// test/recognition/order_id_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
import 'package:singwallet/features/recognition/order_id_parser.dart';

void main() {
  group('OrderIdParser completeness grading and extraction', () {
    test('WeChat full 28-digit transaction number has COMPLETE completeness', () {
      final lines = [
        OcrTextLine(
          text: '交易单号 4200002134202610221234567890',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.7, width: 0.8, height: 0.03),
          confidence: 0.99,
        ),
      ];

      final res = OrderIdParser.parse(lines);
      expect(res.platformTransactionNo, '4200002134202610221234567890');
      expect(res.completeness, IdentifierCompleteness.complete);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Alipay full 28-digit transaction number has COMPLETE completeness', () {
      final lines = [
        OcrTextLine(
          text: '订单号 2026102222001412341412345678',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.7, width: 0.8, height: 0.03),
          confidence: 0.95,
        ),
      ];

      final res = OrderIdParser.parse(lines);
      expect(res.platformTransactionNo, '2026102222001412341412345678');
      expect(res.completeness, IdentifierCompleteness.complete);
    });

    test('Masked order ID with asterisks has MASKED completeness and flags issue', () {
      final lines = [
        OcrTextLine(
          text: '交易单号 420000****1234',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.7, width: 0.8, height: 0.03),
        ),
      ];

      final res = OrderIdParser.parse(lines);
      expect(res.platformTransactionNo, '420000****1234');
      expect(res.completeness, IdentifierCompleteness.masked);
      expect(res.issues.any((i) => i.code == ValidationIssue.maskedOrderId), isTrue);
    });

    test('Truncated order ID with insufficient length has TRUNCATED completeness', () {
      final lines = [
        OcrTextLine(
          text: '交易单号 42000021',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.7, width: 0.8, height: 0.03),
        ),
      ];

      final res = OrderIdParser.parse(lines);
      expect(res.platformTransactionNo, '42000021');
      expect(res.completeness, IdentifierCompleteness.truncated);
      expect(res.issues.any((i) => i.code == ValidationIssue.truncatedOrderId), isTrue);
    });

    test('Merchant order number is correctly distinguished from platform transaction number', () {
      final lines = [
        OcrTextLine(
          text: '商户单号 20261022998877',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.65, width: 0.7, height: 0.03),
        ),
        OcrTextLine(
          text: '交易单号 4200002134202610229988776655',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.7, width: 0.8, height: 0.03),
        ),
      ];

      final res = OrderIdParser.parse(lines);
      expect(res.merchantOrderNo, '20261022998877');
      expect(res.platformTransactionNo, '4200002134202610229988776655');
      expect(res.completeness, IdentifierCompleteness.complete);
    });
  });
}
