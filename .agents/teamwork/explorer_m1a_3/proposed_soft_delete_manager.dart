import 'package:sqflite/sqflite.dart';

/// Financial summary data object for monthly accounting aggregations.
class MonthlyAccountingSummary {
  final int totalExpenseMinor;
  final int totalRefundMinor;
  final int netExpenseMinor;
  final int transactionCount;

  const MonthlyAccountingSummary({
    required this.totalExpenseMinor,
    required this.totalRefundMinor,
    required this.netExpenseMinor,
    required this.transactionCount,
  });

  @override
  String toString() =>
      'MonthlyAccountingSummary(expense: $totalExpenseMinor, refund: $totalRefundMinor, net: $netExpenseMinor, count: $transactionCount)';
}

/// Manages the 30-day Trash Bin lifecycle, soft deletion, restoration, permanent purge,
/// and active ledger query filtering.
class SoftDeleteManager {
  SoftDeleteManager._();

  /// Soft deletes a transaction by populating [deleted_at].
  ///
  /// The transaction remains in the database, preserving all relational data and
  /// [confirmed_identifiers] to detect duplicate re-imports during the 30-day trash retention.
  ///
  /// Returns `true` if a row was updated, `false` if the transaction was not found or already deleted.
  static Future<bool> softDeleteTransaction(
    DatabaseExecutor db,
    String transactionId, {
    DateTime? deletedAt,
  }) async {
    final nowIso = (deletedAt ?? DateTime.now().toUtc()).toIso8601String();
    final count = await db.update(
      'transactions',
      {
        'deleted_at': nowIso,
        'updated_at': nowIso,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [transactionId],
    );
    return count > 0;
  }

  /// Restores a soft-deleted transaction from the trash bin back into active status.
  ///
  /// Clears [deleted_at] and updates [updated_at], keeping the original transaction UUID intact.
  /// Returns `true` if restored, `false` if not found in trash.
  static Future<bool> restoreTransaction(
    DatabaseExecutor db,
    String transactionId, {
    DateTime? restoredAt,
  }) async {
    final nowIso = (restoredAt ?? DateTime.now().toUtc()).toIso8601String();
    final count = await db.update(
      'transactions',
      {
        'deleted_at': null,
        'updated_at': nowIso,
      },
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [transactionId],
    );
    return count > 0;
  }

  /// Permanently removes a transaction from SQLite storage.
  ///
  /// Triggers foreign key cascades:
  /// - [transaction_metadata], [transaction_tags], and [confirmed_identifiers] are cascade deleted.
  /// - [refund_links]: If this was the original expense, the link in `refund_links` is cascade deleted,
  ///   BUT the refund transaction itself remains intact as an unlinked standalone refund!
  ///
  /// Returns `true` if a row was deleted.
  static Future<bool> permanentDeleteTransaction(
    DatabaseExecutor db,
    String transactionId,
  ) async {
    final count = await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    );
    return count > 0;
  }

  /// Automatically purges transactions that have resided in the trash bin for longer than [retentionDays] (default 30).
  ///
  /// All cascaded dependent rows ([confirmed_identifiers], [refund_links], metadata) are purged.
  /// Returns the count of purged transactions.
  static Future<int> purgeExpiredTrash(
    DatabaseExecutor db, {
    int retentionDays = 30,
    DateTime? referenceTime,
  }) async {
    final ref = referenceTime ?? DateTime.now().toUtc();
    final cutoff = ref.subtract(Duration(days: retentionDays)).toIso8601String();

    return await db.delete(
      'transactions',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
  }

  /// Fetches all transactions currently residing in the 30-day trash bin.
  static Future<List<Map<String, Object?>>> getTrashBinTransactions(
    DatabaseExecutor db,
  ) async {
    return await db.query(
      'transactions',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
  }

  /// Calculates monthly financial totals adhering strictly to the occurrence date ([occurred_on])
  /// and active status (`deleted_at IS NULL`).
  ///
  /// Formulas:
  /// - Total Expense = SUM(amount_minor) WHERE type = 'expense' AND deleted_at IS NULL
  /// - Total Refund = SUM(amount_minor) WHERE type = 'refund' AND deleted_at IS NULL
  /// - Net Expense = Total Expense - Total Refund
  /// - Internal transfers (`type = 'transfer'`) are strictly excluded.
  static Future<MonthlyAccountingSummary> calculateMonthlySummary(
    DatabaseExecutor db, {
    required String startDate, // YYYY-MM-DD
    required String endDate,   // YYYY-MM-DD
  }) async {
    // 1. Total expense
    final expenseRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS total_expense, COUNT(*) AS count
      FROM transactions
      WHERE type = 'expense'
        AND deleted_at IS NULL
        AND occurred_on BETWEEN ? AND ?
      ''',
      [startDate, endDate],
    );
    final totalExpense = (expenseRows.first['total_expense'] as int?) ?? 0;
    final expenseCount = (expenseRows.first['count'] as int?) ?? 0;

    // 2. Total refund
    final refundRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS total_refund, COUNT(*) AS count
      FROM transactions
      WHERE type = 'refund'
        AND deleted_at IS NULL
        AND occurred_on BETWEEN ? AND ?
      ''',
      [startDate, endDate],
    );
    final totalRefund = (refundRows.first['total_refund'] as int?) ?? 0;
    final refundCount = (refundRows.first['count'] as int?) ?? 0;

    return MonthlyAccountingSummary(
      totalExpenseMinor: totalExpense,
      totalRefundMinor: totalRefund,
      netExpenseMinor: totalExpense - totalRefund,
      transactionCount: expenseCount + refundCount,
    );
  }
}
