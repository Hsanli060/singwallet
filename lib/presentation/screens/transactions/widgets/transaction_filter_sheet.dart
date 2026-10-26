// lib/presentation/screens/transactions/widgets/transaction_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/repositories/ledger_repository.dart';
import '../../../providers/rule_account_providers.dart';
import '../../../providers/transaction_providers.dart';

/// Multidimensional filter sheet for transactions.
///
/// Filters by Account, Project, Category, Date range, Transaction type, and Keyword.
class TransactionFilterSheet extends ConsumerStatefulWidget {
  const TransactionFilterSheet({super.key});

  /// Convenient modal opener
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const TransactionFilterSheet(),
    );
  }

  @override
  ConsumerState<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends ConsumerState<TransactionFilterSheet> {
  late final TextEditingController _keywordController;
  String? _selectedType;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  String? _selectedProjectId;
  String? _startDate;
  String? _endDate;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(transactionFilterProvider);
    _keywordController = TextEditingController(text: filter.keyword ?? '');
    _selectedType = filter.type;
    _selectedAccountId = filter.accountId;
    _selectedCategoryId = filter.categoryId;
    _selectedProjectId = filter.projectId;
    _startDate = filter.startDate;
    _endDate = filter.endDate;
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _keywordController.clear();
      _selectedType = null;
      _selectedAccountId = null;
      _selectedCategoryId = null;
      _selectedProjectId = null;
      _startDate = null;
      _endDate = null;
    });
  }

  void _apply() {
    final keyword = _keywordController.text.trim();
    final newFilter = TransactionFilter(
      keyword: keyword.isEmpty ? null : keyword,
      type: _selectedType,
      accountId: _selectedAccountId,
      categoryId: _selectedCategoryId,
      projectId: _selectedProjectId,
      startDate: _startDate,
      endDate: _endDate,
    );

    ref.read(transactionFilterProvider.notifier).updateFilter(newFilter);
    Navigator.of(context).pop();
  }

  Future<void> _pickStartDate() async {
    final initial = _startDate != null ? DateTime.tryParse(_startDate!) : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择开始日期',
    );
    if (picked != null) {
      setState(() {
        _startDate =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _pickEndDate() async {
    final initial = _endDate != null ? DateTime.tryParse(_endDate!) : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择结束日期',
    );
    if (picked != null) {
      setState(() {
        _endDate =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _setPresetDate(String preset) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    setState(() {
      switch (preset) {
        case 'today':
          _startDate = todayStr;
          _endDate = todayStr;
          break;
        case 'yesterday':
          final y = now.subtract(const Duration(days: 1));
          final yStr =
              '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
          _startDate = yStr;
          _endDate = yStr;
          break;
        case 'before_yesterday':
          final by = now.subtract(const Duration(days: 2));
          final byStr =
              '${by.year}-${by.month.toString().padLeft(2, '0')}-${by.day.toString().padLeft(2, '0')}';
          _startDate = byStr;
          _endDate = byStr;
          break;
        case 'week':
          final w = now.subtract(const Duration(days: 6));
          final wStr =
              '${w.year}-${w.month.toString().padLeft(2, '0')}-${w.day.toString().padLeft(2, '0')}';
          _startDate = wStr;
          _endDate = todayStr;
          break;
        case 'month':
          final mStart =
              '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
          _startDate = mStart;
          _endDate = todayStr;
          break;
        case 'all':
        default:
          _startDate = null;
          _endDate = null;
          break;
      }
    });
  }

  bool _isPreset(String preset) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (preset == 'today') {
      return _startDate == todayStr && _endDate == todayStr;
    } else if (preset == 'yesterday') {
      final y = now.subtract(const Duration(days: 1));
      final yStr =
          '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
      return _startDate == yStr && _endDate == yStr;
    } else if (preset == 'before_yesterday') {
      final by = now.subtract(const Duration(days: 2));
      final byStr =
          '${by.year}-${by.month.toString().padLeft(2, '0')}-${by.day.toString().padLeft(2, '0')}';
      return _startDate == byStr && _endDate == byStr;
    } else if (preset == 'week') {
      final w = now.subtract(const Duration(days: 6));
      final wStr =
          '${w.year}-${w.month.toString().padLeft(2, '0')}-${w.day.toString().padLeft(2, '0')}';
      return _startDate == wStr && _endDate == todayStr;
    } else if (preset == 'month') {
      final mStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      return _startDate == mStart && _endDate == todayStr;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;

    final categories = ref.watch(categoriesListProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsListProvider).valueOrNull ?? const [];
    final projects = ref.watch(projectsListProvider).valueOrNull ?? const [];

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Sheet Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '筛选流水',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Filter options body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  children: [
                    // 1. Keyword input
                    Text(
                      '关键字搜索',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _keywordController,
                      decoration: InputDecoration(
                        hintText: '搜索商户名称或备注',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _keywordController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _keywordController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),

                    // 2. Transaction Type
                    Text(
                      '交易类型',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('全部'),
                          selected: _selectedType == null,
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedType = null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('支出'),
                          selected: _selectedType == 'expense',
                          onSelected: (selected) {
                            setState(() => _selectedType = selected ? 'expense' : null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('收入'),
                          selected: _selectedType == 'income',
                          onSelected: (selected) {
                            setState(() => _selectedType = selected ? 'income' : null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('退款'),
                          selected: _selectedType == 'refund',
                          onSelected: (selected) {
                            setState(() => _selectedType = selected ? 'refund' : null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('转账'),
                          selected: _selectedType == 'transfer',
                          onSelected: (selected) {
                            setState(() => _selectedType = selected ? 'transfer' : null);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 3. Date Range
                    Text(
                      '日期范围',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('全部日期'),
                          selected: _startDate == null && _endDate == null,
                          onSelected: (s) {
                            if (s) _setPresetDate('all');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('今天'),
                          selected: _isPreset('today'),
                          onSelected: (s) {
                            if (s) _setPresetDate('today');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('昨天'),
                          selected: _isPreset('yesterday'),
                          onSelected: (s) {
                            if (s) _setPresetDate('yesterday');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('前天'),
                          selected: _isPreset('before_yesterday'),
                          onSelected: (s) {
                            if (s) _setPresetDate('before_yesterday');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('近7天'),
                          selected: _isPreset('week'),
                          onSelected: (s) {
                            if (s) _setPresetDate('week');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('本月'),
                          selected: _isPreset('month'),
                          onSelected: (s) {
                            if (s) _setPresetDate('month');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(_startDate ?? '开始日期'),
                            onPressed: _pickStartDate,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('至'),
                        ),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(_endDate ?? '结束日期'),
                            onPressed: _pickEndDate,
                          ),
                        ),
                        if (_startDate != null || _endDate != null)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            tooltip: '清除日期',
                            onPressed: () {
                              setState(() {
                                _startDate = null;
                                _endDate = null;
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 4. Financial Accounts
                    if (accounts.isNotEmpty) ...[
                      Text(
                        '账户渠道',
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('全部'),
                            selected: _selectedAccountId == null,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedAccountId = null);
                            },
                          ),
                          ...accounts.map(
                            (acc) => ChoiceChip(
                              label: Text(acc.name),
                              selected: _selectedAccountId == acc.id,
                              onSelected: (selected) {
                                setState(() => _selectedAccountId = selected ? acc.id : null);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // 5. Category
                    if (categories.isNotEmpty) ...[
                      Text(
                        '分类类别',
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('全部'),
                            selected: _selectedCategoryId == null,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedCategoryId = null);
                            },
                          ),
                          ...categories.map(
                            (cat) => ChoiceChip(
                              label: Text(cat.name),
                              selected: _selectedCategoryId == cat.id,
                              onSelected: (selected) {
                                setState(() => _selectedCategoryId = selected ? cat.id : null);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // 6. Project
                    if (projects.isNotEmpty) ...[
                      Text(
                        '项目标签',
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('全部'),
                            selected: _selectedProjectId == null,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedProjectId = null);
                            },
                          ),
                          ...projects.map(
                            (proj) => ChoiceChip(
                              label: Text('#${proj.name}'),
                              selected: _selectedProjectId == proj.id,
                              onSelected: (selected) {
                                setState(() => _selectedProjectId = selected ? proj.id : null);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              // Bottom Action Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _reset,
                      child: const Text('重置'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _apply,
                        child: const Text('应用筛选'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
