// lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/providers/draft_providers.dart';
import 'package:singwallet/presentation/providers/rule_account_providers.dart';

/// Extension on [RulesListNotifier] supplying required method aliases
/// [toggleRule] and [reorderRules].
extension RulesListNotifierExtension on RulesListNotifier {
  Future<void> toggleRule(String ruleId, bool enabled) => toggleEnabled(ruleId, enabled);
  Future<void> reorderRules(List<ClassificationRule> reordered) => reorder(reordered);
}

/// Tab displaying 6-tier classification rules, drag-and-drop reordering,
/// priority adjustments, active switch toggles, rule creation, and non-retroactive
/// draft re-matching against the active rule engine.
class ClassificationRulesTab extends ConsumerStatefulWidget {
  const ClassificationRulesTab({super.key});

  @override
  ConsumerState<ClassificationRulesTab> createState() => _ClassificationRulesTabState();
}

class _ClassificationRulesTabState extends ConsumerState<ClassificationRulesTab> {
  bool _isRematching = false;

  Future<void> _rematchPendingDrafts() async {
    setState(() => _isRematching = true);
    try {
      final db = ref.read(databaseProvider);
      final ruleEngine = ref.read(classificationRuleEngineProvider);

      // Strictly non-retroactive: only query uncommitted pending drafts, NEVER committed transactions!
      final draftRows = await db.rawQuery('''
        SELECT d.*
        FROM drafts d
        JOIN capture_jobs cj ON d.capture_id = cj.id
        WHERE cj.state IN ('NEEDS_REVIEW', 'IMPORTED')
          AND d.saved_transaction_id IS NULL
      ''');

      int updatedCount = 0;
      for (final row in draftRows) {
        final draftId = row['id'] as String;
        final candidateJson = row['candidate_fields'] as String;

        Map<String, dynamic> candidateMap = {};
        try {
          final decoded = jsonDecode(candidateJson);
          if (decoded is Map<String, dynamic>) {
            candidateMap = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}

        final merchantRaw = (candidateMap['merchant_raw'] ??
                candidateMap['merchantRaw'] ??
                '')
            .toString();
        final merchantNorm = (candidateMap['merchant_normalized'] ??
                candidateMap['merchantNormalized'])
            ?.toString();
        final paymentChannel = (candidateMap['payment_channel'] ??
                candidateMap['paymentChannel'])
            ?.toString();
        final amountMinor = candidateMap['amount_minor'] ?? candidateMap['amountMinor'];
        final txType = (candidateMap['type'] ?? 'expense').toString();

        final matchResult = await ruleEngine.classify(
          merchantRaw: merchantRaw,
          merchantNormalized: merchantNorm,
          paymentChannel: paymentChannel,
          amountMinor: amountMinor is int ? amountMinor : null,
          type: txType,
        );

        candidateMap['suggested_category_id'] = matchResult.categoryId;
        candidateMap['suggestedCategoryId'] = matchResult.categoryId;
        candidateMap['suggested_project_id'] = matchResult.projectId;
        candidateMap['suggestedProjectId'] = matchResult.projectId;
        candidateMap['confidence_score'] = matchResult.confidence;
        candidateMap['confidenceScore'] = matchResult.confidence;

        final nowIso = DateTime.now().toUtc().toIso8601String();
        await db.update(
          'drafts',
          {
            'candidate_fields': jsonEncode(candidateMap),
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [draftId],
        );
        updatedCount++;
      }

      // Refresh draft queue provider so UI immediately reflects updated suggestions
      ref.invalidate(draftsQueueProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '重新匹配完成：已更新 $updatedCount 个待审核草稿建议（严格非追溯：未修改已入账历史流水）',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新匹配失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRematching = false);
      }
    }
  }

  void _showAddRuleDialog(List<Category> categories) {
    final patternController = TextEditingController();
    final priorityController = TextEditingController(text: '100');
    String selectedCategoryId = categories.isNotEmpty ? categories.first.id : 'cat_food';
    String? selectedChannel;
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.rule),
                  SizedBox(width: 8),
                  Text('添加分类规则'),
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
                        controller: patternController,
                        decoration: const InputDecoration(
                          labelText: '商户关键字 / 通配符 *',
                          hintText: '如：星巴克、瑞幸*、美团',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return '请输入商户关键字或匹配模式';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategoryId,
                        borderRadius: BorderRadius.circular(16),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        decoration: const InputDecoration(
                          labelText: '目标分类 *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                        items: categories.map((Category cat) {
                          return DropdownMenuItem<String>(
                            value: cat.id,
                            child: Text(cat.name),
                          );
                        }).toList(),
                        onChanged: (String? val) {
                          if (val != null) {
                            setDialogState(() => selectedCategoryId = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: priorityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '规则优先级 (越大匹配次序越靠前)',
                          hintText: '100',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return '请输入优先级数值';
                          }
                          if (int.tryParse(val.trim()) == null) {
                            return '请输入有效整数';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedChannel,
                        borderRadius: BorderRadius.circular(16),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        decoration: const InputDecoration(
                          labelText: '支付渠道限定 (选填)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('所有支付渠道 (通用)')),
                          DropdownMenuItem<String?>(value: 'wechat', child: Text('仅限微信支付 (WeChat)')),
                          DropdownMenuItem<String?>(value: 'alipay', child: Text('仅限支付宝 (Alipay)')),
                          DropdownMenuItem<String?>(value: 'bank_card', child: Text('仅限银行卡')),
                          DropdownMenuItem<String?>(value: 'cash', child: Text('仅限现金')),
                        ],
                        onChanged: (String? val) {
                          setDialogState(() => selectedChannel = val);
                        },
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
                      final nowIso = DateTime.now().toUtc().toIso8601String();
                      final priority = int.parse(priorityController.text.trim());
                      final pattern = patternController.text.trim();
                      final ruleId = 'rule_${DateTime.now().microsecondsSinceEpoch}';

                      final newRule = ClassificationRule(
                        id: ruleId,
                        priority: priority,
                        merchantPattern: pattern,
                        paymentChannel: selectedChannel,
                        categoryId: selectedCategoryId,
                        enabled: 1,
                        version: 1,
                        createdAt: nowIso,
                        updatedAt: nowIso,
                      );

                      await ref.read(rulesListProvider.notifier).save(newRule);

                      if (!mounted) return;
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text('规则 "$pattern" 添加成功')),
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
    final rulesAsync = ref.watch(rulesListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final categories = categoriesAsync.value ?? <Category>[];

    final categoryMap = <String, String>{};
    for (final cat in categories) {
      categoryMap[cat.id] = cat.name;
    }

    return Scaffold(
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('加载分类规则失败: $err'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.read(rulesListProvider.notifier).refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (List<ClassificationRule> rulesData) {
          // Sort rules strictly descending by priority
          final rules = List<ClassificationRule>.from(rulesData)
            ..sort((a, b) => b.priority.compareTo(a.priority));

          return Column(
            children: [
              // Action Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '分类匹配规则 (${rules.length} 条已配置)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: _isRematching
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: const Text('重新匹配'),
                      onPressed: _isRematching ? null : _rematchPendingDrafts,
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加规则'),
                      onPressed: () => _showAddRuleDialog(categories),
                    ),
                  ],
                ),
              ),

              // Reorderable Rules List
              Expanded(
                child: rules.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.rule_folder_outlined,
                                size: 56, color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            const Text('暂无分类匹配规则'),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.add),
                              label: const Text('添加第一条规则'),
                              onPressed: () => _showAddRuleDialog(categories),
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: rules.length,
                        onReorderItem: (int oldIndex, int newIndex) async {
                          final items = List<ClassificationRule>.from(rules);
                          final moved = items.removeAt(oldIndex);
                          items.insert(newIndex, moved);
                          await ref.read(rulesListProvider.notifier).reorderRules(items);
                        },
                        itemBuilder: (context, index) {
                          final rule = rules[index];
                          final categoryName = categoryMap[rule.categoryId] ?? rule.categoryId;

                          return Card(
                            key: ValueKey(rule.id),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant.withAlpha(128),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  // Drag handle indicator
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: theme.colorScheme.outline,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Pattern & Metadata
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              rule.merchantPattern,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Chip(
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              labelPadding:
                                                  const EdgeInsets.symmetric(horizontal: 8),
                                              label: Text(
                                                categoryName,
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                              backgroundColor:
                                                  theme.colorScheme.primaryContainer.withAlpha(128),
                                            ),
                                            if (rule.paymentChannel != null) ...[
                                              const SizedBox(width: 6),
                                              Chip(
                                                visualDensity: VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                labelPadding:
                                                    const EdgeInsets.symmetric(horizontal: 6),
                                                label: Text(
                                                  rule.paymentChannel!,
                                                  style: const TextStyle(fontSize: 10),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '优先级: ${rule.priority}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '版本: v${rule.version}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: theme.colorScheme.outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Priority adjustment buttons
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward, size: 18),
                                    tooltip: '提升优先级',
                                    onPressed: index > 0
                                        ? () async {
                                            final items = List<ClassificationRule>.from(rules);
                                            final current = items.removeAt(index);
                                            items.insert(index - 1, current);
                                            await ref
                                                .read(rulesListProvider.notifier)
                                                .reorderRules(items);
                                          }
                                        : null,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward, size: 18),
                                    tooltip: '降低优先级',
                                    onPressed: index < rules.length - 1
                                        ? () async {
                                            final items = List<ClassificationRule>.from(rules);
                                            final current = items.removeAt(index);
                                            items.insert(index + 1, current);
                                            await ref
                                                .read(rulesListProvider.notifier)
                                                .reorderRules(items);
                                          }
                                        : null,
                                  ),

                                  // Active Switch
                                  Switch(
                                    value: rule.isEnabled,
                                    onChanged: (bool enabled) {
                                      ref
                                          .read(rulesListProvider.notifier)
                                          .toggleRule(rule.id, enabled);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
