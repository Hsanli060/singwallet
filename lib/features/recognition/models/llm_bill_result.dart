// lib/features/recognition/models/llm_bill_result.dart

import 'dart:convert';

/// 严格限定的已有 8 大账单分类枚举
/// 与数据库预设的 defaultCategories 保持 100% 对齐
enum BillCategory {
  food('餐饮美食', 'cat_food'),
  transport('交通出行', 'cat_transport'),
  shopping('日常购物', 'cat_shopping'),
  entertainment('休闲娱乐', 'cat_entertainment'),
  bills('生活缴费', 'cat_bills'),
  medical('医疗健康', 'cat_medical'),
  other('其他支出', 'cat_other'),
  income('工资收入', 'cat_income');

  final String label;
  final String categoryId;

  const BillCategory(this.label, this.categoryId);

  /// 严格解析大模型输出的分类字符串（带强容错标准化）
  static BillCategory fromString(String value) {
    final normalized = value.trim();
    for (final cat in BillCategory.values) {
      if (cat.label == normalized || cat.name == normalized || cat.categoryId == normalized) {
        return cat;
      }
    }
    // 语义模糊容错匹配
    if (normalized.contains('餐') || normalized.contains('食') || normalized.contains('吃') || normalized.contains('饮')) {
      return BillCategory.food;
    }
    if (normalized.contains('交通') || normalized.contains('车') || normalized.contains('行') || normalized.contains('打车') || normalized.contains('地铁')) {
      return BillCategory.transport;
    }
    if (normalized.contains('购') || normalized.contains('买') || normalized.contains('日用') || normalized.contains('超市') || normalized.contains('商户')) {
      return BillCategory.shopping;
    }
    if (normalized.contains('娱') || normalized.contains('玩') || normalized.contains('游') || normalized.contains('影')) {
      return BillCategory.entertainment;
    }
    if (normalized.contains('缴费') || normalized.contains('水电') || normalized.contains('话费') || normalized.contains('燃气') || normalized.contains('房租')) {
      return BillCategory.bills;
    }
    if (normalized.contains('医') || normalized.contains('药') || normalized.contains('健康') || normalized.contains('门诊') || normalized.contains('挂号')) {
      return BillCategory.medical;
    }
    if (normalized.contains('工资') || normalized.contains('薪') || normalized.contains('收入')) {
      return BillCategory.income;
    }
    return BillCategory.other;
  }
}

/// 支付主渠道（微信、支付宝、云闪付）
enum PaymentChannel {
  wechat('微信', 'wechat'),
  alipay('支付宝', 'alipay'),
  unionpay('云闪付', 'unionpay');

  final String label;
  final String key;

  const PaymentChannel(this.label, this.key);

  static PaymentChannel fromString(String val) {
    final s = val.trim();
    if (s.contains('微信') || s.toLowerCase().contains('wechat') || s.contains('wx') || s.contains('财付通')) {
      return PaymentChannel.wechat;
    }
    if (s.contains('支付宝') || s.toLowerCase().contains('alipay') || s.contains('ali')) {
      return PaymentChannel.alipay;
    }
    if (s.contains('云闪付') || s.toLowerCase().contains('unionpay') || s.contains('银联') || s.contains('云闪')) {
      return PaymentChannel.unionpay;
    }
    throw FormatException('非法的支付主渠道: $val，仅支持 [微信, 支付宝, 云闪付]');
  }
}

/// 支付类型类（大模型输出的专属支付结构类）
///
/// 严格对应业务规则：
/// - 微信 -> 钱包、零钱通、银行卡（需显示卡号后四位）
/// - 支付宝 -> 余额、余额宝、银行卡（需显示卡号后四位）
/// - 云闪付 -> 银行卡（需显示卡号后四位）
class PaymentMethod {
  /// 主渠道（微信、支付宝、云闪付）
  final PaymentChannel channel;

  /// 子账户/子类型名称：
  /// - 微信：'钱包' | '零钱通' | '银行卡'
  /// - 支付宝：'余额' | '余额宝' | '银行卡'
  /// - 云闪付：'银行卡'
  final String subType;

  /// 银行名称（如：招商银行、中国工商银行；非银行卡为 null）
  final String? bankName;

  /// 银行卡号后四位（4位纯数字字符串，如 '8848'；非银行卡为 null）
  final String? cardLast4;

  const PaymentMethod({
    required this.channel,
    required this.subType,
    this.bankName,
    this.cardLast4,
  });

  /// 是否为银行卡扣款
  bool get isBankCard => subType == '银行卡';

  /// 格式化后的完整展示名称
  /// 例如：
  /// - 微信 · 钱包
  /// - 微信 · 零钱通
  /// - 微信 · 招商银行(8848)
  /// - 支付宝 · 余额
  /// - 支付宝 · 余额宝
  /// - 支付宝 · 建设银行(1234)
  /// - 云闪付 · 工商银行(5678)
  String get displayName {
    if (isBankCard) {
      final bank = (bankName != null && bankName!.isNotEmpty) ? bankName! : '银行卡';
      final last4 = (cardLast4 != null && cardLast4!.isNotEmpty) ? cardLast4! : '****';
      return '${channel.label} · $bank($last4)';
    }
    return '${channel.label} · $subType';
  }

  /// 严格构造工厂方法（强行校验渠道与子类型的合法组合，及银行卡后四位要求）
  factory PaymentMethod.create({
    required PaymentChannel channel,
    required String subType,
    String? bankName,
    String? cardLast4,
  }) {
    final cleanSubType = subType.trim();

    // 1. 微信子类型强校验
    if (channel == PaymentChannel.wechat) {
      const allowed = ['钱包', '零钱通', '银行卡'];
      // 容错映射：如果大模型输出 '零钱' 自动标准化为 '钱包'
      final normalized = cleanSubType == '零钱' ? '钱包' : cleanSubType;
      if (!allowed.contains(normalized)) {
        throw FormatException('微信支付子类型非法: $cleanSubType，仅支持 [钱包, 零钱通, 银行卡]');
      }
      if (normalized == '银行卡') {
        _validateCardLast4(cardLast4);
        return PaymentMethod(
          channel: channel,
          subType: '银行卡',
          bankName: bankName?.trim(),
          cardLast4: cardLast4?.trim(),
        );
      }
      return PaymentMethod(channel: channel, subType: normalized);
    }

    // 2. 支付宝子类型强校验
    if (channel == PaymentChannel.alipay) {
      const allowed = ['余额', '余额宝', '银行卡'];
      final normalized = (cleanSubType == '账户余额') ? '余额' : cleanSubType;
      if (!allowed.contains(normalized)) {
        throw FormatException('支付宝支付子类型非法: $cleanSubType，仅支持 [余额, 余额宝, 银行卡]');
      }
      if (normalized == '银行卡') {
        _validateCardLast4(cardLast4);
        return PaymentMethod(
          channel: channel,
          subType: '银行卡',
          bankName: bankName?.trim(),
          cardLast4: cardLast4?.trim(),
        );
      }
      return PaymentMethod(channel: channel, subType: normalized);
    }

    // 3. 云闪付子类型强校验（仅限银行卡）
    if (channel == PaymentChannel.unionpay) {
      if (cleanSubType != '银行卡' && !cleanSubType.contains('卡')) {
        throw FormatException('云闪付支付子类型非法: $cleanSubType，云闪付仅支持 [银行卡]');
      }
      _validateCardLast4(cardLast4);
      return PaymentMethod(
        channel: channel,
        subType: '银行卡',
        bankName: bankName?.trim(),
        cardLast4: cardLast4?.trim(),
      );
    }

    throw FormatException('未支持的支付主渠道: $channel');
  }

  /// 银行卡后四位强格式校验（必须为4位数字）
  static void _validateCardLast4(String? cardLast4) {
    if (cardLast4 == null || cardLast4.trim().isEmpty) {
      throw const FormatException('银行卡扣款必须提供卡号后四位 (card_last_4)');
    }
    final digits = cardLast4.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(digits)) {
      throw FormatException('卡号后四位格式不正确: "$cardLast4"，必须严格为 4 位纯数字 (如 8848)');
    }
  }

  /// 从大模型返回的 JSON 解析
  factory PaymentMethod.fromJson(dynamic json) {
    if (json is String) {
      // 兼容大模型有时以单字符串返回的情况，例如 "微信支付-招商银行(8848)" 或 "支付宝余额"
      return _parseFromString(json);
    }

    if (json is! Map<String, dynamic>) {
      throw FormatException('payment 字段必须为对象或规范字符串: $json');
    }

    final rawChannel = (json['channel'] ?? json['payment_channel'] ?? json['渠道'] ?? '微信').toString();
    final channel = PaymentChannel.fromString(rawChannel);

    final rawSubType = (json['sub_type'] ?? json['subType'] ?? json['type'] ?? json['子类型'] ?? '钱包').toString();
    final bankName = json['bank_name'] ?? json['bankName'] ?? json['银行名称'];
    final cardLast4 = json['card_last_4'] ?? json['cardLast4'] ?? json['卡号后四位'];

    return PaymentMethod.create(
      channel: channel,
      subType: rawSubType,
      bankName: bankName?.toString(),
      cardLast4: cardLast4?.toString(),
    );
  }

  /// 字符串容错解析（处理文本格式）
  static PaymentMethod _parseFromString(String text) {
    final channel = PaymentChannel.fromString(text);
    final cardMatch = RegExp(r'(\d{4})').firstMatch(text);
    final isCard = text.contains('卡') || cardMatch != null;

    if (channel == PaymentChannel.wechat) {
      if (text.contains('零钱通')) {
        return PaymentMethod.create(channel: channel, subType: '零钱通');
      }
      if (isCard && cardMatch != null) {
        return PaymentMethod.create(
          channel: channel,
          subType: '银行卡',
          cardLast4: cardMatch.group(1),
        );
      }
      return PaymentMethod.create(channel: channel, subType: '钱包');
    }

    if (channel == PaymentChannel.alipay) {
      if (text.contains('余额宝')) {
        return PaymentMethod.create(channel: channel, subType: '余额宝');
      }
      if (isCard && cardMatch != null) {
        return PaymentMethod.create(
          channel: channel,
          subType: '银行卡',
          cardLast4: cardMatch.group(1),
        );
      }
      return PaymentMethod.create(channel: channel, subType: '余额');
    }

    // 云闪付
    final last4 = cardMatch != null ? cardMatch.group(1)! : '0000';
    return PaymentMethod.create(
      channel: channel,
      subType: '银行卡',
      cardLast4: last4,
    );
  }

  /// 序列化方法
  Map<String, dynamic> toJson() => {
    'channel': channel.label,
    'channel_key': channel.key,
    'sub_type': subType,
    if (bankName != null && bankName!.isNotEmpty) 'bank_name': bankName,
    if (cardLast4 != null && cardLast4!.isNotEmpty) 'card_last_4': cardLast4,
    'display_name': displayName,
  };

  @override
  String toString() => displayName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaymentMethod &&
        other.channel == channel &&
        other.subType == subType &&
        other.bankName == bankName &&
        other.cardLast4 == cardLast4;
  }

  @override
  int get hashCode => Object.hash(channel, subType, bankName, cardLast4);
}

/// 大模型结构化输出的强类型账单数据类
///
/// 严格对应大模型视觉识别（VLM）输出的确定性结构：
/// 1. 金额（实付）
/// 2. 商家名称
/// 3. 订单时间
/// 4. 订单号
/// 5. 账单类型（严格从已有 8 大类中选）
/// 6. 支付类型（独立类 PaymentMethod：微信、支付宝、云闪付 及相应子类型/卡号后四位）
class LlmBillResult {
  /// 实付金额（元，浮点数，保留两位小数）
  final double amount;

  /// 实付金额（整数分，整数存储，避免浮点精度漂移）
  final int amountInCents;

  /// 商家名称 / 收款方
  final String merchant;

  /// 订单时间
  final DateTime orderTime;

  /// 平台交易单号 / 订单编号
  final String orderId;

  /// 账单类型（严格限定自已有 8 大类）
  final BillCategory category;

  /// 支付类型类（严格限定自 微信/支付宝/云闪付 及相应子字段）
  final PaymentMethod payment;

  const LlmBillResult({
    required this.amount,
    required this.amountInCents,
    required this.merchant,
    required this.orderTime,
    required this.orderId,
    required this.category,
    required this.payment,
  });

  /// 显式构造方法（自动根据元计算整数分）
  factory LlmBillResult.create({
    required double amount,
    required String merchant,
    required DateTime orderTime,
    required String orderId,
    required BillCategory category,
    required PaymentMethod payment,
  }) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', '实付金额必须大于 0');
    }
    if (merchant.trim().isEmpty) {
      throw ArgumentError.value(merchant, 'merchant', '商家名称不能为空');
    }
    if (orderId.trim().isEmpty) {
      throw ArgumentError.value(orderId, 'orderId', '订单号不能为空');
    }

    final cents = (amount * 100).round();
    return LlmBillResult(
      amount: double.parse(amount.toStringAsFixed(2)),
      amountInCents: cents,
      merchant: merchant.trim(),
      orderTime: orderTime,
      orderId: orderId.trim(),
      category: category,
      payment: payment,
    );
  }

  /// 从大模型返回的 JSON Map 中解析并进行严格校验
  factory LlmBillResult.fromJson(Map<String, dynamic> json) {
    // 1. 金额强校验
    final dynamic rawAmount = json['amount'] ?? json['actual_amount'] ?? json['实付金额'] ?? json['金额'];
    double parsedAmount;
    if (rawAmount is num) {
      parsedAmount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      final sanitized = rawAmount.replaceAll(RegExp(r'[¥￥\s,]'), '');
      final parsed = double.tryParse(sanitized);
      if (parsed == null || parsed <= 0) {
        throw FormatException('无法解析有效实付金额: $rawAmount');
      }
      parsedAmount = parsed;
    } else {
      throw FormatException('缺失或非法的实付金额字段: $rawAmount');
    }

    // 2. 商家名称
    final String merchant = (json['merchant'] ?? json['merchant_name'] ?? json['商家名称'] ?? '').toString().trim();
    if (merchant.isEmpty) {
      throw const FormatException('大模型返回的商家名称不能为空');
    }

    // 3. 订单时间
    final dynamic rawTime = json['order_time'] ?? json['orderTime'] ?? json['订单时间'] ?? json['time'];
    DateTime parsedTime;
    if (rawTime is String) {
      final sanitized = rawTime.trim().replaceAll('/', '-');
      final dt = DateTime.tryParse(sanitized);
      if (dt == null) {
        throw FormatException('无法解析订单时间: $rawTime');
      }
      parsedTime = dt;
    } else if (rawTime is DateTime) {
      parsedTime = rawTime;
    } else {
      throw FormatException('缺失或非法的订单时间字段: $rawTime');
    }

    // 4. 订单号
    final String orderId = (json['order_id'] ?? json['orderId'] ?? json['订单号'] ?? '').toString().trim();
    if (orderId.isEmpty) {
      throw const FormatException('大模型返回的订单号不能为空');
    }

    // 5. 账单类型（严格限定已有 8 大类）
    final String rawCategory = (json['category'] ?? json['category_name'] ?? json['账单类型'] ?? '其他支出').toString();
    final BillCategory category = BillCategory.fromString(rawCategory);

    // 6. 支付类型类（严格限定 微信/支付宝/云闪付 及其子字段）
    final dynamic rawPayment = json['payment'] ?? json['payment_method'] ?? json['payment_info'] ?? json['支付类型'] ?? json['payment_channel'];
    final PaymentMethod payment = PaymentMethod.fromJson(rawPayment);

    return LlmBillResult.create(
      amount: parsedAmount,
      merchant: merchant,
      orderTime: parsedTime,
      orderId: orderId,
      category: category,
      payment: payment,
    );
  }

  /// 从 JSON 字符串快捷反序列化
  factory LlmBillResult.fromJsonString(String jsonStr) {
    String cleanStr = jsonStr.trim();
    if (cleanStr.startsWith('```')) {
      final startIndex = cleanStr.indexOf('{');
      final endIndex = cleanStr.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        cleanStr = cleanStr.substring(startIndex, endIndex + 1);
      }
    }
    final dynamic decoded = jsonDecode(cleanStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('大模型输出必须为标准的 JSON Object');
    }
    return LlmBillResult.fromJson(decoded);
  }

  /// 序列化为规范 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'amount': double.parse(amount.toStringAsFixed(2)),
      'amount_in_cents': amountInCents,
      'merchant': merchant,
      'order_time': _formatDateTime(orderTime),
      'order_id': orderId,
      'category': category.label,
      'category_id': category.categoryId,
      'payment': payment.toJson(),
    };
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  /// 供大模型 API 使用的标准 JSON Schema
  /// 可直接用于 Gemini API（responseSchema）、OpenAI（response_format: json_schema）等
  static Map<String, dynamic> get jsonSchema => {
    'type': 'object',
    'properties': {
      'amount': {
        'type': 'number',
        'description': '实付金额（单位：元，必须为用户实际扣款的净额，扣除优惠满减后的最终金额）',
      },
      'merchant': {
        'type': 'string',
        'description': '商家名称/收款方/交易商户全称或规范简称',
      },
      'order_time': {
        'type': 'string',
        'description': '订单交易时间，格式严格为 YYYY-MM-DD HH:mm:ss',
      },
      'order_id': {
        'type': 'string',
        'description': '交易单号/订单号/支付流水号',
      },
      'category': {
        'type': 'string',
        'enum': [
          '餐饮美食',
          '交通出行',
          '日常购物',
          '休闲娱乐',
          '生活缴费',
          '医疗健康',
          '其他支出',
          '工资收入',
        ],
        'description': '账单类型，必须严格从这8大类中根据商户语义选择一个最精准的分类',
      },
      'payment': {
        'type': 'object',
        'description': '支付类型（独立类）：包含主渠道、子账户类型及银行卡后四位',
        'properties': {
          'channel': {
            'type': 'string',
            'enum': ['微信', '支付宝', '云闪付'],
            'description': '主支付渠道',
          },
          'sub_type': {
            'type': 'string',
            'enum': ['钱包', '零钱通', '余额', '余额宝', '银行卡'],
            'description': '子账户扣款方式：微信支持[钱包, 零钱通, 银行卡]；支付宝支持[余额, 余额宝, 银行卡]；云闪付支持[银行卡]',
          },
          'bank_name': {
            'type': 'string',
            'description': '银行名称（如招商银行、中国银行，仅当 sub_type 为银行卡时必填，非银行卡则为空字符串）',
          },
          'card_last_4': {
            'type': 'string',
            'description': '银行卡号后四位（4位纯数字，如 8848，仅当 sub_type 为银行卡时必填，非银行卡则为空字符串）',
          },
        },
        'required': ['channel', 'sub_type'],
        'additionalProperties': false,
      },
    },
    'required': [
      'amount',
      'merchant',
      'order_time',
      'order_id',
      'category',
      'payment',
    ],
    'additionalProperties': false,
  };

  @override
  String toString() {
    return 'LlmBillResult(amount: ¥${amount.toStringAsFixed(2)}, merchant: $merchant, orderId: $orderId, time: ${_formatDateTime(orderTime)}, category: ${category.label}, payment: $payment)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LlmBillResult &&
        other.amountInCents == amountInCents &&
        other.merchant == merchant &&
        other.orderId == orderId &&
        other.orderTime == orderTime &&
        other.category == category &&
        other.payment == payment;
  }

  @override
  int get hashCode {
    return Object.hash(amountInCents, merchant, orderId, orderTime, category, payment);
  }
}
