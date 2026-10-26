// lib/presentation/screens/rules_accounts/widgets/accounts_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:singwallet/core/utils/currency_utils.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/providers/rule_account_providers.dart';

/// Tab displaying financial asset accounts, total assets sum, real-time balances,
/// channel type icons (WeChat, Alipay, Bank Card, Cash), and account creation dialog.
class AccountsTab extends ConsumerStatefulWidget {
  const AccountsTab({super.key});

  @override
  ConsumerState<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends ConsumerState<AccountsTab> {
  IconData _getChannelIcon(String kind, String name) {
    final lowerKind = kind.toLowerCase();
    final lowerName = name.toLowerCase();

    if (lowerKind.contains('wechat') || lowerName.contains('微信')) {
      return Icons.chat_bubble_outline;
    } else if (lowerKind.contains('alipay') || lowerName.contains('支付宝')) {
      return Icons.account_balance_wallet_outlined;
    } else if (lowerKind.contains('card') ||
        lowerKind.contains('bank') ||
        lowerName.contains('银行') ||
        lowerName.contains('卡')) {
      return Icons.credit_card_outlined;
    } else if (lowerKind.contains('cash') || lowerName.contains('现金')) {
      return Icons.payments_outlined;
    }
    return Icons.account_balance_outlined;
  }

  Color _getChannelColor(String kind, String name, ThemeData theme) {
    final lowerKind = kind.toLowerCase();
    final lowerName = name.toLowerCase();

    if (lowerKind.contains('wechat') || lowerName.contains('微信')) {
      return Colors.green.shade600;
    } else if (lowerKind.contains('alipay') || lowerName.contains('支付宝')) {
      return Colors.blue.shade600;
    } else if (lowerKind.contains('card') ||
        lowerKind.contains('bank') ||
        lowerName.contains('银行') ||
        lowerName.contains('卡')) {
      return Colors.indigo.shade500;
    } else if (lowerKind.contains('cash') || lowerName.contains('现金')) {
      return Colors.amber.shade700;
    }
    return theme.colorScheme.primary;
  }

  String _getChannelLabel(String kind) {
    switch (kind) {
      case 'wechat':
        return '微信支付';
      case 'alipay':
        return '支付宝';
      case 'debit_card':
        return '借记卡';
      case 'credit_card':
        return '信用卡';
      case 'cash':
        return '现金';
      case 'e_wallet':
        return '电子钱包';
      default:
        return '金融账户';
    }
  }

  void _showAddAccountDialog() {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0.00');
    final cardLast4Controller = TextEditingController();
    String selectedKind = 'wechat';
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.account_balance_wallet),
                  SizedBox(width: 8),
                  Text('添加资产账户'),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: '账户名称 *',
                          hintText: '如：微信零钱、招商储蓄卡',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return '请输入账户名称';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedKind,
                        borderRadius: BorderRadius.circular(16),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        decoration: const InputDecoration(
                          labelText: '渠道类型 *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'wechat', child: Text('微信支付 (WeChat)')),
                          DropdownMenuItem(value: 'alipay', child: Text('支付宝 (Alipay)')),
                          DropdownMenuItem(value: 'debit_card', child: Text('银行借记卡 (Debit Card)')),
                          DropdownMenuItem(value: 'credit_card', child: Text('银行信用卡 (Credit Card)')),
                          DropdownMenuItem(value: 'cash', child: Text('现金账户 (Cash)')),
                          DropdownMenuItem(value: 'other', child: Text('其他账户 (Other)')),
                        ],
                        onChanged: (String? val) {
                          if (val != null) {
                            setDialogState(() => selectedKind = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: balanceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '初始余额 (元)',
                          prefixText: '¥ ',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return '请输入初始金额';
                          }
                          final parsed = CurrencyUtils.tryParseToMinorUnits(
                            val,
                            allowNegative: true,
                          );
                          if (parsed == null) {
                            return '请输入有效的金额数值';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: cardLast4Controller,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '卡号后四位 (选填)',
                          hintText: '如：8888',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final navigator = Navigator.of(dialogCtx);
                      final messenger = ScaffoldMessenger.of(context);
                      final db = ref.read(databaseProvider);
                      final nowIso = DateTime.now().toUtc().toIso8601String();
                      final todayStr = nowIso.split('T').first;
                      final accountId = 'acc_${DateTime.now().millisecondsSinceEpoch}';
                      final initialCents = CurrencyUtils.tryParseToMinorUnits(
                            balanceController.text.trim(),
                            allowNegative: true,
                          ) ??
                          0;

                      final cardLast4 = cardLast4Controller.text.trim().isNotEmpty
                          ? cardLast4Controller.text.trim()
                          : null;

                      // 1. Insert into accounts table
                      await db.insert('accounts', {
                        'id': accountId,
                        'name': nameController.text.trim(),
                        'kind': selectedKind,
                        'card_last4': cardLast4,
                        'created_at': nowIso,
                        'updated_at': nowIso,
                      });

                      // 2. If initial balance is non-zero, insert an initial income transaction
                      if (initialCents > 0) {
                        final txId = 'tx_init_${accountId}_${DateTime.now().millisecondsSinceEpoch}';
                        await db.insert('transactions', {
                          'id': txId,
                          'type': 'income',
                          'amount_minor': initialCents,
                          'currency': 'CNY',
                          'merchant_raw': '初始余额',
                          'merchant_normalized': '初始余额',
                          'occurred_on': todayStr,
                          'occurred_at': nowIso,
                          'event_timezone': 'Asia/Shanghai',
                          'event_time_source': 'user_selected',
                          'event_time_precision': 'second',
                          'payment_channel': selectedKind == 'wechat'
                              ? 'wechat'
                              : (selectedKind == 'alipay' ? 'alipay' : 'other'),
                          'account_id': accountId,
                          'category_id': 'cat_income',
                          'note': '账户初始化余额',
                          'created_at': nowIso,
                          'updated_at': nowIso,
                        });
                      }

                      // 3. Refresh providers
                      await ref.read(accountsListProvider.notifier).refresh();
                      ref.invalidate(accountBalancesProvider);

                      if (!mounted) return;
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text('账户 "${nameController.text.trim()}" 创建成功')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountsAsync = ref.watch(accountsListProvider);
    final balancesAsync = ref.watch(accountBalancesProvider);

    return Scaffold(
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('加载账户失败: $err'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.read(accountsListProvider.notifier).refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (List<Account> accounts) {
          final balances = balancesAsync.value ?? <String, int>{};

          // Calculate Total Assets sum across all accounts
          var totalAssetsMinor = 0;
          for (final acc in accounts) {
            totalAssetsMinor += balances[acc.id] ?? 0;
          }

          return CustomScrollView(
            slivers: [
              // Top Total Assets Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_balance,
                                    color: theme.colorScheme.onPrimaryContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '总资产 (Total Assets)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onPrimaryContainer.withAlpha(200),
                                    ),
                                  ),
                                ],
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('添加账户'),
                                onPressed: _showAddAccountDialog,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '¥ ${CurrencyUtils.centsToYuanString(totalAssetsMinor)}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '已纳管 ${accounts.length} 个资产账户 • 实时复式记账结余',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onPrimaryContainer.withAlpha(180),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Account Tiles Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Text(
                    '资产账户列表',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

              // Account Tiles
              if (accounts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        const Text('暂无资产账户'),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add),
                          label: const Text('添加第一个账户'),
                          onPressed: _showAddAccountDialog,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final account = accounts[index];
                        final balanceMinor = balances[account.id] ?? 0;
                        final channelIcon = _getChannelIcon(account.kind, account.name);
                        final channelColor = _getChannelColor(account.kind, account.name, theme);
                        final channelLabel = _getChannelLabel(account.kind);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant.withAlpha(128),
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: channelColor.withAlpha(30),
                              foregroundColor: channelColor,
                              child: Icon(channelIcon, size: 22),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  account.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                if (account.cardLast4 != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '尾号 ${account.cardLast4}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              channelLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '¥ ${CurrencyUtils.centsToYuanString(balanceMinor)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: balanceMinor < 0
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  '当前结余',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: accounts.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
