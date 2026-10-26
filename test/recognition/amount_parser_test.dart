// test/recognition/amount_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/features/recognition/amount_parser.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';

void main() {
  group('AmountParser semantic disambiguation & OCR character repair', () {
    test('Labeled line "实付 ¥28.90" is parsed as 2890 minor units', () {
      final lines = [
        OcrTextLine(
          text: '实付 ¥28.90',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.05),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 2890);
      expect(res.paidEvidence, isNotNull);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Disambiguates between 原价, 优惠, 实付, and excludes 余额', () {
      final lines = [
        OcrTextLine(
          text: '商品原价 ¥35.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.4, height: 0.03),
        ),
        OcrTextLine(
          text: '优惠减免 ¥6.10',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.25, width: 0.4, height: 0.03),
        ),
        OcrTextLine(
          text: '实付金额 ¥28.90',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
        OcrTextLine(
          text: '零钱余额 ¥500.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.6, width: 0.4, height: 0.03),
        ),
      ];

      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 2890);
      expect(res.originalAmountMinor, 3500);
      expect(res.discountMinor, 610);
      expect(res.issues.isEmpty, isTrue);
    });

    test('OCR character repairs (O->0, l->1, S->5, B->8)', () {
      final line1 = OcrTextLine(
        text: '实付 ¥ 2O.9O',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
      );
      expect(AmountParser.parse([line1]).paidAmountMinor, 2090);

      final line2 = OcrTextLine(
        text: '支付金额: ¥l2.50',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
      );
      expect(AmountParser.parse([line2]).paidAmountMinor, 1250);

      final line3 = OcrTextLine(
        text: '扣款: ¥S8.00',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
      );
      expect(AmountParser.parse([line3]).paidAmountMinor, 5800);

      final line4 = OcrTextLine(
        text: '实付 ¥ 28.9S',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
      );
      expect(AmountParser.parse([line4]).paidAmountMinor, 2895);
    });

    test('Comma decimal disambiguation (28,90 -> 2890) and thousands separator (1,234.50 -> 123450)', () {
      final line1 = OcrTextLine(
        text: '实付 28,90',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
      );
      expect(AmountParser.parse([line1]).paidAmountMinor, 2890);

      final line2 = OcrTextLine(
        text: '实付 ¥1,234.50',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
      );
      expect(AmountParser.parse([line2]).paidAmountMinor, 123450);
    });

    test('Zero amount flags ZERO_AMOUNT_NOT_PERMITTED and sets paidAmountMinor to null', () {
      final line = OcrTextLine(
        text: '实付 ¥0.00',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
      );
      final res = AmountParser.parse([line]);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.zeroAmountNotPermitted), isTrue);
    });

    test('Missing amount line flags MISSING_AMOUNT', () {
      final line = OcrTextLine(
        text: '微信支付',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.4, height: 0.04),
      );
      final res = AmountParser.parse([line]);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.missingAmount), isTrue);
    });

    test('Multiple conflicting candidate amounts flag MULTIPLE_AMOUNTS', () {
      final lines = [
        OcrTextLine(
          text: '实付 ¥28.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
        OcrTextLine(
          text: '实付 ¥35.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.4, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.issues.any((i) => i.code == ValidationIssue.multipleAmounts), isTrue);
    });

    test('Service fee is correctly parsed into feeMinor', () {
      final lines = [
        OcrTextLine(
          text: '实付 ¥100.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
        OcrTextLine(
          text: '含手续费 ¥0.10',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.4, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 10000);
      expect(res.feeMinor, 10);
      expect(res.feeEvidence, isNotNull);
    });
  });
}
