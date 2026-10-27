// lib/presentation/screens/transactions/widgets/transaction_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../data/models/models.dart';
import '../../../providers/rule_account_providers.dart';
import '../../../providers/transaction_providers.dart';
import '../../../theme/app_icon_registry.dart';

/// Rich transaction tile displaying category icon, merchant title,
/// account capsule, type badge, project label, refund indicator, and formatted amount.
///
/// Supports swipe-to-delete with undo SnackBar.
class TransactionTile extends ConsumerWidget {
  final TransactionEntry transaction;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.onDelete,
  });

  static IconData getIconData(String? iconKey) {
    return AppIconRegistry.resolveCategoryIconByKey(iconKey);
  }

  static String getChannelDisplayName(String channel) {
    return AppIconRegistry.resolveChannelDisplayName(channel);
  }

  static Color getChannelColor(String channel, [ThemeData? theme]) {
    return AppIconRegistry.resolveChannelColor(channel, theme);
  }

  static IconData getChannelIcon(String channel) {
    return AppIconRegistry.resolveChannelIcon(channel);
  }

  void _handleDelete(BuildContext context, WidgetRef ref) {
    if (onDelete != null) {
      onDelete!();
      return;
    }

    final txId = transaction.id;
    ref.read(transactionListProvider.notifier).softDelete(txId);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('已移入回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(transactionListProvider.notifier).restore(txId);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Lookup category, account, and project
    final categories = ref.watch(categoriesListProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsListProvider).valueOrNull ?? const [];
    final projects = ref.watch(projectsListProvider).valueOrNull ?? const [];

    final category = categories.where((c) => c.id == transaction.categoryId).firstOrNull;
    final account = accounts.where((a) => a.id == transaction.accountId).firstOrNull;
    final project = projects.where((p) => p.id == transaction.projectId).firstOrNull;

    // Resolve Category Icon
    final iconData = getIconData(category?.iconKey);

    // Format Amount and Prefix
    final formattedAmount = CurrencyUtils.centsToYuanString(transaction.amountMinor);
    final String amountText;
    final Color amountColor;

    switch (transaction.type) {
      case 'expense':
        amountText = '-¥$formattedAmount';
        amountColor = colorScheme.onSurface;
        break;
      case 'income':
        amountText = '+¥$formattedAmount';
        amountColor = Colors.green.shade700;
        break;
      case 'refund':
        amountText = '+¥$formattedAmount';
        amountColor = Colors.blue.shade700;
        break;
      case 'transfer':
      default:
        amountText = '¥$formattedAmount';
        amountColor = colorScheme.onSurfaceVariant;
        break;
    }

    // Account / Payment Channel text
    final channelName = account?.name ?? getChannelDisplayName(transaction.paymentChannel);
    final isAutoRecognized =
        transaction.originDraftId != null || transaction.eventTimeSource == 'ocr_extracted';

    return Dismissible(
      key: Key('tx_tile_${transaction.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white),
            SizedBox(width: 4),
            Text(
              '删除',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      onDismissed: (_) => _handleDelete(context, ref),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Category Icon with circular tinted container
              CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.primaryContainer.withAlpha(160),
                child: Icon(
                  iconData,
                  size: 22,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              // Merchant, Notes & Badges
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Merchant title
                    Text(
                      transaction.merchantNormalized ?? transaction.merchantRaw,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Badges row: Channel capsule, Category, Type, Project, Note
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Payment channel capsule
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            channelName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        // Category badge (if category exists)
                        if (category != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withAlpha(128),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              category.name,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        // Refund indicator badge
                        if (transaction.type == 'refund')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.shade300, width: 0.5),
                            ),
                            child: Text(
                              '退款',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.blue.shade800,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        // Income indicator badge
                        if (transaction.type == 'income')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300, width: 0.5),
                            ),
                            child: Text(
                              '收入',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.green.shade800,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        // Project label tag
                        if (project != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withAlpha(160),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#${project.name}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        // Note snippet if present
                        if (transaction.note != null && transaction.note!.trim().isNotEmpty)
                          Text(
                            transaction.note!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right Column: Amount formatted with sign/color & Source Tag (自动识别 / 手动录入)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    amountText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAutoRecognized
                          ? colorScheme.tertiaryContainer.withAlpha(120)
                          : colorScheme.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isAutoRecognized ? '自动识别' : '手动录入',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isAutoRecognized
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
