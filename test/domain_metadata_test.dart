// test/domain_metadata_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/constants/domain_metadata.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/presentation/screens/drafts/widgets/category_suggestion_card.dart';
import 'package:singwallet/presentation/screens/transactions/widgets/transaction_tile.dart';
import 'package:singwallet/presentation/theme/app_icon_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DomainMetadata and DatabaseSeeder Synchronization Tests', () {
    test('DomainMetadata.categories and DatabaseSeeder.defaultCategories are 100% in sync', () {
      expect(DomainMetadata.categories.length, equals(8));
      expect(DatabaseSeeder.defaultCategories.length, equals(8));

      for (var i = 0; i < DomainMetadata.categories.length; i++) {
        final meta = DomainMetadata.categories[i];
        final seeded = DatabaseSeeder.defaultCategories[i];

        expect(seeded.id, equals(meta.id));
        expect(seeded.name, equals(meta.name));
        expect(seeded.iconKey, equals(meta.iconKey));
        expect(seeded.sortOrder, equals(meta.sortOrder));
        expect(seeded.applicableType, equals(meta.applicableType));
      }
    });

    test('DomainMetadata.accounts and DatabaseSeeder.defaultAccounts are synchronized', () {
      expect(DomainMetadata.accounts.length, equals(4));
      expect(DatabaseSeeder.defaultAccounts.length, equals(4));

      for (var i = 0; i < DomainMetadata.accounts.length; i++) {
        final meta = DomainMetadata.accounts[i];
        final seeded = DatabaseSeeder.defaultAccounts[i];

        expect(seeded.id, equals(meta.id));
        expect(seeded.name, equals(meta.name));
        expect(seeded.kind, equals(meta.kind));
      }
    });

    test('DomainMetadata.projects and DatabaseSeeder.defaultProjects are synchronized', () {
      expect(DomainMetadata.projects.length, equals(2));
      expect(DatabaseSeeder.defaultProjects.length, equals(2));

      for (var i = 0; i < DomainMetadata.projects.length; i++) {
        final meta = DomainMetadata.projects[i];
        final seeded = DatabaseSeeder.defaultProjects[i];

        expect(seeded.id, equals(meta.id));
        expect(seeded.name, equals(meta.name));
      }
    });
  });

  group('Category Icon & Emoji Single Source of Truth Tests', () {
    test('Emoji and IconData resolution consistency across AppIconRegistry, TransactionTile and CategorySuggestionCard', () {
      for (final cat in DomainMetadata.categories) {
        // AppIconRegistry resolution by key
        final iconByKey = AppIconRegistry.resolveCategoryIconByKey(cat.iconKey);
        final tileIcon = TransactionTile.getIconData(cat.iconKey);
        expect(tileIcon, equals(iconByKey), reason: 'TransactionTile must match AppIconRegistry for ${cat.name}');

        // AppIconRegistry resolution by name
        final iconByName = AppIconRegistry.resolveCategoryIcon(categoryName: cat.name);
        final cardIcon = resolveCategoryIcon(cat.iconKey, cat.name);
        expect(cardIcon, equals(iconByName), reason: 'CategorySuggestionCard must match AppIconRegistry for ${cat.name}');

        // Emoji resolution
        final emojiByKey = AppIconRegistry.resolveCategoryEmoji(iconKey: cat.iconKey);
        final emojiByName = AppIconRegistry.resolveCategoryEmoji(categoryName: cat.name);
        expect(emojiByKey, equals(cat.emoji));
        expect(emojiByName, equals(cat.emoji));
      }
    });

    test('Category finding methods find correct metadata by iconKey, name, or keywords', () {
      expect(DomainMetadata.findCategoryByIconKey('food')?.name, equals('餐饮美食'));
      expect(DomainMetadata.findCategoryByIconKey('transport')?.name, equals('交通出行'));
      expect(DomainMetadata.findCategoryByIconKey('shopping')?.name, equals('日常购物'));
      expect(DomainMetadata.findCategoryByIconKey('entertainment')?.name, equals('休闲娱乐'));
      expect(DomainMetadata.findCategoryByIconKey('utilities')?.name, equals('生活缴费'));
      expect(DomainMetadata.findCategoryByIconKey('medical')?.name, equals('医疗健康'));
      expect(DomainMetadata.findCategoryByIconKey('other')?.name, equals('其他支出'));
      expect(DomainMetadata.findCategoryByIconKey('salary')?.name, equals('工资收入'));

      expect(DomainMetadata.findCategoryByNameOrKeyword('星巴克咖啡')?.name, equals('餐饮美食'));
      expect(DomainMetadata.findCategoryByNameOrKeyword('滴滴出行')?.name, equals('交通出行'));
      expect(DomainMetadata.findCategoryByNameOrKeyword('盒马鲜生')?.name, equals('日常购物'));
      expect(DomainMetadata.findCategoryByNameOrKeyword('生活缴费')?.name, equals('生活缴费'));
      expect(DomainMetadata.findCategoryByNameOrKeyword('发工资啦')?.name, equals('工资收入'));
    });
  });

  group('Channel and Account Type Mappings Tests', () {
    test('resolveChannelKey normalizes various Chinese and English aliases', () {
      expect(DomainMetadata.resolveChannelKey('wechat'), equals('wechat'));
      expect(DomainMetadata.resolveChannelKey('微信支付'), equals('wechat'));
      expect(DomainMetadata.resolveChannelKey('微信零钱'), equals('wechat'));
      expect(DomainMetadata.resolveChannelKey('alipay'), equals('alipay'));
      expect(DomainMetadata.resolveChannelKey('支付宝余额'), equals('alipay'));
      expect(DomainMetadata.resolveChannelKey('bank_card'), equals('bank'));
      expect(DomainMetadata.resolveChannelKey('招商银行'), equals('bank'));
      expect(DomainMetadata.resolveChannelKey('cash'), equals('cash'));
      expect(DomainMetadata.resolveChannelKey('现金钱包'), equals('cash'));
      expect(DomainMetadata.resolveChannelKey('credit_card'), equals('credit'));
      expect(DomainMetadata.resolveChannelKey('unknown'), equals('other'));
    });

    test('resolveChannelIcon and resolveChannelColor return expected values', () {
      expect(AppIconRegistry.resolveChannelIcon('wechat'), equals(Icons.chat_bubble_outline));
      expect(AppIconRegistry.resolveChannelColor('wechat'), equals(const Color(0xFF07C160)));

      expect(AppIconRegistry.resolveChannelColor('alipay'), equals(const Color(0xFF1677FF)));
      expect(AppIconRegistry.resolveChannelColor('bank'), equals(const Color(0xFFFF9800)));
      expect(AppIconRegistry.resolveChannelColor('cash'), equals(const Color(0xFF4CAF50)));
    });

    test('resolveAccountTypeLabel, resolveChannelLabel and resolveChannelDisplayName return proper localized text', () {
      expect(AppIconRegistry.resolveAccountTypeLabel('wechat'), equals('微信支付'));
      expect(AppIconRegistry.resolveAccountTypeLabel('alipay'), equals('支付宝'));
      expect(AppIconRegistry.resolveAccountTypeLabel('debit_card'), equals('借记卡'));
      expect(AppIconRegistry.resolveAccountTypeLabel('credit_card'), equals('信用卡'));
      expect(AppIconRegistry.resolveAccountTypeLabel('cash'), equals('现金'));
      expect(AppIconRegistry.resolveAccountTypeLabel('e_wallet'), equals('电子钱包'));

      expect(AppIconRegistry.resolveChannelLabel('wechat'), equals('微信支付'));
      expect(AppIconRegistry.resolveChannelLabel('alipay'), equals('支付宝'));
      expect(AppIconRegistry.resolveChannelLabel('bank_card'), equals('银行卡'));
      expect(AppIconRegistry.resolveChannelLabel('cash'), equals('现金'));

      expect(AppIconRegistry.resolveChannelDisplayName('wechat'), equals('微信'));
      expect(AppIconRegistry.resolveChannelDisplayName('alipay'), equals('支付宝'));
      expect(AppIconRegistry.resolveChannelDisplayName('bank'), equals('银行卡'));
      expect(AppIconRegistry.resolveChannelDisplayName('cash'), equals('现金'));
      expect(AppIconRegistry.resolveChannelDisplayName('other'), equals('其他'));
    });
  });

  group('Custom Category Management & LLM Constraints Tests', () {
    setUp(() {
      DomainMetadata.resetCustomCategories();
    });

    tearDown(() {
      DomainMetadata.resetCustomCategories();
    });

    test('activeCategoryNames returns initial 8 core categories', () {
      expect(DomainMetadata.activeCategoryNames.length, equals(8));
      expect(
        DomainMetadata.activeCategoryNames,
        equals([
          '餐饮美食',
          '交通出行',
          '日常购物',
          '休闲娱乐',
          '生活缴费',
          '医疗健康',
          '其他支出',
          '工资收入',
        ]),
      );
    });

    test('addCustomCategory successfully adds custom category and prevents duplicates', () {
      final added = DomainMetadata.addCustomCategory('宠物消费', type: 'expense', desc: '猫粮狗粮与宠物医疗');
      expect(added, isTrue);
      expect(DomainMetadata.activeCategoryNames.length, equals(9));
      expect(DomainMetadata.activeCategoryNames.contains('宠物消费'), isTrue);

      // Attempting to add duplicate custom category returns false
      final duplicate = DomainMetadata.addCustomCategory('宠物消费');
      expect(duplicate, isFalse);
      expect(DomainMetadata.activeCategoryNames.length, equals(9));

      // Attempting to add duplicate of core category returns false
      final duplicateCore = DomainMetadata.addCustomCategory('餐饮美食');
      expect(duplicateCore, isFalse);
    });

    test('removeCustomCategory removes category and protects minimum 1 category', () {
      DomainMetadata.addCustomCategory('待删除分类');
      expect(DomainMetadata.activeCategoryNames.contains('待删除分类'), isTrue);

      final removed = DomainMetadata.removeCustomCategory('待删除分类');
      expect(removed, isTrue);
      expect(DomainMetadata.activeCategoryNames.contains('待删除分类'), isFalse);

      // Removing non-existent category returns false
      final nonExistent = DomainMetadata.removeCustomCategory('不存在的分类');
      expect(nonExistent, isFalse);

      // Remove categories until only 1 remains
      while (DomainMetadata.activeCategoryNames.length > 1) {
        final toRemove = DomainMetadata.activeCategoryNames.first;
        final res = DomainMetadata.removeCustomCategory(toRemove);
        expect(res, isTrue);
      }

      // Exactly 1 category remains
      expect(DomainMetadata.activeCategoryNames.length, equals(1));
      final lastCategory = DomainMetadata.activeCategoryNames.first;

      // Attempting to delete the last category must be blocked (returns false)
      final protected = DomainMetadata.removeCustomCategory(lastCategory);
      expect(protected, isFalse);
      expect(DomainMetadata.activeCategoryNames.length, equals(1));
      expect(DomainMetadata.activeCategoryNames.first, equals(lastCategory));
    });

    test('resetCustomCategories restores default 8 core categories', () {
      DomainMetadata.addCustomCategory('分类A');
      DomainMetadata.addCustomCategory('分类B');
      DomainMetadata.removeCustomCategory('餐饮美食');
      expect(DomainMetadata.activeCategoryNames.contains('餐饮美食'), isFalse);

      DomainMetadata.resetCustomCategories();
      expect(DomainMetadata.activeCategoryNames.length, equals(8));
      expect(
        DomainMetadata.activeCategoryNames,
        equals(DomainMetadata.coreCategories.map((c) => c.name).toList()),
      );
    });

    test('buildLlmCategoryEnum dynamically synchronizes with category additions and removals', () {
      final initialEnum = DomainMetadata.buildLlmCategoryEnum();
      expect(initialEnum.length, equals(8));
      expect(initialEnum, equals(DomainMetadata.activeCategoryNames));

      DomainMetadata.addCustomCategory('数码家电');
      final updatedEnum = DomainMetadata.buildLlmCategoryEnum();
      expect(updatedEnum.length, equals(9));
      expect(updatedEnum.contains('数码家电'), isTrue);

      DomainMetadata.removeCustomCategory('数码家电');
      final afterRemoveEnum = DomainMetadata.buildLlmCategoryEnum();
      expect(afterRemoveEnum.length, equals(8));
      expect(afterRemoveEnum.contains('数码家电'), isFalse);
    });

    test('buildLlmCategoryPromptConstraint dynamically generates prompt containing active categories', () {
      final prompt = DomainMetadata.buildLlmCategoryPromptConstraint();
      for (final name in DomainMetadata.activeCategoryNames) {
        expect(prompt.contains(name), isTrue, reason: 'Prompt must contain $name');
      }

      DomainMetadata.addCustomCategory('健身私教');
      final updatedPrompt = DomainMetadata.buildLlmCategoryPromptConstraint();
      expect(updatedPrompt.contains('健身私教'), isTrue);
    });
  });

  group('LLM Protocol and URL Suffix Resolution Tests', () {
    test('4 LLM protocols constants and suffixes match specification', () {
      expect(DomainMetadata.protocolOpenAiChat, equals('OpenAI Chat Completions'));
      expect(DomainMetadata.protocolAnthropicMessages, equals('Anthropic Messages'));
      expect(DomainMetadata.protocolOpenAiResponses, equals('OpenAI Responses API'));
      expect(DomainMetadata.protocolGeminiNative, equals('Gemini Native generateContent'));

      expect(
        DomainMetadata.protocolSuffixes[DomainMetadata.protocolOpenAiChat],
        equals('/v1/chat/completions'),
      );
      expect(
        DomainMetadata.protocolSuffixes[DomainMetadata.protocolAnthropicMessages],
        equals('/v1/messages'),
      );
      expect(
        DomainMetadata.protocolSuffixes[DomainMetadata.protocolOpenAiResponses],
        equals('/v1/responses'),
      );
      expect(
        DomainMetadata.protocolSuffixes[DomainMetadata.protocolGeminiNative],
        equals('/v1beta/models/{model}:generateContent'),
      );

      // Verify LlmProtocol enum definitions
      expect(LlmProtocol.openAiChat.label, equals('OpenAI Chat Completions'));
      expect(LlmProtocol.anthropicMessages.label, equals('Anthropic Messages'));
      expect(LlmProtocol.openAiResponses.label, equals('OpenAI Responses API'));
      expect(LlmProtocol.geminiGenerateContent.label, equals('Gemini Native generateContent'));
    });

    test('applyProtocolSuffixToUrl correctly appends /v1/chat/completions for OpenAI Chat', () {
      // Base URL without trailing slash
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.openai.com',
          DomainMetadata.protocolOpenAiChat,
        ),
        equals('https://api.openai.com/v1/chat/completions'),
      );

      // URL with trailing slash
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.openai.com/',
          DomainMetadata.protocolOpenAiChat,
        ),
        equals('https://api.openai.com/v1/chat/completions'),
      );

      // URL already containing /v1
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.openai.com/v1',
          DomainMetadata.protocolOpenAiChat,
        ),
        equals('https://api.openai.com/v1/chat/completions'),
      );

      // URL already complete with endpoint
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.openai.com/v1/chat/completions',
          DomainMetadata.protocolOpenAiChat,
        ),
        equals('https://api.openai.com/v1/chat/completions'),
      );
    });

    test('applyProtocolSuffixToUrl correctly appends /v1/messages for Anthropic Messages', () {
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.anthropic.com',
          DomainMetadata.protocolAnthropicMessages,
        ),
        equals('https://api.anthropic.com/v1/messages'),
      );

      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.anthropic.com/v1',
          DomainMetadata.protocolAnthropicMessages,
        ),
        equals('https://api.anthropic.com/v1/messages'),
      );
    });

    test('applyProtocolSuffixToUrl correctly appends /v1/responses for OpenAI Responses', () {
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.openai.com',
          DomainMetadata.protocolOpenAiResponses,
        ),
        equals('https://api.openai.com/v1/responses'),
      );

      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://api.openai.com/v1',
          DomainMetadata.protocolOpenAiResponses,
        ),
        equals('https://api.openai.com/v1/responses'),
      );
    });

    test('applyProtocolSuffixToUrl correctly handles Gemini Native generateContent with model replacement', () {
      // With model placeholder replacement
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://generativelanguage.googleapis.com',
          DomainMetadata.protocolGeminiNative,
          model: 'gemini-1.5-flash',
        ),
        equals('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent'),
      );

      // URL already ending with /v1beta
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://generativelanguage.googleapis.com/v1beta',
          DomainMetadata.protocolGeminiNative,
          model: 'gemini-1.5-pro',
        ),
        equals('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent'),
      );

      // Model omitted leaves placeholder intact
      expect(
        DomainMetadata.applyProtocolSuffixToUrl(
          'https://generativelanguage.googleapis.com',
          DomainMetadata.protocolGeminiNative,
        ),
        equals('https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'),
      );
    });
  });

  group('Custom Category Icon Resolution and Fallback Tests', () {
    test('Custom category with semantic keywords matches semantic icon', () {
      // Dining semantic match
      expect(
        AppIconRegistry.resolveCategoryIcon(categoryName: '深夜吃外卖'),
        equals(Icons.restaurant),
      );

      // Transport semantic match
      expect(
        AppIconRegistry.resolveCategoryIcon(categoryName: '滴滴打车出行'),
        equals(Icons.directions_subway),
      );
    });

    test('Custom category without semantic keywords gracefully falls back to label_outline_rounded', () {
      // Arbitrary custom category name
      expect(
        AppIconRegistry.resolveCategoryIcon(categoryName: '私人借款备忘'),
        equals(Icons.label_outline_rounded),
      );

      // Custom icon keys
      expect(
        AppIconRegistry.resolveCategoryIcon(iconKey: 'custom'),
        equals(Icons.label_outline_rounded),
      );
      expect(
        AppIconRegistry.resolveCategoryIconByKey('custom'),
        equals(Icons.label_outline_rounded),
      );
      expect(
        AppIconRegistry.resolveCategoryIconByKey('label'),
        equals(Icons.label_outline_rounded),
      );
      expect(
        AppIconRegistry.resolveCategoryIconByKey('unknown_custom_icon'),
        equals(Icons.label_outline_rounded),
      );
    });
  });

  group('Order ID Deduplication Pure Functions Tests', () {
    test('normalizeOrderId trims whitespace and recognizes placeholder empty values', () {
      expect(DomainMetadata.normalizeOrderId(null), equals(''));
      expect(DomainMetadata.normalizeOrderId(''), equals(''));
      expect(DomainMetadata.normalizeOrderId('   '), equals(''));
      expect(DomainMetadata.normalizeOrderId('无'), equals(''));
      expect(DomainMetadata.normalizeOrderId('--'), equals(''));
      expect(DomainMetadata.normalizeOrderId('-'), equals(''));
      expect(DomainMetadata.normalizeOrderId('null'), equals(''));
      expect(DomainMetadata.normalizeOrderId('none'), equals(''));
      expect(DomainMetadata.normalizeOrderId('NONE'), equals(''));
      expect(
        DomainMetadata.normalizeOrderId('  4200003143202610252738865252  '),
        equals('4200003143202610252738865252'),
      );
    });

    test('isOrderIdDuplicate matches duplicate orders and ignores empty orders', () {
      final existing = ['4200001234', '  4500005678  ', null, ''];

      // Match exact
      expect(DomainMetadata.isOrderIdDuplicate('4200001234', existing), isTrue);
      // Match with whitespace
      expect(DomainMetadata.isOrderIdDuplicate('  4200001234  ', existing), isTrue);
      expect(DomainMetadata.isOrderIdDuplicate('4500005678', existing), isTrue);

      // Unique order
      expect(DomainMetadata.isOrderIdDuplicate('9999999999', existing), isFalse);

      // Empty / invalid orders do not count as duplicate
      expect(DomainMetadata.isOrderIdDuplicate(null, existing), isFalse);
      expect(DomainMetadata.isOrderIdDuplicate('', existing), isFalse);
      expect(DomainMetadata.isOrderIdDuplicate('无', existing), isFalse);
      expect(DomainMetadata.isOrderIdDuplicate('--', existing), isFalse);
      expect(DomainMetadata.isOrderIdDuplicate('4200001234', null), isFalse);
    });

    test('partitionDraftsByDedup splits drafts into valid and duplicates with intra-batch dedup', () {
      final existingOrders = ['COMMITTED_ORDER_001'];
      final drafts = [
        {'id': 'd1', 'order': 'COMMITTED_ORDER_001', 'desc': '与已入账重复'},
        {'id': 'd2', 'order': 'UNIQUE_ORDER_100', 'desc': '首笔唯一单号'},
        {'id': 'd3', 'order': 'UNIQUE_ORDER_100', 'desc': '同批次自重复单号'},
        {'id': 'd4', 'order': '   ', 'desc': '无单号草稿'},
        {'id': 'd5', 'order': 'UNIQUE_ORDER_200', 'desc': '另一笔唯一单号'},
      ];

      final result = DomainMetadata.partitionDraftsByDedup(
        drafts: drafts,
        orderIdExtractor: (item) => item['order'],
        existingOrderIds: existingOrders,
      );

      // d2, d4, d5 should be valid
      expect(result.valid.length, equals(3));
      expect(result.valid.map((e) => e['id']), containsAll(['d2', 'd4', 'd5']));

      // d1 (committed duplicate) and d3 (intra-batch duplicate) should be intercepted
      expect(result.duplicates.length, equals(2));
      expect(result.duplicates.map((e) => e['id']), containsAll(['d1', 'd3']));
    });
  });

  group('Category Breakdown and Chart Aggregation Tests', () {
    test('formatCompactAmount formats decimals to compact strings without trailing zeros', () {
      expect(DomainMetadata.formatCompactAmount(437.20), equals('437.2'));
      expect(DomainMetadata.formatCompactAmount(5000.00), equals('5000'));
      expect(DomainMetadata.formatCompactAmount(15.77), equals('15.77'));
      expect(DomainMetadata.formatCompactAmount(0), equals('0'));
      expect(DomainMetadata.formatCompactAmount(0.0), equals('0'));
      expect(DomainMetadata.formatCompactAmount(12.30), equals('12.3'));
    });

    test('computeCategoryBreakdown aggregates and formats breakdown with Largest Remainder 100% sum', () {
      final expenses = {
        '日常购物': 437.20,
        '餐饮美食': 150.00,
        '交通出行': 95.50,
        '工资收入': 8000.00, // Should be excluded from expense breakdown
      };

      final result = DomainMetadata.computeCategoryBreakdown(expenses);

      // Verify total
      expect(result.totalExpense, equals(682.70));
      expect(result.totalExpenseText, equals('682.7'));
      expect(result.items.length, equals(3));

      // Verify order by amount descending
      expect(result.items[0].category, equals('日常购物'));
      expect(result.items[0].amount, equals(437.20));
      expect(result.items[0].amountText, equals('437.2'));
      expect(result.items[0].percentage, equals(64));
      expect(result.items[0].label, equals('日常购物(64%):437.2'));

      expect(result.items[1].category, equals('餐饮美食'));
      expect(result.items[1].percentage, equals(22));
      expect(result.items[1].label, equals('餐饮美食(22%):150'));

      expect(result.items[2].category, equals('交通出行'));
      expect(result.items[2].percentage, equals(14));
      expect(result.items[2].label, equals('交通出行(14%):95.5'));

      // Verify exact 100% sum via largest remainder method
      final totalPercent = result.items.fold<int>(0, (sum, it) => sum + it.percentage);
      expect(totalPercent, equals(100));
    });

    test('computeCategoryBreakdown dynamically reflects custom active categories', () {
      final expenses = {
        '日常购物': 300.0,
        '餐饮美食': 100.0,
        '自定义分类A': 200.0,
      };

      // Only '日常购物' and '自定义分类A' are active
      final result = DomainMetadata.computeCategoryBreakdown(
        expenses,
        activeCategories: ['日常购物', '自定义分类A'],
      );

      expect(result.items.length, equals(2));
      expect(result.items.any((it) => it.category == '餐饮美食'), isFalse);
      expect(result.totalExpense, equals(500.0));
      expect(result.items[0].category, equals('日常购物'));
      expect(result.items[0].percentage, equals(60));
      expect(result.items[1].category, equals('自定义分类A'));
      expect(result.items[1].percentage, equals(40));
    });

    test('computeCategoryBreakdown handles empty and zero-total expenses gracefully', () {
      final emptyResult = DomainMetadata.computeCategoryBreakdown({});
      expect(emptyResult.totalExpense, equals(0.0));
      expect(emptyResult.totalExpenseText, equals('0'));
      expect(emptyResult.items, isEmpty);

      final zeroResult = DomainMetadata.computeCategoryBreakdown({'餐饮美食': 0.0});
      expect(zeroResult.totalExpense, equals(0.0));
      expect(zeroResult.items, isEmpty);
    });
  });
}
