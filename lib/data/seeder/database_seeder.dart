// lib/data/seeder/database_seeder.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/models.dart';

/// Seeds default system categories and accounts into SQLite database.
///
/// Designed to be completely idempotent: checks existing entities by ID
/// before inserting to avoid constraint violations on repeated runs.
class DatabaseSeeder {
  DatabaseSeeder._();

  /// Default categories satisfying foreign key constraints in `transactions`
  /// and classification rules.
  static final List<Category> defaultCategories = [
    Category(
      id: 'cat_food',
      name: '餐饮美食',
      applicableType: 'expense',
      iconKey: 'restaurant',
      sortOrder: 1,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Category(
      id: 'cat_transport',
      name: '交通出行',
      applicableType: 'expense',
      iconKey: 'directions_car',
      sortOrder: 2,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Category(
      id: 'cat_shopping',
      name: '日常购物',
      applicableType: 'expense',
      iconKey: 'shopping_bag',
      sortOrder: 3,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Category(
      id: 'cat_entertainment',
      name: '休闲娱乐',
      applicableType: 'expense',
      iconKey: 'sports_esports',
      sortOrder: 4,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Category(
      id: 'cat_bills',
      name: '生活缴费',
      applicableType: 'expense',
      iconKey: 'receipt_long',
      sortOrder: 5,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Category(
      id: 'cat_medical',
      name: '医疗健康',
      applicableType: 'expense',
      iconKey: 'local_hospital',
      sortOrder: 6,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Category(
      id: 'cat_other',
      name: '其他支出',
      applicableType: 'both',
      iconKey: 'more_horiz',
      sortOrder: 99,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Category(
      id: 'cat_income',
      name: '工资收入',
      applicableType: 'income',
      iconKey: 'account_balance_wallet',
      sortOrder: 100,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
  ];

  /// Default accounts for common Chinese payment channels and methods.
  static final List<Account> defaultAccounts = [
    Account(
      id: 'acc_wechat',
      name: '微信支付',
      kind: 'e_wallet',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Account(
      id: 'acc_alipay',
      name: '支付宝',
      kind: 'e_wallet',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Account(
      id: 'acc_bank',
      name: '银行卡',
      kind: 'debit_card',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Account(
      id: 'acc_cash',
      name: '现金',
      kind: 'cash',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
  ];

  /// Default project labels for orthogonal budgeting.
  static final List<Project> defaultProjects = [
    Project(
      id: 'proj_travel',
      name: '旅行出游',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
    Project(
      id: 'proj_home',
      name: '家居装修',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
  ];

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
