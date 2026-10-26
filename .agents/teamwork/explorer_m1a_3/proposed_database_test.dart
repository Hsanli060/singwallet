import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// In actual implementation, these are imported from:
// import 'package:singwallet/data/database/app_database.dart';
// import 'package:singwallet/data/database/state_machine.dart';
// import 'package:singwallet/data/database/soft_delete_manager.dart';

void main() {
  // Initialize sqflite for desktop/unit test environments
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const String canonicalSchemaSql = '''
    CREATE TABLE IF NOT EXISTS capture_jobs (
        id TEXT PRIMARY KEY NOT NULL,
        content_hash TEXT NOT NULL,
        source_kind TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        private_image_ref TEXT NOT NULL,
        state TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        parser_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_capture_jobs_hash ON capture_jobs(content_hash);
    CREATE INDEX IF NOT EXISTS idx_capture_jobs_state ON capture_jobs(state);

    CREATE TABLE IF NOT EXISTS drafts (
        id TEXT PRIMARY KEY NOT NULL,
        capture_id TEXT NOT NULL UNIQUE,
        candidate_fields TEXT NOT NULL,
        field_evidence TEXT NOT NULL,
        validation_issues TEXT NOT NULL,
        duplicate_candidates TEXT NOT NULL,
        saved_transaction_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(capture_id) REFERENCES capture_jobs(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_drafts_saved_tx ON drafts(saved_transaction_id);

    CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        card_last4 TEXT,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        parent_id TEXT,
        applicable_type TEXT NOT NULL,
        icon_key TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(parent_id) REFERENCES categories(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY NOT NULL,
        origin_draft_id TEXT UNIQUE,
        type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        currency TEXT NOT NULL DEFAULT 'CNY',
        merchant_raw TEXT NOT NULL,
        merchant_normalized TEXT,
        occurred_on TEXT NOT NULL,
        occurred_at TEXT,
        event_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
        event_time_source TEXT NOT NULL,
        event_time_precision TEXT NOT NULL,
        payment_channel TEXT NOT NULL,
        account_id TEXT,
        transfer_to_account_id TEXT,
        category_id TEXT,
        project_id TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        CHECK (amount_minor > 0),
        FOREIGN KEY(origin_draft_id) REFERENCES drafts(id) ON DELETE SET NULL,
        FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE SET NULL,
        FOREIGN KEY(transfer_to_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
        FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT,
        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
    );
    CREATE INDEX IF NOT EXISTS idx_tx_occurred_on ON transactions(occurred_on);
    CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);
    CREATE INDEX IF NOT EXISTS idx_tx_deleted_at ON transactions(deleted_at);
    CREATE INDEX IF NOT EXISTS idx_tx_project ON transactions(project_id);
    CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);

    CREATE TABLE IF NOT EXISTS transaction_metadata (
        transaction_id TEXT PRIMARY KEY NOT NULL,
        original_amount_minor INTEGER,
        discount_minor INTEGER,
        fee_minor INTEGER,
        payment_status TEXT NOT NULL DEFAULT 'SUCCESS',
        platform_transaction_no TEXT,
        merchant_order_no TEXT,
        identifier_completeness TEXT NOT NULL DEFAULT 'NONE',
        payment_method_label TEXT,
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS transaction_tags (
        transaction_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (transaction_id, tag_id),
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_transaction_tags_tag ON transaction_tags(tag_id);

    CREATE TABLE IF NOT EXISTS refund_links (
        refund_transaction_id TEXT PRIMARY KEY NOT NULL,
        original_expense_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_refund_original ON refund_links(original_expense_id);

    CREATE TABLE IF NOT EXISTS classification_rules (
        id TEXT PRIMARY KEY NOT NULL,
        priority INTEGER NOT NULL DEFAULT 100,
        merchant_pattern TEXT NOT NULL,
        payment_channel TEXT,
        category_id TEXT NOT NULL,
        project_id TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS confirmed_identifiers (
        namespace TEXT NOT NULL,
        identifier_type TEXT NOT NULL,
        complete_value TEXT NOT NULL,
        stable_event_kind TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind),
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_confirmed_identifiers_tx ON confirmed_identifiers(transaction_id);
  ''';

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        final statements = canonicalSchemaSql
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        for (final statement in statements) {
          await db.execute('$statement;');
        }
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('1. Database DDL & Indices Verification', () {
    test('All 12 required tables exist', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
      );
      final actualTables = rows.map((r) => r['name'] as String).toSet();

      final expectedTables = {
        'capture_jobs',
        'drafts',
        'accounts',
        'categories',
        'projects',
        'tags',
        'transactions',
        'transaction_metadata',
        'transaction_tags',
        'refund_links',
        'classification_rules',
        'confirmed_identifiers',
      };

      for (final expected in expectedTables) {
        expect(
          actualTables.contains(expected),
          isTrue,
          reason: 'Table "$expected" must be created in SQLite schema',
        );
      }
      expect(actualTables.length, equals(12));
    });

    test('All 11 required performance indices exist with exact names', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%';",
      );
      final actualIndices = rows.map((r) => r['name'] as String).toSet();

      final expectedIndices = {
        'idx_capture_jobs_hash',
        'idx_capture_jobs_state',
        'idx_drafts_saved_tx',
        'idx_tx_occurred_on',
        'idx_tx_category',
        'idx_tx_deleted_at',
        'idx_tx_project',
        'idx_tx_account',
        'idx_transaction_tags_tag',
        'idx_refund_original',
        'idx_confirmed_identifiers_tx',
      };

      for (final expected in expectedIndices) {
        expect(
          actualIndices.contains(expected),
          isTrue,
          reason: 'Index "$expected" must exist in SQLite database',
        );
      }
      expect(actualIndices.length, equals(11));
    });
  });

  group('2. CHECK Constraints & Integer Cent Currency Storage', () {
    setUp(() async {
      await db.insert('categories', {
        'id': 'cat_food',
        'name': '餐饮美食',
        'applicable_type': 'expense',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    });

    test('CHECK (amount_minor > 0) strictly rejects zero-amount transaction', () async {
      expect(
        () async => await db.insert('transactions', {
          'id': 'tx_zero',
          'type': 'expense',
          'amount_minor': 0, // Illegal: zero cents
          'currency': 'CNY',
          'merchant_raw': '非法零元商户',
          'occurred_on': '2026-10-22',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'minute',
          'payment_channel': 'wechat',
          'category_id': 'cat_food',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('CHECK (amount_minor > 0) strictly rejects negative-amount transaction', () async {
      expect(
        () async => await db.insert('transactions', {
          'id': 'tx_negative',
          'type': 'expense',
          'amount_minor': -2890, // Illegal: negative cents
          'currency': 'CNY',
          'merchant_raw': '非法负数商户',
          'occurred_on': '2026-10-22',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'minute',
          'payment_channel': 'wechat',
          'category_id': 'cat_food',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('Accepts positive integer amounts without float precision truncation', () async {
      const int standardAmount = 2890; // 28.90 CNY
      const int largeAmount = 9223372036854775807; // 64-bit signed max

      await db.insert('transactions', {
        'id': 'tx_valid_1',
        'type': 'expense',
        'amount_minor': standardAmount,
        'currency': 'CNY',
        'merchant_raw': '星巴克咖啡',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_food',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      await db.insert('transactions', {
        'id': 'tx_valid_2',
        'type': 'expense',
        'amount_minor': largeAmount,
        'currency': 'CNY',
        'merchant_raw': '大额资产交易',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'unionpay',
        'category_id': 'cat_food',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      final rows = await db.query('transactions', orderBy: 'id ASC');
      expect(rows.length, equals(2));
      expect(rows[0]['amount_minor'], equals(standardAmount));
      expect(rows[1]['amount_minor'], equals(largeAmount));
    });
  });

  group('3. Unique & Primary Key Constraints', () {
    setUp(() async {
      await db.insert('capture_jobs', {
        'id': 'job_001',
        'content_hash': 'hash_123',
        'source_kind': 'photoPicker',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/job_001.jpg',
        'state': 'NEEDS_REVIEW',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('drafts', {
        'id': 'draft_001',
        'capture_id': 'job_001',
        'candidate_fields': '{}',
        'field_evidence': '{}',
        'validation_issues': '[]',
        'duplicate_candidates': '[]',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('categories', {
        'id': 'cat_dining',
        'name': '正餐',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
    });

    test('drafts.capture_id UNIQUE constraint rejects duplicate draft for same job', () async {
      expect(
        () async => await db.insert('drafts', {
          'id': 'draft_002',
          'capture_id': 'job_001', // Duplicate capture_id
          'candidate_fields': '{}',
          'field_evidence': '{}',
          'validation_issues': '[]',
          'duplicate_candidates': '[]',
          'created_at': '2026-10-22T10:00:00Z',
          'updated_at': '2026-10-22T10:00:00Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('transactions.origin_draft_id UNIQUE constraint rejects duplicate commit', () async {
      await db.insert('transactions', {
        'id': 'tx_first',
        'origin_draft_id': 'draft_001',
        'type': 'expense',
        'amount_minor': 1000,
        'merchant_raw': '快餐店',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      expect(
        () async => await db.insert('transactions', {
          'id': 'tx_duplicate',
          'origin_draft_id': 'draft_001', // Duplicate origin_draft_id!
          'type': 'expense',
          'amount_minor': 1000,
          'merchant_raw': '快餐店重复保存',
          'occurred_on': '2026-10-22',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'minute',
          'payment_channel': 'alipay',
          'category_id': 'cat_dining',
          'created_at': '2026-10-22T10:00:00Z',
          'updated_at': '2026-10-22T10:00:00Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('confirmed_identifiers compound primary key rejects duplicate identifier', () async {
      await db.insert('transactions', {
        'id': 'tx_base',
        'type': 'expense',
        'amount_minor': 3500,
        'merchant_raw': '便利蜂',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'second',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'wechat_pay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': '420000123456789012345678',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_base',
      });

      // Inserting identical compound primary key referencing different transaction fails
      expect(
        () async => await db.insert('confirmed_identifiers', {
          'namespace': 'wechat_pay',
          'identifier_type': 'platform_transaction_no',
          'complete_value': '420000123456789012345678',
          'stable_event_kind': 'payment',
          'transaction_id': 'tx_other',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('4. Foreign Key Cascades & Restrict Integrity', () {
    setUp(() async {
      // 1. Parent and child categories
      await db.insert('categories', {
        'id': 'cat_parent',
        'name': '餐饮美食',
        'parent_id': null,
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
      await db.insert('categories', {
        'id': 'cat_child',
        'name': '快餐简餐',
        'parent_id': 'cat_parent',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // 2. Project
      await db.insert('projects', {
        'id': 'proj_travel',
        'name': '云南旅行',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // 3. Transactions: original expense and refund
      await db.insert('transactions', {
        'id': 'tx_expense_orig',
        'type': 'expense',
        'amount_minor': 10000,
        'merchant_raw': '度假酒店',
        'occurred_on': '2026-10-20',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'wechat',
        'category_id': 'cat_child',
        'project_id': 'proj_travel',
        'created_at': '2026-10-20T10:00:00Z',
        'updated_at': '2026-10-20T10:00:00Z',
      });

      await db.insert('transactions', {
        'id': 'tx_refund_item',
        'type': 'refund',
        'amount_minor': 3000,
        'merchant_raw': '度假酒店退款',
        'occurred_on': '2026-10-21',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'wechat',
        'category_id': 'cat_child',
        'created_at': '2026-10-21T10:00:00Z',
        'updated_at': '2026-10-21T10:00:00Z',
      });

      await db.insert('refund_links', {
        'refund_transaction_id': 'tx_refund_item',
        'original_expense_id': 'tx_expense_orig',
        'created_at': '2026-10-21T10:00:00Z',
      });

      await db.insert('transaction_metadata', {
        'transaction_id': 'tx_expense_orig',
        'original_amount_minor': 12000,
        'discount_minor': 2000,
        'payment_status': 'SUCCESS',
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'wechat_pay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'wx_hotel_12345',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_expense_orig',
      });
    });

    test('ON DELETE RESTRICT rejects deletion of category referenced by active transaction', () async {
      expect(
        () async => await db.delete('categories', where: 'id = ?', whereArgs: ['cat_child']),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('ON DELETE SET NULL sets child parent_id to NULL when parent category is deleted', () async {
      await db.delete('categories', where: 'id = ?', whereArgs: ['cat_parent']);
      final rows = await db.query('categories', where: 'id = ?', whereArgs: ['cat_child']);
      expect(rows.first['parent_id'], isNull);
    });

    test('ON DELETE SET NULL sets transaction project_id to NULL when project is deleted', () async {
      await db.delete('projects', where: 'id = ?', whereArgs: ['proj_travel']);
      final rows = await db.query('transactions', where: 'id = ?', whereArgs: ['tx_expense_orig']);
      expect(rows.first['project_id'], isNull);
    });

    test('Original expense deletion unlinks refund_links but preserves refund transaction intact', () async {
      // Delete original expense
      final deleted = await db.delete('transactions', where: 'id = ?', whereArgs: ['tx_expense_orig']);
      expect(deleted, equals(1));

      // 1. refund_links row must be cascade-deleted
      final links = await db.query(
        'refund_links',
        where: 'original_expense_id = ?',
        whereArgs: ['tx_expense_orig'],
      );
      expect(links, isEmpty, reason: 'refund_links entry must be automatically cascade-deleted');

      // 2. Refund transaction must REMAIN INTACT in transactions table!
      final refundRows = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: ['tx_refund_item'],
      );
      expect(refundRows.length, equals(1), reason: 'Refund transaction itself must NEVER be deleted');
      expect(refundRows.first['amount_minor'], equals(3000));
      expect(refundRows.first['type'], equals('refund'));

      // 3. Metadata and confirmed identifiers of deleted expense must be cascade-deleted
      final meta = await db.query('transaction_metadata', where: 'transaction_id = ?', whereArgs: ['tx_expense_orig']);
      expect(meta, isEmpty);

      final identifiers = await db.query('confirmed_identifiers', where: 'transaction_id = ?', whereArgs: ['tx_expense_orig']);
      expect(identifiers, isEmpty);
    });
  });

  group('5. 30-Day Trash Bin & Soft Deletes', () {
    setUp(() async {
      await db.insert('categories', {
        'id': 'cat_general',
        'name': '通用',
        'applicable_type': 'both',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // Expense 1: 5000 cents (Active)
      await db.insert('transactions', {
        'id': 'tx_exp_1',
        'type': 'expense',
        'amount_minor': 5000,
        'merchant_raw': '超市购物',
        'occurred_on': '2026-10-15',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_general',
        'created_at': '2026-10-15T10:00:00Z',
        'updated_at': '2026-10-15T10:00:00Z',
      });

      // Expense 2: 2000 cents (Soft Deleted)
      await db.insert('transactions', {
        'id': 'tx_exp_2',
        'type': 'expense',
        'amount_minor': 2000,
        'merchant_raw': '误买商品',
        'occurred_on': '2026-10-16',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_general',
        'created_at': '2026-10-16T10:00:00Z',
        'updated_at': '2026-10-16T12:00:00Z',
        'deleted_at': '2026-10-16T12:00:00Z', // In trash bin
      });

      // Refund 1: 1000 cents (Active)
      await db.insert('transactions', {
        'id': 'tx_ref_1',
        'type': 'refund',
        'amount_minor': 1000,
        'merchant_raw': '超市退货',
        'occurred_on': '2026-10-18',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_general',
        'created_at': '2026-10-18T10:00:00Z',
        'updated_at': '2026-10-18T10:00:00Z',
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'alipay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'ali_order_99999',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_exp_2',
      });
    });

    test('Monthly aggregation queries with deleted_at IS NULL exclude soft-deleted items', () async {
      // Total active expense should be 5000 (excluding 2000 in trash)
      final expRows = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_minor), 0) AS total
        FROM transactions
        WHERE type = 'expense'
          AND deleted_at IS NULL
          AND occurred_on BETWEEN '2026-10-01' AND '2026-10-31';
      ''');
      expect(expRows.first['total'], equals(5000));

      // Total active refund should be 1000
      final refRows = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_minor), 0) AS total
        FROM transactions
        WHERE type = 'refund'
          AND deleted_at IS NULL
          AND occurred_on BETWEEN '2026-10-01' AND '2026-10-31';
      ''');
      expect(refRows.first['total'], equals(1000));

      // Net expense = 5000 - 1000 = 4000
      final netExpense = (expRows.first['total'] as int) - (refRows.first['total'] as int);
      expect(netExpense, equals(4000));
    });

    test('Soft-deleted item retains confirmed_identifiers for trash duplicate detection', () async {
      // Confirmed identifier exists in table
      final idRows = await db.rawQuery('''
        SELECT ci.transaction_id, t.deleted_at
        FROM confirmed_identifiers ci
        JOIN transactions t ON ci.transaction_id = t.id
        WHERE ci.complete_value = 'ali_order_99999';
      ''');
      expect(idRows.length, equals(1));
      expect(idRows.first['deleted_at'], isNotNull, reason: 'Must detect transaction is in trash');
    });

    test('Restoring from trash clears deleted_at and updates net expense', () async {
      // Restore tx_exp_2
      await db.update(
        'transactions',
        {
          'deleted_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: ['tx_exp_2'],
      );

      final expRows = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_minor), 0) AS total
        FROM transactions
        WHERE type = 'expense'
          AND deleted_at IS NULL
          AND occurred_on BETWEEN '2026-10-01' AND '2026-10-31';
      ''');
      expect(expRows.first['total'], equals(7000)); // 5000 + 2000
    });

    test('Purge query removes transactions expired beyond 30 days', () async {
      // Insert an expired transaction (35 days old in trash)
      final oldTrashDate = DateTime.now().toUtc().subtract(const Duration(days: 35)).toIso8601String();
      await db.insert('transactions', {
        'id': 'tx_expired_trash',
        'type': 'expense',
        'amount_minor': 800,
        'merchant_raw': '过期废品',
        'occurred_on': '2026-09-01',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'cash',
        'category_id': 'cat_general',
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': oldTrashDate,
        'deleted_at': oldTrashDate,
      });

      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
      final purged = await db.delete(
        'transactions',
        where: 'deleted_at IS NOT NULL AND deleted_at < ?',
        whereArgs: [cutoff],
      );

      expect(purged, equals(1));
      final check = await db.query('transactions', where: 'id = ?', whereArgs: ['tx_expired_trash']);
      expect(check, isEmpty);
    });
  });

  group('6. Ingestion State Machine Transitions & Startup Recovery', () {
    test('Standard linear flow: IMPORTED -> RECOGNIZING -> NEEDS_REVIEW -> COMMITTED', () async {
      await db.insert('capture_jobs', {
        'id': 'job_flow_1',
        'content_hash': 'sha256_flow1',
        'source_kind': 'systemShare',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/flow1.jpg',
        'state': 'IMPORTED',
        'attempt_count': 0,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // IMPORTED -> RECOGNIZING
      await db.update(
        'capture_jobs',
        {'state': 'RECOGNIZING', 'attempt_count': 1, 'updated_at': '2026-10-22T10:00:05Z'},
        where: 'id = ?',
        whereArgs: ['job_flow_1'],
      );

      // RECOGNIZING -> NEEDS_REVIEW
      await db.update(
        'capture_jobs',
        {'state': 'NEEDS_REVIEW', 'updated_at': '2026-10-22T10:00:10Z'},
        where: 'id = ?',
        whereArgs: ['job_flow_1'],
      );

      // NEEDS_REVIEW -> COMMITTED
      await db.update(
        'capture_jobs',
        {'state': 'COMMITTED', 'updated_at': '2026-10-22T10:00:20Z'},
        where: 'id = ?',
        whereArgs: ['job_flow_1'],
      );

      final row = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_flow_1'])).first;
      expect(row['state'], equals('COMMITTED'));
      expect(row['attempt_count'], equals(1));
    });

    test('Startup recovery resets lingering RECOGNIZING jobs to IMPORTED if attempts < max', () async {
      await db.insert('capture_jobs', {
        'id': 'job_lingering_1',
        'content_hash': 'hash_lingering',
        'source_kind': 'systemShare',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/lingering.jpg',
        'state': 'RECOGNIZING', // Stuck due to killed process
        'attempt_count': 1,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // Simulate recovery query
      final lingering = await db.query(
        'capture_jobs',
        where: 'state = ?',
        whereArgs: ['RECOGNIZING'],
      );
      expect(lingering.length, equals(1));

      const int maxAttempts = 3;
      for (final job in lingering) {
        final id = job['id'] as String;
        final attempts = job['attempt_count'] as int;
        if (attempts < maxAttempts) {
          await db.update(
            'capture_jobs',
            {'state': 'IMPORTED', 'updated_at': DateTime.now().toUtc().toIso8601String()},
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await db.update(
            'capture_jobs',
            {'state': 'FAILED', 'updated_at': DateTime.now().toUtc().toIso8601String()},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      final recovered = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_lingering_1'])).first;
      expect(recovered['state'], equals('IMPORTED'));
    });

    test('Startup recovery marks job FAILED if attempts >= max', () async {
      await db.insert('capture_jobs', {
        'id': 'job_max_attempts',
        'content_hash': 'hash_max',
        'source_kind': 'photoPicker',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/max.jpg',
        'state': 'RECOGNIZING',
        'attempt_count': 3, // Limit reached
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      final lingering = await db.query(
        'capture_jobs',
        where: 'state = ?',
        whereArgs: ['RECOGNIZING'],
      );

      const int maxAttempts = 3;
      for (final job in lingering) {
        final id = job['id'] as String;
        final attempts = job['attempt_count'] as int;
        if (attempts >= maxAttempts) {
          await db.update(
            'capture_jobs',
            {'state': 'FAILED', 'updated_at': DateTime.now().toUtc().toIso8601String()},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      final recovered = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_max_attempts'])).first;
      expect(recovered['state'], equals('FAILED'));
    });
  });
}
