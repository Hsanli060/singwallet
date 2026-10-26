// lib/presentation/screens/transactions/transactions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../providers/rule_account_providers.dart';
import '../../providers/transaction_providers.dart';
import 'widgets/monthly_summary_card.dart';
import 'widgets/transaction_filter_sheet.dart';
import 'widgets/transaction_group_list.dart';
import 'widgets/trash_bin_dialog.dart';

/// Transactions Screen and Real-time Financial Dashboard.
///
/// Integrates:
/// - Top AppBar with Filter and Recycling Bin actions
/// - [MonthlySummaryCard] with month picker and financial metrics
/// - Dynamic active filter chips bar with quick dismissal
/// - [TransactionGroupList] with daily net subtotals and rich tiles
/// - Pull-to-refresh integration
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(transactionFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('交易流水'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '回收站',
            onPressed: () => TrashBinDialog.show(context),
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: filter.hasActiveFilters,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: '筛选',
            onPressed: () => TransactionFilterSheet.show(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(transactionListProvider.notifier).refresh(),
            ref.refresh(monthlySummaryProvider.future),
          ]);
        },
        child: Column(
          children: [
            const MonthlySummaryCard(),
            if (filter.hasActiveFilters) _ActiveFilterChipsBar(filter: filter),
            const Expanded(
              child: TransactionGroupList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrollable bar showing currently active filters with quick-dismiss actions.
class _ActiveFilterChipsBar extends ConsumerWidget {
  final TransactionFilter filter;

  const _ActiveFilterChipsBar({required this.filter});

  String _getTypeLabel(String type) {
    switch (type) {
      case 'expense':
        return '支出';
      case 'income':
        return '收入';
      case 'refund':
        return '退款';
      case 'transfer':
        return '转账';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final categories = ref.watch(categoriesListProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsListProvider).valueOrNull ?? const [];
    final projects = ref.watch(projectsListProvider).valueOrNull ?? const [];

    final categoryName =
        categories.where((c) => c.id == filter.categoryId).firstOrNull?.name;
    final accountName =
        accounts.where((a) => a.id == filter.accountId).firstOrNull?.name;
    final projectName =
        projects.where((p) => p.id == filter.projectId).firstOrNull?.name;

    final chips = <Widget>[];

    // Reset all action chip
    chips.add(
      ActionChip(
        avatar: const Icon(Icons.clear_all, size: 16),
        label: const Text('重置全部'),
        onPressed: () {
          ref.read(transactionFilterProvider.notifier).reset();
        },
      ),
    );

    // Keyword chip
    if (filter.keyword != null && filter.keyword!.trim().isNotEmpty) {
      chips.add(
        InputChip(
          label: Text('搜: ${filter.keyword}'),
          onDeleted: () {
            ref.read(transactionFilterProvider.notifier).setKeyword(null);
          },
        ),
      );
    }

    // Type chip
    if (filter.type != null) {
      chips.add(
        InputChip(
          label: Text('类型: ${_getTypeLabel(filter.type!)}'),
          onDeleted: () {
            ref.read(transactionFilterProvider.notifier).setType(null);
          },
        ),
      );
    }

    // Date range chip
    if (filter.startDate != null || filter.endDate != null) {
      final dateText = '${filter.startDate ?? ''} ~ ${filter.endDate ?? ''}';
      chips.add(
        InputChip(
          label: Text('日期: $dateText'),
          onDeleted: () {
            ref.read(transactionFilterProvider.notifier).setDateRange(null, null);
          },
        ),
      );
    }

    // Account chip
    if (filter.accountId != null) {
      chips.add(
        InputChip(
          label: Text('账户: ${accountName ?? filter.accountId}'),
          onDeleted: () {
            ref.read(transactionFilterProvider.notifier).setAccount(null);
          },
        ),
      );
    }

    // Category chip
    if (filter.categoryId != null) {
      chips.add(
        InputChip(
          label: Text('分类: ${categoryName ?? filter.categoryId}'),
          onDeleted: () {
            ref.read(transactionFilterProvider.notifier).setCategory(null);
          },
        ),
      );
    }

    // Project chip
    if (filter.projectId != null) {
      chips.add(
        InputChip(
          label: Text('项目: #${projectName ?? filter.projectId}'),
          onDeleted: () {
            ref.read(transactionFilterProvider.notifier).setProject(null);
          },
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips
              .map((c) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: c,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
