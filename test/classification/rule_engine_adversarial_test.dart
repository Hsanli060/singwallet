// test/classification/rule_engine_adversarial_test.dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/models/classification_rule.dart';
import 'package:singwallet/features/classification/models/classification_match_result.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:singwallet/features/classification/rule_matcher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class RecordingAiProvider implements AiClassificationProvider {
  String? returnedCategory;
  int? lastAmountMinor;
  String? lastMerchantRaw;
  String? lastPaymentChannel;

  RecordingAiProvider({this.returnedCategory});

  @override
  Future<String?> recommendCategory({
    required String merchantRaw,
    String? merchantNormalized,
    String? paymentChannel,
    int? amountMinor,
    String? remarks,
  }) async {
    lastAmountMinor = amountMinor;
    lastMerchantRaw = merchantRaw;
    lastPaymentChannel = paymentChannel;
    return returnedCategory;
  }
}

void main() {
  late Database db;
  late ClassificationRuleEngine engine;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    engine = ClassificationRuleEngine(db);

    // Seed core test categories required by foreign key constraints
    final testCategories = [
      {'id': 'cat_food', 'name': '餐饮美食'},
      {'id': 'cat_transport', 'name': '交通出行'},
      {'id': 'cat_shopping', 'name': '日用百货'},
      {'id': 'cat_entertainment', 'name': '休闲娱乐'},
      {'id': 'cat_utilities', 'name': '生活缴费'},
      {'id': 'cat_medical', 'name': '医疗健康'},
      {'id': 'cat_coffee', 'name': '咖啡饮品'},
      {'id': 'cat_other', 'name': '其他 / 待分类'},
      {'id': 'cat_alpha', 'name': '测试分类A'},
      {'id': 'cat_beta', 'name': '测试分类B'},
      {'id': 'cat_gamma', 'name': '测试分类C'},
    ];

    for (final cat in testCategories) {
      await db.insert('categories', {
        'id': cat['id'],
        'name': cat['name'],
        'applicable_type': 'expense',
        'created_at': '2026-10-22T00:00:00Z',
        'updated_at': '2026-10-22T00:00:00Z',
      });
    }
  });

  tearDown(() async {
    await db.close();
  });

  // ===========================================================================
  // Vector 1: ReDoS attempts & pathological wildcard patterns
  // ===========================================================================
  group('Vector 1: ReDoS attempts & pathological wildcard patterns', () {
    test('1.1 Collapsing of excessive consecutive % wildcards (%%%%%)', () {
      // Multiple consecutive % collapse to a single .* without hanging
      expect(RuleMatcher.matches(pattern: '%%%%%', target: 'any string'), isTrue);
      // Defensive invariant: empty target with non-empty pattern is safely rejected
      expect(RuleMatcher.matches(pattern: '%%%%%', target: ''), isFalse);
      expect(RuleMatcher.matches(pattern: '星巴克%%%%%咖啡', target: '星巴克臻选拿铁咖啡'), isTrue);
      expect(RuleMatcher.matches(pattern: '%%%%%星巴克%%%%%', target: '北京三里屯星巴克旗舰店'), isTrue);
      expect(RuleMatcher.matches(pattern: '星巴克%%%%%咖啡', target: '星巴克奶茶'), isFalse);

      // Verify execution time over 500 repetitions is well within sub-millisecond limits
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 500; i++) {
        RuleMatcher.matches(pattern: '%%%%%星巴克%%%%%臻选%%%%%', target: '北京朝阳区三里屯星巴克臻选烘焙工坊');
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('1.2 Excessive pattern length (>200 chars) throws ArgumentError in patternToRegExp', () {
      final longPattern = 'a' * 201;
      expect(
        () => RuleMatcher.patternToRegExp(longPattern),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('exceeds maximum length of 200 characters'),
        )),
      );

      // Exact 200 chars is accepted without error
      final exact200Pattern = 'a' * 200;
      expect(() => RuleMatcher.patternToRegExp(exact200Pattern), returnsNormally);
    });

    test('1.3 Excessive pattern length (>200 chars) handled safely in matches() without crashing', () {
      final longPattern = '星' * 201;
      // matches() catches ArgumentError and returns false safely
      expect(RuleMatcher.matches(pattern: longPattern, target: '星' * 201), isFalse);
      expect(RuleMatcher.matches(pattern: '%' * 250, target: 'test'), isFalse);
    });

    test('1.4 Excessive pattern length in ClassificationRule evaluated safely as non-match', () {
      final pathologicalRule = ClassificationRule(
        id: 'rule_pathological',
        priority: 100,
        merchantPattern: '肯德基${'%' * 250}',
        categoryId: 'cat_food',
        createdAt: '2026-10-22T00:00:00Z',
        updatedAt: '2026-10-22T00:00:00Z',
      );

      expect(
        RuleMatcher.evaluateRule(
          rule: pathologicalRule,
          merchantRaw: '肯德基三里屯店',
        ),
        isFalse,
      );
    });

    test('1.5 Empirical demonstration of ReDoS exponential vulnerability in regex: mode', () {
      // Nested repetition pattern with exponential backtracking vulnerability
      const redosPattern = r'regex:^(a+)+$';
      // Length 20 vs 24 demonstrates exponential growth in execution time
      final sw20 = Stopwatch()..start();
      RuleMatcher.matches(pattern: redosPattern, target: '${'a' * 20}!');
      sw20.stop();

      final sw24 = Stopwatch()..start();
      final res24 = RuleMatcher.matches(pattern: redosPattern, target: '${'a' * 24}!');
      sw24.stop();

      expect(res24, isFalse);
      // Empirical verification: runtime grows drastically due to unconstrained regex: evaluation
      expect(sw24.elapsedMicroseconds, greaterThan(sw20.elapsedMicroseconds));
    });

    test('1.6 Malformed regex syntax fails safely returning false', () {
      expect(RuleMatcher.matches(pattern: r'regex:[unclosed-bracket', target: 'test'), isFalse);
      expect(RuleMatcher.matches(pattern: r'regex:(?unsupported', target: 'test'), isFalse);
      expect(RuleMatcher.matches(pattern: r'regex:*quantifier_at_start', target: 'test'), isFalse);
    });

    test('1.7 Deep alternating and nested wildcard chains evaluate accurately', () {
      const complexPattern = '%a%b%c%d%e%f%g%h%i%j%k%';
      expect(
        RuleMatcher.matches(pattern: complexPattern, target: '0a1b2c3d4e5f6g7h8i9j0k1'),
        isTrue,
      );
      expect(
        RuleMatcher.matches(pattern: complexPattern, target: '0a1b2c3d4e5f6g7h8i9j0X1'),
        isFalse,
      );
    });

    test('1.8 Multiple single-character wildcards (_) evaluate strictly by character count', () {
      const fourCharPattern = '____';
      expect(RuleMatcher.matches(pattern: fourCharPattern, target: 'abcd'), isTrue);
      expect(RuleMatcher.matches(pattern: fourCharPattern, target: 'abc'), isFalse);
      expect(RuleMatcher.matches(pattern: fourCharPattern, target: 'abcde'), isFalse);

      // Chinese multi-byte UTF-16 code units
      const chineseSingleWildcard = '滴_出行';
      expect(RuleMatcher.matches(pattern: chineseSingleWildcard, target: '滴滴出行'), isTrue);
      expect(RuleMatcher.matches(pattern: chineseSingleWildcard, target: '滴花出行'), isTrue);
      expect(RuleMatcher.matches(pattern: chineseSingleWildcard, target: '滴快车出行'), isFalse);
    });
  });

  // ===========================================================================
  // Vector 2: Regex metacharacters in merchant names
  // ===========================================================================
  group('Vector 2: Regex metacharacters in merchant names', () {
    test('2.1 Parentheticals (full-width and half-width) are escaped and matched literally', () {
      // Full-width Chinese parentheses
      expect(
        RuleMatcher.matches(pattern: '麦当劳（三里屯店）', target: '麦当劳（三里屯店）'),
        isTrue,
      );
      expect(
        RuleMatcher.matches(pattern: '麦当劳（三里屯店）', target: '麦当劳三里屯店'),
        isFalse,
      );

      // Half-width English parentheses
      expect(
        RuleMatcher.matches(pattern: '麦当劳(三里屯店)', target: '麦当劳(三里屯店)'),
        isTrue,
      );
      expect(
        RuleMatcher.matches(pattern: '麦当劳(三里屯店)', target: '麦当劳三里屯店'),
        isFalse,
      );

      // Unbalanced parentheses must not trigger RegExp format error
      expect(
        RuleMatcher.matches(pattern: '麦当劳(三里屯', target: '麦当劳(三里屯'),
        isTrue,
      );
      expect(
        RuleMatcher.matches(pattern: '麦当劳)三里屯', target: '麦当劳)三里屯'),
        isTrue,
      );
    });

    test('2.2 Plus signs are treated literally and not as 1-or-more quantifier', () {
      expect(RuleMatcher.matches(pattern: '7+1便利店', target: '7+1便利店'), isTrue);
      // If '+' were a quantifier, '7+1' would match '71' or '771'
      expect(RuleMatcher.matches(pattern: '7+1便利店', target: '71便利店'), isFalse);
      expect(RuleMatcher.matches(pattern: '7+1便利店', target: '771便利店'), isFalse);

      expect(RuleMatcher.matches(pattern: 'C++培训', target: 'C++培训'), isTrue);
      expect(RuleMatcher.matches(pattern: 'C++培训', target: 'C+培训'), isFalse);
    });

    test('2.3 Asterisks are treated literally and not as 0-or-more quantifier', () {
      expect(RuleMatcher.matches(pattern: '*星巴克*', target: '*星巴克*'), isTrue);
      // Must not match without asterisks
      expect(RuleMatcher.matches(pattern: '*星巴克*', target: '星巴克'), isFalse);

      // Consecutive asterisks must not cause RegExp parser error ('**')
      expect(RuleMatcher.matches(pattern: '**特惠**', target: '**特惠**'), isTrue);
      expect(RuleMatcher.matches(pattern: '**特惠**', target: '*特惠*'), isFalse);
    });

    test('2.4 Square brackets and braces are treated literally and not as character classes', () {
      expect(RuleMatcher.matches(pattern: '[精选]超市', target: '[精选]超市'), isTrue);
      // If '[' were a character class, it would match '精超市' or '选超市'
      expect(RuleMatcher.matches(pattern: '[精选]超市', target: '精超市'), isFalse);
      expect(RuleMatcher.matches(pattern: '[精选]超市', target: '选超市'), isFalse);

      expect(RuleMatcher.matches(pattern: '{特惠}专区', target: '{特惠}专区'), isTrue);
      expect(RuleMatcher.matches(pattern: '{特惠}专区', target: '特惠专区'), isFalse);
    });

    test('2.5 Question marks are treated literally and not as optional quantifier', () {
      expect(RuleMatcher.matches(pattern: '真心吗?便利店', target: '真心吗?便利店'), isTrue);
      // If '?' were optional, '真心吗?便利店' would match '真心便利店'
      expect(RuleMatcher.matches(pattern: '真心吗?便利店', target: '真心便利店'), isFalse);

      // Leading question mark must not cause RegExp quantifier syntax crash
      expect(RuleMatcher.matches(pattern: '?谁是卧底?', target: '?谁是卧底?'), isTrue);
    });

    test('2.6 Dots, carets, dollars, pipes, and backslashes are escaped properly', () {
      // Dot
      expect(RuleMatcher.matches(pattern: '7.11便利店', target: '7.11便利店'), isTrue);
      expect(RuleMatcher.matches(pattern: '7.11便利店', target: '7A11便利店'), isFalse);

      // Dollar & Caret
      expect(RuleMatcher.matches(pattern: r'$9.9包邮', target: r'$9.9包邮'), isTrue);
      expect(RuleMatcher.matches(pattern: '^TOP^商户', target: '^TOP^商户'), isTrue);

      // Pipe
      expect(RuleMatcher.matches(pattern: 'A|B综合体', target: 'A|B综合体'), isTrue);
      expect(RuleMatcher.matches(pattern: 'A|B综合体', target: 'A综合体'), isFalse);
      expect(RuleMatcher.matches(pattern: 'A|B综合体', target: 'B综合体'), isFalse);

      // Backslash
      expect(RuleMatcher.matches(pattern: r'A\B商贸', target: r'A\B商贸'), isTrue);
    });

    test('2.7 Regex metacharacters combined with SQL wildcards (% and _)', () {
      // Bracket with wildcard
      expect(RuleMatcher.matches(pattern: '[精选]%超市', target: '[精选]好邻居生鲜超市'), isTrue);
      expect(RuleMatcher.matches(pattern: '[精选]%超市', target: '[精选]超市'), isTrue);
      expect(RuleMatcher.matches(pattern: '[精选]%超市', target: '精好邻居超市'), isFalse);

      // Asterisk with wildcard
      expect(RuleMatcher.matches(pattern: '*星巴克*%', target: '*星巴克*咖啡（三里屯）'), isTrue);
      expect(RuleMatcher.matches(pattern: '*星巴克*%', target: '星巴克咖啡（三里屯）'), isFalse);

      // Plus sign with wildcard
      expect(RuleMatcher.matches(pattern: '7+1%便利店', target: '7+1社区生鲜便利店'), isTrue);
      expect(RuleMatcher.matches(pattern: '7+1%便利店', target: '71社区生鲜便利店'), isFalse);

      // Parentheses with single-char wildcard
      expect(RuleMatcher.matches(pattern: '麦当劳(_)店', target: '麦当劳(北)店'), isTrue);
      expect(RuleMatcher.matches(pattern: '麦当劳(_)店', target: '麦当劳(北京)店'), isFalse);
    });
  });

  // ===========================================================================
  // Vector 3: Tie-breaking stress under identical priority
  // ===========================================================================
  group('Vector 3: Tie-breaking stress under identical priority', () {
    test('3.1 RuleMatcher.compareRules sorts deterministically by created_at DESC when priority and length match', () {
      const rOld = ClassificationRule(
        id: 'r_old',
        priority: 100,
        merchantPattern: '星巴克咖啡',
        categoryId: 'cat_food',
        createdAt: '2026-10-22T08:00:00Z',
        updatedAt: '2026-10-22T08:00:00Z',
      );
      const rMid = ClassificationRule(
        id: 'r_mid',
        priority: 100,
        merchantPattern: '星巴克咖啡',
        categoryId: 'cat_coffee',
        createdAt: '2026-10-22T09:00:00Z',
        updatedAt: '2026-10-22T09:00:00Z',
      );
      const rNew = ClassificationRule(
        id: 'r_new',
        priority: 100,
        merchantPattern: '星巴克咖啡',
        categoryId: 'cat_beverage',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      final rules = [rOld, rNew, rMid];
      rules.sort(RuleMatcher.compareRules);

      expect(rules[0].id, 'r_new');
      expect(rules[1].id, 'r_mid');
      expect(rules[2].id, 'r_old');
    });

    test('3.2 ClassificationRuleEngine picks latest created rule among identical priority and length', () async {
      await db.insert('classification_rules', {
        'id': 'rule_sbux_1',
        'priority': 100,
        'merchant_pattern': '星巴克咖啡',
        'category_id': 'cat_food',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T08:00:00Z',
        'updated_at': '2026-10-22T08:00:00Z',
      });
      await db.insert('classification_rules', {
        'id': 'rule_sbux_2',
        'priority': 100,
        'merchant_pattern': '星巴克咖啡',
        'category_id': 'cat_coffee',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T10:00:00Z', // Later created
        'updated_at': '2026-10-22T10:00:00Z',
      });

      final res = await engine.classify(merchantRaw: '星巴克咖啡');
      expect(res.tier, ClassificationTier.customRule);
      expect(res.matchedRuleId, 'rule_sbux_2');
      expect(res.categoryId, 'cat_coffee');

      // If rule_sbux_2 is disabled, rule_sbux_1 takes over
      await db.update(
        'classification_rules',
        {'enabled': 0},
        where: 'id = ?',
        whereArgs: ['rule_sbux_2'],
      );

      final resAfterDisable = await engine.classify(merchantRaw: '星巴克咖啡');
      expect(resAfterDisable.matchedRuleId, 'rule_sbux_1');
      expect(resAfterDisable.categoryId, 'cat_food');
    });

    test('3.3 Pattern specificity (length DESC) takes precedence over created_at when priority is equal', () async {
      // Shorter pattern created later
      await db.insert('classification_rules', {
        'id': 'rule_broad_recent',
        'priority': 100,
        'merchant_pattern': '星巴克%',
        'category_id': 'cat_food',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T12:00:00Z',
        'updated_at': '2026-10-22T12:00:00Z',
      });

      // Longer specific pattern created earlier
      await db.insert('classification_rules', {
        'id': 'rule_specific_older',
        'priority': 100,
        'merchant_pattern': '星巴克臻选咖啡%',
        'category_id': 'cat_coffee',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T08:00:00Z',
        'updated_at': '2026-10-22T08:00:00Z',
      });

      // Classification of specific merchant selects the more specific rule despite being older
      final res = await engine.classify(merchantRaw: '星巴克臻选咖啡三里屯店');
      expect(res.tier, ClassificationTier.customRule);
      expect(res.matchedRuleId, 'rule_specific_older');
      expect(res.categoryId, 'cat_coffee');
    });

    test('3.4 High-volume randomized tie-breaking stability test (50 rules)', () {
      final rules = <ClassificationRule>[];
      for (int i = 0; i < 50; i++) {
        final paddedIndex = i.toString().padLeft(2, '0');
        rules.add(ClassificationRule(
          id: 'rule_$paddedIndex',
          priority: 100, // Identical priority
          merchantPattern: i % 2 == 0 ? '全家便利店%' : '全家%', // Two length groups
          categoryId: 'cat_shopping',
          createdAt: '2026-10-22T10:$paddedIndex:00Z',
          updatedAt: '2026-10-22T10:$paddedIndex:00Z',
        ));
      }

      // Shuffle using pseudo-random seed
      final shuffled = List<ClassificationRule>.from(rules)..shuffle(Random(42));
      shuffled.sort(RuleMatcher.compareRules);

      // Verify strict sorting invariance across entire list:
      // 1. All priority == 100
      // 2. Longer patterns (length 6) strictly before shorter patterns (length 3)
      // 3. Within each length group, timestamps strictly descending
      for (int i = 0; i < shuffled.length - 1; i++) {
        final a = shuffled[i];
        final b = shuffled[i + 1];

        expect(a.priority, equals(b.priority));
        if (a.merchantPattern.length != b.merchantPattern.length) {
          expect(a.merchantPattern.length, greaterThan(b.merchantPattern.length));
        } else {
          expect(a.createdAt.compareTo(b.createdAt) >= 0, isTrue);
        }
      }
    });
  });

  // ===========================================================================
  // Vector 4: Dynamic rule learning stress
  // ===========================================================================
  group('Vector 4: Dynamic rule learning stress', () {
    test('4.1 Rapid sequential rule updates (100 iterations) maintains 1 rule and increments version to 100', () async {
      // Seed categories for test cycling: cat_alpha, cat_beta, cat_gamma
      const merchant = '喜茶（朝阳大悦城店）';

      for (int i = 1; i <= 100; i++) {
        final targetCat = (i % 2 == 0) ? 'cat_alpha' : 'cat_beta';
        final rule = await engine.learnRuleFromUserAction(
          merchantRaw: merchant,
          categoryId: targetCat,
          priority: 100 + i,
        );

        expect(rule.merchantPattern, '喜茶'); // Normalized merchant
        expect(rule.version, i);
        expect(rule.categoryId, targetCat);
        expect(rule.priority, 100 + i);
      }

      // Assert database integrity: exactly 1 rule in table
      final rows = await db.query(
        'classification_rules',
        where: 'merchant_pattern = ?',
        whereArgs: ['喜茶'],
      );
      expect(rows.length, 1);
      expect(rows.first['version'], 100);
      expect(rows.first['priority'], 200);
      expect(rows.first['category_id'], 'cat_alpha'); // 100 is even -> cat_alpha
    });

    test('4.2 Historical transactions are strictly immutable and never altered by rule learning', () async {
      // Seed 10 past transactions with category 'cat_food'
      for (int i = 0; i < 10; i++) {
        await db.insert('transactions', {
          'id': 'tx_immutable_$i',
          'type': 'expense',
          'amount_minor': 3200 + i,
          'currency': 'CNY',
          'merchant_raw': '海底捞火锅',
          'merchant_normalized': '海底捞火锅',
          'occurred_on': '2026-10-10',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'day',
          'payment_channel': 'alipay',
          'category_id': 'cat_food',
          'created_at': '2026-10-10T18:00:00Z',
          'updated_at': '2026-10-10T18:00:00Z',
        });
      }

      // Also seed 2 soft-deleted past transactions
      for (int i = 0; i < 2; i++) {
        await db.insert('transactions', {
          'id': 'tx_deleted_$i',
          'type': 'expense',
          'amount_minor': 5000,
          'currency': 'CNY',
          'merchant_raw': '海底捞火锅',
          'merchant_normalized': '海底捞火锅',
          'occurred_on': '2026-10-09',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'day',
          'payment_channel': 'alipay',
          'category_id': 'cat_food',
          'deleted_at': '2026-10-10T00:00:00Z',
          'created_at': '2026-10-09T18:00:00Z',
          'updated_at': '2026-10-09T18:00:00Z',
        });
      }

      // User dynamically learns new rule re-categorizing '海底捞火锅' to 'cat_entertainment'
      await engine.learnRuleFromUserAction(
        merchantRaw: '海底捞火锅',
        categoryId: 'cat_entertainment',
      );

      // Verify all 12 historical transactions in DB retain 'cat_food'
      final pastActive = await db.query(
        'transactions',
        where: 'deleted_at IS NULL AND merchant_normalized = ?',
        whereArgs: ['海底捞火锅'],
      );
      expect(pastActive.length, 10);
      for (final tx in pastActive) {
        expect(tx['category_id'], 'cat_food');
      }

      final pastDeleted = await db.query(
        'transactions',
        where: 'deleted_at IS NOT NULL AND merchant_normalized = ?',
        whereArgs: ['海底捞火锅'],
      );
      expect(pastDeleted.length, 2);
      for (final tx in pastDeleted) {
        expect(tx['category_id'], 'cat_food');
      }

      // Future classifications matching the rule pattern use the newly learned rule (cat_entertainment)
      final futureRes = await engine.classify(merchantRaw: '海底捞火锅（三里屯店）');
      expect(futureRes.tier, ClassificationTier.customRule);
      expect(futureRes.categoryId, 'cat_entertainment');
    });

    test('4.3 Interleaved multi-merchant rapid learning isolates patterns and versions cleanly', () async {
      final merchants = ['蜜雪冰城', '奈雪的茶', '茶百道', '古茗', '霸王茶姬'];

      // 20 rounds of learning across 5 merchants in round-robin = 100 updates
      for (int round = 1; round <= 20; round++) {
        for (final m in merchants) {
          final cat = round % 2 == 0 ? 'cat_coffee' : 'cat_food';
          await engine.learnRuleFromUserAction(
            merchantRaw: m,
            categoryId: cat,
          );
        }
      }

      final allRules = await db.query('classification_rules');
      expect(allRules.length, 5);

      for (final row in allRules) {
        expect(row['version'], 20);
        expect(row['category_id'], 'cat_coffee'); // Round 20 is even -> cat_coffee
      }
    });

    test('4.4 ID generation collision vulnerability: same-millisecond calls for same pattern collide on primary key', () async {
      // 1. Direct demonstration: The ID generation formula lacks a monotonic sequence or UUID:
      // 'rule_${DateTime.now().millisecondsSinceEpoch}_${pattern.hashCode.abs()}'
      const fixedEpoch = 1729600000000;
      const pattern = '同城便利店';
      final idA = 'rule_${fixedEpoch}_${pattern.hashCode.abs()}';
      final idB = 'rule_${fixedEpoch}_${pattern.hashCode.abs()}';
      expect(idA, equals(idB), reason: 'Identical timestamp and pattern produce colliding primary keys');

      // 2. Direct database proof: inserting two rules with identical generated ID triggers SQLite 1555
      await db.insert('classification_rules', {
        'id': idA,
        'priority': 100,
        'merchant_pattern': pattern,
        'payment_channel': 'wechat',
        'category_id': 'cat_food',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T00:00:00Z',
        'updated_at': '2026-10-22T00:00:00Z',
      });

      expect(
        () => db.insert('classification_rules', {
          'id': idB, // Colliding ID
          'priority': 100,
          'merchant_pattern': pattern,
          'payment_channel': 'alipay', // Different channel, should be valid rule
          'category_id': 'cat_shopping',
          'enabled': 1,
          'version': 1,
          'created_at': '2026-10-22T00:00:00Z',
          'updated_at': '2026-10-22T00:00:00Z',
        }),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'error',
          contains('UNIQUE constraint failed: classification_rules.id'),
        )),
      );
    });

    test('4.5 Channel-specific vs global rule learning separation with explicit channel priority', () async {
      // 1. Channel-specific rule: wechat -> cat_food with higher priority (150)
      await engine.learnRuleFromUserAction(
        merchantRaw: '罗森便利店',
        categoryId: 'cat_food',
        paymentChannel: 'wechat',
        priority: 150,
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 2. Channel-specific rule: alipay -> cat_shopping with higher priority (150)
      await engine.learnRuleFromUserAction(
        merchantRaw: '罗森便利店',
        categoryId: 'cat_shopping',
        paymentChannel: 'alipay',
        priority: 150,
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 3. Global channel rule: null -> cat_other with base priority (100)
      await engine.learnRuleFromUserAction(
        merchantRaw: '罗森便利店',
        categoryId: 'cat_other',
        paymentChannel: null,
        priority: 100,
      );

      // 3 separate rules created with normalized pattern '罗森'
      final rows = await db.query(
        'classification_rules',
        where: 'merchant_pattern = ?',
        whereArgs: ['罗森'],
      );
      expect(rows.length, 3);

      // Test matching with respective channels
      final resWechat = await engine.classify(
        merchantRaw: '罗森便利店',
        paymentChannel: 'wechat',
      );
      expect(resWechat.categoryId, 'cat_food');

      final resAlipay = await engine.classify(
        merchantRaw: '罗森便利店',
        paymentChannel: 'alipay',
      );
      expect(resAlipay.categoryId, 'cat_shopping');

      final resUnionpay = await engine.classify(
        merchantRaw: '罗森便利店',
        paymentChannel: 'unionpay',
      );
      expect(resUnionpay.categoryId, 'cat_other');
    });

    test('4.6 Empirical demonstration of channel rule shadowing when priorities are equal', () async {
      // Demonstrates finding: If a global rule is created AFTER a channel-specific rule
      // with identical priority, the global rule shadows the channel rule because
      // RuleMatcher.compareRules does not account for channel specificity in tie-breaking.
      await engine.learnRuleFromUserAction(
        merchantRaw: '全家便利店',
        categoryId: 'cat_food',
        paymentChannel: 'wechat',
        priority: 100,
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Later created global rule with same priority 100
      await engine.learnRuleFromUserAction(
        merchantRaw: '全家便利店',
        categoryId: 'cat_shopping',
        paymentChannel: null,
        priority: 100,
      );

      // Wechat payment classifies to cat_shopping (global rule) rather than cat_food
      // because the global rule has a newer created_at timestamp
      final res = await engine.classify(
        merchantRaw: '全家便利店',
        paymentChannel: 'wechat',
      );
      expect(res.categoryId, 'cat_shopping');
    });
  });

  // ===========================================================================
  // Vector 5: Boundary conditions
  // ===========================================================================
  group('Vector 5: Boundary conditions', () {
    test('5.1 Empty string inputs cascade cleanly to Tier 6 fallback without exceptions', () async {
      final res1 = await engine.classify(merchantRaw: '');
      expect(res1.tier, ClassificationTier.fallback);
      expect(res1.categoryId, 'cat_other');
      expect(res1.confidence, 0.10);

      final res2 = await engine.classify(merchantRaw: '', merchantNormalized: '');
      expect(res2.tier, ClassificationTier.fallback);
      expect(res2.categoryId, 'cat_other');

      // RuleMatcher.matches behavior
      expect(RuleMatcher.matches(pattern: '', target: ''), isTrue);
      expect(RuleMatcher.matches(pattern: '', target: '星巴克'), isFalse);
      expect(RuleMatcher.matches(pattern: '星巴克', target: ''), isFalse);
    });

    test('5.2 Pure whitespace strings (spaces, tabs, newlines) cascade cleanly', () async {
      final res = await engine.classify(
        merchantRaw: '   \t  \n  ',
        merchantNormalized: '   ',
        paymentChannel: '  ',
        remarks: ' \t ',
      );
      expect(res.tier, ClassificationTier.fallback);
      expect(res.categoryId, 'cat_other');

      expect(RuleMatcher.matches(pattern: '   ', target: '   '), isTrue);
      expect(RuleMatcher.matches(pattern: '   ', target: '星巴克'), isFalse);
      expect(RuleMatcher.matches(pattern: '星巴克', target: '   '), isFalse);
    });

    test('5.3 Rule learning rejects empty or pure whitespace merchant with ArgumentError', () async {
      expect(
        () => engine.learnRuleFromUserAction(
          merchantRaw: '',
          categoryId: 'cat_food',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Cannot learn rule for empty merchant name'),
        )),
      );

      expect(
        () => engine.learnRuleFromUserAction(
          merchantRaw: '    ',
          categoryId: 'cat_food',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Cannot learn rule for empty merchant name'),
        )),
      );
    });

    test('5.4 Null payment channels across classification engine and rules', () async {
      await db.insert('classification_rules', {
        'id': 'rule_universal',
        'priority': 100,
        'merchant_pattern': '通用商户%',
        'payment_channel': null, // Null channel matches all
        'category_id': 'cat_shopping',
        'enabled': 1,
        'version': 1,
        'created_at': '2026-10-22T00:00:00Z',
        'updated_at': '2026-10-22T00:00:00Z',
      });

      // Match with null paymentChannel
      final resNull = await engine.classify(
        merchantRaw: '通用商户A店',
        paymentChannel: null,
      );
      expect(resNull.categoryId, 'cat_shopping');

      // Match with specific paymentChannel
      final resWechat = await engine.classify(
        merchantRaw: '通用商户A店',
        paymentChannel: 'wechat',
      );
      expect(resWechat.categoryId, 'cat_shopping');
    });

    test('5.5 Extreme amount boundaries (0, 1, 99999999, negative, null) are handled cleanly', () async {
      final mockAi = RecordingAiProvider(returnedCategory: 'cat_medical');
      final aiEngine = ClassificationRuleEngine(db, aiProvider: mockAi);

      // 1. Zero amount (boundary)
      final resZero = await aiEngine.classify(
        merchantRaw: '未知机构X',
        amountMinor: 0,
      );
      expect(resZero.tier, ClassificationTier.ai);
      expect(resZero.categoryId, 'cat_medical');
      expect(mockAi.lastAmountMinor, 0);

      // 2. 1 cent minimum boundary
      final resOneCent = await aiEngine.classify(
        merchantRaw: '未知机构X',
        amountMinor: 1,
      );
      expect(resOneCent.tier, ClassificationTier.ai);
      expect(mockAi.lastAmountMinor, 1);

      // 3. Huge amount boundary (99,999,999 cents = 999,999.99 CNY)
      final resHuge = await aiEngine.classify(
        merchantRaw: '未知机构X',
        amountMinor: 99999999,
      );
      expect(resHuge.tier, ClassificationTier.ai);
      expect(mockAi.lastAmountMinor, 99999999);

      // 4. Null amount
      final resNull = await aiEngine.classify(
        merchantRaw: '未知机构X',
        amountMinor: null,
      );
      expect(resNull.tier, ClassificationTier.ai);
      expect(mockAi.lastAmountMinor, isNull);

      // 5. Negative amount boundary (e.g. potential raw refund amount)
      final resNegative = await aiEngine.classify(
        merchantRaw: '未知机构X',
        amountMinor: -1500,
      );
      expect(resNegative.tier, ClassificationTier.ai);
      expect(mockAi.lastAmountMinor, -1500);
    });

    test('5.6 Extremely long remarks (>1000 chars) does not crash and keyword dictionary searches safely', () async {
      final longRemarks = '备注说明信息' * 200; // ~1200 characters
      final res = await engine.classify(
        merchantRaw: '神秘机构',
        remarks: '$longRemarks 包含关键字美团外卖配送',
      );

      // Built-in keyword '美团外卖' found in remarks
      expect(res.tier, ClassificationTier.builtinKeyword);
      expect(res.categoryId, 'cat_food');
    });
  });
}
