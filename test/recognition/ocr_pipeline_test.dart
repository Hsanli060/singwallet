// test/recognition/ocr_pipeline_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
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

    // Seed basic categories for classification
    await db.insert('categories', {
      'id': 'cat_food',
      'name': '餐饮美食',
      'applicable_type': 'expense',
      'created_at': '2026-10-22T00:00:00Z',
      'updated_at': '2026-10-22T00:00:00Z',
    });
    await db.insert('categories', {
      'id': 'cat_transport',
      'name': '交通出行',
      'applicable_type': 'expense',
      'created_at': '2026-10-22T00:00:00Z',
      'updated_at': '2026-10-22T00:00:00Z',
    });
    await db.insert('categories', {
      'id': 'cat_other',
      'name': '其他 / 待分类',
      'applicable_type': 'expense',
      'created_at': '2026-10-22T00:00:00Z',
      'updated_at': '2026-10-22T00:00:00Z',
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('OcrParsingPipeline end-to-end receipt recognition', () {
    test('Scenario A: Standard WeChat Pay dining receipt', () async {
      final doc = OcrDocument(
        captureId: 'cap_wechat_001',
        engineIdentifier: 'MLKit_Android_v2',
        processTimeMs: 120,
        lines: [
          OcrTextLine(
            text: '09:41', // Status bar noise
            boundingBox: OcrBoundingBox(left: 0.05, top: 0.02, width: 0.1, height: 0.02),
          ),
          OcrTextLine(
            text: '微信支付',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.10, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '支付成功',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.15, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '特约商户-海底捞火锅（西单店）',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.22, width: 0.7, height: 0.04),
          ),
          OcrTextLine(
            text: '¥328.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.30, width: 0.4, height: 0.06),
          ),
          OcrTextLine(
            text: '商品原价 ¥360.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.38, width: 0.5, height: 0.03),
          ),
          OcrTextLine(
            text: '优惠减免 ¥32.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.42, width: 0.5, height: 0.03),
          ),
          OcrTextLine(
            text: '支付方式 招商银行储蓄卡(8899)',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.50, width: 0.6, height: 0.03),
          ),
          OcrTextLine(
            text: '交易单号 4200002134202610229988776655',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.60, width: 0.8, height: 0.03),
          ),
          OcrTextLine(
            text: '商户单号 2026102212345678',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.65, width: 0.7, height: 0.03),
          ),
          OcrTextLine(
            text: '创建时间 2026-10-22 19:30:15',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.72, width: 0.7, height: 0.03),
          ),
          OcrTextLine(
            text: '查看账单详情', // Chrome noise
            boundingBox: OcrBoundingBox(left: 0.3, top: 0.88, width: 0.4, height: 0.04),
          ),
          OcrTextLine(
            text: '—', // Home bar noise
            boundingBox: OcrBoundingBox(left: 0.4, top: 0.97, width: 0.2, height: 0.01),
          ),
        ],
      );

      final result = await pipeline.process(doc);

      expect(result.captureId, 'cap_wechat_001');
      expect(result.paymentChannel, 'wechat');
      expect(result.paymentStatus, 'SUCCESS');
      expect(result.type, 'expense');
      expect(result.amountMinor, 32800);
      expect(result.originalAmountMinor, 36000);
      expect(result.discountMinor, 3200);
      expect(result.merchantRaw, '海底捞火锅（西单店）');
      expect(result.merchantNormalized, '海底捞火锅');
      expect(result.occurredOn, '2026-10-22');
      expect(result.occurredAt, '2026-10-22T11:30:15.000Z');
      expect(result.eventTimePrecision, 'second');
      expect(result.eventTimeSource, 'ocr_extracted');
      expect(result.platformTransactionNo, '4200002134202610229988776655');
      expect(result.merchantOrderNo, '2026102212345678');
      expect(result.identifierCompleteness, IdentifierCompleteness.complete);
      expect(result.paymentMethodLabel, '招商银行储蓄卡(8899)');
      expect(result.suggestedCategoryId, 'cat_food');
      expect(result.isConfident, isTrue);
      expect(result.validationIssues.isEmpty, isTrue);

      // Verify field evidence map
      expect(result.fieldEvidence.containsKey('amount'), isTrue);
      expect(result.fieldEvidence.containsKey('merchant'), isTrue);
      expect(result.fieldEvidence.containsKey('occurred_at'), isTrue);
      expect(result.fieldEvidence.containsKey('platform_transaction_no'), isTrue);

      // Verify SQLite Draft entity conversion
      final draft = result.toDraftEntity(draftId: 'draft_001', captureId: 'cap_wechat_001');
      expect(draft.id, 'draft_001');
      expect(draft.captureId, 'cap_wechat_001');

      // Verify valid JSON serializations
      final candidateMap = jsonDecode(draft.candidateFields) as Map<String, dynamic>;
      expect(candidateMap['amountMinor'], 32800);
      expect(candidateMap['paymentChannel'], 'wechat');

      final evidenceMap = jsonDecode(draft.fieldEvidence) as Map<String, dynamic>;
      expect(evidenceMap.containsKey('amount'), isTrue);
    });

    test('Scenario B: Alipay ride receipt with masked order ID', () async {
      final doc = OcrDocument(
        captureId: 'cap_alipay_002',
        engineIdentifier: 'AppleVision_iOS_17',
        processTimeMs: 95,
        lines: [
          OcrTextLine(
            text: '支付宝',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.10, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '滴滴出行',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.18, width: 0.4, height: 0.04),
          ),
          OcrTextLine(
            text: '-18.50',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.28, width: 0.3, height: 0.05),
          ),
          OcrTextLine(
            text: '支付成功',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.38, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '订单号 20261022220014****5678',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.50, width: 0.7, height: 0.03),
          ),
          OcrTextLine(
            text: '创建时间 2026-10-22 08:45',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.58, width: 0.6, height: 0.03),
          ),
        ],
      );

      final result = await pipeline.process(doc);
      expect(result.paymentChannel, 'alipay');
      expect(result.amountMinor, 1850);
      expect(result.merchantNormalized, '滴滴出行');
      expect(result.occurredOn, '2026-10-22');
      expect(result.eventTimePrecision, 'minute');
      expect(result.identifierCompleteness, IdentifierCompleteness.masked);
      expect(result.validationIssues.any((i) => i.code == ValidationIssue.maskedOrderId), isTrue);
      expect(result.suggestedCategoryId, 'cat_transport');
    });

    test('Scenario C: Incomplete receipt with missing date, pending status, zero amount', () async {
      final doc = OcrDocument(
        captureId: 'cap_incomplete_003',
        engineIdentifier: 'MLKit_Android_v2',
        processTimeMs: 110,
        lines: [
          OcrTextLine(
            text: '微信支付',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.10, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '待支付',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.20, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '某某小吃',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.30, width: 0.4, height: 0.04),
          ),
          OcrTextLine(
            text: '实付 ¥0.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.40, width: 0.3, height: 0.04),
          ),
        ],
      );

      final result = await pipeline.process(doc);
      expect(result.paymentStatus, 'PENDING');
      expect(result.amountMinor, isNull);
      expect(result.isConfident, isFalse);
      expect(result.eventTimeSource, 'suggested_today');
      expect(result.validationIssues.any((i) => i.code == ValidationIssue.paymentNotSuccess), isTrue);
      expect(result.validationIssues.any((i) => i.code == ValidationIssue.zeroAmountNotPermitted), isTrue);
      expect(result.validationIssues.any((i) => i.code == ValidationIssue.missingDate), isTrue);
    });

    test('Scenario D: Deduplication fuzzy match warning on duplicate receipt', () async {
      // Seed an existing committed transaction
      await db.insert('transactions', {
        'id': 'tx_existing_subway',
        'type': 'expense',
        'amount_minor': 3500,
        'currency': 'CNY',
        'merchant_raw': '赛百味',
        'merchant_normalized': '赛百味',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_food',
        'created_at': '2026-10-22T12:00:00Z',
        'updated_at': '2026-10-22T12:00:00Z',
      });

      final doc = OcrDocument(
        captureId: 'cap_duplicate_004',
        engineIdentifier: 'MLKit_Android_v2',
        processTimeMs: 100,
        lines: [
          OcrTextLine(
            text: '微信支付',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.3, height: 0.03),
          ),
          OcrTextLine(
            text: '赛百味',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.4, height: 0.04),
          ),
          OcrTextLine(
            text: '实付 ¥35.00',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.3, width: 0.4, height: 0.05),
          ),
          OcrTextLine(
            text: '时间 2026-10-22 12:05',
            boundingBox: OcrBoundingBox(left: 0.1, top: 0.4, width: 0.6, height: 0.03),
          ),
        ],
      );

      final result = await pipeline.process(doc);
      expect(result.amountMinor, 3500);
      expect(result.duplicateCandidates.contains('tx_existing_subway'), isTrue);
      expect(result.validationIssues.any((i) => i.code == ValidationIssue.suspectedDuplicate), isTrue);
    });
  });
}
