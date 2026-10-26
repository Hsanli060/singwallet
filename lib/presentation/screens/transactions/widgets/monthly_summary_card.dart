// lib/presentation/screens/transactions/widgets/monthly_summary_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../data/repositories/ledger_repository.dart';
import '../../../providers/transaction_providers.dart';

/// Real-time monthly accounting summary dashboard card.
///
/// Consumes [selectedMonthProvider] for month navigation and
/// [monthlySummaryProvider] for calculated financial aggregations.
class MonthlySummaryCard extends ConsumerWidget {
  const MonthlySummaryCard({super.key});

  static String formatYearMonth(String ym) {
    final parts = ym.split('-');
    if (parts.length == 2) {
      return '${parts[0]}年${parts[1]}月';
    }
    return ym;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final summaryAsync = ref.watch(monthlySummaryProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month navigation header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: '上一月',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref.read(selectedMonthProvider.notifier).previousMonth();
                      },
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showMonthPickerSheet(context, ref, selectedMonth),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatYearMonth(selectedMonth),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: '下一月',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref.read(selectedMonthProvider.notifier).nextMonth();
                      },
                    ),
                  ],
                ),
                summaryAsync.when(
                  data: (MonthlyAccountingSummary summary) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(150),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '共 ${summary.transactionCount} 笔',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Financial aggregations
            summaryAsync.when(
              data: (MonthlyAccountingSummary summary) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryMetricItem(
                            label: '本月支出',
                            amountMinor: summary.totalExpenseMinor,
                            color: colorScheme.error,
                            prefix: '¥',
                          ),
                        ),
                        Expanded(
                          child: _SummaryMetricItem(
                            label: '退款总计',
                            amountMinor: summary.totalRefundMinor,
                            color: Colors.amber.shade800,
                            prefix: '¥',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryMetricItem(
                            label: '净支出',
                            amountMinor: summary.netExpenseMinor,
                            color: colorScheme.primary,
                            prefix: '¥',
                            isEmphasized: true,
                          ),
                        ),
                        Expanded(
                          child: _SummaryMetricItem(
                            label: '总收入',
                            amountMinor: summary.totalIncomeMinor,
                            color: Colors.green.shade700,
                            prefix: '¥',
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (Object error, StackTrace? _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        '月度汇总加载失败',
                        style: TextStyle(color: colorScheme.error, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重试'),
                        onPressed: () {
                          ref.invalidate(monthlySummaryProvider);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetricItem extends StatelessWidget {
  final String label;
  final int amountMinor;
  final Color color;
  final String prefix;
  final bool isEmphasized;

  const _SummaryMetricItem({
    required this.label,
    required this.amountMinor,
    required this.color,
    this.prefix = '',
    this.isEmphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedAmount = CurrencyUtils.centsToYuanString(amountMinor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.normal,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$prefix$formattedAmount',
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: isEmphasized ? FontWeight.w800 : FontWeight.w600,
            fontSize: isEmphasized ? 17 : 15,
          ),
        ),
      ],
    );
  }
}

Future<void> _showMonthPickerSheet(BuildContext context, WidgetRef ref, String currentYm) {
  final parts = currentYm.split('-');
  int selectedYear = int.tryParse(parts[0]) ?? DateTime.now().year;

  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '选择月度账本看板',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(modalContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Year navigation bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: '上一年',
                          onPressed: () {
                            setModalState(() {
                              selectedYear--;
                            });
                          },
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$selectedYear 年',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Quick year pills
                            ...[2024, 2025, 2026].map((y) {
                              final isCurrent = y == selectedYear;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                child: ChoiceChip(
                                  label: Text('$y'),
                                  selected: isCurrent,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setModalState(() {
                                        selectedYear = y;
                                      });
                                    }
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: '下一年',
                          onPressed: () {
                            setModalState(() {
                              selectedYear++;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 1-12 Months Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.8,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      final monthNum = index + 1;
                      final isSelected = selectedYear == (int.tryParse(parts[0]) ?? 0) &&
                          monthNum == (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);

                      return FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: isSelected
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          foregroundColor: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          final newYm =
                              '$selectedYear-${monthNum.toString().padLeft(2, '0')}';
                          ref.read(selectedMonthProvider.notifier).setMonth(newYm);
                          Navigator.of(modalContext).pop();
                        },
                        child: Text(
                          '$monthNum月',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
