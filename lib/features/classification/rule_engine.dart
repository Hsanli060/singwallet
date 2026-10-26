// lib/features/classification/rule_engine.dart
import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../data/models/classification_rule.dart';
import '../recognition/merchant_normalizer.dart';
import 'models/classification_match_result.dart';
import 'rule_matcher.dart';

/// Pluggable interface for Tier 5 AI classification providers
abstract class AiClassificationProvider {
  Future<String?> recommendCategory({
    required String merchantRaw,
    String? merchantNormalized,
    String? paymentChannel,
    int? amountMinor,
    String? remarks,
  });
}

/// Cold-start keyword entry
class _DictionaryEntry {
  final String keyword;
  final String categoryId;

  const _DictionaryEntry(this.keyword, this.categoryId);
}

/// 6-Tier Classification Rule Engine (Features F27, F28, F29, F30)
class ClassificationRuleEngine {
  static int _ruleCounter = 0;

  final DatabaseExecutor _db;
  final AiClassificationProvider? _aiProvider;
  final List<_DictionaryEntry> _dictionaryEntries;

  ClassificationRuleEngine(
    this._db, {
    AiClassificationProvider? aiProvider,
    Map<String, String>? customKeywords,
  })  : _aiProvider = aiProvider,
        _dictionaryEntries = _buildDictionary(customKeywords);

  static List<_DictionaryEntry> _buildDictionary(Map<String, String>? customKeywords) {
    final map = <String, List<String>>{
      'cat_food': [
        '麦当劳', '肯德基', '汉堡王', '星巴克咖啡', '星巴克', '瑞幸咖啡', '瑞幸', '喜茶',
        '奈雪的茶', '奈雪', '茶百道', '古茗', '蜜雪冰城', '霸王茶姬', '益禾堂',
        '海底捞火锅', '海底捞', '必胜客', '赛百味', '达美乐', '黄焖鸡米饭', '黄焖鸡',
        '沙县小吃', '绝味鸭脖', '周黑鸭', '美团外卖', '饿了么', '盒马鲜食',
        '咖啡', '奶茶', '烘焙', '面包', '蛋糕', '饮品', '饭店', '餐厅', '烤肉',
        '火锅', '麻辣烫', '面馆', '快餐', '料理', '烧烤', '小吃', '馄饨', '饺子',
        '披萨', '寿司', '食堂', '早餐', '午餐', '晚餐', '美食', '酒楼', '菜馆', '大排档',
      ],
      'cat_transport': [
        '地铁', '公交', '轨道交通', '铁路', '12306', '火车站', '高铁', '动车',
        '一卡通', '乘车码', '交通卡', '公共交通', '滴滴出行', '滴滴快车', '滴滴',
        '花小猪', 'T3出行', '曹操出行', '高德打车', '出租车', '顺风车', '专车', '快车',
        '拼车', '货拉拉', '机票', '航旅纵横', '东方航空', '南方航空', '中国国航',
        '携程机票', '飞猪机票', '机场', '加油站', '中石油', '中石化', '延长石油',
        '充电桩', '特来电', '星星充电', '停车', '停车场', '泊车', 'ETC',
        '高速公路', '路桥费', '洗车', '修车', '保养', '加油',
      ],
      'cat_shopping': [
        '7-Eleven', '711', '全家', '罗森', '美宜佳', '喜士多', '便利蜂',
        '盒马鲜生', '盒马', '山姆会员店', '山姆', '沃尔玛', '大润发', '永辉超市',
        '永辉', '华润万家', '物美超市', '物美', '超市', '便利店', '菜市场', '生鲜',
        '水果店', '淘宝', '天猫', '京东', '拼多多', '唯品会', '闲鱼', '抖音电商',
        '快手电商', '得物', '网易严选', '严选', '服饰', '服装', '优衣库', 'ZARA',
        '屈臣氏', '万宁', '专卖店', '数码', '电脑', '手机',
      ],
      'cat_entertainment': [
        '电影', '万达影城', '大地影院', '猫眼', '淘票票', '影音', 'KTV', '网吧',
        '剧本杀', '密室逃脱', '腾讯互娱', '网易游戏', '米哈游', 'Steam', 'Nintendo',
        'PlayStation', '游戏充值', '游乐园', '迪士尼', '环球影城', '景区门票',
        '爱奇艺', '腾讯视频', '优酷', '哔哩哔哩', 'B站', '芒果TV', '网易云音乐',
        'QQ音乐', 'Apple', 'Google', '订阅', '健身房', '游泳馆', '运动馆', '瑜伽',
        '羽毛球', '篮球',
      ],
      'cat_utilities': [
        '国家电网', '南方电网', '水费', '电费', '燃气费', '暖气费', '物业费',
        '自来水', '燃气', '中国移动', '中国联通', '中国电信', '话费充值', '宽带',
        '手机充值', '房租', '自如', '链家', '泊寓', '租房', '家政', '保洁', '维修', '物业',
      ],
      'cat_medical': [
        '医院', '诊所', '门诊', '药店', '大药房', '益丰', '一心堂', '国大药房',
        '老百姓大药房', '体检', '挂号', '医疗', '口腔', '齿科', '眼镜', '药房', '医药',
      ],
      'cat_income': [
        '工资', '薪酬', '奖金', '劳务报酬', '报销', '退税', '分红', '利息', '理财收益', '投资收益',
      ],
    };

    final list = <_DictionaryEntry>[];
    map.forEach((catId, keywords) {
      for (final kw in keywords) {
        list.add(_DictionaryEntry(kw, catId));
      }
    });

    if (customKeywords != null) {
      customKeywords.forEach((kw, catId) {
        list.add(_DictionaryEntry(kw, catId));
      });
    }

    // Sort by keyword length descending (Longest match first!)
    list.sort((a, b) => b.keyword.length.compareTo(a.keyword.length));
    return list;
  }

  /// Classifies candidate transaction data using strict 6-tier hierarchy:
  /// Tier 1: User manual override
  /// Tier 2: Custom active rules (ordered by priority DESC, specificity DESC)
  /// Tier 3: Historical identical merchant category mapping
  /// Tier 4: Built-in Chinese keyword dictionary
  /// Tier 5: Optional AI recommendation
  /// Tier 6: Default fallback ('cat_other')
  Future<ClassificationMatchResult> classify({
    String? manualCategoryId,
    String? manualProjectId,
    List<String> manualTagIds = const [],
    required String merchantRaw,
    String? merchantNormalized,
    String? paymentChannel,
    int? amountMinor,
    String? remarks,
    String type = 'expense',
  }) async {
    // -------------------------------------------------------------------------
    // Tier 1: User Manual Explicit Selection
    // -------------------------------------------------------------------------
    if (manualCategoryId != null && manualCategoryId.trim().isNotEmpty) {
      return ClassificationMatchResult.manual(
        categoryId: manualCategoryId.trim(),
        projectId: manualProjectId,
        tagIds: manualTagIds,
      );
    }

    final effRaw = merchantRaw.trim();
    final effNorm = merchantNormalized?.trim() ??
        MerchantNormalizer.normalize(effRaw);

    // -------------------------------------------------------------------------
    // Tier 2: Custom Active Rules
    // -------------------------------------------------------------------------
    final customRuleResult = await _matchCustomRules(
      merchantRaw: effRaw,
      merchantNormalized: effNorm,
      paymentChannel: paymentChannel,
    );
    if (customRuleResult != null) {
      return customRuleResult;
    }

    // -------------------------------------------------------------------------
    // Tier 3: Historical Identical Merchant Transactions
    // -------------------------------------------------------------------------
    final historyResult = await _matchHistory(
      merchantRaw: effRaw,
      merchantNormalized: effNorm,
      type: type,
    );
    if (historyResult != null) {
      return historyResult;
    }

    // -------------------------------------------------------------------------
    // Tier 4: Built-in Keyword Dictionary Mapping
    // -------------------------------------------------------------------------
    final dictResult = _matchDictionary(
      merchantRaw: effRaw,
      merchantNormalized: effNorm,
      remarks: remarks,
    );
    if (dictResult != null) {
      return dictResult;
    }

    // -------------------------------------------------------------------------
    // Tier 5: Optional AI Recommendation (Local Schema Validated)
    // -------------------------------------------------------------------------
    if (_aiProvider != null) {
      final aiResult = await _matchAi(
        merchantRaw: effRaw,
        merchantNormalized: effNorm,
        paymentChannel: paymentChannel,
        amountMinor: amountMinor,
        remarks: remarks,
      );
      if (aiResult != null) {
        return aiResult;
      }
    }

    // -------------------------------------------------------------------------
    // Tier 6: Default Fallback
    // -------------------------------------------------------------------------
    return ClassificationMatchResult.fallback(categoryId: 'cat_other');
  }

  Future<ClassificationMatchResult?> _matchCustomRules({
    required String merchantRaw,
    required String merchantNormalized,
    String? paymentChannel,
  }) async {
    final rows = await _db.query(
      'classification_rules',
      where: 'enabled = 1',
    );

    if (rows.isEmpty) return null;

    final rules = rows.map((r) => ClassificationRule.fromMap(r)).toList();
    // Sort according to tie-breaking comparator (priority DESC, length DESC, created DESC)
    rules.sort(RuleMatcher.compareRules);

    for (final rule in rules) {
      if (RuleMatcher.evaluateRule(
        rule: rule,
        merchantRaw: merchantRaw,
        merchantNormalized: merchantNormalized,
        paymentChannel: paymentChannel,
      )) {
        return ClassificationMatchResult.customRule(
          categoryId: rule.categoryId,
          projectId: rule.projectId,
          ruleId: rule.id,
          pattern: rule.merchantPattern,
          priority: rule.priority,
        );
      }
    }

    return null;
  }

  Future<ClassificationMatchResult?> _matchHistory({
    required String merchantRaw,
    required String merchantNormalized,
    required String type,
  }) async {
    if (merchantRaw.isEmpty && merchantNormalized.isEmpty) return null;

    const sql = '''
      SELECT category_id, project_id, COUNT(*) as freq, MAX(occurred_on) as latest_date
      FROM transactions
      WHERE (merchant_normalized = ? OR merchant_raw = ?)
        AND deleted_at IS NULL
        AND category_id IS NOT NULL
        AND type = ?
      GROUP BY category_id
      ORDER BY freq DESC, latest_date DESC
      LIMIT 1;
    ''';

    final effectiveTarget = merchantNormalized.isNotEmpty ? merchantNormalized : merchantRaw;
    final rows = await _db.rawQuery(sql, [effectiveTarget, merchantRaw, type]);

    if (rows.isEmpty) return null;

    final row = rows.first;
    final catId = row['category_id'] as String;
    final projId = row['project_id'] as String?;
    final freq = row['freq'] as int;
    final confidence = freq >= 2 ? 0.90 : 0.80;

    return ClassificationMatchResult.history(
      categoryId: catId,
      projectId: projId,
      frequency: freq,
      confidence: confidence,
    );
  }

  ClassificationMatchResult? _matchDictionary({
    required String merchantRaw,
    required String merchantNormalized,
    String? remarks,
  }) {
    // 1. Try normalized merchant
    if (merchantNormalized.isNotEmpty) {
      final entry = _findDictionaryEntry(merchantNormalized);
      if (entry != null) {
        return ClassificationMatchResult.builtinKeyword(
          categoryId: entry.categoryId,
          keyword: entry.keyword,
        );
      }
    }

    // 2. Try raw merchant
    if (merchantRaw.isNotEmpty && merchantRaw != merchantNormalized) {
      final entry = _findDictionaryEntry(merchantRaw);
      if (entry != null) {
        return ClassificationMatchResult.builtinKeyword(
          categoryId: entry.categoryId,
          keyword: entry.keyword,
        );
      }
    }

    // 3. Try remarks
    if (remarks != null && remarks.trim().isNotEmpty) {
      final entry = _findDictionaryEntry(remarks);
      if (entry != null) {
        return ClassificationMatchResult.builtinKeyword(
          categoryId: entry.categoryId,
          keyword: entry.keyword,
        );
      }
    }

    return null;
  }

  _DictionaryEntry? _findDictionaryEntry(String text) {
    final lower = text.toLowerCase();
    for (final entry in _dictionaryEntries) {
      if (lower.contains(entry.keyword.toLowerCase())) {
        return entry;
      }
    }
    return null;
  }

  Future<ClassificationMatchResult?> _matchAi({
    required String merchantRaw,
    String? merchantNormalized,
    String? paymentChannel,
    int? amountMinor,
    String? remarks,
  }) async {
    try {
      final suggestedCatId = await _aiProvider!.recommendCategory(
        merchantRaw: merchantRaw,
        merchantNormalized: merchantNormalized,
        paymentChannel: paymentChannel,
        amountMinor: amountMinor,
        remarks: remarks,
      );
      if (suggestedCatId == null || suggestedCatId.trim().isEmpty) return null;

      final trimmedCatId = suggestedCatId.trim();
      // Validate that category actually exists in local database and is not archived
      final rows = await _db.query(
        'categories',
        where: 'id = ? AND archived_at IS NULL',
        whereArgs: [trimmedCatId],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        return ClassificationMatchResult.ai(categoryId: trimmedCatId);
      }
    } catch (_) {
      // AI provider failure silently falls through to fallback
    }
    return null;
  }

  /// Dynamic Rule Learning (F30):
  /// Creates or updates a classification rule when user confirms or modifies a category.
  /// Strict non-retroactivity: never modifies already committed transactions!
  Future<ClassificationRule> learnRuleFromUserAction({
    required String merchantRaw,
    required String categoryId,
    String? projectId,
    String? paymentChannel,
    int priority = 100,
  }) async {
    final normalized = MerchantNormalizer.normalize(merchantRaw);
    final pattern = normalized.isNotEmpty ? normalized : merchantRaw.trim();

    if (pattern.isEmpty) {
      throw ArgumentError('Cannot learn rule for empty merchant name.');
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Check existing rule with identical pattern
    final List<Map<String, dynamic>> existing;
    if (paymentChannel != null) {
      existing = await _db.query(
        'classification_rules',
        where: 'merchant_pattern = ? AND payment_channel = ?',
        whereArgs: [pattern, paymentChannel],
        limit: 1,
      );
    } else {
      existing = await _db.query(
        'classification_rules',
        where: 'merchant_pattern = ? AND payment_channel IS NULL',
        whereArgs: [pattern],
        limit: 1,
      );
    }

    if (existing.isNotEmpty) {
      final oldRule = ClassificationRule.fromMap(existing.first);
      final updated = oldRule.copyWith(
        categoryId: categoryId,
        projectId: projectId,
        priority: priority,
        enabled: 1,
        version: oldRule.version + 1,
        updatedAt: nowIso,
      );
      await _db.update(
        'classification_rules',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      return updated;
    }

    // Insert new rule with collision-free monotonic microsecond identifier
    final ruleId = 'rule_${DateTime.now().microsecondsSinceEpoch}_${pattern.hashCode.abs()}_${_ruleCounter++}';
    final newRule = ClassificationRule(
      id: ruleId,
      priority: priority,
      merchantPattern: pattern,
      paymentChannel: paymentChannel,
      categoryId: categoryId,
      projectId: projectId,
      enabled: 1,
      version: 1,
      createdAt: nowIso,
      updatedAt: nowIso,
    );

    await _db.insert('classification_rules', newRule.toMap());
    return newRule;
  }
}
