// test/recognition/ocr_adversarial_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/utils/currency_utils.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/amount_parser.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
import 'package:singwallet/features/recognition/noise_filter.dart';
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:singwallet/features/recognition/order_id_parser.dart';

void main() {
  group('Vector 1: Optical character confusion on amounts', () {
    test('Vector 1.1: Labeled "实付 ¥2O.OO" -> 2000 minor units (O repaired to 0)', () {
      final lines = [
        OcrTextLine(
          text: '实付 ¥2O.OO',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 2000);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 1.2: Labeled "实付 l2.5O" -> 1250 minor units (l repaired to 1, O to 0)', () {
      final lines = [
        OcrTextLine(
          text: '实付 l2.5O',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 1250);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 1.3: Labeled "实付 S8.OO" -> 5800 minor units (S repaired to 5, O to 0)', () {
      final lines = [
        OcrTextLine(
          text: '实付 S8.OO',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 5800);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 1.4: Labeled "实付 B8.9O" -> 8890 minor units (B repaired to 8, O to 0)', () {
      final lines = [
        OcrTextLine(
          text: '实付 B8.9O',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 8890);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 1.5: Labeled "实付 28,90" (comma as decimal separator) -> 2890 minor units', () {
      final lines = [
        OcrTextLine(
          text: '实付 28,90',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 2890);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 1.6: Labeled "实付 1,234.50" (thousands grouping separator) -> 123450 minor units', () {
      final lines = [
        OcrTextLine(
          text: '实付 1,234.50',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 123450);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 1.7: Standalone confused amounts without labels', () {
      final testCases = [
        ('¥2O.OO', 2000),
        ('l2.5O', 1250),
        ('S8.OO', 5800),
        ('B8.9O', 8890),
        ('28,90', 2890),
        ('1,234.50', 123450),
      ];

      for (final (text, expectedCents) in testCases) {
        final lines = [
          OcrTextLine(
            text: text,
            boundingBox: OcrBoundingBox(left: 0.2, top: 0.3, width: 0.3, height: 0.05),
          ),
        ];
        final res = AmountParser.parse(lines);
        expect(res.paidAmountMinor, expectedCents,
            reason: 'Standalone amount "$text" should parse to $expectedCents cents');
      }
    });

    test('Vector 1.8: CurrencyUtils and AmountParser character repair mechanisms', () {
      // Direct verification of AmountParser character repair logic
      expect(AmountParser.extractMinorUnits('￥２８．９０'), 2890);
      expect(AmountParser.extractMinorUnits('¥28·90'), 2890);
      expect(AmountParser.extractMinorUnits('¥28。90'), 2890);
      expect(AmountParser.extractMinorUnits('¥2O.OO'), 2000);
      expect(AmountParser.extractMinorUnits('l2.5O'), 1250);
      expect(AmountParser.extractMinorUnits('S8.OO'), 5800);
      expect(AmountParser.extractMinorUnits('B8.9O'), 8890);
      expect(AmountParser.extractMinorUnits('28,90'), 2890);
      expect(AmountParser.extractMinorUnits('1,234.50'), 123450);
    });

    test('Vector 1.9: Consecutive OCR confused characters (¥1OOO.OO) must be repaired to ¥1000.00', () {
      // Optical confusion with consecutive 'O' characters
      expect(AmountParser.repairOcrNumbers('¥1OOO.OO'), '¥1000.00',
          reason: 'Consecutive "O"s must be fully repaired without leaving stray "O"s');
    });
  });

  group('Vector 2: Negative, zero, or distorted amounts', () {
    test('Vector 2.1: "0.00" triggers ZERO_AMOUNT_NOT_PERMITTED validation issue and sets paidAmountMinor to null', () {
      final lines = [
        OcrTextLine(
          text: '实付 ¥0.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.zeroAmountNotPermitted), isTrue);
    });

    test('Vector 2.2: Integer "0" triggers ZERO_AMOUNT_NOT_PERMITTED validation issue', () {
      final lines = [
        OcrTextLine(
          text: '实付 0',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.zeroAmountNotPermitted), isTrue);
    });

    test('Vector 2.3: Single decimal "0.0" triggers ZERO_AMOUNT_NOT_PERMITTED validation issue', () {
      final lines = [
        OcrTextLine(
          text: '实付 0.0',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.zeroAmountNotPermitted), isTrue);
    });

    test('Vector 2.4: Invalid symbols (@#\$%!~) trigger MISSING_AMOUNT validation issue', () {
      final lines = [
        OcrTextLine(
          text: '实付 @#\$%!~',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.missingAmount), isTrue);
    });

    test('Vector 2.5: Empty currency or standalone punctuation (¥.) triggers MISSING_AMOUNT validation issue', () {
      final lines = [
        OcrTextLine(
          text: '实付 ¥.',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.missingAmount), isTrue);
    });

    test('Vector 2.5b: Distorted amount with multiple decimals (12.34.56) should not be silently truncated', () {
      final lines = [
        OcrTextLine(
          text: '实付 12.34.56',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, isNull,
          reason: 'Distorted amount "12.34.56" must not be silently truncated to 12.34 / 1234 cents');
    });

    test('Vector 2.6: CurrencyUtils strictly rejects invalid distorted formats with FormatException', () {
      expect(
        () => CurrencyUtils.parseToMinorUnits('12.34.56'),
        throwsA(isA<FormatException>()),
      );
      expect(CurrencyUtils.tryParseToMinorUnits('12.34.56'), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits(''), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits('.'), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits('abc'), isNull);
    });

    test('Vector 2.7: CurrencyUtils strictly rejects negative amount when allowNegative is false', () {
      expect(
        () => CurrencyUtils.parseToMinorUnits('-50.00'),
        throwsA(isA<FormatException>()),
      );
      expect(CurrencyUtils.tryParseToMinorUnits('-50.00'), isNull);
    });

    test('Vector 2.8: Mobile receipt negative amount convention (-50.00) is parsed to positive cents for SQLite CHECK (amount_minor > 0)', () {
      // WeChat / Alipay expense receipts format expenditure with leading minus: "-50.00".
      // The parser normalizes this to positive integer cents to satisfy the SQLite CHECK constraint.
      final lines = [
        OcrTextLine(
          text: '实付 -50.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 5000);
      expect(res.paidAmountMinor! > 0, isTrue);
    });
  });

  group('Vector 3: Multi-amount receipt disambiguation', () {
    test('Vector 3.1: Complete receipt containing 原价, 优惠, 折扣, 实付, 手续费, 零钱余额 strictly selects 实付 and excludes balance', () {
      final lines = [
        OcrTextLine(
          text: '商品原价 ¥120.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.20, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '店铺优惠 ¥15.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.25, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '折扣 ¥5.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.30, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '实付金额 ¥100.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.35, width: 0.5, height: 0.04),
        ),
        OcrTextLine(
          text: '含手续费 ¥0.80',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.40, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '零钱余额 ¥8888.88',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.60, width: 0.6, height: 0.03),
        ),
        OcrTextLine(
          text: '账户可用余额 ¥666.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.65, width: 0.6, height: 0.03),
        ),
        OcrTextLine(
          text: '当前余额 ¥1000.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.70, width: 0.6, height: 0.03),
        ),
      ];

      final res = AmountParser.parse(lines);

      // Verify that paid amount is strictly 实付 (10000 cents = 100.00 yuan)
      expect(res.paidAmountMinor, 10000);
      expect(res.originalAmountMinor, 12000);
      expect(res.discountMinor, 1500);
      expect(res.feeMinor, 80);

      // Verify none of the balance amounts (888888, 66600, 100000) were selected as paid amount
      expect(res.paidAmountMinor != 888888, isTrue);
      expect(res.paidAmountMinor != 66600, isTrue);
      expect(res.paidAmountMinor != 100000, isTrue);

      // Verify evidences are captured
      expect(res.paidEvidence, isNotNull);
      expect(res.paidEvidence!.rawText, contains('实付金额 ¥100.00'));
      expect(res.originalEvidence, isNotNull);
      expect(res.discountEvidence, isNotNull);
      expect(res.feeEvidence, isNotNull);

      // No validation issues for clearly disambiguated amounts
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 3.2: Receipt where 零钱余额 appears before 实付', () {
      final lines = [
        OcrTextLine(
          text: '零钱余额 ¥5000.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.15, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '实付 ¥45.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.30, width: 0.4, height: 0.04),
        ),
      ];

      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 4500);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Vector 3.3: Receipt with only 零钱余额 triggers MISSING_AMOUNT issue', () {
      final lines = [
        OcrTextLine(
          text: '零钱余额 ¥1250.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.30, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '账户可用余额 ¥800.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.40, width: 0.5, height: 0.03),
        ),
      ];

      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.missingAmount), isTrue);
    });

    test('Vector 3.4: Multiple conflicting 实付 lines trigger MULTIPLE_AMOUNTS warning issue', () {
      final lines = [
        OcrTextLine(
          text: '实付 ¥50.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.30, width: 0.4, height: 0.04),
        ),
        OcrTextLine(
          text: '实付款 ¥65.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.40, width: 0.4, height: 0.04),
        ),
      ];

      final res = AmountParser.parse(lines);
      // Takes first candidate but flags multiple amounts warning
      expect(res.paidAmountMinor, 5000);
      expect(res.issues.any((i) => i.code == ValidationIssue.multipleAmounts), isTrue);
    });
  });

  group('Vector 4: Extreme status bar & home bar bounding boxes at boundary edges', () {
    test('Boundary 4.1: Default status bar edge threshold (0.059 vs 0.061)', () {
      final lineBelow = OcrTextLine(
        text: '09:41',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.059, width: 0.2, height: 0.02),
      );
      final lineOnThreshold = OcrTextLine(
        text: '中国移动',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.060, width: 0.2, height: 0.02),
      );
      final lineAbove = OcrTextLine(
        text: '瑞幸咖啡',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.061, width: 0.4, height: 0.04),
      );

      expect(NoiseFilter.isNoise(lineBelow), isTrue,
          reason: 'top=0.059 < 0.06 must be filtered as status bar noise');
      expect(NoiseFilter.isNoise(lineOnThreshold), isFalse,
          reason: 'top=0.060 >= 0.06 is at boundary, not top noise');
      expect(NoiseFilter.isNoise(lineAbove), isFalse,
          reason: 'top=0.061 >= 0.06 must be retained as receipt content');
    });

    test('Boundary 4.2: Dynamic Island status bar threshold (0.074 vs 0.076)', () {
      final lineBelow = OcrTextLine(
        text: '5G',
        boundingBox: OcrBoundingBox(left: 0.8, top: 0.074, width: 0.1, height: 0.02),
      );
      final lineOnThreshold = OcrTextLine(
        text: '100%',
        boundingBox: OcrBoundingBox(left: 0.8, top: 0.075, width: 0.1, height: 0.02),
      );
      final lineAbove = OcrTextLine(
        text: '星巴克咖啡',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.076, width: 0.4, height: 0.04),
      );

      expect(NoiseFilter.isNoise(lineBelow, hasDynamicIsland: true), isTrue,
          reason: 'top=0.074 < 0.075 must be filtered under dynamic island profile');
      expect(NoiseFilter.isNoise(lineOnThreshold, hasDynamicIsland: true), isFalse,
          reason: 'top=0.075 >= 0.075 is at boundary');
      expect(NoiseFilter.isNoise(lineAbove, hasDynamicIsland: true), isFalse,
          reason: 'top=0.076 >= 0.075 must be retained as receipt content');
    });

    test('Boundary 4.3: Home indicator bottom threshold (0.949 vs 0.951)', () {
      final lineAbove = OcrTextLine(
        text: '合计',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.949, width: 0.2, height: 0.02),
      );
      final lineOnThreshold = OcrTextLine(
        text: '—',
        boundingBox: OcrBoundingBox(left: 0.4, top: 0.950, width: 0.2, height: 0.01),
      );
      final lineBelow = OcrTextLine(
        text: '—',
        boundingBox: OcrBoundingBox(left: 0.4, top: 0.951, width: 0.2, height: 0.01),
      );

      expect(NoiseFilter.isNoise(lineAbove), isFalse,
          reason: 'top=0.949 and bottom < 0.98 must be retained');
      expect(NoiseFilter.isNoise(lineOnThreshold), isTrue,
          reason: 'top=0.950 >= 0.95 must be filtered as home indicator');
      expect(NoiseFilter.isNoise(lineBelow), isTrue,
          reason: 'top=0.951 >= 0.95 must be filtered as home indicator');
    });

    test('Boundary 4.4: Bottom edge span threshold (top + height >= 0.98)', () {
      final lineSpanningBottom = OcrTextLine(
        text: '底部装饰条',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.940, width: 0.8, height: 0.045), // 0.940 + 0.045 = 0.985 >= 0.98
      );
      final lineInsideSafeArea = OcrTextLine(
        text: '温馨提示',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.940, width: 0.8, height: 0.035), // 0.940 + 0.035 = 0.975 < 0.98
      );

      expect(NoiseFilter.isNoise(lineSpanningBottom), isTrue,
          reason: 'top + height >= 0.98 must be filtered');
      expect(NoiseFilter.isNoise(lineInsideSafeArea), isFalse,
          reason: 'top < 0.95 and bottom < 0.98 must be retained');
    });

    test('Boundary 4.5: Action button chrome filtering regardless of position', () {
      final chromeButtons = [
        '查看账单详情',
        '完成',
        '关闭',
        '返回商家',
        '开发票',
        '评价',
      ];

      for (final text in chromeButtons) {
        final line = OcrTextLine(
          text: text,
          boundingBox: OcrBoundingBox(left: 0.3, top: 0.50, width: 0.4, height: 0.04), // Middle of screen!
        );
        expect(NoiseFilter.isNoise(line), isTrue,
            reason: 'Button "$text" must be recognized as UI chrome noise');
      }
    });

    test('Boundary 4.6: End-to-end pipeline respects boundary filtering across regions', () async {
      final db = await AppDatabase.openInMemory();
      final pipeline = OcrParsingPipeline(
        dedupEngine: DeduplicationEngine(db),
      );

      final doc = OcrDocument(
        captureId: 'cap_boundary_test',
        engineIdentifier: 'test',
        processTimeMs: 50,
        lines: [
          OcrTextLine(
            text: '09:41',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.059, width: 0.2, height: 0.02), // noise (filtered)
          ),
          OcrTextLine(
            text: '微信支付',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.080, width: 0.3, height: 0.03), // retained
          ),
          OcrTextLine(
            text: '实付 ¥25.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.30, width: 0.4, height: 0.04), // retained
          ),
          OcrTextLine(
            text: '—',
            boundingBox: OcrBoundingBox(left: 0.4, top: 0.951, width: 0.2, height: 0.01), // noise (filtered)
          ),
        ],
      );

      final result = await pipeline.process(doc);
      expect(result.amountMinor, 2500);
      expect(result.paymentChannel, 'wechat');

      await db.close();
    });
  });

  group('Vector 5: Masked & truncated order numbers', () {
    test('Vector 5.1: Masked order IDs (*, ..., …, x, X) are NOT complete and NOT eligible for hard dedup', () {
      final testCases = [
        ('4200002134****88776655', 'contains asterisks *'),
        ('202610222200...5678', 'contains dots ...'),
        ('202610222200…5678', 'contains unicode ellipsis …'),
        ('4200002134xxxx88776655', 'contains lowercase x'),
        ('4200002134XXXX88776655', 'contains uppercase X'),
      ];

      for (final (id, description) in testCases) {
        final line = OcrTextLine(
          text: '交易单号 $id',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.04),
        );
        final res = OrderIdParser.parse([line]);

        // CRITICAL ADVERSARIAL ASSERTION:
        // Masked order IDs MUST NOT be marked as complete platform identifiers!
        expect(res.completeness == IdentifierCompleteness.complete, isFalse,
            reason: '$id ($description) must NOT have COMPLETE completeness');

        // Must be classified as masked (or truncated if unicode ellipsis splits regex)
        expect(
          res.completeness == IdentifierCompleteness.masked ||
              res.completeness == IdentifierCompleteness.truncated,
          isTrue,
          reason: '$id must be classified as either masked or truncated',
        );

        // Deduplication eligibility must be false
        final platformId = PlatformIdentifier(
          namespace: 'wechat_pay',
          identifierType: 'platform_transaction_no',
          completeValue: res.platformTransactionNo ?? id,
          stableEventKind: 'payment',
          completeness: res.completeness,
        );
        expect(platformId.isEligibleForHardDedup, isFalse,
            reason: '$id must NOT be eligible for Tier 3 hard deduplication');

        // Validation issues must be generated
        expect(
          res.issues.any((i) =>
              i.code == ValidationIssue.maskedOrderId ||
              i.code == ValidationIssue.truncatedOrderId),
          isTrue,
          reason: '$id must generate a validation issue',
        );
      }
    });

    test('Vector 5.1b: Masked order ID with ellipsis … and 16+ prefix digits must NOT be marked COMPLETE', () {
      final line = OcrTextLine(
        text: '交易单号 4200002134202610…1234',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.04),
      );
      final res = OrderIdParser.parse([line]);
      // CRITICAL HARD-DEDUP SAFETY VULNERABILITY:
      // Because _platformNoRegex stops before '…', platformTransactionNo is extracted as '4200002134202610' (16 digits).
      // Since length >= 16 and contains no '*', it is falsely marked as COMPLETE.
      expect(res.completeness == IdentifierCompleteness.complete, isFalse,
          reason: 'Masked ID with ellipsis must NOT be graded as complete');
    });

    test('Vector 5.2: Truncated order IDs (< 16 chars or ending with .) are NOT complete and NOT eligible for hard dedup', () {
      final testCases = [
        ('4200002134', '10 chars < 16'),
        ('123456789012345', '15 chars < 16'),
        ('4200002134202610229988.', 'ends with dot'),
      ];

      for (final (id, description) in testCases) {
        final line = OcrTextLine(
          text: '交易单号 $id',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.04),
        );
        final res = OrderIdParser.parse([line]);

        expect(res.completeness == IdentifierCompleteness.complete, isFalse,
            reason: '$id ($description) must NOT have COMPLETE completeness');
        expect(res.completeness, IdentifierCompleteness.truncated,
            reason: '$id ($description) must be graded as TRUNCATED');

        final platformId = PlatformIdentifier(
          namespace: 'wechat_pay',
          identifierType: 'platform_transaction_no',
          completeValue: res.platformTransactionNo ?? id,
          stableEventKind: 'payment',
          completeness: res.completeness,
        );
        expect(platformId.isEligibleForHardDedup, isFalse,
            reason: '$id must NOT be eligible for Tier 3 hard deduplication');

        expect(res.issues.any((i) => i.code == ValidationIssue.truncatedOrderId), isTrue,
            reason: '$id must trigger TRUNCATED_ORDER_ID validation issue');
      }
    });

    test('Vector 5.3: Low OCR confidence (< 0.60) grades completeness as UNRELIABLE', () {
      final line = OcrTextLine(
        text: '交易单号 4200002134202610229988776655',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.04),
        confidence: 0.45,
      );
      final res = OrderIdParser.parse([line]);

      expect(res.completeness, IdentifierCompleteness.unreliable);
      expect(res.completeness == IdentifierCompleteness.complete, isFalse);

      final platformId = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: res.platformTransactionNo!,
        stableEventKind: 'payment',
        completeness: res.completeness,
      );
      expect(platformId.isEligibleForHardDedup, isFalse);
    });

    test('Vector 5.4: Legitimate unmasked 28-digit WeChat and Alipay IDs are COMPLETE and eligible for hard dedup', () {
      final wechatLine = OcrTextLine(
        text: '交易单号 4200002134202610229988776655',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.04),
        confidence: 0.95,
      );
      final wechatRes = OrderIdParser.parse([wechatLine]);
      expect(wechatRes.completeness, IdentifierCompleteness.complete);
      expect(wechatRes.platformTransactionNo, '4200002134202610229988776655');

      final wechatId = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: wechatRes.platformTransactionNo!,
        stableEventKind: 'payment',
        completeness: wechatRes.completeness,
      );
      expect(wechatId.isEligibleForHardDedup, isTrue);

      final alipayLine = OcrTextLine(
        text: '支付宝交易号 2026102222001412345678901234',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.04),
        confidence: 0.92,
      );
      final alipayRes = OrderIdParser.parse([alipayLine]);
      expect(alipayRes.completeness, IdentifierCompleteness.complete);

      final alipayId = PlatformIdentifier(
        namespace: 'alipay',
        identifierType: 'platform_transaction_no',
        completeValue: alipayRes.platformTransactionNo!,
        stableEventKind: 'payment',
        completeness: alipayRes.completeness,
      );
      expect(alipayId.isEligibleForHardDedup, isTrue);
    });

    test('Vector 5.5: Tier 3 hard deduplication engine rejects masked / truncated IDs from matching', () async {
      final db = await AppDatabase.openInMemory();
      final dedupEngine = DeduplicationEngine(db);

      // Seed an existing confirmed identifier
      await db.insert('transactions', {
        'id': 'tx_anchor_001',
        'type': 'expense',
        'amount_minor': 10000,
        'currency': 'CNY',
        'merchant_raw': '商户A',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'wechat',
        'created_at': '2026-10-22T00:00:00Z',
        'updated_at': '2026-10-22T00:00:00Z',
      });
      await db.insert('confirmed_identifiers', {
        'namespace': 'wechat_pay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': '4200002134202610229988776655',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_anchor_001',
      });

      // 1. Masked ID query must MISS (not crash, not match)
      final maskedIdentifier = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '4200002134****88776655',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.masked,
      );
      final resMasked = await dedupEngine.checkTier3PlatformId(maskedIdentifier);
      expect(resMasked.isMatched, isFalse, reason: 'Masked ID must not match');

      // 2. Truncated ID query must MISS
      final truncatedIdentifier = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '4200002134',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.truncated,
      );
      final resTruncated = await dedupEngine.checkTier3PlatformId(truncatedIdentifier);
      expect(resTruncated.isMatched, isFalse, reason: 'Truncated ID must not match');

      // 3. Exact complete ID query must HIT
      final completeIdentifier = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '4200002134202610229988776655',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.complete,
      );
      final resComplete = await dedupEngine.checkTier3PlatformId(completeIdentifier);
      expect(resComplete.isMatched, isTrue, reason: 'Complete unmasked ID must match');
      expect(resComplete.matchedTransactionId, 'tx_anchor_001');

      await db.close();
    });
  });
}
