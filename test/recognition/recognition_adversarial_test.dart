// test/recognition/recognition_adversarial_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/utils/date_utils.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/amount_parser.dart';
import 'package:singwallet/features/recognition/merchant_normalizer.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
import 'package:singwallet/features/recognition/noise_filter.dart';
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:singwallet/features/recognition/order_id_parser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Adversarial Challenge 1: NoiseFilter Geometry & Boundaries', () {
    test('Boundary 1.1: Exact cutoff boundary for standard status bar (0.059 vs 0.060)', () {
      final lineBelow = OcrTextLine(
        text: '09:41',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.059, width: 0.2, height: 0.01),
      );
      final lineAt = OcrTextLine(
        text: '星巴克咖啡',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.060, width: 0.2, height: 0.02),
      );

      expect(NoiseFilter.isNoise(lineBelow, hasDynamicIsland: false), isTrue);
      expect(NoiseFilter.isNoise(lineAt, hasDynamicIsland: false), isFalse);
    });

    test('Boundary 1.2: Exact cutoff boundary for dynamic island (0.074 vs 0.075)', () {
      final lineBelow = OcrTextLine(
        text: '中国电信 5G',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.074, width: 0.2, height: 0.01),
      );
      final lineAt = OcrTextLine(
        text: '瑞幸咖啡',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.075, width: 0.2, height: 0.02),
      );

      expect(NoiseFilter.isNoise(lineBelow, hasDynamicIsland: true), isTrue);
      expect(NoiseFilter.isNoise(lineAt, hasDynamicIsland: true), isFalse);
    });

    test('Boundary 1.3: Home indicator bottom threshold and span overflow (top+height >= 0.98)', () {
      final normalLineNearBottom = OcrTextLine(
        text: '支付时间: 2026-10-22 12:00:00',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.940, width: 0.5, height: 0.03),
      );
      expect(NoiseFilter.isNoise(normalLineNearBottom), isFalse);

      final lineCrossing98 = OcrTextLine(
        text: '底部装饰条',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.945, width: 0.5, height: 0.04), // 0.945 + 0.04 = 0.985 >= 0.98
      );
      expect(NoiseFilter.isNoise(lineCrossing98), isTrue);
    });

    test('Boundary 1.4: Extreme out-of-range coordinates are clamped safely without crash', () {
      final negativeTopLine = OcrTextLine(
        text: 'Status Header',
        boundingBox: OcrBoundingBox(left: -0.5, top: -0.2, width: 2.0, height: 0.5),
      );
      expect(NoiseFilter.isNoise(negativeTopLine), isTrue);
    });
  });

  group('Adversarial Challenge 2: AmountParser Disambiguation & Stress', () {
    test('Boundary 2.1: Balance keyword on non-paid lines is strictly excluded', () {
      final lines = [
        OcrTextLine(
          text: '账户可用余额 ¥9999.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '当前余额 888.88元',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.25, width: 0.5, height: 0.03),
        ),
        OcrTextLine(
          text: '实付 ¥42.50',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.35, width: 0.5, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      expect(res.paidAmountMinor, 4250);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Boundary 2.2: Standalone numbers do not guess balance when paid label is present', () {
      final lines = [
        OcrTextLine(
          text: '999.99', // Standalone big number
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.04),
        ),
        OcrTextLine(
          text: '实付金额 ¥15.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.5, height: 0.04),
        ),
      ];
      final res = AmountParser.parse(lines);
      // Labeled amount must strictly take precedence over standalone
      expect(res.paidAmountMinor, 1500);
    });

    test('Boundary 2.3: Zero amount permutations are strictly rejected (0, 0.0, 0.00)', () {
      for (final zeroStr in ['实付 ¥0', '实付款: 0.0', '支付金额: ¥0.00', '金额：0.00元']) {
        final line = OcrTextLine(
          text: zeroStr,
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.5, height: 0.04),
        );
        final res = AmountParser.parse([line]);
        expect(res.paidAmountMinor, isNull, reason: 'Failed for $zeroStr');
        expect(res.issues.any((i) => i.code == ValidationIssue.zeroAmountNotPermitted), isTrue);
      }
    });

    test('Boundary 2.4: OCR optical confusion repairs across multiple characters', () {
      expect(AmountParser.repairOcrNumbers('¥l2S.8O'), '¥125.80');
      expect(AmountParser.repairOcrNumbers('¥S8.9S'), '¥58.95');
      expect(AmountParser.repairOcrNumbers('¥B8.00'), '¥88.00');
      expect(AmountParser.repairOcrNumbers('¥1OOO.OO'), '¥1000.00');
    });

    test('Boundary 2.5: Thousands separator and European comma decimals', () {
      final res1 = AmountParser.parse([
        OcrTextLine(
          text: '实付 ¥12,345.67',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.5, height: 0.04),
        ),
      ]);
      expect(res1.paidAmountMinor, 1234567);

      final res2 = AmountParser.parse([
        OcrTextLine(
          text: '实付 99,50',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.5, height: 0.04),
        ),
      ]);
      expect(res2.paidAmountMinor, 9950);
    });
  });

  group('Adversarial Challenge 3: Merchant Normalization & System Keyword Immunity', () {
    test('Boundary 3.1: System keywords are never extracted as merchant names', () {
      final lines = [
        OcrTextLine(
          text: '微信支付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.3, height: 0.03),
        ),
        OcrTextLine(
          text: '支付成功',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.15, width: 0.3, height: 0.03),
        ),
        OcrTextLine(
          text: '账单详情',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.03),
        ),
        OcrTextLine(
          text: '¥50.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.25, width: 0.3, height: 0.03),
        ),
      ];

      final res = MerchantNormalizer.extractAndNormalize(lines);
      expect(res.rawMerchant, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.missingMerchant), isTrue);
    });

    test('Boundary 3.2: Complex chained prefixes & store branch stripping', () {
      expect(
        MerchantNormalizer.normalize('特约商户 - 扫码付款给 喜茶（北京朝阳大悦城店）'),
        '喜茶',
      );
      expect(
        MerchantNormalizer.normalize('收款商户：便利蜂（中关村南路分店）'),
        '便利蜂',
      );
      expect(
        MerchantNormalizer.normalize('向商户付款 - 屈臣氏 亮马桥店'),
        '屈臣氏',
      );
    });
  });

  group('Adversarial Challenge 4: Order ID Completeness & Anti-Collision', () {
    test('Boundary 4.1: Masked characters (*, ..., x) downgrade completeness', () {
      for (final maskedId in [
        '420000****1234',
        '202610222200...1234',
        '420000xxxx8888',
      ]) {
        final line = OcrTextLine(
          text: '交易单号 $maskedId',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.03),
        );
        final res = OrderIdParser.parse([line]);
        expect(res.completeness, IdentifierCompleteness.masked, reason: 'Failed for $maskedId');
        expect(res.issues.any((i) => i.code == ValidationIssue.maskedOrderId), isTrue);
      }
    });

    test('Boundary 4.1b: Ellipsis character … in masked order ID must be graded MASKED', () {
      final line = OcrTextLine(
        text: '交易单号 4200002134202610…1234',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.03),
      );
      final res = OrderIdParser.parse([line]);
      expect(res.completeness, IdentifierCompleteness.masked);
      expect(res.issues.any((i) => i.code == ValidationIssue.maskedOrderId), isTrue);
    });

    test('Boundary 4.2: Truncated ID (< 16 chars or ending in dot) downgrades to truncated', () {
      final line = OcrTextLine(
        text: '交易单号 4200002134.',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.03),
      );
      final res = OrderIdParser.parse([line]);
      expect(res.completeness, IdentifierCompleteness.truncated);
      expect(res.issues.any((i) => i.code == ValidationIssue.truncatedOrderId), isTrue);
    });

    test('Boundary 4.3: Low OCR confidence (< 0.60) downgrades to unreliable', () {
      final line = OcrTextLine(
        text: '交易单号 4200002134202610221234567890',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.8, height: 0.03),
        confidence: 0.55,
      );
      final res = OrderIdParser.parse([line]);
      expect(res.completeness, IdentifierCompleteness.unreliable);
    });
  });

  group('Adversarial Challenge 5: DateUtils Calendar Strictness & Zero Hallucination', () {
    test('Boundary 5.1: Non-leap year 2026-02-29 is strictly rejected', () {
      expect(DateUtils.parseReceiptDateTime('2026-02-29 12:00:00'), isNull);
    });

    test('Boundary 5.2: Leap year 2024-02-29 is accepted', () {
      final res = DateUtils.parseReceiptDateTime('2024-02-29 12:00:00');
      expect(res, isNotNull);
      expect(res!.occurredOn, '2024-02-29');
    });

    test('Boundary 5.3: Months with 30 days (April, June, Sept, Nov) reject 31st', () {
      expect(DateUtils.parseReceiptDateTime('2026-04-31 10:00:00'), isNull);
      expect(DateUtils.parseReceiptDateTime('2026-06-31 10:00:00'), isNull);
      expect(DateUtils.parseReceiptDateTime('2026-09-31 10:00:00'), isNull);
      expect(DateUtils.parseReceiptDateTime('2026-11-31 10:00:00'), isNull);
    });

    test('Boundary 5.4: Date-only text strictly avoids time hallucination (occurredAt is null)', () {
      final res = DateUtils.parseReceiptDateTime('支付日期：2026年10月22日');
      expect(res, isNotNull);
      expect(res!.occurredOn, '2026-10-22');
      expect(res.occurredAt, isNull);
      expect(res.precision, 'day');
    });
  });

  group('Adversarial Challenge 6: End-to-End Pipeline Robustness & Integrity', () {
    late Database db;
    late DeduplicationEngine dedupEngine;
    late ClassificationRuleEngine classificationEngine;
    late OcrParsingPipeline pipeline;

    setUp(() async {
      db = await AppDatabase.openInMemory();
      dedupEngine = DeduplicationEngine(db);
      classificationEngine = ClassificationRuleEngine(db);
      pipeline = OcrParsingPipeline(
        dedupEngine: dedupEngine,
        classificationEngine: classificationEngine,
      );

      await db.insert('categories', {
        'id': 'cat_food',
        'name': '餐饮美食',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T00:00:00Z',
        'updated_at': '2026-10-22T00:00:00Z',
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('Scenario 6.1: Clamping coordinates outside [0.0, 1.0] does not throw or corrupt schema', () async {
      final doc = OcrDocument(
        captureId: 'cap_corrupted_coords',
        engineIdentifier: 'Test_Engine',
        processTimeMs: 50,
        lines: [
          OcrTextLine(
            text: '海底捞火锅',
            boundingBox: OcrBoundingBox(left: -0.2, top: 0.2, width: 1.5, height: 0.05),
          ),
          OcrTextLine(
            text: '实付 ¥120.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.05),
          ),
          OcrTextLine(
            text: '2026-10-22 18:00:00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.4, width: 0.5, height: 0.03),
          ),
        ],
      );

      final result = await pipeline.process(doc);
      expect(result.amountMinor, 12000);
      expect(result.merchantNormalized, '海底捞火锅');

      final draft = result.toDraftEntity(draftId: 'draft_clamp_001', captureId: 'cap_corrupted_coords');
      final evidence = jsonDecode(draft.fieldEvidence) as Map<String, dynamic>;
      final merchantBox = evidence['merchant']['boundingBox'] as Map<String, dynamic>;
      expect(merchantBox['left'], 0.0);
      expect(merchantBox['top'], 0.2);
      expect((merchantBox['width'] as num) <= 1.0, isTrue);
      expect((merchantBox['height'] as num) <= 1.0, isTrue);
    });

    test('Scenario 6.2: Payment status FAILED prevents isConfident flag', () async {
      final doc = OcrDocument(
        captureId: 'cap_failed_001',
        engineIdentifier: 'Test_Engine',
        processTimeMs: 40,
        lines: [
          OcrTextLine(
            text: '支付宝',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '支付失败',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '麦当劳',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '实付 ¥35.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.4, width: 0.3, height: 0.04),
          ),
          OcrTextLine(
            text: '2026-10-22 12:00:00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.5, width: 0.5, height: 0.03),
          ),
        ],
      );

      final result = await pipeline.process(doc);
      expect(result.paymentStatus, 'FAILED');
      expect(result.isConfident, isFalse);
      expect(result.validationIssues.any((i) => i.code == ValidationIssue.paymentNotSuccess), isTrue);
    });
  });
}
