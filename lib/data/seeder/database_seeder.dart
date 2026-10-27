// lib/data/seeder/database_seeder.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/constants/domain_metadata.dart';
import '../models/models.dart';

/// Seeds default system categories and accounts into SQLite database.
///
/// Designed to be completely idempotent: checks existing entities by ID
/// before inserting to avoid constraint violations on repeated runs.
class DatabaseSeeder {
  DatabaseSeeder._();

  /// Default categories derived directly from [DomainMetadata] as single source of truth.
  static final List<Category> defaultCategories =
      DomainMetadata.categories.map((c) => c.toCategory()).toList();

  /// Default accounts derived directly from [DomainMetadata].
  static final List<Account> defaultAccounts =
      DomainMetadata.accounts.map((a) => a.toAccount()).toList();

  /// Default project labels derived directly from [DomainMetadata].
  static final List<Project> defaultProjects =
      DomainMetadata.projects.map((p) => p.toProject()).toList();

  /// Executes idempotent seeding against [db].
  ///
  /// Checks whether each entity exists before inserting.
  /// If [initialBalances] are provided (account ID -> minor units amount),
  /// an initial balance transaction is seeded for accounts that have non-zero balance
  /// and don't yet have an initial balance transaction.
  static Future<void> seedIfNeeded(
    DatabaseExecutor db, {
    Map<String, int>? initialBalances,
  }) async {
    // 1. Seed Categories
    for (final category in defaultCategories) {
      final rows = await db.query(
        'categories',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [category.id],
      );
      if (rows.isEmpty) {
        await db.insert('categories', category.toMap());
      }
    }

    // 2. Seed Accounts
    for (final account in defaultAccounts) {
      final rows = await db.query(
        'accounts',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [account.id],
      );
      if (rows.isEmpty) {
        await db.insert('accounts', account.toMap());
      }
    }

    // 3. Seed Projects
    for (final project in defaultProjects) {
      final rows = await db.query(
        'projects',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [project.id],
      );
      if (rows.isEmpty) {
        await db.insert('projects', project.toMap());
      }
    }

    // 4. Seed initial balances if provided
    if (initialBalances != null && initialBalances.isNotEmpty) {
      final nowUtc = DateTime.now().toUtc();
      final todayStr =
          '${nowUtc.year.toString().padLeft(4, '0')}-${nowUtc.month.toString().padLeft(2, '0')}-${nowUtc.day.toString().padLeft(2, '0')}';
      final nowIso = nowUtc.toIso8601String();

      for (final entry in initialBalances.entries) {
        final accountId = entry.key;
        final amountMinor = entry.value;
        if (amountMinor <= 0) continue;

        // Check if an initial balance tx already exists for this account
        final existingTx = await db.query(
          'transactions',
          columns: ['id'],
          where: 'account_id = ? AND merchant_raw = ?',
          whereArgs: [accountId, '初始余额'],
        );

        if (existingTx.isEmpty) {
          final txId = 'tx_init_${accountId}_${nowUtc.millisecondsSinceEpoch}';
          final tx = TransactionEntry(
            id: txId,
            type: 'income',
            amountMinor: amountMinor,
            currency: 'CNY',
            merchantRaw: '初始余额',
            merchantNormalized: '初始余额',
            occurredOn: todayStr,
            occurredAt: nowIso,
            eventTimeSource: 'user_selected',
            eventTimePrecision: 'second',
            paymentChannel: 'other',
            accountId: accountId,
            categoryId: 'cat_income',
            note: '系统账户初始化余额',
            createdAt: nowIso,
            updatedAt: nowIso,
          );
          await db.insert('transactions', tx.toMap());
        }
      }
    }
  }
}
