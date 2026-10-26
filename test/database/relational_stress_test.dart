import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
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

  group('Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections)', () {
    setUp(() async {
      // Seed a capture job in NEEDS_REVIEW and a draft
      await db.insert('capture_jobs', {
        'id': 'job_stress_1',
        'content_hash': 'sha256_stress_1',
        'source_kind': 'photoPicker',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/stress_1.jpg',
        'state': 'NEEDS_REVIEW',
        'attempt_count': 1,
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('drafts', {
        'id': 'draft_stress_1',
        'capture_id': 'job_stress_1',
        'candidate_fields': '{"amountMinor": 3800}',
        'field_evidence': '{}',
        'validation_issues': '[]',
        'duplicate_candidates': '[]',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('categories', {
        'id': 'cat_valid',
        'name': '餐饮美食',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('tags', {
        'id': 'tag_valid_1',
        'name': '日常标签',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
    });

    test('1.1 Fail on invalid Category FK in commitDraft -> Zero partial rows remain', () async {
      const invalidTx = TransactionEntry(
        id: 'tx_bad_cat',
        originDraftId: 'draft_stress_1',
        type: 'expense',
        amountMinor: 3800,
        currency: 'CNY',
        merchantRaw: '非法分类商家',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_NON_EXISTENT', // Violates FOREIGN KEY(category_id)
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      const meta = TransactionMetadata(
        transactionId: 'tx_bad_cat',
        originalAmountMinor: 4000,
        discountMinor: 200,
        paymentStatus: 'SUCCESS',
      );

      const ident = ConfirmedIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: 'wx_bad_cat_12345',
        stableEventKind: 'payment',
        transactionId: 'tx_bad_cat',
      );

      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(
            transaction: invalidTx,
            metadata: meta,
            tagIds: ['tag_valid_1'],
            identifier: ident,
          ),
          customExecutor: db,
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Verify ZERO partial rows
      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_bad_cat']), isEmpty);
      expect(await db.query('transaction_metadata', where: 'transaction_id = ?', whereArgs: ['tx_bad_cat']), isEmpty);
      expect(await db.query('transaction_tags', where: 'transaction_id = ?', whereArgs: ['tx_bad_cat']), isEmpty);
      expect(await db.query('confirmed_identifiers', where: 'transaction_id = ?', whereArgs: ['tx_bad_cat']), isEmpty);

      // Verify draft and job state remain unchanged
      final draft = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_stress_1'])).first;
      expect(draft['saved_transaction_id'], isNull);

      final job = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_stress_1'])).first;
      expect(job['state'], equals('NEEDS_REVIEW'));
    });

    test('1.2 Fail on non-existent Tag FK (Step 6 failure) -> Zero partial rows remain', () async {
      const tx = TransactionEntry(
        id: 'tx_bad_tag',
        originDraftId: 'draft_stress_1',
        type: 'expense',
        amountMinor: 2500,
        currency: 'CNY',
        merchantRaw: '标签测试商家',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'alipay',
        categoryId: 'cat_valid',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      const meta = TransactionMetadata(
        transactionId: 'tx_bad_tag',
        originalAmountMinor: 2500,
        discountMinor: 0,
        paymentStatus: 'SUCCESS',
      );

      // tag_GHOST does not exist in tags table
      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(
            transaction: tx,
            metadata: meta,
            tagIds: ['tag_valid_1', 'tag_GHOST'],
          ),
          customExecutor: db,
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Transactions and metadata inserted earlier in transaction MUST be rolled back
      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_bad_tag']), isEmpty);
      expect(await db.query('transaction_metadata', where: 'transaction_id = ?', whereArgs: ['tx_bad_tag']), isEmpty);
      expect(await db.query('transaction_tags', where: 'transaction_id = ?', whereArgs: ['tx_bad_tag']), isEmpty);

      final draft = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_stress_1'])).first;
      expect(draft['saved_transaction_id'], isNull);

      final job = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_stress_1'])).first;
      expect(job['state'], equals('NEEDS_REVIEW'));
    });

    test('1.3 Fail on duplicate confirmed_identifier (pre-commit check) -> Zero partial rows', () async {
      // Seed an active existing transaction with this identifier
      await db.insert('transactions', {
        'id': 'tx_existing_owner',
        'type': 'expense',
        'amount_minor': 5000,
        'merchant_raw': '已有商户',
        'occurred_on': '2026-10-22',
        'event_time_source': 'user_confirmed',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_valid',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
      await db.insert('confirmed_identifiers', {
        'namespace': 'wechat_pay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'wx_hard_dup_99999',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_existing_owner',
      });

      const tx = TransactionEntry(
        id: 'tx_colliding',
        originDraftId: 'draft_stress_1',
        type: 'expense',
        amountMinor: 3800,
        currency: 'CNY',
        merchantRaw: '冲突商户',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_valid',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      const duplicateIdent = ConfirmedIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: 'wx_hard_dup_99999',
        stableEventKind: 'payment',
        transactionId: 'tx_colliding',
      );

      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(
            transaction: tx,
            identifier: duplicateIdent,
          ),
          customExecutor: db,
        ),
        throwsA(isA<HardDuplicateException>()),
      );

      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_colliding']), isEmpty);
      final draft = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_stress_1'])).first;
      expect(draft['saved_transaction_id'], isNull);
      final job = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_stress_1'])).first;
      expect(job['state'], equals('NEEDS_REVIEW'));
    });

    test('1.4 Fail on non-existent originalExpenseId in refund commitDraft -> Zero partial rows', () async {
      const refundTx = TransactionEntry(
        id: 'tx_refund_orphan',
        originDraftId: 'draft_stress_1',
        type: 'refund',
        amountMinor: 1500,
        currency: 'CNY',
        merchantRaw: '孤立退款',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_valid',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(
            transaction: refundTx,
            originalExpenseId: 'tx_NON_EXISTENT_EXPENSE', // FK failure on refund_links
          ),
          customExecutor: db,
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_refund_orphan']), isEmpty);
      expect(await db.query('refund_links', where: 'refund_transaction_id = ?', whereArgs: ['tx_refund_orphan']), isEmpty);
      final draft = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_stress_1'])).first;
      expect(draft['saved_transaction_id'], isNull);
      final job = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_stress_1'])).first;
      expect(job['state'], equals('NEEDS_REVIEW'));
    });

    test('1.5 Fail when job is in illegal state (RECOGNIZING) -> Rejection and rollback', () async {
      await db.update(
        'capture_jobs',
        {'state': 'RECOGNIZING'},
        where: 'id = ?',
        whereArgs: ['job_stress_1'],
      );

      const tx = TransactionEntry(
        id: 'tx_illegal_state',
        originDraftId: 'draft_stress_1',
        type: 'expense',
        amountMinor: 2000,
        currency: 'CNY',
        merchantRaw: '状态错误商户',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_valid',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(transaction: tx),
          customExecutor: db,
        ),
        throwsA(isA<InvalidStateTransitionException>()),
      );

      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_illegal_state']), isEmpty);
      final job = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_stress_1'])).first;
      expect(job['state'], equals('RECOGNIZING'));
    });

    test('1.6 Fail on duplicate tag in tagIds -> UNIQUE constraint failure and clean rollback', () async {
      const tx = TransactionEntry(
        id: 'tx_dup_tags',
        originDraftId: 'draft_stress_1',
        type: 'expense',
        amountMinor: 1500,
        currency: 'CNY',
        merchantRaw: '重复标签商家',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_valid',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      // Passing identical tagId twice violates PRIMARY KEY (transaction_id, tag_id)
      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(
            transaction: tx,
            tagIds: ['tag_valid_1', 'tag_valid_1'],
          ),
          customExecutor: db,
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Verify clean rollback of transaction row
      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_dup_tags']), isEmpty);
      expect(await db.query('transaction_tags', where: 'transaction_id = ?', whereArgs: ['tx_dup_tags']), isEmpty);
      final draft = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_stress_1'])).first;
      expect(draft['saved_transaction_id'], isNull);
      final job = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_stress_1'])).first;
      expect(job['state'], equals('NEEDS_REVIEW'));
    });

    test('1.7 Fail on TrashBinCollisionException -> Clean rollback', () async {
      // Seed a soft-deleted transaction in the trash bin
      await db.insert('transactions', {
        'id': 'tx_in_trash_bin',
        'type': 'expense',
        'amount_minor': 9900,
        'merchant_raw': '回收站商户',
        'occurred_on': '2026-10-20',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_valid',
        'created_at': '2026-10-20T10:00:00Z',
        'updated_at': '2026-10-21T10:00:00Z',
        'deleted_at': '2026-10-21T10:00:00Z',
      });
      await db.insert('confirmed_identifiers', {
        'namespace': 'wechat_pay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'wx_trash_collision_id_111',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_in_trash_bin',
      });

      const tx = TransactionEntry(
        id: 'tx_colliding_trash',
        originDraftId: 'draft_stress_1',
        type: 'expense',
        amountMinor: 3800,
        currency: 'CNY',
        merchantRaw: '冲突商户',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_valid',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );

      const ident = ConfirmedIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: 'wx_trash_collision_id_111',
        stableEventKind: 'payment',
        transactionId: 'tx_colliding_trash',
      );

      expect(
        () async => await txManager.commitDraft(
          const CommitDraftRequest(
            transaction: tx,
            identifier: ident,
          ),
          customExecutor: db,
        ),
        throwsA(isA<TrashBinCollisionException>()),
      );

      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_colliding_trash']), isEmpty);
      final draft = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_stress_1'])).first;
      expect(draft['saved_transaction_id'], isNull);
      final job = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_stress_1'])).first;
      expect(job['state'], equals('NEEDS_REVIEW'));
    });
  });


  group('Stress Suite 2: Refund Cascade & Unlinking Multi-Case Testing', () {
    setUp(() async {
      await db.insert('categories', {
        'id': 'cat_shopping',
        'name': '购物消费',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // Original expense: 10000 cents (100.00 CNY)
      await db.insert('transactions', {
        'id': 'tx_orig_parent',
        'type': 'expense',
        'amount_minor': 10000,
        'merchant_raw': '苹果授权专卖店',
        'occurred_on': '2026-10-10',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'alipay',
        'category_id': 'cat_shopping',
        'created_at': '2026-10-10T10:00:00Z',
        'updated_at': '2026-10-10T10:00:00Z',
      });

      // Refund 1: 3000 cents
      await db.insert('transactions', {
        'id': 'tx_refund_part1',
        'type': 'refund',
        'amount_minor': 3000,
        'merchant_raw': '苹果授权专卖店部分退款1',
        'occurred_on': '2026-10-12',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'alipay',
        'category_id': 'cat_shopping',
        'created_at': '2026-10-12T10:00:00Z',
        'updated_at': '2026-10-12T10:00:00Z',
      });

      // Refund 2: 2000 cents
      await db.insert('transactions', {
        'id': 'tx_refund_part2',
        'type': 'refund',
        'amount_minor': 2000,
        'merchant_raw': '苹果授权专卖店部分退款2',
        'occurred_on': '2026-10-14',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'alipay',
        'category_id': 'cat_shopping',
        'created_at': '2026-10-14T10:00:00Z',
        'updated_at': '2026-10-14T10:00:00Z',
      });

      // Link both refunds to original expense
      await db.insert('refund_links', {
        'refund_transaction_id': 'tx_refund_part1',
        'original_expense_id': 'tx_orig_parent',
        'created_at': '2026-10-12T10:00:00Z',
      });

      await db.insert('refund_links', {
        'refund_transaction_id': 'tx_refund_part2',
        'original_expense_id': 'tx_orig_parent',
        'created_at': '2026-10-14T10:00:00Z',
      });
    });

    test('2.1 Permanently deleting original expense unlinks all refunds while preserving them intact', () async {
      final deletedCount = await db.delete('transactions', where: 'id = ?', whereArgs: ['tx_orig_parent']);
      expect(deletedCount, equals(1));

      // All refund links pointing to original expense must be cascade-deleted
      final links = await db.query('refund_links', where: 'original_expense_id = ?', whereArgs: ['tx_orig_parent']);
      expect(links, isEmpty);

      // BOTH refund transactions MUST remain intact in transactions
      final refunds = await db.query(
        'transactions',
        where: 'id IN (?, ?)',
        whereArgs: ['tx_refund_part1', 'tx_refund_part2'],
        orderBy: 'id ASC',
      );
      expect(refunds.length, equals(2));
      expect(refunds[0]['id'], equals('tx_refund_part1'));
      expect(refunds[0]['amount_minor'], equals(3000));
      expect(refunds[1]['id'], equals('tx_refund_part2'));
      expect(refunds[1]['amount_minor'], equals(2000));
    });

    test('2.2 Permanently deleting a refund transaction unlinks its link but preserves original expense', () async {
      final deleted = await db.delete('transactions', where: 'id = ?', whereArgs: ['tx_refund_part1']);
      expect(deleted, equals(1));

      // Only tx_refund_part1 link was removed; tx_refund_part2 link remains
      final links = await db.query('refund_links', orderBy: 'refund_transaction_id ASC');
      expect(links.length, equals(1));
      expect(links.first['refund_transaction_id'], equals('tx_refund_part2'));

      // Original expense remains completely intact
      final orig = await db.query('transactions', where: 'id = ?', whereArgs: ['tx_orig_parent']);
      expect(orig.length, equals(1));
      expect(orig.first['amount_minor'], equals(10000));
    });

    test('2.3 Soft-deleting original expense preserves refund_links and enables trash recovery', () async {
      await SoftDeleteManager.softDeleteTransaction(db, 'tx_orig_parent');

      // refund_links is NOT deleted on soft-delete
      final links = await db.query('refund_links', where: 'original_expense_id = ?', whereArgs: ['tx_orig_parent']);
      expect(links.length, equals(2));

      // Monthly calculation excludes soft-deleted expense but includes active refunds
      final summaryBeforeRestore = await SoftDeleteManager.calculateMonthlySummary(
        db,
        startDate: '2026-10-01',
        endDate: '2026-10-31',
      );
      expect(summaryBeforeRestore.totalExpenseMinor, equals(0));
      expect(summaryBeforeRestore.totalRefundMinor, equals(5000));
      expect(summaryBeforeRestore.netExpenseMinor, equals(-5000));

      // Restore expense
      await SoftDeleteManager.restoreTransaction(db, 'tx_orig_parent');
      final summaryAfterRestore = await SoftDeleteManager.calculateMonthlySummary(
        db,
        startDate: '2026-10-01',
        endDate: '2026-10-31',
      );
      expect(summaryAfterRestore.totalExpenseMinor, equals(10000));
      expect(summaryAfterRestore.totalRefundMinor, equals(5000));
      expect(summaryAfterRestore.netExpenseMinor, equals(5000));
    });

    test('2.4 Direct invalid insert into refund_links violates foreign key constraints', () async {
      // Non-existent original_expense_id
      expect(
        () async => await db.insert('refund_links', {
          'refund_transaction_id': 'tx_refund_part1',
          'original_expense_id': 'tx_DOES_NOT_EXIST',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );

      // Duplicate refund_transaction_id (Primary Key constraint)
      expect(
        () async => await db.insert('refund_links', {
          'refund_transaction_id': 'tx_refund_part1', // Already in refund_links
          'original_expense_id': 'tx_orig_parent',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('2.5 Purging expired trash transaction unlinks refund_links while preserving refund intact', () async {
      // Soft-delete tx_orig_parent with timestamp 35 days ago
      final oldTrashDate = DateTime.now().toUtc().subtract(const Duration(days: 35)).toIso8601String();
      await db.update(
        'transactions',
        {'deleted_at': oldTrashDate, 'updated_at': oldTrashDate},
        where: 'id = ?',
        whereArgs: ['tx_orig_parent'],
      );

      // Verify refund_links still exist before purge
      final linksBefore = await db.query('refund_links', where: 'original_expense_id = ?', whereArgs: ['tx_orig_parent']);
      expect(linksBefore.length, equals(2));

      // Purge expired trash
      final purgedCount = await SoftDeleteManager.purgeExpiredTrash(db, retentionDays: 30);
      expect(purgedCount, equals(1));

      // Original expense must be permanently gone
      expect(await db.query('transactions', where: 'id = ?', whereArgs: ['tx_orig_parent']), isEmpty);

      // refund_links MUST be cascade deleted
      expect(await db.query('refund_links', where: 'original_expense_id = ?', whereArgs: ['tx_orig_parent']), isEmpty);

      // Both refunds must remain in transactions intact
      final refunds = await db.query('transactions', where: 'id IN (?, ?)', whereArgs: ['tx_refund_part1', 'tx_refund_part2']);
      expect(refunds.length, equals(2));
    });
  });


  group('Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing', () {
    setUp(() async {
      await db.insert('accounts', {
        'id': 'acc_debit',
        'name': '工行卡',
        'kind': 'debit_card',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
      await db.insert('accounts', {
        'id': 'acc_transfer_target',
        'name': '招行卡',
        'kind': 'debit_card',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('categories', {
        'id': 'cat_lvl1',
        'name': '一级分类',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
      await db.insert('categories', {
        'id': 'cat_lvl2',
        'name': '二级分类',
        'parent_id': 'cat_lvl1',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
      await db.insert('categories', {
        'id': 'cat_lvl3',
        'name': '三级分类',
        'parent_id': 'cat_lvl2',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('projects', {
        'id': 'proj_fk_test',
        'name': '项目测试',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('tags', {
        'id': 'tag_fk_test',
        'name': '标签测试',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('transactions', {
        'id': 'tx_fk_hub',
        'type': 'transfer',
        'amount_minor': 50000,
        'merchant_raw': '内部转账',
        'occurred_on': '2026-10-22',
        'event_time_source': 'user_confirmed',
        'event_time_precision': 'minute',
        'payment_channel': 'unionpay',
        'account_id': 'acc_debit',
        'transfer_to_account_id': 'acc_transfer_target',
        'category_id': 'cat_lvl3',
        'project_id': 'proj_fk_test',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('transaction_tags', {
        'transaction_id': 'tx_fk_hub',
        'tag_id': 'tag_fk_test',
      });

      await db.insert('transaction_metadata', {
        'transaction_id': 'tx_fk_hub',
        'payment_status': 'SUCCESS',
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'unionpay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'up_99887766',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_fk_hub',
      });

      await db.insert('classification_rules', {
        'id': 'rule_fk_test',
        'priority': 50,
        'merchant_pattern': '内部%',
        'category_id': 'cat_lvl3',
        'project_id': 'proj_fk_test',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
    });

    test('3.1 Category ON DELETE RESTRICT blocks deletion of leaf and intermediate nodes', () async {
      // cat_lvl3 is directly referenced by tx_fk_hub
      expect(
        () async => await db.delete('categories', where: 'id = ?', whereArgs: ['cat_lvl3']),
        throwsA(isA<DatabaseException>()),
      );

      // Unused category can be deleted freely
      await db.insert('categories', {
        'id': 'cat_unused',
        'name': '未引用分类',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });
      final deleted = await db.delete('categories', where: 'id = ?', whereArgs: ['cat_unused']);
      expect(deleted, equals(1));
    });

    test('3.2 Category ON DELETE SET NULL cascades down hierarchical chain', () async {
      // Deleting top-level cat_lvl1
      await db.delete('categories', where: 'id = ?', whereArgs: ['cat_lvl1']);

      // cat_lvl2.parent_id should now be NULL
      final lvl2 = (await db.query('categories', where: 'id = ?', whereArgs: ['cat_lvl2'])).first;
      expect(lvl2['parent_id'], isNull);

      // cat_lvl3.parent_id should STILL be cat_lvl2
      final lvl3 = (await db.query('categories', where: 'id = ?', whereArgs: ['cat_lvl3'])).first;
      expect(lvl3['parent_id'], equals('cat_lvl2'));
    });

    test('3.3 Account ON DELETE SET NULL clears both account_id and transfer_to_account_id', () async {
      await db.delete('accounts', where: 'id = ?', whereArgs: ['acc_debit']);
      var tx = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_fk_hub'])).first;
      expect(tx['account_id'], isNull);
      expect(tx['transfer_to_account_id'], equals('acc_transfer_target'));

      await db.delete('accounts', where: 'id = ?', whereArgs: ['acc_transfer_target']);
      tx = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_fk_hub'])).first;
      expect(tx['transfer_to_account_id'], isNull);
    });

    test('3.4 Project ON DELETE SET NULL clears project_id in both transactions and classification_rules', () async {
      await db.delete('projects', where: 'id = ?', whereArgs: ['proj_fk_test']);

      final tx = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_fk_hub'])).first;
      expect(tx['project_id'], isNull);

      final rule = (await db.query('classification_rules', where: 'id = ?', whereArgs: ['rule_fk_test'])).first;
      expect(rule['project_id'], isNull);
    });

    test('3.5 Tag ON DELETE CASCADE cleans transaction_tags without deleting transaction', () async {
      await db.delete('tags', where: 'id = ?', whereArgs: ['tag_fk_test']);

      final joinRows = await db.query('transaction_tags', where: 'tag_id = ?', whereArgs: ['tag_fk_test']);
      expect(joinRows, isEmpty);

      final tx = await db.query('transactions', where: 'id = ?', whereArgs: ['tx_fk_hub']);
      expect(tx.length, equals(1));
    });

    test('3.6 Transaction permanent delete cascades metadata, tags, and confirmed identifiers', () async {
      await db.delete('transactions', where: 'id = ?', whereArgs: ['tx_fk_hub']);

      expect(await db.query('transaction_metadata', where: 'transaction_id = ?', whereArgs: ['tx_fk_hub']), isEmpty);
      expect(await db.query('transaction_tags', where: 'transaction_id = ?', whereArgs: ['tx_fk_hub']), isEmpty);
      expect(await db.query('confirmed_identifiers', where: 'transaction_id = ?', whereArgs: ['tx_fk_hub']), isEmpty);
    });

    test('3.7 CHECK (amount_minor > 0) strictly tested across INSERT and UPDATE', () async {
      // 0 cents on insert
      expect(
        () async => await db.insert('transactions', {
          'id': 'tx_zero_test',
          'type': 'expense',
          'amount_minor': 0,
          'merchant_raw': '测试',
          'occurred_on': '2026-10-22',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'day',
          'payment_channel': 'cash',
          'created_at': '2026-10-22T10:00:00Z',
          'updated_at': '2026-10-22T10:00:00Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      // -100 cents on insert
      expect(
        () async => await db.insert('transactions', {
          'id': 'tx_neg_test',
          'type': 'expense',
          'amount_minor': -100,
          'merchant_raw': '测试',
          'occurred_on': '2026-10-22',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'day',
          'payment_channel': 'cash',
          'created_at': '2026-10-22T10:00:00Z',
          'updated_at': '2026-10-22T10:00:00Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      // Updating an existing valid transaction to 0 cents
      expect(
        () async => await db.update(
          'transactions',
          {'amount_minor': 0},
          where: 'id = ?',
          whereArgs: ['tx_fk_hub'],
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Updating an existing valid transaction to negative cents
      expect(
        () async => await db.update(
          'transactions',
          {'amount_minor': -9999},
          where: 'id = ?',
          whereArgs: ['tx_fk_hub'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('3.8 CaptureJob ON DELETE CASCADE cascades to drafts, and drafts unlinks origin_draft_id', () async {
      await db.insert('capture_jobs', {
        'id': 'job_cascade_test',
        'content_hash': 'hash_cascade',
        'source_kind': 'photoPicker',
        'imported_at': '2026-10-22T10:00:00Z',
        'private_image_ref': 'captures/cascade.jpg',
        'state': 'NEEDS_REVIEW',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('drafts', {
        'id': 'draft_cascade_test',
        'capture_id': 'job_cascade_test',
        'candidate_fields': '{}',
        'field_evidence': '{}',
        'validation_issues': '[]',
        'duplicate_candidates': '[]',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('transactions', {
        'id': 'tx_linked_draft',
        'origin_draft_id': 'draft_cascade_test',
        'type': 'expense',
        'amount_minor': 4900,
        'merchant_raw': '级联商户',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'wechat',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // Deleting capture_jobs must cascade delete draft
      await db.delete('capture_jobs', where: 'id = ?', whereArgs: ['job_cascade_test']);
      final drafts = await db.query('drafts', where: 'id = ?', whereArgs: ['draft_cascade_test']);
      expect(drafts, isEmpty, reason: 'draft must be cascade-deleted with capture_job');

      // Draft deletion must SET NULL on transaction.origin_draft_id
      final tx = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_linked_draft'])).first;
      expect(tx['origin_draft_id'], isNull, reason: 'origin_draft_id must be SET NULL when draft is deleted');
    });

    test('3.9 Classification rule CASCADE deletion when referenced category has no transactions', () async {
      await db.insert('categories', {
        'id': 'cat_rules_only',
        'name': '纯规则分类',
        'applicable_type': 'expense',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      await db.insert('classification_rules', {
        'id': 'rule_cascade_cat',
        'priority': 80,
        'merchant_pattern': '规则级联%',
        'category_id': 'cat_rules_only',
        'created_at': '2026-10-22T10:00:00Z',
        'updated_at': '2026-10-22T10:00:00Z',
      });

      // Category has no transactions, so deleting it must CASCADE delete classification_rules
      final deleted = await db.delete('categories', where: 'id = ?', whereArgs: ['cat_rules_only']);
      expect(deleted, equals(1));

      final rules = await db.query('classification_rules', where: 'id = ?', whereArgs: ['rule_cascade_cat']);
      expect(rules, isEmpty, reason: 'classification_rules must be cascade-deleted when category is deleted');
    });

    test('3.10 Category ON DELETE RESTRICT prevents cascade deletion of classification_rules when transaction exists', () async {
      // rule_fk_test references cat_lvl3, which is also referenced by tx_fk_hub
      // Attempting to delete cat_lvl3 must throw RESTRICT error, protecting both transaction and rule
      expect(
        () async => await db.delete('categories', where: 'id = ?', whereArgs: ['cat_lvl3']),
        throwsA(isA<DatabaseException>()),
      );

      final rules = await db.query('classification_rules', where: 'id = ?', whereArgs: ['rule_fk_test']);
      expect(rules.length, equals(1), reason: 'Rule must remain untouched because category deletion failed');
    });
  });
}

