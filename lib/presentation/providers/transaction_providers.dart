// lib/presentation/providers/transaction_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/models.dart';
import '../../data/repositories/ledger_repository.dart';
import 'core_providers.dart';

/// Notifier managing current active transaction filter.
class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() {
    return const TransactionFilter();
  }

  void updateFilter(TransactionFilter filter) {
    state = filter;
  }

  void reset() {
    state = const TransactionFilter();
  }

  void setDateRange(String? startDate, String? endDate) {
    state = state.copyWith(
      startDate: startDate,
      endDate: endDate,
      clearStartDate: startDate == null,
      clearEndDate: endDate == null,
    );
  }

  void setAccount(String? accountId) {
    state = state.copyWith(
      accountId: accountId,
      clearAccountId: accountId == null,
    );
  }

  void setCategory(String? categoryId) {
    state = state.copyWith(
      categoryId: categoryId,
      clearCategoryId: categoryId == null,
    );
  }

  void setProject(String? projectId) {
    state = state.copyWith(
      projectId: projectId,
      clearProjectId: projectId == null,
    );
  }

  void setType(String? type) {
    state = state.copyWith(
      type: type,
      clearType: type == null,
    );
  }

  void setKeyword(String? keyword) {
    state = state.copyWith(
      keyword: keyword,
      clearKeyword: keyword == null,
    );
  }
}

/// Provider for active transaction filter state.
final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
  TransactionFilterNotifier.new,
);

/// Notifier managing grouped transactions list reactively.
class TransactionListNotifier extends AsyncNotifier<List<TransactionGroup>> {
  @override
  Future<List<TransactionGroup>> build() async {
    final repo = ref.watch(ledgerRepositoryProvider);
    final filter = ref.watch(transactionFilterProvider);
    return repo.getGroupedTransactions(filter);
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<TransactionGroup>>.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(ledgerRepositoryProvider);
      final filter = ref.read(transactionFilterProvider);
      return repo.getGroupedTransactions(filter);
    });
  }

  Future<void> softDelete(String transactionId) async {
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.softDeleteTransaction(transactionId);
    ref.invalidate(monthlySummaryProvider);
    ref.invalidate(trashBinListProvider);
    await refresh();
  }

  Future<void> restore(String transactionId) async {
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.restoreTransaction(transactionId);
    ref.invalidate(monthlySummaryProvider);
    ref.invalidate(trashBinListProvider);
    await refresh();
  }

  Future<void> permanentDelete(String transactionId) async {
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.permanentlyDeleteTransaction(transactionId);
    ref.invalidate(trashBinListProvider);
    await refresh();
  }
}

/// Provider for reactive grouped transaction list.
final transactionListProvider =
    AsyncNotifierProvider<TransactionListNotifier, List<TransactionGroup>>(
  TransactionListNotifier.new,
);

/// Notifier managing the currently selected month for monthly summary card ('YYYY-MM').
class SelectedMonthNotifier extends Notifier<String> {
  @override
  String build() {
    final now = DateTime.now();
    final monthStr = now.month.toString().padLeft(2, '0');
    return '${now.year}-$monthStr';
  }

  void setMonth(String yearMonth) {
    state = yearMonth;
  }

  void previousMonth() {
    final parts = state.split('-');
    var year = int.parse(parts[0]);
    var month = int.parse(parts[1]) - 1;
    if (month < 1) {
      year -= 1;
      month = 12;
    }
    state = '$year-${month.toString().padLeft(2, '0')}';
  }

  void nextMonth() {
    final parts = state.split('-');
    var year = int.parse(parts[0]);
    var month = int.parse(parts[1]) + 1;
    if (month > 12) {
      year += 1;
      month = 1;
    }
    state = '$year-${month.toString().padLeft(2, '0')}';
  }
}

/// Provider for the currently selected month ('YYYY-MM').
final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, String>(
  SelectedMonthNotifier.new,
);

/// Provider for monthly financial summary calculated for the currently selected month.
final monthlySummaryProvider =
    FutureProvider<MonthlyAccountingSummary>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  final month = ref.watch(selectedMonthProvider);
  return repo.getMonthlySummary(month);
});

/// Family provider for monthly summary of any arbitrary 'YYYY-MM'.
final monthlySummaryFamilyProvider =
    FutureProvider.family<MonthlyAccountingSummary, String>((ref, yearMonth) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getMonthlySummary(yearMonth);
});

/// Notifier managing 30-day trash bin transactions.
class TrashBinListNotifier extends AsyncNotifier<List<TransactionEntry>> {
  @override
  Future<List<TransactionEntry>> build() async {
    final repo = ref.watch(ledgerRepositoryProvider);
    return repo.getTrashBinTransactions();
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<TransactionEntry>>.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(ledgerRepositoryProvider);
      return repo.getTrashBinTransactions();
    });
  }

  Future<void> restore(String id) async {
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.restoreTransaction(id);
    ref.invalidate(transactionListProvider);
    ref.invalidate(monthlySummaryProvider);
    await refresh();
  }

  Future<void> permanentlyDelete(String id) async {
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.permanentlyDeleteTransaction(id);
    await refresh();
  }

  Future<void> purgeAll({int retentionDays = 0}) async {
    final repo = ref.read(ledgerRepositoryProvider);
    await repo.purgeTrash(retentionDays: retentionDays);
    await refresh();
  }
}

/// Provider for soft-deleted trash bin transactions.
final trashBinListProvider =
    AsyncNotifierProvider<TrashBinListNotifier, List<TransactionEntry>>(
  TrashBinListNotifier.new,
);
