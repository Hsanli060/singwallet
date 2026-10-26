// lib/presentation/screens/transactions/widgets/trash_bin_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../data/models/models.dart';
import '../../../providers/transaction_providers.dart';

/// 30-Day Recycling Bin dialog displaying soft-deleted transactions.
///
/// Supports restoring items back to the active ledger, permanently deleting
/// single items, or purging the entire trash bin.
class TrashBinDialog extends ConsumerWidget {
  const TrashBinDialog({super.key});

  /// Convenient dialog opener
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const TrashBinDialog(),
    );
  }

  void _confirmPurgeAll(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('确定要清空回收站吗？回收站内的所有账目将被彻底永久删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await ref.read(trashBinListProvider.notifier).purgeAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('回收站已清空')),
                );
              }
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  void _confirmPermanentDelete(BuildContext context, WidgetRef ref, TransactionEntry tx) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('彻底删除账目'),
        content: Text('确定要彻底删除“${tx.merchantNormalized ?? tx.merchantRaw}”吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await ref.read(trashBinListProvider.notifier).permanentlyDelete(tx.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('账目已彻底删除')),
                );
              }
            },
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(trashBinListProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '回收站',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      trashAsync.maybeWhen(
                        data: (items) => items.isNotEmpty
                            ? TextButton.icon(
                                icon: const Icon(Icons.delete_forever, size: 18),
                                label: const Text('清空'),
                                style: TextButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                ),
                                onPressed: () => _confirmPurgeAll(context, ref),
                              )
                            : const SizedBox.shrink(),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body List
            Expanded(
              child: trashAsync.when(
                data: (List<TransactionEntry> items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 56,
                              color: colorScheme.outlineVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '回收站为空',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '已删除的账目将在此处保留 30 天',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final tx = items[index];
                      final amountStr = CurrencyUtils.centsToYuanString(tx.amountMinor);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.receipt_outlined,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          tx.merchantNormalized ?? tx.merchantRaw,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${tx.occurredOn} · 金额: ¥$amountStr',
                          style: TextStyle(color: colorScheme.outline, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore, size: 20),
                              tooltip: '恢复',
                              color: colorScheme.primary,
                              onPressed: () async {
                                await ref.read(trashBinListProvider.notifier).restore(tx.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '已恢复“${tx.merchantNormalized ?? tx.merchantRaw}”',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever, size: 20),
                              tooltip: '彻底删除',
                              color: colorScheme.error,
                              onPressed: () => _confirmPermanentDelete(context, ref, tx),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('加载回收站失败: $error', style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => ref.read(trashBinListProvider.notifier).refresh(),
                        child: const Text('重试'),
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
