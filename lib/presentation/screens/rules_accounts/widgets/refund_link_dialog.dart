// lib/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:singwallet/core/utils/currency_utils.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/data/repositories/ledger_repository.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';

/// Dialog allowing user to associate a refund transaction with its original expense.
///
/// Ensures compliance with `refund_links ON DELETE CASCADE` integrity constraints:
/// permanently purging the original expense unlinks the refund relationship without
/// deleting the refund transaction itself.
class RefundLinkDialog extends ConsumerStatefulWidget {
  final String? refundTxId;
  final TransactionEntry? refundTransaction;

  const RefundLinkDialog({
    super.key,
    this.refundTxId,
    this.refundTransaction,
  });

  @override
  ConsumerState<RefundLinkDialog> createState() => _RefundLinkDialogState();
}

class _RefundLinkDialogState extends ConsumerState<RefundLinkDialog> {
  final TextEditingController _searchController = TextEditingController();

  TransactionEntry? _selectedRefund;
  String? _selectedExpenseId;

  List<TransactionEntry> _availableRefunds = <TransactionEntry>[];
  List<TransactionEntry> _candidateExpenses = <TransactionEntry>[];

  bool _isLoading = true;
  bool _isSearchingExpenses = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedRefund = widget.refundTransaction;
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    final repo = ref.read(ledgerRepositoryProvider);

    try {
      // 1. If refundTxId was passed but not refundTransaction, fetch it
      if (_selectedRefund == null && widget.refundTxId != null) {
        _selectedRefund = await repo.getTransactionById(widget.refundTxId!);
      }

      // 2. If still no refund selected, load candidate refunds (type == 'refund', active)
      if (_selectedRefund == null) {
        _availableRefunds = await repo.getTransactions(
          const TransactionFilter(type: 'refund'),
        );
        if (_availableRefunds.isNotEmpty) {
          _selectedRefund = _availableRefunds.first;
        }
      }

      // 3. Load initial candidate expense transactions (deleted_at IS NULL)
      _candidateExpenses = await repo.getTransactions(
        const TransactionFilter(type: 'expense'),
      );
    } catch (e) {
      _errorMessage = '数据加载失败: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _isSearchingExpenses = true);
    final repo = ref.read(ledgerRepositoryProvider);

    try {
      final trimmed = query.trim();
      final results = await repo.getTransactions(
        TransactionFilter(
          type: 'expense',
          keyword: trimmed.isEmpty ? null : trimmed,
        ),
      );
      if (mounted) {
        setState(() {
          _candidateExpenses = results;
          _isSearchingExpenses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchingExpenses = false;
          _errorMessage = '搜索失败: $e';
        });
      }
    }
  }

  Future<void> _submitLink() async {
    final refundId = _selectedRefund?.id ?? widget.refundTxId;
    if (refundId == null || _selectedExpenseId == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(ledgerRepositoryProvider);
      await repo.linkRefund(
        refundTxId: refundId,
        originalExpenseTxId: _selectedExpenseId!,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已成功建立退款与原消费账目关联')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '关联失败: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _isLoading
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Icon(
                          Icons.link,
                          color: theme.colorScheme.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '退款账目关联',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Foreign Key Cascade Safety Note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withAlpha(128),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '外键级联安全机制说明：本关联依托 SQLite refund_links ON DELETE CASCADE 机制。若未来对原支出记录执行彻底清理（Purge），系统仅级联解除退款关联关系，退款账目本身将安全保留，绝不会被误删。',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Refund Selector / Summary
                    if (widget.refundTransaction == null &&
                        widget.refundTxId == null &&
                        _availableRefunds.isNotEmpty) ...[
                      const Text(
                        '选择待关联的退款记录：',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<TransactionEntry>(
                        initialValue: _selectedRefund,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: _availableRefunds.map((TransactionEntry tx) {
                          return DropdownMenuItem<TransactionEntry>(
                            value: tx,
                            child: Text(
                              '${tx.occurredOn} ${tx.merchantRaw} (+¥${CurrencyUtils.centsToYuanString(tx.amountMinor)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (TransactionEntry? value) {
                          setState(() {
                            _selectedRefund = value;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                    ] else if (_selectedRefund != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer.withAlpha(70),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt_long, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '退款: ${_selectedRefund!.merchantRaw} (+¥${CurrencyUtils.centsToYuanString(_selectedRefund!.amountMinor)}) [${_selectedRefund!.occurredOn}]',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Search Original Expense
                    const Text(
                      '检索原支出账目 (仅限未删除支出)：',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: '按商户名、备注或金额搜索...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    const SizedBox(height: 10),

                    // Expense Candidate List
                    Expanded(
                      child: _isSearchingExpenses
                          ? const Center(child: CircularProgressIndicator())
                          : _candidateExpenses.isEmpty
                              ? Center(
                                  child: Text(
                                    '未检索到符合条件的原支出账目',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _candidateExpenses.length,
                                  itemBuilder: (context, index) {
                                    final expense = _candidateExpenses[index];
                                    final isSelected = _selectedExpenseId == expense.id;

                                    return Card(
                                      elevation: isSelected ? 2 : 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.outlineVariant,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      color: isSelected
                                          ? theme.colorScheme.primaryContainer.withAlpha(80)
                                          : theme.colorScheme.surface,
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      child: ListTile(
                                        dense: true,
                                        leading: Icon(
                                          isSelected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.outline,
                                        ),
                                        title: Text(
                                          expense.merchantRaw,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          '${expense.occurredOn} • 渠道: ${expense.paymentChannel}${expense.note != null && expense.note!.isNotEmpty ? " • 备注: ${expense.note}" : ""}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: Text(
                                          '-¥${CurrencyUtils.centsToYuanString(expense.amountMinor)}',
                                          style: TextStyle(
                                            color: theme.colorScheme.error,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        onTap: () {
                                          setState(() => _selectedExpenseId = expense.id);
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                      ),
                    ],

                    const SizedBox(height: 14),
                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.link, size: 18),
                          label: const Text('确认关联'),
                          onPressed: (_selectedExpenseId != null &&
                                  _selectedRefund != null &&
                                  !_isSubmitting)
                              ? _submitLink
                              : null,
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
