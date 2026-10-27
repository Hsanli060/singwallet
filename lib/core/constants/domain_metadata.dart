// lib/core/constants/domain_metadata.dart
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/project.dart';

/// Metadata for a financial classification category.
class CategoryMetadata {
  final String id;
  final String name;
  final String iconKey;
  final String emoji;
  final int type; // 0: expense, 1: income, 2: both
  final int sortOrder;
  final List<String> keywords;
  final List<String> subCategories;
  final String applicableType; // 'expense', 'income', 'both'
  final String? description;

  const CategoryMetadata({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.emoji,
    required this.type,
    required this.sortOrder,
    this.keywords = const [],
    this.subCategories = const [],
    this.applicableType = 'expense',
    this.description,
  });

  /// Converts this metadata into an immutable [Category] database entity.
  Category toCategory({String? timestamp}) {
    final ts = timestamp ?? DateTime.utc(2026, 1, 1).toIso8601String();
    return Category(
      id: id,
      name: name,
      applicableType: applicableType,
      iconKey: iconKey,
      sortOrder: sortOrder,
      createdAt: ts,
      updatedAt: ts,
    );
  }
}

/// Metadata for seeding default financial accounts.
class AccountSeedMetadata {
  final String id;
  final String name;
  final String kind; // cash, debit_card, credit_card, e_wallet, other
  final String? cardLast4;
  final String? alias;

  const AccountSeedMetadata({
    required this.id,
    required this.name,
    required this.kind,
    this.cardLast4,
    this.alias,
  });

  /// Converts this metadata into an immutable [Account] database entity.
  Account toAccount({String? timestamp}) {
    final ts = timestamp ?? DateTime.utc(2026, 1, 1).toIso8601String();
    return Account(
      id: id,
      name: name,
      kind: kind,
      cardLast4: cardLast4,
      createdAt: ts,
      updatedAt: ts,
    );
  }
}

/// Metadata for seeding default budgeting projects.
class ProjectSeedMetadata {
  final String id;
  final String name;
  final String? alias;

  const ProjectSeedMetadata({
    required this.id,
    required this.name,
    this.alias,
  });

  /// Converts this metadata into an immutable [Project] database entity.
  Project toProject({String? timestamp}) {
    final ts = timestamp ?? DateTime.utc(2026, 1, 1).toIso8601String();
    return Project(
      id: id,
      name: name,
      createdAt: ts,
      updatedAt: ts,
    );
  }
}

/// Metadata for payment channels and alias recognition.
class ChannelMetadata {
  final String key;
  final String name;
  final String iconKey;
  final List<String> aliases;

  const ChannelMetadata({
    required this.key,
    required this.name,
    required this.iconKey,
    this.aliases = const [],
  });
}

/// 分类占比饼图统计条目
class CategoryBreakdownItem {
  final String category;
  final double amount;
  final String amountText;
  final int percentage;
  final double ratio;
  final String color;
  final String label;

  const CategoryBreakdownItem({
    required this.category,
    required this.amount,
    required this.amountText,
    required this.percentage,
    required this.ratio,
    required this.color,
    required this.label,
  });
}

/// 分类占比统计聚合结果
class CategoryBreakdownResult {
  final double totalExpense;
  final String totalExpenseText;
  final List<CategoryBreakdownItem> items;

  const CategoryBreakdownResult({
    required this.totalExpense,
    required this.totalExpenseText,
    required this.items,
  });
}

class _RawBreakdown {
  final String category;
  final double amount;
  final double ratio;
  int floorPercent;
  final double remainder;
  final int origIndex;

  _RawBreakdown({
    required this.category,
    required this.amount,
    required this.ratio,
    required this.floorPercent,
    required this.remainder,
    required this.origIndex,
  });
}

enum LlmProtocol {
  openAiChat(
    id: 'openai_chat_completions',
    label: 'OpenAI Chat Completions',
    pathSuffix: '/v1/chat/completions',
  ),
  anthropicMessages(
    id: 'anthropic_messages',
    label: 'Anthropic Messages',
    pathSuffix: '/v1/messages',
  ),
  openAiResponses(
    id: 'openai_responses',
    label: 'OpenAI Responses API',
    pathSuffix: '/v1/responses',
  ),
  geminiGenerateContent(
    id: 'gemini_generate_content',
    label: 'Gemini Native generateContent',
    pathSuffix: '/v1beta/models/{model}:generateContent',
  );

  final String id;
  final String label;
  final String pathSuffix;

  const LlmProtocol({
    required this.id,
    required this.label,
    required this.pathSuffix,
  });
}

/// Central single source of truth for domain metadata across SingWallet.
///
/// Decouples domain definitions from database seeders, UI widgets, and theme registries.
class DomainMetadata {
  DomainMetadata._();

  /// 4 Major LLM Model Protocol String Constants
  static const String protocolOpenAiChat = 'OpenAI Chat Completions';
  static const String protocolAnthropicMessages = 'Anthropic Messages';
  static const String protocolOpenAiResponses = 'OpenAI Responses API';
  static const String protocolGeminiNative = 'Gemini Native generateContent';
  static const String protocolGeminiGenerateContent = protocolGeminiNative;

  /// Standard path suffixes for the 4 LLM protocols
  static const Map<String, String> protocolSuffixes = {
    protocolOpenAiChat: '/v1/chat/completions',
    protocolAnthropicMessages: '/v1/messages',
    protocolOpenAiResponses: '/v1/responses',
    protocolGeminiNative: '/v1beta/models/{model}:generateContent',
  };

  /// 8 default core categories defined by domain standards.
  static const List<CategoryMetadata> coreCategories = [
    CategoryMetadata(
      id: 'cat_food',
      name: '餐饮美食',
      iconKey: 'food',
      emoji: '🍔',
      type: 0,
      sortOrder: 1,
      applicableType: 'expense',
      keywords: [
        '餐饮',
        '美食',
        '吃',
        '外卖',
        '饭',
        '餐厅',
        '肯德基',
        '麦当劳',
        '星巴克',
        '喜茶',
        '咖啡',
        '火锅',
        '早点',
        '午餐',
        '晚餐',
      ],
      subCategories: ['正餐', '外卖', '饮品咖啡', '水果零食'],
    ),
    CategoryMetadata(
      id: 'cat_transport',
      name: '交通出行',
      iconKey: 'transport',
      emoji: '🚗',
      type: 0,
      sortOrder: 2,
      applicableType: 'expense',
      keywords: [
        '交通',
        '出行',
        '车',
        '地铁',
        '打车',
        '滴滴',
        '公交',
        '火车',
        '高铁',
        '机票',
        '加油',
        '停车',
        '单车',
      ],
      subCategories: ['公共交通', '打车出租', '私家车费用', '城际交通'],
    ),
    CategoryMetadata(
      id: 'cat_shopping',
      name: '日常购物',
      iconKey: 'shopping',
      emoji: '🛒',
      type: 0,
      sortOrder: 3,
      applicableType: 'expense',
      keywords: [
        '购物',
        '超市',
        '日用',
        '百货',
        '淘宝',
        '京东',
        '拼多多',
        '商场',
        '便利店',
        '盒马',
        '服饰',
        '数码',
      ],
      subCategories: ['商超日用', '服饰鞋帽', '数码家电', '美妆个护'],
    ),
    CategoryMetadata(
      id: 'cat_entertainment',
      name: '休闲娱乐',
      iconKey: 'entertainment',
      emoji: '🎮',
      type: 0,
      sortOrder: 4,
      applicableType: 'expense',
      keywords: [
        '娱乐',
        '休闲',
        '玩',
        '影',
        '电影',
        '游戏',
        '网吧',
        'KTV',
        '门票',
        '演出',
        '游乐',
        '剧本杀',
      ],
      subCategories: ['游戏电竞', '电影演出', '聚会运动', '旅游度假'],
    ),
    CategoryMetadata(
      id: 'cat_bills',
      name: '生活缴费',
      iconKey: 'utilities',
      emoji: '⚡',
      type: 0,
      sortOrder: 5,
      applicableType: 'expense',
      keywords: [
        '生活缴费',
        '账单',
        '水电',
        '电费',
        '水费',
        '燃气',
        '物业',
        '话费',
        '宽带',
        '房租',
        '费',
      ],
      subCategories: ['水电气暖', '话费宽带', '物业房租', '税费规费'],
    ),
    CategoryMetadata(
      id: 'cat_medical',
      name: '医疗健康',
      iconKey: 'medical',
      emoji: '💊',
      type: 0,
      sortOrder: 6,
      applicableType: 'expense',
      keywords: [
        '医疗',
        '健康',
        '药',
        '医院',
        '诊所',
        '体检',
        '看病',
        '药房',
        '牙科',
        '挂号',
      ],
      subCategories: ['药品配剂', '门诊挂号', '健康体检', '医疗器材'],
    ),
    CategoryMetadata(
      id: 'cat_other',
      name: '其他支出',
      iconKey: 'other',
      emoji: '📦',
      type: 0,
      sortOrder: 7,
      applicableType: 'both',
      keywords: [
        '其他',
        '其它',
        '杂项',
        '兜底',
      ],
      subCategories: ['其他杂项', '意外支出'],
    ),
    CategoryMetadata(
      id: 'cat_income',
      name: '工资收入',
      iconKey: 'salary',
      emoji: '💰',
      type: 1,
      sortOrder: 8,
      applicableType: 'income',
      keywords: [
        '收入',
        '工资',
        '红包',
        '薪资',
        '奖金',
        '转账',
        '兼职',
        '报酬',
        '分红',
        '收益',
      ],
      subCategories: ['主业工资', '副业收入', '理财收益', '礼金红包'],
    ),
  ];

  /// Backward-compatible alias pointing directly to [coreCategories].
  static const List<CategoryMetadata> categories = coreCategories;

  /// Dynamic list of currently active categories (initialized to default 8 core categories).
  static final List<CategoryMetadata> _activeCategories =
      List<CategoryMetadata>.from(coreCategories);

  /// Returns an unmodifiable list of currently active categories metadata.
  static List<CategoryMetadata> get activeCategories =>
      List.unmodifiable(_activeCategories);

  /// Returns all currently active category names.
  static List<String> get activeCategoryNames =>
      _activeCategories.map((c) => c.name).toList();

  /// Adds a custom category. Returns `false` if a category with the same name already exists.
  static bool addCustomCategory(String name, {String type = 'expense', String? desc}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    // Check if category name already exists (case-insensitive)
    final exists = _activeCategories.any(
      (c) => c.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) return false;

    final int typeVal = type == 'income' ? 1 : (type == 'both' ? 2 : 0);
    final keywords = <String>[trimmed];
    if (desc != null && desc.trim().isNotEmpty) {
      keywords.add(desc.trim());
    }

    final emoji = _detectEmojiForCategory(trimmed, desc);

    final newCat = CategoryMetadata(
      id: 'cat_custom_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      iconKey: 'custom',
      emoji: emoji,
      type: typeVal,
      sortOrder: _activeCategories.length + 1,
      applicableType: type,
      keywords: keywords,
      subCategories: const [],
      description: desc?.trim(),
    );

    _activeCategories.add(newCat);
    return true;
  }

  /// Removes a category by name or ID. If only 1 category remains, deletion is protected and returns `false`.
  static bool removeCustomCategory(String name) {
    if (_activeCategories.length <= 1) {
      return false;
    }

    final trimmed = name.trim().toLowerCase();
    final index = _activeCategories.indexWhere(
      (c) => c.name.toLowerCase() == trimmed || c.id.toLowerCase() == trimmed,
    );

    if (index == -1) {
      return false;
    }

    _activeCategories.removeAt(index);
    return true;
  }

  /// Resets active categories to default 8 core categories.
  static void resetCustomCategories() {
    _activeCategories
      ..clear()
      ..addAll(coreCategories);
  }

  /// Dynamically builds the JSON Schema `enum` constraint for LLM services based on active categories.
  static List<String> buildLlmCategoryEnum() {
    return List<String>.from(activeCategoryNames);
  }

  /// Dynamically builds Prompt category scope description for LLM services.
  static String buildLlmCategoryPromptConstraint() {
    final names = activeCategoryNames.map((n) => '"$n"').join('、');
    return '分类范围必须严格限定在以下集合中，禁止臆造其他分类：[$names]。请根据商户名称和交易消费场景语义选择一个最精准的分类。';
  }

  /// Formats and applies the appropriate protocol path suffix to a given base or raw URL.
  ///
  /// Supports:
  /// - 'OpenAI Chat Completions' -> '/v1/chat/completions'
  /// - 'Anthropic Messages' -> '/v1/messages'
  /// - 'OpenAI Responses API' -> '/v1/responses'
  /// - 'Gemini Native generateContent' -> '/v1beta/models/{model}:generateContent'
  ///
  /// Replaces `{model}` placeholder when [model] is provided.
  /// Intelligently avoids redundant `/v1` or duplicate suffixes if already included in [rawUrl].
  static String applyProtocolSuffixToUrl(
    String rawUrl,
    String protocol, {
    String model = '',
  }) {
    var url = rawUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    final p = protocol.trim().toLowerCase();
    String suffix;

    if (p == protocolOpenAiChat.toLowerCase() ||
        p.contains('chat/completions') ||
        p.contains('chat_completions') ||
        p.contains('openai chat') ||
        p == 'openai') {
      suffix = '/v1/chat/completions';
    } else if (p == protocolAnthropicMessages.toLowerCase() ||
        p.contains('messages') ||
        p.contains('anthropic')) {
      suffix = '/v1/messages';
    } else if (p == protocolOpenAiResponses.toLowerCase() ||
        p.contains('responses') ||
        p.contains('openai responses')) {
      suffix = '/v1/responses';
    } else if (p == protocolGeminiNative.toLowerCase() ||
        p.contains('gemini') ||
        p.contains('generatecontent')) {
      suffix = '/v1beta/models/{model}:generateContent';
    } else if (protocolSuffixes.containsKey(protocol)) {
      suffix = protocolSuffixes[protocol]!;
    } else {
      suffix = protocol.startsWith('/') ? protocol : '/$protocol';
    }

    if (model.trim().isNotEmpty) {
      suffix = suffix.replaceAll('{model}', model.trim());
    }

    if (url.isEmpty) {
      return suffix;
    }

    // If url already ends with suffix, return as is
    if (url.endsWith(suffix)) {
      return url;
    }

    // Avoid duplicate /v1 if url already ends with /v1 and suffix starts with /v1/
    if (suffix.startsWith('/v1/') && url.endsWith('/v1')) {
      return '${url.substring(0, url.length - 3)}$suffix';
    }

    // Avoid duplicate /v1beta if url already ends with /v1beta and suffix starts with /v1beta/
    if (suffix.startsWith('/v1beta/') && url.endsWith('/v1beta')) {
      return '${url.substring(0, url.length - 7)}$suffix';
    }

    return '$url$suffix';
  }

  static String _detectEmojiForCategory(String name, String? desc) {
    final text = '$name ${desc ?? ''}'.toLowerCase();
    if (text.contains('健身') || text.contains('运动')) return '🏋️';
    if (text.contains('宠') || text.contains('猫') || text.contains('狗')) return '🐾';
    if (text.contains('书') || text.contains('学') || text.contains('课')) return '📚';
    if (text.contains('房') || text.contains('租')) return '🏠';
    if (text.contains('美') || text.contains('妆') || text.contains('理发')) return '💄';
    if (text.contains('车') || text.contains('油')) return '🚗';
    if (text.contains('数码') || text.contains('手机') || text.contains('电脑')) return '💻';
    if (text.contains('母婴') || text.contains('娃') || text.contains('宝宝')) return '🍼';
    return '🏷️';
  }

  /// Default 4 financial accounts satisfying both production seeding and test assertions.
  static const List<AccountSeedMetadata> accounts = [
    AccountSeedMetadata(
      id: 'acc_wechat',
      name: '微信支付',
      kind: 'e_wallet',
      alias: '微信零钱',
    ),
    AccountSeedMetadata(
      id: 'acc_alipay',
      name: '支付宝',
      kind: 'e_wallet',
      alias: '支付宝余额',
    ),
    AccountSeedMetadata(
      id: 'acc_bank',
      name: '银行卡',
      kind: 'debit_card',
      alias: '招商银行储蓄卡',
    ),
    AccountSeedMetadata(
      id: 'acc_cash',
      name: '现金',
      kind: 'cash',
      alias: '现金钱包',
    ),
  ];

  /// Extended account seed templates for custom creation presets.
  static const List<AccountSeedMetadata> presetAccounts = [
    AccountSeedMetadata(
      id: 'acc_wechat',
      name: '微信零钱',
      kind: 'e_wallet',
      alias: '微信支付',
    ),
    AccountSeedMetadata(
      id: 'acc_alipay',
      name: '支付宝余额',
      kind: 'e_wallet',
      alias: '支付宝',
    ),
    AccountSeedMetadata(
      id: 'acc_bank',
      name: '招商银行储蓄卡',
      kind: 'debit_card',
      cardLast4: '8848',
      alias: '银行卡',
    ),
    AccountSeedMetadata(
      id: 'acc_cash',
      name: '现金钱包',
      kind: 'cash',
      alias: '现金',
    ),
  ];

  /// Default 2 budget projects satisfying both database foreign keys and test assertions.
  static const List<ProjectSeedMetadata> projects = [
    ProjectSeedMetadata(
      id: 'proj_travel',
      name: '旅行出游',
      alias: '2026春节旅游',
    ),
    ProjectSeedMetadata(
      id: 'proj_home',
      name: '家居装修',
      alias: '房屋装修',
    ),
  ];

  /// Extended project seed templates for custom creation presets.
  static const List<ProjectSeedMetadata> presetProjects = [
    ProjectSeedMetadata(
      id: 'proj_daily',
      name: '日常开销',
    ),
    ProjectSeedMetadata(
      id: 'proj_travel',
      name: '2026春节旅游',
      alias: '旅行出游',
    ),
    ProjectSeedMetadata(
      id: 'proj_home',
      name: '房屋装修',
      alias: '家居装修',
    ),
    ProjectSeedMetadata(
      id: 'proj_side',
      name: '副业收入',
    ),
  ];

  /// Payment channel metadata and alias mappings.
  static const List<ChannelMetadata> channels = [
    ChannelMetadata(
      key: 'wechat',
      name: '微信支付',
      iconKey: 'wechat',
      aliases: ['wechat', 'wx', '微信', '微信支付', '微信零钱', '财付通'],
    ),
    ChannelMetadata(
      key: 'alipay',
      name: '支付宝',
      iconKey: 'alipay',
      aliases: ['alipay', '支付宝', '支付宝余额', '花呗', '余额宝'],
    ),
    ChannelMetadata(
      key: 'bank',
      name: '银行卡',
      iconKey: 'bank',
      aliases: [
        'bank',
        'bank_card',
        'unionpay',
        'card',
        'debit_card',
        '银行卡',
        '借记卡',
        '储蓄卡',
        '银联',
        '招商银行',
        '招行',
        '工商银行',
        '建设银行',
        '农业银行',
      ],
    ),
    ChannelMetadata(
      key: 'credit',
      name: '信用卡',
      iconKey: 'credit',
      aliases: ['credit', 'credit_card', '信用卡', '贷记卡'],
    ),
    ChannelMetadata(
      key: 'cash',
      name: '现金',
      iconKey: 'cash',
      aliases: ['cash', '现金', '现金钱包', '纸币', '零钱'],
    ),
    ChannelMetadata(
      key: 'other',
      name: '其他',
      iconKey: 'other',
      aliases: ['other', '其他', '其它', '其他渠道', '未知渠道'],
    ),
  ];

  /// Finds category metadata by icon key or ID (supporting aliases like 'restaurant', 'bills').
  static CategoryMetadata? findCategoryByIconKey(String? key) {
    if (key == null || key.trim().isEmpty) return null;
    final lower = key.trim().toLowerCase();

    for (final cat in _activeCategories) {
      if (cat.iconKey.toLowerCase() == lower || cat.id.toLowerCase() == lower) {
        return cat;
      }
    }

    for (final cat in coreCategories) {
      if (cat.iconKey.toLowerCase() == lower || cat.id.toLowerCase() == lower) {
        return cat;
      }
    }

    if (lower.contains('food') || lower.contains('restaurant')) return coreCategories[0];
    if (lower.contains('transport') || lower.contains('car') || lower.contains('subway')) return coreCategories[1];
    if (lower.contains('shop')) return coreCategories[2];
    if (lower.contains('entertain') || lower.contains('game') || lower.contains('sport')) return coreCategories[3];
    if (lower.contains('util') || lower.contains('bill') || lower.contains('receipt')) return coreCategories[4];
    if (lower.contains('med') || lower.contains('hosp')) return coreCategories[5];
    if (lower.contains('sal') || lower.contains('income') || lower.contains('wallet')) return coreCategories[7];
    if (lower.contains('other') || lower.contains('more_horiz')) return coreCategories[6];

    return null;
  }

  /// Finds category metadata by matching name or recognized keywords.
  static CategoryMetadata? findCategoryByNameOrKeyword(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final query = text.trim().toLowerCase();

    // 1. Direct ID or Name match in active categories
    for (final cat in _activeCategories) {
      if (cat.id.toLowerCase() == query || cat.name.toLowerCase() == query) {
        return cat;
      }
    }

    // 2. Keyword match in active categories
    for (final cat in _activeCategories) {
      for (final kw in cat.keywords) {
        if (query.contains(kw.toLowerCase())) {
          return cat;
        }
      }
    }

    // 3. Subcategories match in active categories
    for (final cat in _activeCategories) {
      for (final sub in cat.subCategories) {
        if (query.contains(sub.toLowerCase())) {
          return cat;
        }
      }
    }

    // 4. Fallback search against core categories
    for (final cat in coreCategories) {
      if (cat.id.toLowerCase() == query || cat.name.toLowerCase() == query) {
        return cat;
      }
      for (final kw in cat.keywords) {
        if (query.contains(kw.toLowerCase())) {
          return cat;
        }
      }
      for (final sub in cat.subCategories) {
        if (query.contains(sub.toLowerCase())) {
          return cat;
        }
      }
    }

    return null;
  }

  /// Resolves standard channel key ('wechat', 'alipay', 'bank', 'cash', 'credit', 'other')
  /// from raw channel strings or Chinese names.
  static String resolveChannelKey(String? channelOrType) {
    if (channelOrType == null || channelOrType.trim().isEmpty) return 'other';
    final lower = channelOrType.trim().toLowerCase();

    for (final channel in channels) {
      if (channel.key == lower) return channel.key;
      for (final alias in channel.aliases) {
        if (alias.toLowerCase() == lower || lower.contains(alias.toLowerCase())) {
          return channel.key;
        }
      }
    }

    return 'other';
  }

  /// 规范化账单订单号 (忽略首尾空白及常见无单号占位符)
  static String normalizeOrderId(String? rawOrderId) {
    if (rawOrderId == null) return '';
    final clean = rawOrderId.trim();
    if (clean.isEmpty) return '';
    if (clean == '无' ||
        clean == '--' ||
        clean == '-' ||
        clean == 'null' ||
        clean == 'undefined' ||
        clean.toLowerCase() == 'none') {
      return '';
    }
    return clean;
  }

  /// 纯函数：判断单个订单号是否与已有订单号集合存在重复
  static bool isOrderIdDuplicate(
    String? orderId,
    Iterable<String?>? existingOrderIds,
  ) {
    final clean = normalizeOrderId(orderId);
    if (clean.isEmpty || existingOrderIds == null) return false;

    for (final existing in existingOrderIds) {
      if (normalizeOrderId(existing) == clean) {
        return true;
      }
    }
    return false;
  }

  /// 批量草稿去重分流器 (支持与已有账单比对 + 批次内自去重)
  static ({List<T> valid, List<T> duplicates}) partitionDraftsByDedup<T>({
    required Iterable<T> drafts,
    required String? Function(T item) orderIdExtractor,
    Iterable<String?>? existingOrderIds,
  }) {
    final committedSet = <String>{};
    if (existingOrderIds != null) {
      for (final id in existingOrderIds) {
        final c = normalizeOrderId(id);
        if (c.isNotEmpty) committedSet.add(c);
      }
    }

    final seenBatch = <String>{};
    final validList = <T>[];
    final dupList = <T>[];

    for (final draft in drafts) {
      final rawOrd = orderIdExtractor(draft);
      final ord = normalizeOrderId(rawOrd);

      // 无单号草稿不拦截，允许正常入账
      if (ord.isEmpty) {
        validList.add(draft);
        continue;
      }

      // 与已有流水重复
      if (committedSet.contains(ord)) {
        dupList.add(draft);
        continue;
      }

      // 同批次内自去重拦截
      if (seenBatch.contains(ord)) {
        dupList.add(draft);
        continue;
      }

      seenBatch.add(ord);
      validList.add(draft);
    }

    return (valid: validList, duplicates: dupList);
  }

  /// 分类占比图表调色板 (适配深色/深紫背景的高辨识度配色)
  static const List<String> categoryChartPalette = [
    '#fbbf24', '#34d399', '#38bdf8', '#f472b6', '#a78bfa',
    '#fb923c', '#2dd4bf', '#e879f9', '#facc15', '#60a5fa',
  ];

  /// 将数值格式化为最多保留 2 位小数且自动去除末尾多余 0 的紧凑字符串
  static String formatCompactAmount(num amount) {
    final fixed = amount.toStringAsFixed(2);
    if (fixed.contains('.')) {
      final trimmed = fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return trimmed.isEmpty ? '0' : trimmed;
    }
    return fixed;
  }

  /// 支出分类占比聚合与最大余额法百分比统计纯函数
  static CategoryBreakdownResult computeCategoryBreakdown(
    Map<String, double> categoryExpenses, {
    List<String>? activeCategories,
  }) {
    final activeSet = (activeCategories != null && activeCategories.isNotEmpty)
        ? activeCategories.toSet()
        : activeCategoryNames.toSet();

    final filtered = <String, double>{};
    for (final entry in categoryExpenses.entries) {
      final cat = entry.key.trim();
      final amt = entry.value;
      if (amt <= 0 || !activeSet.contains(cat) || cat == '工资收入') continue;
      filtered[cat] = (filtered[cat] ?? 0.0) + amt;
    }

    final total = filtered.values.fold<double>(0.0, (sum, val) => sum + val);
    if (total <= 0) {
      return const CategoryBreakdownResult(
        totalExpense: 0.0,
        totalExpenseText: '0',
        items: [],
      );
    }

    // 按金额降序排列
    final sortedEntries = filtered.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 最大余额法计算整数百分比
    final rawList = <_RawBreakdown>[];
    for (var i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final ratio = entry.value / total;
      final exact = ratio * 100;
      final floorVal = exact.floor();
      final remainder = exact - floorVal;
      rawList.add(_RawBreakdown(
        category: entry.key,
        amount: entry.value,
        ratio: ratio,
        floorPercent: floorVal,
        remainder: remainder,
        origIndex: i,
      ));
    }

    final sumFloor = rawList.fold<int>(0, (sum, it) => sum + it.floorPercent);
    final diff = 100 - sumFloor;

    final byRemainder = List<_RawBreakdown>.from(rawList)
      ..sort((a, b) => b.remainder.compareTo(a.remainder));

    for (var i = 0; i < diff && i < byRemainder.length; i++) {
      byRemainder[i].floorPercent += 1;
    }

    rawList.sort((a, b) => a.origIndex.compareTo(b.origIndex));

    final items = <CategoryBreakdownItem>[];
    for (var i = 0; i < rawList.length; i++) {
      final it = rawList[i];
      final amtText = formatCompactAmount(it.amount);
      final color = categoryChartPalette[i % categoryChartPalette.length];
      items.add(CategoryBreakdownItem(
        category: it.category,
        amount: double.parse(it.amount.toStringAsFixed(2)),
        amountText: amtText,
        percentage: it.floorPercent,
        ratio: it.ratio,
        color: color,
        label: '${it.category}(${it.floorPercent}%):$amtText',
      ));
    }

    return CategoryBreakdownResult(
      totalExpense: double.parse(total.toStringAsFixed(2)),
      totalExpenseText: formatCompactAmount(total),
      items: items,
    );
  }
}
