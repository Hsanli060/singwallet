// lib/presentation/screens/transactions/widgets/transaction_group_list.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/ledger_repository.dart';
import '../../../providers/rule_account_providers.dart';
import '../../../providers/transaction_providers.dart';
import 'transaction_tile.dart';

/// Grouped transaction list sorted chronologically by occurred date.
///
/// Displays daily headers with net subtotals and renders rich [TransactionTile]s.
class TransactionGroupList extends ConsumerStatefulWidget {
  final void Function(TransactionEntry)? onTransactionTap;

  const TransactionGroupList({
    super.key,
    this.onTransactionTap,
  });

  static String formatDateLabel(String dateStr) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    if (dateStr == todayStr) {
      return '$dateStr 今天';
    } else if (dateStr == yesterdayStr) {
      return '$dateStr 昨天';
    }

    // Try parsing weekday
    try {
      final parsed = DateTime.parse(dateStr);
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final weekdayStr = weekdays[parsed.weekday - 1];
      return '$dateStr $weekdayStr';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  ConsumerState<TransactionGroupList> createState() => _TransactionGroupListState();
}

class _TransactionGroupListState extends ConsumerState<TransactionGroupList> {
  final Set<String> _dismissedIds = <String>{};

  void _handleSoftDelete(TransactionEntry tx) {
    setState(() {
      _dismissedIds.add(tx.id);
    });

    ref.read(transactionListProvider.notifier).softDelete(tx.id);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('已移入回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            setState(() {
              _dismissedIds.remove(tx.id);
            });
            ref.read(transactionListProvider.notifier).restore(tx.id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(transactionListProvider);
    // Pre-warm category, account, and project lookups concurrently
    ref.watch(categoriesListProvider);
    ref.watch(accountsListProvider);
    ref.watch(projectsListProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return groupsAsync.when(
      data: (List<TransactionGroup> groups) {
        // Filter out locally dismissed transactions to satisfy Dismissible contracts immediately
        final filteredGroups = <TransactionGroup>[];
        for (final group in groups) {
          final visibleTxs =
              group.transactions.where((t) => !_dismissedIds.contains(t.id)).toList();
          if (visibleTxs.isNotEmpty) {
            filteredGroups.add(TransactionGroup(
              date: group.date,
              transactions: visibleTxs,
              totalExpenseMinor: group.totalExpenseMinor,
              totalIncomeMinor: group.totalIncomeMinor,
              totalRefundMinor: group.totalRefundMinor,
              netSubtotalMinor: group.netSubtotalMinor,
            ));
          }
        }

        if (filteredGroups.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无流水记录',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '草稿箱确认或手动录入的账单将在此处展示',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: filteredGroups.length,
          itemBuilder: (context, groupIndex) {
            final group = filteredGroups[groupIndex];
            final dateLabel = TransactionGroupList.formatDateLabel(group.date);

            // Daily subtotal breakdown
            final subtotalParts = <String>[];
            if (group.totalExpenseMinor > 0) {
              subtotalParts.add(
                '支出 ¥${CurrencyUtils.centsToYuanString(group.totalExpenseMinor)}',
              );
            }
            if (group.totalRefundMinor > 0) {
              subtotalParts.add(
                '退款 ¥${CurrencyUtils.centsToYuanString(group.totalRefundMinor)}',
              );
            }
            if (group.totalIncomeMinor > 0) {
              subtotalParts.add(
                '收入 ¥${CurrencyUtils.centsToYuanString(group.totalIncomeMinor)}',
              );
            }

            final subtotalText = subtotalParts.isNotEmpty
                ? subtotalParts.join('  ')
                : '净计 ¥${CurrencyUtils.centsToYuanString(group.netSubtotalMinor)}';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Group Date Header
                () {
                  final currentFilter = ref.watch(transactionFilterProvider);
                  final isDayFocused =
                      currentFilter.startDate == group.date && currentFilter.endDate == group.date;

                  return Material(
                    color: isDayFocused
                        ? colorScheme.primaryContainer.withAlpha(120)
                        : colorScheme.surfaceContainerHighest.withAlpha(90),
                    child: InkWell(
                      onTap: () {
                        if (isDayFocused) {
                          ref
                              .read(transactionFilterProvider.notifier)
                              .setDateRange(null, null);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已取消日聚焦，恢复全月流水'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        } else {
                          ref
                              .read(transactionFilterProvider.notifier)
                              .setDateRange(group.date, group.date);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已聚焦筛选日消费：$dateLabel'),
                              duration: const Duration(seconds: 2),
                              action: SnackBarAction(
                                label: '取消',
                                onPressed: () {
                                  ref
                                      .read(transactionFilterProvider.notifier)
                                      .setDateRange(null, null);
                                },
                              ),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  dateLabel,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isDayFocused
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDayFocused
                                        ? colorScheme.primary
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isDayFocused
                                          ? colorScheme.primary
                                          : colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isDayFocused
                                            ? Icons.check_circle_outline
                                            : Icons.filter_alt_outlined,
                                        size: 12,
                                        color: isDayFocused
                                            ? colorScheme.onPrimary
                                            : colorScheme.primary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        isDayFocused ? '已聚焦' : '仅看此日',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isDayFocused
                                              ? colorScheme.onPrimary
                                              : colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              subtotalText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isDayFocused
                                    ? colorScheme.primary
                                    : colorScheme.outline,
                                fontWeight: isDayFocused ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
                // Group Transactions
                ...group.transactions.map((tx) {
                  return Column(
                    children: [
                      TransactionTile(
                        transaction: tx,
                        onTap: widget.onTransactionTap != null
                            ? () => widget.onTransactionTap!(tx)
                            : null,
                        onDelete: () => _handleSoftDelete(tx),
                      ),
                      const Divider(height: 1, indent: 68, endIndent: 16),
                    ],
                  );
                }),
              ],
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (Object error, StackTrace? _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(
                '流水数据加载失败',
                style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
                onPressed: () {
                  ref.read(transactionListProvider.notifier).refresh();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
