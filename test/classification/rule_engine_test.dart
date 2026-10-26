// test/classification/rule_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/features/classification/models/classification_match_result.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockAiProvider implements AiClassificationProvider {
  final String? returnedCategory;
  MockAiProvider(this.returnedCategory);

  @override
  Future<String?> recommendCategory({
    required String merchantRaw,
    String? merchantNormalized,
    String? paymentChannel,
    int? amountMinor,
    String? remarks,
  }) async {
    return returnedCategory;
  }
}

void main() {
  late Database db;
  late ClassificationRuleEngine engine;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    engine = ClassificationRuleEngine(db);

    // Seed basic test categories
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
    await db.insert('categories', {
      'id': 'cat_coffee',
      'name': '咖啡饮品',
      'applicable_type': 'expense',
      'created_at': '2026-10-22T00:00:00Z',
      'updated_at': '2026-10-22T00:00:00Z',
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('ClassificationRuleEngine 6-Tier Hierarchy', () {
    test('Tier 1: User manual override takes absolute precedence with confidence 1.0', () async {
      final res = await engine.classify(
        manualCategoryId: 'cat_coffee',
        merchantRaw: '肯德基', // Normally cat_food
      );
      expect(res.tier, ClassificationTier.manual);
      expect(res.categoryId, 'cat_coffee');
      expect(res.confidence, 1.0);
    });

    test('Tier 2: Custom active rule matches and prioritizes higher priority', () async {
      await db.insert('classification_rules', {
        'id': 'rule_kfc_low',
        'priority': 100,
        'merchant_pattern': '肯德基%',
        'category_id': 'cat_food',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T01:00:00Z',
        'updated_at': '2026-10-22T01:00:00Z',
      });
      await db.insert('classification_rules', {
        'id': 'rule_kfc_high',
        'priority': 200,
        'merchant_pattern': '肯德基%',
        'category_id': 'cat_coffee',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T02:00:00Z',
        'updated_at': '2026-10-22T02:00:00Z',
      });

      final res = await engine.classify(merchantRaw: '肯德基三里屯店');
      expect(res.tier, ClassificationTier.customRule);
      expect(res.categoryId, 'cat_coffee'); // High priority rule won
      expect(res.matchedRuleId, 'rule_kfc_high');
    });

    test('Tier 2: Disabled rule (enabled=0) is ignored', () async {
      await db.insert('classification_rules', {
        'id': 'rule_disabled',
        'priority': 100,
        'merchant_pattern': '星巴克%',
        'category_id': 'cat_other',
        'enabled': 0, // Disabled
        'version': 1,
        'created_at': '2026-10-22T01:00:00Z',
        'updated_at': '2026-10-22T01:00:00Z',
      });

      // Built-in keyword should be used instead
      final res = await engine.classify(merchantRaw: '星巴克');
      expect(res.tier, ClassificationTier.builtinKeyword);
      expect(res.categoryId, 'cat_food');
    });

    test('Tier 3: Historical identical merchant category mapping', () async {
      // Seed 3 historical transactions for "老张卤肉饭" pointing to cat_food
      for (int i = 0; i < 3; i++) {
        await db.insert('transactions', {
          'id': 'tx_lz_$i',
          'type': 'expense',
          'amount_minor': 2500,
          'currency': 'CNY',
          'merchant_raw': '老张卤肉饭',
          'merchant_normalized': '老张卤肉饭',
          'occurred_on': '2026-10-20',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'day',
          'payment_channel': 'wechat',
          'category_id': 'cat_food',
          'created_at': '2026-10-20T12:00:00Z',
          'updated_at': '2026-10-20T12:00:00Z',
        });
      }

      final res = await engine.classify(merchantRaw: '老张卤肉饭');
      expect(res.tier, ClassificationTier.history);
      expect(res.categoryId, 'cat_food');
      expect(res.confidence, 0.90);
    });

    test('Tier 3: Soft-deleted transactions (deleted_at IS NOT NULL) do not count towards history', () async {
      await db.insert('transactions', {
        'id': 'tx_deleted_1',
        'type': 'expense',
        'amount_minor': 2500,
        'currency': 'CNY',
        'merchant_raw': '未知名小炒',
        'merchant_normalized': '未知名小炒',
        'occurred_on': '2026-10-20',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'wechat',
        'category_id': 'cat_food',
        'deleted_at': '2026-10-21T00:00:00Z',
        'created_at': '2026-10-20T12:00:00Z',
        'updated_at': '2026-10-20T12:00:00Z',
      });

      final res = await engine.classify(merchantRaw: '未知名小炒');
      expect(res.tier, isNot(ClassificationTier.history));
    });

    test('Tier 4: Built-in keyword dictionary matches with longest match first', () async {
      final res1 = await engine.classify(merchantRaw: '滴滴快车');
      expect(res1.tier, ClassificationTier.builtinKeyword);
      expect(res1.categoryId, 'cat_transport');

      final res2 = await engine.classify(merchantRaw: '中国石化加油站');
      expect(res2.tier, ClassificationTier.builtinKeyword);
      expect(res2.categoryId, 'cat_transport');
    });

    test('Tier 5: Valid AI provider suggestion is accepted with schema verification', () async {
      final aiEngine = ClassificationRuleEngine(
        db,
        aiProvider: MockAiProvider('cat_transport'),
      );

      final res = await aiEngine.classify(merchantRaw: '未知科技飞天火箭服务');
      expect(res.tier, ClassificationTier.ai);
      expect(res.categoryId, 'cat_transport');
      expect(res.confidence, 0.60);
    });

    test('Tier 5: Invalid AI provider suggestion (non-existent category) drops to Tier 6 fallback', () async {
      final aiEngine = ClassificationRuleEngine(
        db,
        aiProvider: MockAiProvider('cat_non_existent_fake'),
      );

      final res = await aiEngine.classify(merchantRaw: '未知小作坊');
      expect(res.tier, ClassificationTier.fallback);
      expect(res.categoryId, 'cat_other');
      expect(res.confidence, 0.10);
    });

    test('Tier 6: Fallback category cat_other assigned when no match', () async {
      final res = await engine.classify(merchantRaw: '完全未知的神秘字符串98765');
      expect(res.tier, ClassificationTier.fallback);
      expect(res.categoryId, 'cat_other');
      expect(res.confidence, 0.10);
    });
  });

  group('Dynamic Rule Learning (F30)', () {
    test('Learns new rule on user action and saves to classification_rules', () async {
      final rule = await engine.learnRuleFromUserAction(
        merchantRaw: '特约商户-喜茶（国贸店）',
        categoryId: 'cat_coffee',
        priority: 150,
      );

      expect(rule.merchantPattern, '喜茶');
      expect(rule.categoryId, 'cat_coffee');
      expect(rule.priority, 150);

      // Subsequent classification hits Tier 2 custom rule
      final res = await engine.classify(merchantRaw: '喜茶三里屯店');
      expect(res.tier, ClassificationTier.customRule);
      expect(res.categoryId, 'cat_coffee');
    });

    test('Updating rule for same merchant is idempotent and increments version', () async {
      final r1 = await engine.learnRuleFromUserAction(
        merchantRaw: '茶百道',
        categoryId: 'cat_food',
      );
      expect(r1.version, 1);

      final r2 = await engine.learnRuleFromUserAction(
        merchantRaw: '茶百道',
        categoryId: 'cat_coffee',
      );
      expect(r2.version, 2);
      expect(r2.categoryId, 'cat_coffee');

      // Rule count in database remains 1
      final rows = await db.query(
        'classification_rules',
        where: 'merchant_pattern = ?',
        whereArgs: ['茶百道'],
      );
      expect(rows.length, 1);
    });

    test('Non-retroactivity: learning a new rule does NOT mutate existing transactions', () async {
      await db.insert('transactions', {
        'id': 'tx_past_1',
        'type': 'expense',
        'amount_minor': 1800,
        'currency': 'CNY',
        'merchant_raw': '书亦烧仙草',
        'merchant_normalized': '书亦烧仙草',
        'occurred_on': '2026-10-15',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'wechat',
        'category_id': 'cat_food', // Originally categorized as cat_food
        'created_at': '2026-10-15T12:00:00Z',
        'updated_at': '2026-10-15T12:00:00Z',
      });

      // User learns a new rule mapping "书亦烧仙草" to "cat_coffee"
      await engine.learnRuleFromUserAction(
        merchantRaw: '书亦烧仙草',
        categoryId: 'cat_coffee',
      );

      // Verify historical transaction in database was NOT altered
      final pastTx = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: ['tx_past_1'],
      );
      expect(pastTx.first['category_id'], 'cat_food');
    });
  });
}
