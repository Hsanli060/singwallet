// lib/data/repositories/ledger_repository.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/soft_delete_manager.dart' as db_soft;
import '../database/transaction_manager.dart';
import '../models/models.dart';
import '../seeder/database_seeder.dart';

typedef AccountEntry = Account;
typedef CategoryEntry = Category;
typedef ProjectEntry = Project;

/// Filter configuration for querying transactions.
class TransactionFilter {
  final String? startDate; // 'YYYY-MM-DD'
  final String? endDate; // 'YYYY-MM-DD'
  final String? accountId;
  final String? projectId;
  final String? categoryId;
  final String? type; // 'expense', 'income', 'refund', 'transfer'
  final String? keyword;
  final bool inTrash;

  const TransactionFilter({
    this.startDate,
    this.endDate,
    this.accountId,
    this.projectId,
    this.categoryId,
    this.type,
    this.keyword,
    this.inTrash = false,
  });

  bool get hasActiveFilters =>
      startDate != null ||
      endDate != null ||
      accountId != null ||
      projectId != null ||
      categoryId != null ||
      type != null ||
      (keyword != null && keyword!.trim().isNotEmpty);

  TransactionFilter copyWith({
    String? startDate,
    String? endDate,
    String? accountId,
    String? projectId,
    String? categoryId,
    String? type,
    String? keyword,
    bool? inTrash,
    bool clearStartDate = false,
    bool clearEndDate = false,
    bool clearAccountId = false,
    bool clearProjectId = false,
    bool clearCategoryId = false,
    bool clearType = false,
    bool clearKeyword = false,
  }) {
    return TransactionFilter(
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      type: clearType ? null : (type ?? this.type),
      keyword: clearKeyword ? null : (keyword ?? this.keyword),
      inTrash: inTrash ?? this.inTrash,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionFilter &&
          runtimeType == other.runtimeType &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          accountId == other.accountId &&
          projectId == other.projectId &&
          categoryId == other.categoryId &&
          type == other.type &&
          keyword == other.keyword &&
          inTrash == other.inTrash;

  @override
  int get hashCode => Object.hash(
        startDate,
        endDate,
        accountId,
        projectId,
        categoryId,
        type,
        keyword,
        inTrash,
      );
}

/// A group of transactions occurring on the same date, with financial subtotals.
class TransactionGroup {
  final String date; // 'YYYY-MM-DD'
  final List<TransactionEntry> transactions;
  final int totalExpenseMinor;
  final int totalIncomeMinor;
  final int totalRefundMinor;
  final int netSubtotalMinor; // totalExpenseMinor - totalRefundMinor

  const TransactionGroup({
    required this.date,
    required this.transactions,
    required this.totalExpenseMinor,
    required this.totalIncomeMinor,
    required this.totalRefundMinor,
    required this.netSubtotalMinor,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionGroup &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          totalExpenseMinor == other.totalExpenseMinor &&
          totalIncomeMinor == other.totalIncomeMinor &&
          totalRefundMinor == other.totalRefundMinor &&
          netSubtotalMinor == other.netSubtotalMinor &&
          transactions.length == other.transactions.length;

  @override
  int get hashCode => Object.hash(
        date,
        totalExpenseMinor,
        totalIncomeMinor,
        totalRefundMinor,
        netSubtotalMinor,
      );

  @override
  String toString() =>
      'TransactionGroup(date: $date, txs: ${transactions.length}, netSubtotal: $netSubtotalMinor)';
}

/// Financial summary data object for monthly accounting aggregations.
class MonthlyAccountingSummary {
  final int totalExpenseMinor;
  final int totalRefundMinor;
  final int netExpenseMinor;
  final int totalIncomeMinor;
  final int transactionCount;

  const MonthlyAccountingSummary({
    required this.totalExpenseMinor,
    required this.totalRefundMinor,
    required this.netExpenseMinor,
    this.totalIncomeMinor = 0,
    required this.transactionCount,
  });

  /// Net balance = total income - net expense.
  int get netBalanceMinor => totalIncomeMinor - netExpenseMinor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthlyAccountingSummary &&
          runtimeType == other.runtimeType &&
          totalExpenseMinor == other.totalExpenseMinor &&
          totalRefundMinor == other.totalRefundMinor &&
          netExpenseMinor == other.netExpenseMinor &&
          totalIncomeMinor == other.totalIncomeMinor &&
          transactionCount == other.transactionCount;

  @override
  int get hashCode => Object.hash(
        totalExpenseMinor,
        totalRefundMinor,
        netExpenseMinor,
        totalIncomeMinor,
        transactionCount,
      );

  @override
  String toString() =>
      'MonthlyAccountingSummary(expense: $totalExpenseMinor, refund: $totalRefundMinor, net: $netExpenseMinor, income: $totalIncomeMinor, count: $transactionCount)';
}

/// Abstract contract for the formal Ledger repository.
abstract class ILedgerRepository {
  Future<void> seedInitialDataIfEmpty({Map<String, int>? initialBalances});
  Future<MonthlyAccountingSummary> getMonthlySummary(String yearMonth);
  Future<List<TransactionGroup>> getGroupedTransactions(TransactionFilter filter);
  Future<List<TransactionEntry>> getTransactions([TransactionFilter? filter]);
  Future<TransactionEntry?> getTransactionById(String id);
  Future<void> softDeleteTransaction(String id);
  Future<void> restoreTransaction(String id);
  Future<void> permanentlyDeleteTransaction(String id);
  Future<List<TransactionEntry>> getTrashBinTransactions();
  Future<int> purgeTrash({int retentionDays = 30});
  Future<List<AccountEntry>> getAccounts({bool includeArchived = false});
  Future<List<CategoryEntry>> getCategories({bool includeArchived = false});
  Future<List<ProjectEntry>> getProjects({bool includeArchived = false});
  Future<void> linkRefund({required String refundTxId, required String originalExpenseTxId});
  Future<Map<String, int>> getAccountBalances();
}

/// Production implementation of [ILedgerRepository] powered by SQLite.
class LedgerRepository implements ILedgerRepository {
  final DatabaseExecutor _db;
  final TransactionManager _txManager;

  LedgerRepository(
    DatabaseExecutor db, {
    TransactionManager? txManager,
  })  : _db = db,
        _txManager = txManager ?? TransactionManager();

  @override
  Future<void> seedInitialDataIfEmpty({Map<String, int>? initialBalances}) async {
    await DatabaseSeeder.seedIfNeeded(_db, initialBalances: initialBalances);
  }

  @override
  Future<MonthlyAccountingSummary> getMonthlySummary(String yearMonth) async {
    final startDate = '$yearMonth-01';
    final endDate = '$yearMonth-31';

    final rows = await _db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor ELSE 0 END), 0) AS total_expense,
        COALESCE(SUM(CASE WHEN type = 'refund' THEN amount_minor ELSE 0 END), 0) AS total_refund,
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE 0 END), 0) AS total_income,
        COUNT(CASE WHEN type IN ('expense', 'refund') THEN 1 ELSE NULL END) AS tx_count
      FROM transactions
      WHERE deleted_at IS NULL
        AND occurred_on BETWEEN ? AND ?
    ''', [startDate, endDate]);

    final first = rows.first;
    final totalExpense = (first['total_expense'] as int?) ?? 0;
    final totalRefund = (first['total_refund'] as int?) ?? 0;
    final totalIncome = (first['total_income'] as int?) ?? 0;
    final txCount = (first['tx_count'] as int?) ?? 0;

    return MonthlyAccountingSummary(
      totalExpenseMinor: totalExpense,
      totalRefundMinor: totalRefund,
      netExpenseMinor: totalExpense - totalRefund,
      totalIncomeMinor: totalIncome,
      transactionCount: txCount,
    );
  }

  @override
  Future<List<TransactionEntry>> getTransactions([TransactionFilter? filter]) async {
    final conditions = <String>[];
    final args = <Object?>[];

    final inTrash = filter?.inTrash ?? false;
    if (inTrash) {
      conditions.add('deleted_at IS NOT NULL');
    } else {
      conditions.add('deleted_at IS NULL');
    }

    if (filter != null) {
      if (filter.startDate != null) {
        conditions.add('occurred_on >= ?');
        args.add(filter.startDate);
      }
      if (filter.endDate != null) {
        conditions.add('occurred_on <= ?');
        args.add(filter.endDate);
      }
      if (filter.accountId != null) {
        conditions.add('(account_id = ? OR transfer_to_account_id = ?)');
        args.add(filter.accountId);
        args.add(filter.accountId);
      }
      if (filter.projectId != null) {
        conditions.add('project_id = ?');
        args.add(filter.projectId);
      }
      if (filter.categoryId != null) {
        conditions.add('category_id = ?');
        args.add(filter.categoryId);
      }
      if (filter.type != null) {
        conditions.add('type = ?');
        args.add(filter.type);
      }
      if (filter.keyword != null && filter.keyword!.trim().isNotEmpty) {
        final kw = '%${filter.keyword!.trim()}%';
        conditions.add('(merchant_raw LIKE ? OR merchant_normalized LIKE ? OR note LIKE ?)');
        args.add(kw);
        args.add(kw);
        args.add(kw);
      }
    }

    final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;
    final rows = await _db.query(
      'transactions',
      where: whereClause,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: inTrash ? 'deleted_at DESC' : 'occurred_on DESC, created_at DESC',
    );

    return rows.map(TransactionEntry.fromMap).toList();
  }

  @override
  Future<TransactionEntry?> getTransactionById(String id) async {
    final rows = await _db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionEntry.fromMap(rows.first);
  }

  @override
  Future<List<TransactionGroup>> getGroupedTransactions(TransactionFilter filter) async {
    final txs = await getTransactions(filter);

    // Group transactions by occurred_on preserving descending order
    final groupedMap = <String, List<TransactionEntry>>{};
    for (final tx in txs) {
      groupedMap.putIfAbsent(tx.occurredOn, () => []).add(tx);
    }

    final groups = <TransactionGroup>[];
    for (final entry in groupedMap.entries) {
      final date = entry.key;
      final list = entry.value;

      var totalExpense = 0;
      var totalIncome = 0;
      var totalRefund = 0;

      for (final tx in list) {
        if (tx.type == 'expense') {
          totalExpense += tx.amountMinor;
        } else if (tx.type == 'income') {
          totalIncome += tx.amountMinor;
        } else if (tx.type == 'refund') {
          totalRefund += tx.amountMinor;
        }
      }

      groups.add(TransactionGroup(
        date: date,
        transactions: list,
        totalExpenseMinor: totalExpense,
        totalIncomeMinor: totalIncome,
        totalRefundMinor: totalRefund,
        netSubtotalMinor: totalExpense - totalRefund,
      ));
    }

    return groups;
  }

  @override
  Future<void> softDeleteTransaction(String id) async {
    await _txManager.softDeleteTransaction(id, customExecutor: _db);
  }

  @override
  Future<void> restoreTransaction(String id) async {
    await _txManager.restoreFromTrash(id, customExecutor: _db);
  }

  @override
  Future<void> permanentlyDeleteTransaction(String id) async {
    await _txManager.permanentDeleteTransaction(id, customExecutor: _db);
  }

  @override
  Future<List<TransactionEntry>> getTrashBinTransactions() async {
    final rawRows = await db_soft.SoftDeleteManager.getTrashBinTransactions(_db);
    return rawRows.map(TransactionEntry.fromMap).toList();
  }

  @override
  Future<int> purgeTrash({int retentionDays = 30}) async {
    return await _txManager.purgeExpiredTrash(
      retentionDays: retentionDays,
      customExecutor: _db,
    );
  }

  @override
  Future<List<AccountEntry>> getAccounts({bool includeArchived = false}) async {
    final rows = await _db.query(
      'accounts',
      where: includeArchived ? null : 'archived_at IS NULL',
      orderBy: 'created_at ASC',
    );
    return rows.map(Account.fromMap).toList();
  }

  @override
  Future<List<CategoryEntry>> getCategories({bool includeArchived = false}) async {
    final rows = await _db.query(
      'categories',
      where: includeArchived ? null : 'archived_at IS NULL',
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<List<ProjectEntry>> getProjects({bool includeArchived = false}) async {
    final rows = await _db.query(
      'projects',
      where: includeArchived ? null : 'archived_at IS NULL',
      orderBy: 'name ASC',
    );
    return rows.map(Project.fromMap).toList();
  }

  @override
  Future<void> linkRefund({
    required String refundTxId,
    required String originalExpenseTxId,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _db.insert(
      'refund_links',
      {
        'refund_transaction_id': refundTxId,
        'original_expense_id': originalExpenseTxId,
        'created_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<String, int>> getAccountBalances() async {
    final accounts = await getAccounts(includeArchived: true);
    final balances = <String, int>{};

    for (final acc in accounts) {
      final rows = await _db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE
            WHEN type = 'income' AND account_id = ? THEN amount_minor
            WHEN type = 'expense' AND account_id = ? THEN -amount_minor
            WHEN type = 'refund' AND account_id = ? THEN amount_minor
            WHEN type = 'transfer' AND transfer_to_account_id = ? THEN amount_minor
            WHEN type = 'transfer' AND account_id = ? THEN -amount_minor
            ELSE 0 END), 0) AS balance
        FROM transactions
        WHERE deleted_at IS NULL
      ''', [acc.id, acc.id, acc.id, acc.id, acc.id]);

      final balance = (rows.first['balance'] as int?) ?? 0;
      balances[acc.id] = balance;
    }

    return balances;
  }
}
