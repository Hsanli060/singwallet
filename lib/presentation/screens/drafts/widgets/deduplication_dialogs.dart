// lib/presentation/screens/drafts/widgets/deduplication_dialogs.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../features/deduplication/deduplication_engine.dart';

/// Result of evaluating deduplication checks and presenting user interception dialogs.
sealed class DedupResolution {
  const DedupResolution();
}

/// Proceed with normal draft commit.
class DedupProceed extends DedupResolution {
  const DedupProceed();
}

/// Hard duplicate blocked by Tier 3 (or Tier 1). User acknowledged dialog.
class DedupBlocked extends DedupResolution {
  final String reason;
  final String? existingTransactionId;

  const DedupBlocked({
    required this.reason,
    this.existingTransactionId,
  });
}

/// User cancelled committing upon seeing duplicate warning.
class DedupCancelled extends DedupResolution {
  const DedupCancelled();
}

/// Duplicate found in trash bin and user chose to restore it.
class DedupRestoreRequested extends DedupResolution {
  final String transactionId;

  const DedupRestoreRequested(this.transactionId);
}

/// Pre-commit deduplication dialog interception suite.
///
/// Implements:
/// - Tier 3 active duplicate: Red blocking alert dialog ("发现完全相同订单号的已确认交易，禁止重复入账").
/// - Tier 3 trash duplicate: Amber alert dialog ("此订单号曾被删除，存在于回收站中，是否直接恢复？").
/// - Tier 4 24h heuristic duplicate: Secondary confirmation dialog ("24小时内发现相同金额的相似交易，是否确认这笔交易不是重复记录？").
class DeduplicationDialogs {
  DeduplicationDialogs._();

  /// Evaluates 4-tier deduplication and shows appropriate intercept dialogs.
  static Future<DedupResolution> evaluateAndIntercept({
    required BuildContext context,
    required DeduplicationEngine engine,
    String? originDraftId,
    String? imageContentHash,
    PlatformIdentifier? platformIdentifier,
    required String merchantRaw,
    String? merchantNormalized,
    required int amountMinor,
    required String occurredOn,
    String? occurredAt,
  }) async {
    final evaluation = await engine.evaluate(
      originDraftId: originDraftId,
      imageContentHash: imageContentHash,
      platformIdentifier: platformIdentifier,
      merchantRaw: merchantRaw,
      merchantNormalized: merchantNormalized,
      amountMinor: amountMinor,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
    );

    if (!context.mounted) {
      return const DedupCancelled();
    }

    // 1. Check Tier 3 Hard Platform Identifier Duplicate (or Tier 1 Idempotence)
    if (evaluation.tier3.isMatched) {
      if (evaluation.tier3.isInTrash) {
        // Tier 3 Trash duplicate -> Amber restore dialog
        final txId = evaluation.tier3.matchedTransactionId!;
        final shouldRestore = await showTier3TrashDialog(
          context,
          trashTransactionId: txId,
          transaction: evaluation.tier3.matchedTransaction,
        );
        if (shouldRestore) {
          return DedupRestoreRequested(txId);
        } else {
          return const DedupCancelled();
        }
      } else {
        // Tier 3 Active duplicate -> Red blocking dialog
        await showTier3ActiveDialog(
          context,
          transactionId: evaluation.tier3.matchedTransactionId,
          transaction: evaluation.tier3.matchedTransaction,
        );
        return DedupBlocked(
          reason: '发现完全相同订单号的已确认交易，禁止重复入账',
          existingTransactionId: evaluation.tier3.matchedTransactionId,
        );
      }
    }

    // Check Tier 1 Idempotence if origin draft already committed
    if (evaluation.tier1.isMatched) {
      if (evaluation.tier1.isInTrash) {
        final txId = evaluation.tier1.existingTransactionId!;
        final shouldRestore = await showTier3TrashDialog(
          context,
          trashTransactionId: txId,
        );
        if (shouldRestore) {
          return DedupRestoreRequested(txId);
        } else {
          return const DedupCancelled();
        }
      } else {
        await showTier3ActiveDialog(
          context,
          transactionId: evaluation.tier1.existingTransactionId,
        );
        return DedupBlocked(
          reason: '此草稿已完成入账，禁止重复提交',
          existingTransactionId: evaluation.tier1.existingTransactionId,
        );
      }
    }

    // 2. Check Tier 4 24-Hour Heuristic Duplicate
    if (evaluation.tier4.hasSuspectedDuplicates) {
      final shouldProceed = await showTier4FuzzyDialog(
        context,
        candidates: evaluation.tier4.candidateTransactions,
      );
      if (shouldProceed) {
        return const DedupProceed();
      } else {
        return const DedupCancelled();
      }
    }

    // All clean!
    return const DedupProceed();
  }

  /// Tier 3 Active duplicate: Red blocking alert dialog.
  static Future<void> showTier3ActiveDialog(
    BuildContext context, {
    String? transactionId,
    Map<String, dynamic>? transaction,
  }) async {
    final theme = Theme.of(context);
    final txMerchant = transaction?['merchant_raw'] as String?;
    final txAmountMinor = transaction?['amount_minor'] as int?;
    final txOccurredOn = transaction?['occurred_on'] as String?;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: CircleAvatar(
            backgroundColor: theme.colorScheme.errorContainer,
            radius: 28,
            child: Icon(
              Icons.block,
              color: theme.colorScheme.error,
              size: 32,
            ),
          ),
          title: const Text(
            '发现重复交易',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '发现完全相同订单号的已确认交易，禁止重复入账。',
                style: TextStyle(fontSize: 14),
              ),
              if (txMerchant != null || txAmountMinor != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(120),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (txMerchant != null)
                        Text(
                          '商户: $txMerchant',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      if (txAmountMinor != null)
                        Text(
                          '金额: ¥${CurrencyUtils.centsToYuanString(txAmountMinor)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      if (txOccurredOn != null)
                        Text(
                          '日期: $txOccurredOn',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              key: const ValueKey('tier3_active_dialog_ok'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('我知道了'),
            ),
          ],
        );
      },
    );
  }

  /// Tier 3 Trash duplicate: Amber alert dialog ("此订单号曾被删除，存在于回收站中，是否直接恢复？").
  static Future<bool> showTier3TrashDialog(
    BuildContext context, {
    required String trashTransactionId,
    Map<String, dynamic>? transaction,
  }) async {
    final txMerchant = transaction?['merchant_raw'] as String?;
    final txAmountMinor = transaction?['amount_minor'] as int?;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: CircleAvatar(
            backgroundColor: Colors.amber.shade100,
            radius: 28,
            child: Icon(
              Icons.restore_from_trash,
              color: Colors.amber.shade900,
              size: 32,
            ),
          ),
          title: const Text(
            '回收站存在相同交易',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '此订单号曾被删除，存在于回收站中，是否直接恢复？',
                style: TextStyle(fontSize: 14),
              ),
              if (txMerchant != null || txAmountMinor != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (txMerchant != null)
                        Text(
                          '原商户: $txMerchant',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      if (txAmountMinor != null)
                        Text(
                          '原金额: ¥${CurrencyUtils.centsToYuanString(txAmountMinor)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('tier3_trash_dialog_cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('tier3_trash_dialog_restore'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('直接恢复'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  /// Tier 4 Heuristic duplicate: Secondary confirmation dialog.
  static Future<bool> showTier4FuzzyDialog(
    BuildContext context, {
    required List<Map<String, dynamic>> candidates,
  }) async {
    final theme = Theme.of(context);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: CircleAvatar(
            backgroundColor: theme.colorScheme.secondaryContainer,
            radius: 28,
            child: Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.secondary,
              size: 32,
            ),
          ),
          title: const Text(
            '疑似重复交易',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '24小时内发现相同金额的相似交易，是否确认这笔交易不是重复记录？',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  '相似交易候选:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = candidates[index];
                      final mRaw = (item['merchant_raw'] as String?) ?? '未知商户';
                      final amt = (item['amount_minor'] as int?) ?? 0;
                      final date = (item['occurred_on'] as String?) ?? '';

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withAlpha(100),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mRaw,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    date,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '¥${CurrencyUtils.centsToYuanString(amt)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('tier4_fuzzy_dialog_cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('tier4_fuzzy_dialog_proceed'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续入账'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}
