// test/database/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/schema.dart';
import 'package:singwallet/data/database/soft_delete_manager.dart';
import 'package:singwallet/data/database/state_machine.dart';
import 'package:singwallet/data/database/transaction_manager.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late TransactionManager txManager;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    txManager = TransactionManager();
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

      for (final expected in AppSchema.expectedTableNames) {
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

      for (final expected in AppSchema.expectedIndexNames) {
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

      await db.insert('projects', {
        'id': 'proj_travel',
        'name': '云南旅行',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

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
        'deleted_at': '2026-10-16T12:00:00Z',
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
      final summary = await SoftDeleteManager.calculateMonthlySummary(
        db,
        startDate: '2026-10-01',
        endDate: '2026-10-31',
      );

      expect(summary.totalExpenseMinor, equals(5000));
      expect(summary.totalRefundMinor, equals(1000));
      expect(summary.netExpenseMinor, equals(4000));
      expect(summary.transactionCount, equals(2));
    });

    test('Soft-deleted item retains confirmed_identifiers for trash duplicate detection', () async {
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
      final restored = await SoftDeleteManager.restoreTransaction(db, 'tx_exp_2');
      expect(restored, isTrue);

      final summary = await SoftDeleteManager.calculateMonthlySummary(
        db,
        startDate: '2026-10-01',
        endDate: '2026-10-31',
      );
      expect(summary.totalExpenseMinor, equals(7000)); // 5000 + 2000
      expect(summary.netExpenseMinor, equals(6000));
    });

    test('Purge query removes transactions expired beyond 30 days', () async {
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

      final purged = await SoftDeleteManager.purgeExpiredTrash(db, retentionDays: 30);
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
      await CaptureJobStateMachine.transition(db, 'job_flow_1', CaptureJobState.recognizing);

      // RECOGNIZING -> NEEDS_REVIEW
      await CaptureJobStateMachine.transition(db, 'job_flow_1', CaptureJobState.needsReview);

      // NEEDS_REVIEW -> COMMITTED
      await CaptureJobStateMachine.transition(db, 'job_flow_1', CaptureJobState.committed);

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
        'state': 'RECOGNIZING',
        'attempt_count': 1,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      final recoveredCount = await CaptureJobStateMachine.recoverLingeringJobs(db, maxAttempts: 3);
      expect(recoveredCount, equals(1));

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
        'attempt_count': 3,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      final recoveredCount = await CaptureJobStateMachine.recoverLingeringJobs(db, maxAttempts: 3);
      expect(recoveredCount, equals(1));

      final recovered = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_max_attempts'])).first;
      expect(recovered['state'], equals('FAILED'));
    });

    test('Illegal transition throws InvalidStateTransitionException', () async {
      await db.insert('capture_jobs', {
        'id': 'job_terminal_test',
        'content_hash': 'hash_term',
        'source_kind': 'systemShare',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/term.jpg',
        'state': 'COMMITTED',
        'attempt_count': 1,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      expect(
        () async => await CaptureJobStateMachine.transition(
          db,
          'job_terminal_test',
          CaptureJobState.recognizing,
        ),
        throwsA(isA<InvalidStateTransitionException>()),
      );
    });
  });

  group('7. Atomic Draft Commitment (TransactionManager)', () {
    setUp(() async {
      await db.insert('capture_jobs', {
        'id': 'job_commit_1',
        'content_hash': 'hash_commit_1',
        'source_kind': 'photoPicker',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/commit_1.jpg',
        'state': 'NEEDS_REVIEW',
        'attempt_count': 1,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('drafts', {
        'id': 'draft_commit_1',
        'capture_id': 'job_commit_1',
        'candidate_fields': '{}',
        'field_evidence': '{}',
        'validation_issues': '[]',
        'duplicate_candidates': '[]',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('categories', {
        'id': 'cat_dining',
        'name': '餐饮',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('tags', {
        'id': 'tag_lunch',
        'name': '工作午餐',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
    });

    test('Atomically commits draft across all affected tables', () async {
      const tx = TransactionEntry(
        id: 'tx_commit_ok',
        originDraftId: 'draft_commit_1',
        type: 'expense',
        amountMinor: 3200,
        currency: 'CNY',
        merchantRaw: '日料小馆',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_dining',
        createdAt: '2026-10-22T12:00:00Z',
        updatedAt: '2026-10-22T12:00:00Z',
      );

      const meta = TransactionMetadata(
        transactionId: 'tx_commit_ok',
        originalAmountMinor: 4000,
        discountMinor: 800,
        paymentStatus: 'SUCCESS',
        platformTransactionNo: 'wx_commit_999888',
        identifierCompleteness: 'COMPLETE',
      );

      const identifier = ConfirmedIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: 'wx_commit_999888',
        stableEventKind: 'payment',
        transactionId: 'tx_commit_ok',
      );

      final committed = await txManager.commitDraft(
        const CommitDraftRequest(
          transaction: tx,
          metadata: meta,
          tagIds: ['tag_lunch'],
          identifier: identifier,
        ),
        customExecutor: db,
      );

      expect(committed.id, equals('tx_commit_ok'));

      // Check transactions row
      final txRow = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_commit_ok'])).first;
      expect(txRow['amount_minor'], equals(3200));

      // Check metadata row
      final metaRow = (await db.query('transaction_metadata', where: 'transaction_id = ?', whereArgs: ['tx_commit_ok'])).first;
      expect(metaRow['discount_minor'], equals(800));

      // Check tags join row
      final tagRows = await db.query('transaction_tags', where: 'transaction_id = ?', whereArgs: ['tx_commit_ok']);
      expect(tagRows.length, equals(1));
      expect(tagRows.first['tag_id'], equals('tag_lunch'));

      // Check confirmed identifier row
      final idRows = await db.query('confirmed_identifiers', where: 'transaction_id = ?', whereArgs: ['tx_commit_ok']);
      expect(idRows.length, equals(1));
      expect(idRows.first['complete_value'], equals('wx_commit_999888'));

      // Check draft updated with saved_transaction_id
      final draftRow = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_commit_1'])).first;
      expect(draftRow['saved_transaction_id'], equals('tx_commit_ok'));

      // Check capture_jobs state transitioned to COMMITTED
      final jobRow = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_commit_1'])).first;
      expect(jobRow['state'], equals('COMMITTED'));
    });

    test('Rolls back entire transaction on constraint violation', () async {
      // Transaction with invalid amount_minor = 0 (fails CHECK constraint)
      const invalidTx = TransactionEntry(
        id: 'tx_fail_rollback',
        originDraftId: 'draft_commit_1',
        type: 'expense',
        amountMinor: 0, // Violates CHECK (amount_minor > 0)
        currency: 'CNY',
        merchantRaw: '非法商家',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_dining',
        createdAt: '2026-10-22T12:00:00Z',
        updatedAt: '2026-10-22T12:00:00Z',
      );

      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(transaction: invalidTx),
          customExecutor: db,
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Verify clean rollback: transactions row was not inserted
      final txRows = await db.query('transactions', where: 'id = ?', whereArgs: ['tx_fail_rollback']);
      expect(txRows, isEmpty);

      // Draft still has saved_transaction_id = NULL
      final draftRow = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_commit_1'])).first;
      expect(draftRow['saved_transaction_id'], isNull);

      // Capture job remains in NEEDS_REVIEW state
      final jobRow = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_commit_1'])).first;
      expect(jobRow['state'], equals('NEEDS_REVIEW'));
    });
  });
}
