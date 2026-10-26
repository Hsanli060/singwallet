// test/classification/rule_matcher_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/models/classification_rule.dart';
import 'package:singwallet/features/classification/rule_matcher.dart';

void main() {
  group('RuleMatcher pattern compilation and rule matching', () {
    test('Prefix wildcard matching (星巴克%)', () {
      expect(RuleMatcher.matches(pattern: '星巴克%', target: '星巴克'), isTrue);
      expect(RuleMatcher.matches(pattern: '星巴克%', target: '星巴克咖啡（三里屯店）'), isTrue);
      expect(RuleMatcher.matches(pattern: '星巴克%', target: '北京星巴克'), isFalse);
    });

    test('Suffix / contains wildcard matching (%便利店%)', () {
      expect(RuleMatcher.matches(pattern: '%便利店%', target: '便利店'), isTrue);
      expect(RuleMatcher.matches(pattern: '%便利店%', target: '全家便利店'), isTrue);
      expect(RuleMatcher.matches(pattern: '%便利店%', target: '全家超市'), isFalse);
    });

    test('Middle wildcard matching (美团%肯德基)', () {
      expect(RuleMatcher.matches(pattern: '美团%肯德基', target: '美团外卖-肯德基'), isTrue);
      expect(RuleMatcher.matches(pattern: '美团%肯德基', target: '饿了么-肯德基'), isFalse);
    });

    test('Single character placeholder matching (滴_出行)', () {
      expect(RuleMatcher.matches(pattern: '滴_出行', target: '滴滴出行'), isTrue);
      expect(RuleMatcher.matches(pattern: '滴_出行', target: '滴滴滴出行'), isFalse);
    });

    test(r'Explicit regex matching (regex:^滴滴(出行|快车)$)', () {
      expect(RuleMatcher.matches(pattern: r'regex:^滴滴(出行|快车)$', target: '滴滴快车'), isTrue);
      expect(RuleMatcher.matches(pattern: r'regex:^滴滴(出行|快车)$', target: '滴滴代驾'), isFalse);
    });

    test('Special regex characters in merchant names do not cause parser crash', () {
      expect(RuleMatcher.matches(pattern: 'C&A (服装)', target: 'C&A (服装)'), isTrue);
      expect(RuleMatcher.matches(pattern: '7-Eleven+', target: '7-Eleven+'), isTrue);
      expect(RuleMatcher.matches(pattern: '麦当劳(王府井店)', target: '麦当劳(王府井店)'), isTrue);
    });

    test('Case insensitivity by default', () {
      expect(RuleMatcher.matches(pattern: 'kfc%', target: 'KFC 汽车穿梭餐厅'), isTrue);
      expect(RuleMatcher.matches(pattern: 'Apple Store', target: 'apple store'), isTrue);
    });

    test('Channel restriction on ClassificationRule evaluation', () {
      const rule = ClassificationRule(
        id: 'r1',
        merchantPattern: '星巴克%',
        paymentChannel: 'wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-22T00:00:00Z',
        updatedAt: '2026-10-22T00:00:00Z',
      );

      // Matches when channel is wechat
      expect(
        RuleMatcher.evaluateRule(
          rule: rule,
          merchantRaw: '星巴克咖啡',
          paymentChannel: 'wechat',
        ),
        isTrue,
      );

      // Fails when channel is alipay
      expect(
        RuleMatcher.evaluateRule(
          rule: rule,
          merchantRaw: '星巴克咖啡',
          paymentChannel: 'alipay',
        ),
        isFalse,
      );
    });

    test('Tie-breaking comparator prefers higher priority and longer pattern', () {
      const r1 = ClassificationRule(
        id: 'r1',
        priority: 100,
        merchantPattern: '星巴克%',
        categoryId: 'cat_food',
        createdAt: '2026-10-22T00:00:00Z',
        updatedAt: '2026-10-22T00:00:00Z',
      );
      const r2 = ClassificationRule(
        id: 'r2',
        priority: 200,
        merchantPattern: '星巴克%',
        categoryId: 'cat_food',
        createdAt: '2026-10-22T00:00:00Z',
        updatedAt: '2026-10-22T00:00:00Z',
      );
      const r3 = ClassificationRule(
        id: 'r3',
        priority: 100,
        merchantPattern: '星巴克臻选%',
        categoryId: 'cat_food',
        createdAt: '2026-10-22T00:00:00Z',
        updatedAt: '2026-10-22T00:00:00Z',
      );

      // r2 (priority 200) beats r1 (priority 100)
      expect(RuleMatcher.compareRules(r1, r2) > 0, isTrue);

      // r3 (longer pattern) beats r1 on same priority 100
      expect(RuleMatcher.compareRules(r1, r3) > 0, isTrue);
    });
  });
}
