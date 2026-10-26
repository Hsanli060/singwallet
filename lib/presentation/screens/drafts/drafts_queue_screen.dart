// lib/presentation/screens/drafts/drafts_queue_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/currency_utils.dart';
import '../../providers/draft_providers.dart';
import 'draft_confirmation_screen.dart';

/// Screen displaying pending OCR bill drafts in NEEDS_REVIEW or IMPORTED state.
///
/// Features:
/// 1. Consumes [draftsQueueProvider] with real-time reactive updates.
/// 2. Displays list of pending drafts with merchant name, amount preview, channel, and timestamp.
/// 3. Pull-to-refresh integration.
/// 4. Tapping item navigates to [DraftConfirmationScreen].
class DraftsQueueScreen extends ConsumerWidget {
  const DraftsQueueScreen({super.key});

  IconData _getChannelIcon(String channel) {
    switch (channel.toLowerCase()) {
      case 'wechat':
        return Icons.chat_bubble_outline;
      case 'alipay':
        return Icons.payment;
      case 'bank_card':
        return Icons.credit_card;
      case 'cash':
        return Icons.money;
      default:
        return Icons.receipt_outlined;
    }
  }

  Color _getChannelColor(String channel, ThemeData theme) {
    switch (channel.toLowerCase()) {
      case 'wechat':
        return const Color(0xFF07C160);
      case 'alipay':
        return const Color(0xFF1677FF);
      case 'bank_card':
        return const Color(0xFFFF9800);
      case 'cash':
        return const Color(0xFF4CAF50);
      default:
        return theme.colorScheme.primary;
    }
  }

  String _getChannelLabel(String channel) {
    switch (channel.toLowerCase()) {
      case 'wechat':
        return '微信支付';
      case 'alipay':
        return '支付宝';
      case 'bank_card':
        return '银行卡';
      case 'cash':
        return '现金';
      default:
        return '其他渠道';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queueAsync = ref.watch(draftsQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('待确认草稿箱'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新草稿箱',
            onPressed: () => ref.read(draftsQueueProvider.notifier).refresh(),
          ),
        ],
      ),
      body: queueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                '加载草稿队列失败: $err',
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.read(draftsQueueProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (drafts) {
          if (drafts.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(draftsQueueProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 64,
                            color: theme.colorScheme.outline.withAlpha(150),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '暂无待确认草稿',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '截图或分享导入的账单将显示在此处，等待确认入账',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(draftsQueueProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              itemCount: drafts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final draft = drafts[index];
                Map<String, dynamic> candidateFields = {};
                try {
                  final decoded = jsonDecode(draft.candidateFields);
                  if (decoded is Map<String, dynamic>) {
                    candidateFields = decoded;
                  }
                } catch (_) {}

                final merchant = (candidateFields['merchant_raw'] ??
                    candidateFields['merchantRaw'] ??
                    '未知商户') as String;
                final rawAmountMinor =
                    candidateFields['amount_minor'] ?? candidateFields['amountMinor'];
                final int? amountMinor = rawAmountMinor is int ? rawAmountMinor : null;
                final channel = (candidateFields['payment_channel'] ??
                    candidateFields['paymentChannel'] ??
                    'other') as String;
                final occurredOn = (candidateFields['occurred_on'] ??
                    candidateFields['occurredOn'] ??
                    draft.createdAt.split('T').first) as String;

                final channelColor = _getChannelColor(channel, theme);
                final channelIcon = _getChannelIcon(channel);
                final channelLabel = _getChannelLabel(channel);

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withAlpha(100),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) =>
                              DraftConfirmationScreen(draftId: draft.id),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: channelColor.withAlpha(30),
                            child: Icon(
                              channelIcon,
                              color: channelColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  merchant,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        channelLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      occurredOn,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                amountMinor != null
                                    ? '¥${CurrencyUtils.centsToYuanString(amountMinor)}'
                                    : '¥ --',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '待确认',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            color: theme.colorScheme.outline.withAlpha(120),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
