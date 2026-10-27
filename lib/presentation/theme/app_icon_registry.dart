// lib/presentation/theme/app_icon_registry.dart
import 'package:flutter/material.dart';
import '../../core/constants/domain_metadata.dart';

/// Central icon, emoji, and color registry for categories and payment channels across SingWallet.
class AppIconRegistry {
  AppIconRegistry._();

  /// Resolves category [IconData] strictly by iconKey.
  ///
  /// Aligns with [TransactionTile.getIconData] return values:
  /// - 'food' / 'restaurant' -> [Icons.restaurant]
  /// - 'transport' / 'directions_car' -> [Icons.directions_car]
  /// - 'shopping' / 'shopping_bag' -> [Icons.shopping_bag]
  /// - 'entertainment' / 'sports_esports' -> [Icons.sports_esports]
  /// - 'utilities' / 'receipt_long' / 'bills' -> [Icons.receipt_long]
  /// - 'medical' / 'local_hospital' -> [Icons.local_hospital]
  /// - 'salary' / 'income' / 'account_balance_wallet' -> [Icons.account_balance_wallet]
  /// - 'other' -> [Icons.inventory_2]
  /// - 'more_horiz' -> [Icons.more_horiz]
  /// - 'flight' -> [Icons.flight]
  /// - 'home' -> [Icons.home]
  /// - default -> [Icons.category]
  static IconData resolveCategoryIconByKey(String? iconKey) {
    switch (iconKey?.toLowerCase()) {
      case 'food':
      case 'restaurant':
        return Icons.restaurant;
      case 'transport':
      case 'directions_car':
        return Icons.directions_car;
      case 'shopping':
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'entertainment':
      case 'sports_esports':
        return Icons.sports_esports;
      case 'utilities':
      case 'bills':
      case 'receipt_long':
        return Icons.receipt_long;
      case 'medical':
      case 'local_hospital':
        return Icons.local_hospital;
      case 'salary':
      case 'income':
      case 'account_balance_wallet':
        return Icons.account_balance_wallet;
      case 'other':
        return Icons.inventory_2;
      case 'more_horiz':
        return Icons.more_horiz;
      case 'flight':
        return Icons.flight;
      case 'home':
        return Icons.home;
      case 'label':
      case 'custom':
      case 'tag':
        return Icons.label_outline_rounded;
      case 'category':
        return Icons.category;
      default:
        return Icons.label_outline_rounded;
    }
  }

  /// Resolves category [IconData] aligning with [CategorySuggestionCard.resolveCategoryIcon].
  ///
  /// Prioritizes [iconKey], then falls back to [categoryName] and [DomainMetadata]
  /// keywords matching. Guarantees 100% compatibility with existing widget tests.
  static IconData resolveCategoryIcon({String? iconKey, String? categoryName}) {
    final key = (iconKey ?? '').toLowerCase();
    final name = (categoryName ?? '').toLowerCase();

    // 1. Food / Dining
    if (key.contains('food') ||
        key.contains('restaurant') ||
        name.contains('餐饮') ||
        name.contains('吃') ||
        name.contains('美食')) {
      return Icons.restaurant;
    }

    // 2. Transport
    if (key.contains('transport') ||
        key.contains('car') ||
        key.contains('subway') ||
        name.contains('交通') ||
        name.contains('出行') ||
        name.contains('车')) {
      return Icons.directions_subway;
    }

    // 3. Shopping
    if (key.contains('shop') ||
        name.contains('购物') ||
        name.contains('超市') ||
        name.contains('日用')) {
      return Icons.shopping_bag_outlined;
    }

    // 4. Entertainment
    if (key.contains('entertainment') ||
        key.contains('sport') ||
        key.contains('game') ||
        name.contains('娱乐') ||
        name.contains('玩') ||
        name.contains('影')) {
      return Icons.sports_esports_outlined;
    }

    // 5. Bills / Utilities
    if (key.contains('bill') ||
        key.contains('utilities') ||
        name.contains('生活缴费') ||
        name.contains('账单') ||
        name.contains('水电') ||
        name.contains('费')) {
      return Icons.receipt_long_outlined;
    }

    // 6. Medical
    if (key.contains('medical') ||
        key.contains('hospital') ||
        name.contains('医疗') ||
        name.contains('药') ||
        name.contains('健康')) {
      return Icons.medical_services_outlined;
    }

    // 7. Income / Salary
    if (key.contains('income') ||
        key.contains('salary') ||
        name.contains('收入') ||
        name.contains('工资') ||
        name.contains('红包')) {
      return Icons.savings_outlined;
    }

    // 8. Other / More
    if (key.contains('other') || name.contains('其他')) {
      return Icons.more_horiz;
    }

    // Keyword fallback using DomainMetadata
    final meta = DomainMetadata.findCategoryByNameOrKeyword(categoryName);
    if (meta != null) {
      switch (meta.iconKey) {
        case 'food':
          return Icons.restaurant;
        case 'transport':
          return Icons.directions_subway;
        case 'shopping':
          return Icons.shopping_bag_outlined;
        case 'entertainment':
          return Icons.sports_esports_outlined;
        case 'utilities':
          return Icons.receipt_long_outlined;
        case 'medical':
          return Icons.medical_services_outlined;
        case 'salary':
          return Icons.savings_outlined;
        case 'other':
          return Icons.more_horiz;
        case 'label':
        case 'custom':
        case 'tag':
          return Icons.label_outline_rounded;
        default:
          return resolveCategoryIconByKey(meta.iconKey);
      }
    }

    if (key.contains('label') || key.contains('custom') || key.contains('tag')) {
      return Icons.label_outline_rounded;
    }

    // Default fallback for custom or unmapped categories
    return Icons.label_outline_rounded;
  }

  /// Resolves the unified Emoji for a category via [DomainMetadata].
  ///
  /// Changes in DomainMetadata automatically propagate globally.
  static String resolveCategoryEmoji({String? iconKey, String? categoryName}) {
    if (iconKey != null && iconKey.trim().isNotEmpty) {
      final meta = DomainMetadata.findCategoryByIconKey(iconKey);
      if (meta != null) return meta.emoji;
    }
    if (categoryName != null && categoryName.trim().isNotEmpty) {
      final meta = DomainMetadata.findCategoryByNameOrKeyword(categoryName);
      if (meta != null) return meta.emoji;
    }
    if (iconKey != null && (iconKey.contains('label') || iconKey.contains('custom'))) {
      return '🏷️';
    }
    return '📦';
  }

  /// Resolves payment channel or account kind [IconData].
  static IconData resolveChannelIcon(String? channelOrKind, [String? name]) {
    final lower = '${channelOrKind ?? ''} ${name ?? ''}'.toLowerCase();

    if (lower.contains('wechat') || lower.contains('微信')) {
      return Icons.chat_bubble_outline;
    }
    if (lower.contains('alipay') || lower.contains('支付宝')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (lower.contains('card') ||
        lower.contains('bank') ||
        lower.contains('debit') ||
        lower.contains('credit') ||
        lower.contains('银行') ||
        lower.contains('卡')) {
      return Icons.credit_card_outlined;
    }
    if (lower.contains('cash') || lower.contains('现金')) {
      return Icons.payments_outlined;
    }

    return Icons.account_balance_outlined;
  }

  /// Resolves payment channel or account kind [Color].
  static Color resolveChannelColor(String? channelOrKind, [ThemeData? theme, String? name]) {
    final lower = '${channelOrKind ?? ''} ${name ?? ''}'.toLowerCase();

    if (lower.contains('wechat') || lower.contains('微信')) {
      return const Color(0xFF07C160);
    }
    if (lower.contains('alipay') || lower.contains('支付宝')) {
      return const Color(0xFF1677FF);
    }
    if (lower.contains('card') ||
        lower.contains('bank') ||
        lower.contains('debit') ||
        lower.contains('credit') ||
        lower.contains('银行') ||
        lower.contains('卡')) {
      return const Color(0xFFFF9800);
    }
    if (lower.contains('cash') || lower.contains('现金')) {
      return const Color(0xFF4CAF50);
    }

    return theme?.colorScheme.primary ?? const Color(0xFF6750A4);
  }

  /// Resolves human-readable account kind label (e.g. '借记卡', '电子钱包').
  static String resolveAccountTypeLabel(String kindOrChannel) {
    switch (kindOrChannel.toLowerCase()) {
      case 'wechat':
        return '微信支付';
      case 'alipay':
        return '支付宝';
      case 'debit_card':
        return '借记卡';
      case 'credit_card':
        return '信用卡';
      case 'bank':
      case 'bank_card':
        return '银行卡';
      case 'cash':
        return '现金';
      case 'e_wallet':
        return '电子钱包';
      default:
        return '金融账户';
    }
  }

  /// Resolves payment channel display label (e.g. for drafts queue).
  static String resolveChannelLabel(String channel) {
    switch (channel.toLowerCase()) {
      case 'wechat':
        return '微信支付';
      case 'alipay':
        return '支付宝';
      case 'bank_card':
      case 'bank':
        return '银行卡';
      case 'cash':
        return '现金';
      default:
        return '其他渠道';
    }
  }

  /// Resolves short channel capsule display name (e.g. '微信', '支付宝', '银行卡', '现金').
  static String resolveChannelDisplayName(String channel) {
    switch (channel.toLowerCase()) {
      case 'wechat':
        return '微信';
      case 'alipay':
        return '支付宝';
      case 'bank':
      case 'unionpay':
      case 'bank_card':
        return '银行卡';
      case 'cash':
        return '现金';
      case 'other':
      default:
        return '其他';
    }
  }
}
