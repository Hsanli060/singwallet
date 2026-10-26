// test/deduplication/deduplication_adversarial_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/state_machine.dart';
import 'package:singwallet/data/database/transaction_manager.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DeduplicationEngine engine;
  late TransactionManager txManager;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    engine = DeduplicationEngine(db);
    txManager = TransactionManager(AppDatabase.instance);

    // Seed basic category
    await db.insert('categories', {
      'id': 'cat_dining',
      'name': '餐饮美食',
      'applicable_type': 'expense',
      'created_at': '2026-10-22T00:00:00Z',
      'updated_at': '2026-10-22T00:00:00Z',
    });
  });

  tearDown(() async {
    await db.close();
  });

  // Helper to create a valid capture job & draft in NEEDS_REVIEW state
  Future<void> seedJobAndDraft({
    required String jobId,
    required String draftId,
    required String contentHash,
    CaptureJobState jobState = CaptureJobState.needsReview,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('capture_jobs', {
      'id': jobId,
      'content_hash': contentHash,
      'source_kind': 'photoPicker',
      'imported_at': now,
      'private_image_ref': 'captures/$jobId.jpg',
      'state': jobState.value,
      'attempt_count': 1,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert('drafts', {
      'id': draftId,
      'capture_id': jobId,
      'candidate_fields': '{"merchant":"星巴克","amountMinor":3800}',
      'field_evidence': '{}',
      'validation_issues': '[]',
      'duplicate_candidates': '[]',
      'saved_transaction_id': null,
      'created_at': now,
      'updated_at': now,
    });
  }

  // =========================================================================
  // TIER 1: TECHNICAL IDEMPOTENCE STRESS & ADVERSARIAL CHALLENGES
  // =========================================================================
  group('Adversarial Challenge Tier 1: Technical Idempotence', () {
    test('1.1: Committing the exact same origin_draft_id twice is blocked and rolls back atomically', () async {
      await seedJobAndDraft(
        jobId: 'job_tier1_1',
        draftId: 'draft_tier1_1',
        contentHash: 'hash_tier1_1',
      );

      final now = DateTime.now().toUtc().toIso8601String();
      final req1 = CommitDraftRequest(
        transaction: TransactionEntry(
          id: 'tx_tier1_1',
          originDraftId: 'draft_tier1_1',
          type: 'expense',
          amountMinor: 3800,
          merchantRaw: '星巴克',
          occurredOn: '2026-10-22',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'minute',
          paymentChannel: 'wechat',
          categoryId: 'cat_dining',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 1st commit: succeeds cleanly
      final committedTx = await txManager.commitDraft(req1, customExecutor: db);
      expect(committedTx.id, equals('tx_tier1_1'));

      // Verify draft saved_transaction_id is updated and job is COMMITTED
      final draftRow = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_tier1_1'])).first;
      expect(draftRow['saved_transaction_id'], equals('tx_tier1_1'));

      final jobRow = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_tier1_1'])).first;
      expect(jobRow['state'], equals('COMMITTED'));

      // 2nd commit with same draft: MUST throw DraftAlreadyCommittedException or DuplicateTransactionException
      final req2 = CommitDraftRequest(
        transaction: TransactionEntry(
          id: 'tx_tier1_2',
          originDraftId: 'draft_tier1_1', // Re-attempt with same origin draft
          type: 'expense',
          amountMinor: 3800,
          merchantRaw: '星巴克',
          occurredOn: '2026-10-22',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'minute',
          paymentChannel: 'wechat',
          categoryId: 'cat_dining',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        () async => await txManager.commitDraft(req2, customExecutor: db),
        throwsA(isA<DraftAlreadyCommittedException>()),
      );

      // Verify no second transaction was inserted
      final txRows = await db.query('transactions', where: 'origin_draft_id = ?', whereArgs: ['draft_tier1_1']);
      expect(txRows.length, equals(1));
      expect(txRows.first['id'], equals('tx_tier1_1'));
    });

    test('1.2: Direct raw SQLite INSERT of duplicate origin_draft_id is blocked by UNIQUE constraint', () async {
      await seedJobAndDraft(
        jobId: 'job_tier1_raw',
        draftId: 'draft_tier1_raw',
        contentHash: 'hash_tier1_raw',
      );

      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('transactions', {
        'id': 'tx_raw_1',
        'origin_draft_id': 'draft_tier1_raw',
        'type': 'expense',
        'amount_minor': 3000,
        'currency': 'CNY',
        'merchant_raw': 'Costa Coffee',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      // Direct second insert with identical origin_draft_id
      expect(
        () async => await db.insert('transactions', {
          'id': 'tx_raw_2',
          'origin_draft_id': 'draft_tier1_raw', // DUPLICATE
          'type': 'expense',
          'amount_minor': 3000,
          'currency': 'CNY',
          'merchant_raw': 'Costa Coffee',
          'occurred_on': '2026-10-22',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'minute',
          'payment_channel': 'alipay',
          'category_id': 'cat_dining',
          'created_at': now,
          'updated_at': now,
        }),
        throwsA(isA<DatabaseException>()),
      );

      final rows = await db.query('transactions', where: 'origin_draft_id = ?', whereArgs: ['draft_tier1_raw']);
      expect(rows.length, equals(1));
    });

    test('1.3: Concurrency / race simulation: Parallel commitDraft calls on same origin_draft_id allow exactly 1 success', () async {
      await seedJobAndDraft(
        jobId: 'job_tier1_race',
        draftId: 'draft_tier1_race',
        contentHash: 'hash_tier1_race',
      );

      int successCount = 0;
      int errorCount = 0;
      final now = DateTime.now().toUtc().toIso8601String();

      final futures = List.generate(5, (index) async {
        try {
          await txManager.commitDraft(
            CommitDraftRequest(
              transaction: TransactionEntry(
                id: 'tx_race_$index',
                originDraftId: 'draft_tier1_race',
                type: 'expense',
                amountMinor: 2500,
                merchantRaw: 'Cafe $index',
                occurredOn: '2026-10-22',
                eventTimeSource: 'ocr_extracted',
                eventTimePrecision: 'minute',
                paymentChannel: 'wechat',
                categoryId: 'cat_dining',
                createdAt: now,
                updatedAt: now,
              ),
            ),
            customExecutor: db,
          );
          successCount++;
        } catch (_) {
          errorCount++;
        }
      });

      await Future.wait(futures);

      expect(successCount, equals(1));
      expect(errorCount, equals(4));

      final rows = await db.query('transactions', where: 'origin_draft_id = ?', whereArgs: ['draft_tier1_race']);
      expect(rows.length, equals(1));
    });

    test('1.4: Null origin_draft_id allows multiple manual transactions without UNIQUE collision', () async {
      final now = DateTime.now().toUtc().toIso8601String();
      for (int i = 0; i < 3; i++) {
        await db.insert('transactions', {
          'id': 'tx_manual_$i',
          'origin_draft_id': null, // Manual entries have null draft IDs
          'type': 'expense',
          'amount_minor': 1000 * (i + 1),
          'currency': 'CNY',
          'merchant_raw': 'Manual Merchant $i',
          'occurred_on': '2026-10-22',
          'event_time_source': 'user_selected',
          'event_time_precision': 'day',
          'payment_channel': 'cash',
          'category_id': 'cat_dining',
          'created_at': now,
          'updated_at': now,
        });
      }

      final rows = await db.query('transactions', where: 'origin_draft_id IS NULL');
      expect(rows.length, equals(3));
    });
  });

  // =========================================================================
  // TIER 2: IMAGE SHA-256 HASH MATCHING ACROSS JOBS
  // =========================================================================
  group('Adversarial Challenge Tier 2: Image SHA-256 Hash Matching', () {
    test('2.1: Identical SHA-256 content hashes detected across multiple capture jobs', () async {
      const identicalHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      // Job 1 committed to a transaction
      await seedJobAndDraft(
        jobId: 'job_hash_1',
        draftId: 'draft_hash_1',
        contentHash: identicalHash,
        jobState: CaptureJobState.committed,
      );

      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('transactions', {
        'id': 'tx_hash_1',
        'origin_draft_id': 'draft_hash_1',
        'type': 'expense',
        'amount_minor': 5000,
        'currency': 'CNY',
        'merchant_raw': 'Bookstore',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      await db.update('drafts', {'saved_transaction_id': 'tx_hash_1'}, where: 'id = ?', whereArgs: ['draft_hash_1']);

      // New ingestion with identical image hash
      final res = await engine.checkTier2ImageHash(identicalHash);

      expect(res.isMatched, isTrue);
      expect(res.existingJobId, equals('job_hash_1'));
      expect(res.jobState, equals('COMMITTED'));
      expect(res.existingDraftId, equals('draft_hash_1'));
      expect(res.existingTransactionId, equals('tx_hash_1'));
      expect(res.isTransactionInTrash, isFalse);
    });

    test('2.2: Image hash matching when existing transaction has been soft-deleted', () async {
      const trashedImageHash = 'hash_image_trashed_999';

      await seedJobAndDraft(
        jobId: 'job_hash_trashed',
        draftId: 'draft_hash_trashed',
        contentHash: trashedImageHash,
        jobState: CaptureJobState.committed,
      );

      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('transactions', {
        'id': 'tx_hash_trashed',
        'origin_draft_id': 'draft_hash_trashed',
        'type': 'expense',
        'amount_minor': 8800,
        'currency': 'CNY',
        'merchant_raw': 'Steakhouse',
        'occurred_on': '2026-10-21',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now, // In trash bin
      });

      await db.update('drafts', {'saved_transaction_id': 'tx_hash_trashed'}, where: 'id = ?', whereArgs: ['draft_hash_trashed']);

      final res = await engine.checkTier2ImageHash(trashedImageHash);

      expect(res.isMatched, isTrue);
      expect(res.existingTransactionId, equals('tx_hash_trashed'));
      expect(res.isTransactionInTrash, isTrue);
    });

    test('2.3: Non-existent image hash returns clean miss', () async {
      final res = await engine.checkTier2ImageHash('sha256_unseen_image_12345');
      expect(res.isMatched, isFalse);
      expect(res.existingJobId, isNull);
      expect(res.existingTransactionId, isNull);
    });
  });

  // =========================================================================
  // TIER 3: HARD PLATFORM TRANSACTION IDENTIFIER & COMPOUND PK STRESS
  // =========================================================================
  group('Adversarial Challenge Tier 3: Hard Platform Identifier & Compound PK', () {
    test('3.1: Compound PK (namespace, identifier_type, complete_value, stable_event_kind) uniqueness in SQLite', () async {
      final now = DateTime.now().toUtc().toIso8601String();

      // Insert transaction 1
      await db.insert('transactions', {
        'id': 'tx_cpk_1',
        'type': 'expense',
        'amount_minor': 10000,
        'currency': 'CNY',
        'merchant_raw': 'Apple Store',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      // Insert confirmed_identifier 1
      await db.insert('confirmed_identifiers', {
        'namespace': 'alipay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': '20261022220014999901',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_cpk_1',
      });

      // Insert transaction 2
      await db.insert('transactions', {
        'id': 'tx_cpk_2',
        'type': 'expense',
        'amount_minor': 10000,
        'currency': 'CNY',
        'merchant_raw': 'Apple Store',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      // Attempting to insert identical compound PK for transaction 2 MUST throw SQLite constraint error
      expect(
        () async => await db.insert('confirmed_identifiers', {
          'namespace': 'alipay',
          'identifier_type': 'platform_transaction_no',
          'complete_value': '20261022220014999901',
          'stable_event_kind': 'payment',
          'transaction_id': 'tx_cpk_2',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('3.2: Different namespace or identifier_type with same order number do NOT collide', () async {
      final now = DateTime.now().toUtc().toIso8601String();

      await db.insert('transactions', {
        'id': 'tx_multi_ns_1',
        'type': 'expense',
        'amount_minor': 5000,
        'currency': 'CNY',
        'merchant_raw': 'Merchant A',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('transactions', {
        'id': 'tx_multi_ns_2',
        'type': 'expense',
        'amount_minor': 5000,
        'currency': 'CNY',
        'merchant_raw': 'Merchant B',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      // Same order number, different namespaces: wechat_pay vs alipay
      await db.insert('confirmed_identifiers', {
        'namespace': 'wechat_pay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'SAME_ORDER_12345',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_multi_ns_1',
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'alipay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'SAME_ORDER_12345',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_multi_ns_2',
      });

      // Same namespace and order, different identifier_type: merchant_order_no
      await db.insert('transactions', {
        'id': 'tx_multi_ns_3',
        'type': 'expense',
        'amount_minor': 5000,
        'currency': 'CNY',
        'merchant_raw': 'Merchant C',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'alipay',
        'identifier_type': 'merchant_order_no', // different identifier_type
        'complete_value': 'SAME_ORDER_12345',
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_multi_ns_3',
      });

      final rows = await db.query('confirmed_identifiers', where: 'complete_value = ?', whereArgs: ['SAME_ORDER_12345']);
      expect(rows.length, equals(3));
    });

    test('3.3: Incomplete, masked, truncated, and unreliable identifiers are strictly excluded from Tier 3 hard uniqueness', () async {
      for (final incompleteKind in [
        IdentifierCompleteness.masked,
        IdentifierCompleteness.truncated,
        IdentifierCompleteness.unreliable,
        IdentifierCompleteness.none,
      ]) {
        final id = PlatformIdentifier(
          namespace: 'wechat_pay',
          identifierType: 'platform_transaction_no',
          completeValue: '420000****7890',
          stableEventKind: 'payment',
          completeness: incompleteKind,
        );

        expect(id.isEligibleForHardDedup, isFalse, reason: 'Completeness $incompleteKind must NOT be eligible for hard dedup');

        final res = await engine.checkTier3PlatformId(id);
        expect(res.isMatched, isFalse, reason: 'checkTier3PlatformId must return miss for completeness $incompleteKind');
      }

      // Empty completeValue is also excluded even if completeness says complete
      final emptyId = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '   ',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.complete,
      );
      expect(emptyId.isEligibleForHardDedup, isFalse);
    });

    test('3.4: Refund vs payment distinction: refund referencing original payment order number does NOT collide', () async {
      const orderNo = '420000202610229876543210';
      final now = DateTime.now().toUtc().toIso8601String();

      // Original Payment Transaction
      await db.insert('transactions', {
        'id': 'tx_pay_original',
        'type': 'expense',
        'amount_minor': 19900,
        'currency': 'CNY',
        'merchant_raw': 'Uniqlo',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'wechat_pay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': orderNo,
        'stable_event_kind': 'payment', // PAYMENT
        'transaction_id': 'tx_pay_original',
      });

      // Checking refund with same order number against payment MUST NOT MATCH
      final refundCheck = await engine.checkTier3PlatformId(PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: orderNo,
        stableEventKind: 'refund', // REFUND
      ));

      expect(refundCheck.isMatched, isFalse);

      // Seed draft for refund
      await seedJobAndDraft(
        jobId: 'job_refund_1',
        draftId: 'draft_refund_1',
        contentHash: 'hash_refund_1',
      );

      // Commit refund via TransactionManager
      final refundReq = CommitDraftRequest(
        transaction: TransactionEntry(
          id: 'tx_refund_1',
          originDraftId: 'draft_refund_1',
          type: 'refund',
          amountMinor: 19900,
          merchantRaw: 'Uniqlo',
          occurredOn: '2026-10-22',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'minute',
          paymentChannel: 'wechat',
          categoryId: 'cat_dining',
          createdAt: now,
          updatedAt: now,
        ),
        identifier: const ConfirmedIdentifier(
          namespace: 'wechat_pay',
          identifierType: 'platform_transaction_no',
          completeValue: orderNo,
          stableEventKind: 'refund', // REFUND KIND
          transactionId: 'tx_refund_1',
        ),
        originalExpenseId: 'tx_pay_original',
      );

      final committedRefund = await txManager.commitDraft(refundReq, customExecutor: db);
      expect(committedRefund.id, equals('tx_refund_1'));

      // Both payment and refund coexist in confirmed_identifiers
      final idRows = await db.query('confirmed_identifiers', where: 'complete_value = ?', whereArgs: [orderNo]);
      expect(idRows.length, equals(2));

      // Attempting to commit a duplicate refund for the same order number MUST be blocked
      await seedJobAndDraft(
        jobId: 'job_refund_dup',
        draftId: 'draft_refund_dup',
        contentHash: 'hash_refund_dup',
      );

      final duplicateRefundReq = CommitDraftRequest(
        transaction: TransactionEntry(
          id: 'tx_refund_dup',
          originDraftId: 'draft_refund_dup',
          type: 'refund',
          amountMinor: 19900,
          merchantRaw: 'Uniqlo',
          occurredOn: '2026-10-22',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'minute',
          paymentChannel: 'wechat',
          categoryId: 'cat_dining',
          createdAt: now,
          updatedAt: now,
        ),
        identifier: const ConfirmedIdentifier(
          namespace: 'wechat_pay',
          identifierType: 'platform_transaction_no',
          completeValue: orderNo,
          stableEventKind: 'refund',
          transactionId: 'tx_refund_dup',
        ),
        originalExpenseId: 'tx_pay_original',
      );

      expect(
        () async => await txManager.commitDraft(duplicateRefundReq, customExecutor: db),
        throwsA(isA<HardDuplicateException>()),
      );
    });

    test('3.5: Soft-deleted item detection prompts for restoration and avoids duplicate creation', () async {
      const orderNo = '20261022220014888888';
      final now = DateTime.now().toUtc().toIso8601String();

      // Seed soft-deleted transaction in 30-day trash bin
      await db.insert('transactions', {
        'id': 'tx_trashed_target',
        'type': 'expense',
        'amount_minor': 6600,
        'currency': 'CNY',
        'merchant_raw': 'HeyTea',
        'occurred_on': '2026-10-21',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now, // IN TRASH
      });

      await db.insert('confirmed_identifiers', {
        'namespace': 'alipay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': orderNo,
        'stable_event_kind': 'payment',
        'transaction_id': 'tx_trashed_target',
      });

      // 1. DeduplicationEngine detects trashBinDuplicate
      final t3Res = await engine.checkTier3PlatformId(PlatformIdentifier(
        namespace: 'alipay',
        identifierType: 'platform_transaction_no',
        completeValue: orderNo,
        stableEventKind: 'payment',
      ));

      expect(t3Res.isMatched, isTrue);
      expect(t3Res.isInTrash, isTrue);
      expect(t3Res.matchedTransactionId, equals('tx_trashed_target'));

      // 2. Commit attempt throws TrashBinCollisionException
      await seedJobAndDraft(
        jobId: 'job_restore_test',
        draftId: 'draft_restore_test',
        contentHash: 'hash_restore_test',
      );

      final req = CommitDraftRequest(
        transaction: TransactionEntry(
          id: 'tx_new_incoming',
          originDraftId: 'draft_restore_test',
          type: 'expense',
          amountMinor: 6600,
          merchantRaw: 'HeyTea',
          occurredOn: '2026-10-21',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'minute',
          paymentChannel: 'alipay',
          categoryId: 'cat_dining',
          createdAt: now,
          updatedAt: now,
        ),
        identifier: const ConfirmedIdentifier(
          namespace: 'alipay',
          identifierType: 'platform_transaction_no',
          completeValue: orderNo,
          stableEventKind: 'payment',
          transactionId: 'tx_new_incoming',
        ),
      );

      expect(
        () async => await txManager.commitDraft(req, customExecutor: db),
        throwsA(isA<TrashBinCollisionException>()),
      );

      // 3. Application restores original transaction from trash instead of duplicating
      final restoreSuccess = await txManager.restoreFromTrash(
        'tx_trashed_target',
        targetDraftId: 'draft_restore_test',
        customExecutor: db,
      );
      expect(restoreSuccess, isTrue);

      // Verify restored transaction is active (deleted_at IS NULL)
      final restoredTx = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_trashed_target'])).first;
      expect(restoredTx['deleted_at'], isNull);

      // Verify draft linked to restored transaction and job is COMMITTED
      final draftRow = (await db.query('drafts', where: 'id = ?', whereArgs: ['draft_restore_test'])).first;
      expect(draftRow['saved_transaction_id'], equals('tx_trashed_target'));

      final jobRow = (await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_restore_test'])).first;
      expect(jobRow['state'], equals('COMMITTED'));

      // Exactly 1 transaction exists in transactions table
      final allTx = await db.query('transactions', where: 'id LIKE ?', whereArgs: ['%target%']);
      expect(allTx.length, equals(1));
    });
  });

  // =========================================================================
  // TIER 4: HEURISTIC FUZZY MATCHING BOUNDARY & ADVERSARIAL CHALLENGES
  // =========================================================================
  group('Adversarial Challenge Tier 4: Heuristic Fuzzy Matching Boundary', () {
    setUp(() async {
      const baseTime = '2026-10-22T12:00:00Z';
      await db.insert('transactions', {
        'id': 'tx_fuzzy_base',
        'type': 'expense',
        'amount_minor': 4500,
        'currency': 'CNY',
        'merchant_raw': '星巴克咖啡（国贸旗舰店）',
        'merchant_normalized': '星巴克',
        'occurred_on': '2026-10-22',
        'occurred_at': baseTime,
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'second',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': baseTime,
        'updated_at': baseTime,
        'deleted_at': null,
      });
    });

    test('4.1a: Boundary stress: 23 hours 59 minutes later MATCHES (within 24h window)', () async {
      // 2026-10-23T11:59:00Z (23h 59m later)
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-23',
        occurredAt: '2026-10-23T11:59:00Z',
      );

      expect(res.hasSuspectedDuplicates, isTrue);
      expect(res.candidateTransactionIds, contains('tx_fuzzy_base'));
    });

    test('4.1b: Boundary stress: Exactly 24 hours 00 minutes later MATCHES (inclusive boundary)', () async {
      // 2026-10-23T12:00:00Z (exact 24h delta)
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-23',
        occurredAt: '2026-10-23T12:00:00Z',
      );

      expect(res.hasSuspectedDuplicates, isTrue);
      expect(res.candidateTransactionIds, contains('tx_fuzzy_base'));
    });

    test('4.1c: Boundary stress: 24 hours 01 minutes later DOES NOT MATCH (> 24h window)', () async {
      // 2026-10-23T12:01:00Z (24h 01m later)
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-23',
        occurredAt: '2026-10-23T12:01:00Z',
      );

      expect(res.hasSuspectedDuplicates, isFalse);
      expect(res.candidateTransactionIds, isEmpty);
    });

    test('4.1d: Backward boundary stress: 23 hours 59 minutes earlier MATCHES (within 24h window)', () async {
      // 2026-10-21T12:01:00Z (23h 59m earlier)
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-21',
        occurredAt: '2026-10-21T12:01:00Z',
      );

      expect(res.hasSuspectedDuplicates, isTrue);
      expect(res.candidateTransactionIds, contains('tx_fuzzy_base'));
    });

    test('4.1e: Backward boundary stress: 24 hours 01 minutes earlier DOES NOT MATCH (> 24h window)', () async {
      // 2026-10-21T11:59:00Z (24h 01m earlier)
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-21',
        occurredAt: '2026-10-21T11:59:00Z',
      );

      expect(res.hasSuspectedDuplicates, isFalse);
      expect(res.candidateTransactionIds, isEmpty);
    });

    test('4.2: Merchant matching behavior: exact raw, normalized, cross-match, whitespace, and case sensitivity', () async {
      // Raw matches DB Raw
      final res1 = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克咖啡（国贸旗舰店）',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T13:00:00Z',
      );
      expect(res1.hasSuspectedDuplicates, isTrue);

      // Normalized matches DB Normalized
      final res2 = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克（望京店）',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T13:00:00Z',
      );
      expect(res2.hasSuspectedDuplicates, isTrue);

      // Candidate Raw matches DB Normalized
      final res3 = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T13:00:00Z',
      );
      expect(res3.hasSuspectedDuplicates, isTrue);

      // Whitespace trimmed matching
      final res4 = await engine.checkTier4Fuzzy(
        merchantRaw: '  星巴克咖啡（国贸旗舰店）  ',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T13:00:00Z',
      );
      expect(res4.hasSuspectedDuplicates, isTrue);

      // Different merchant DOES NOT MATCH
      final res5 = await engine.checkTier4Fuzzy(
        merchantRaw: '瑞幸咖啡',
        merchantNormalized: '瑞幸咖啡',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T13:00:00Z',
      );
      expect(res5.hasSuspectedDuplicates, isFalse);
    });

    test('4.3: Date-only transactions (without precise time) safely search +/- 1 calendar day window', () async {
      // Seed date-only transaction in DB (occurred_at == null)
      await db.insert('transactions', {
        'id': 'tx_date_only_base',
        'type': 'expense',
        'amount_minor': 1200,
        'currency': 'CNY',
        'merchant_raw': '7-Eleven',
        'merchant_normalized': '7-Eleven',
        'occurred_on': '2026-10-22',
        'occurred_at': null, // NO TIME
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'day',
        'payment_channel': 'alipay',
        'category_id': 'cat_dining',
        'created_at': '2026-10-22T00:00:00Z',
        'updated_at': '2026-10-22T00:00:00Z',
        'deleted_at': null,
      });

      // 4.3a: Candidate on same calendar day (date-only) -> MATCHES
      final sameDayRes = await engine.checkTier4Fuzzy(
        merchantRaw: '7-Eleven',
        amountMinor: 1200,
        occurredOn: '2026-10-22',
      );
      expect(sameDayRes.hasSuspectedDuplicates, isTrue);
      expect(sameDayRes.candidateTransactionIds, contains('tx_date_only_base'));

      // 4.3b: Candidate on previous calendar day (-1 day, date-only) -> MATCHES
      final prevDayRes = await engine.checkTier4Fuzzy(
        merchantRaw: '7-Eleven',
        amountMinor: 1200,
        occurredOn: '2026-10-21',
      );
      expect(prevDayRes.hasSuspectedDuplicates, isTrue);
      expect(prevDayRes.candidateTransactionIds, contains('tx_date_only_base'));

      // 4.3c: Candidate on next calendar day (+1 day, date-only) -> MATCHES
      final nextDayRes = await engine.checkTier4Fuzzy(
        merchantRaw: '7-Eleven',
        amountMinor: 1200,
        occurredOn: '2026-10-23',
      );
      expect(nextDayRes.hasSuspectedDuplicates, isTrue);
      expect(nextDayRes.candidateTransactionIds, contains('tx_date_only_base'));

      // 4.3d: Candidate 2 days earlier (-2 days, date-only) -> DOES NOT MATCH
      final twoDaysPriorRes = await engine.checkTier4Fuzzy(
        merchantRaw: '7-Eleven',
        amountMinor: 1200,
        occurredOn: '2026-10-20',
      );
      expect(twoDaysPriorRes.hasSuspectedDuplicates, isFalse);

      // 4.3e: Candidate 2 days later (+2 days, date-only) -> DOES NOT MATCH
      final twoDaysLaterRes = await engine.checkTier4Fuzzy(
        merchantRaw: '7-Eleven',
        amountMinor: 1200,
        occurredOn: '2026-10-24',
      );
      expect(twoDaysLaterRes.hasSuspectedDuplicates, isFalse);
    });

    test('4.4: Soft-deleted transaction in trash bin is excluded from Tier 4 fuzzy match', () async {
      // Soft-delete base transaction
      await db.update('transactions', {'deleted_at': '2026-10-22T12:05:00Z'}, where: 'id = ?', whereArgs: ['tx_fuzzy_base']);

      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T12:30:00Z',
      );

      expect(res.hasSuspectedDuplicates, isFalse);
      expect(res.candidateTransactionIds, isEmpty);
    });

    test('4.5: Consecutive identical purchases at same merchant survive fuzzy warning and are saved successfully', () async {
      // 1st purchase already exists at 12:00:00Z for 45.00 CNY
      // 2nd purchase happens at 12:15:00Z for 45.00 CNY
      final fuzzyWarn = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克咖啡（国贸旗舰店）',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T12:15:00Z',
      );

      // Soft warning is raised
      expect(fuzzyWarn.hasSuspectedDuplicates, isTrue);

      // User confirms "This is a legitimate separate purchase" -> saved as second transaction
      const secondTxId = 'tx_fuzzy_consecutive_2';
      const now = '2026-10-22T12:15:00Z';
      await db.insert('transactions', {
        'id': secondTxId,
        'origin_draft_id': null,
        'type': 'expense',
        'amount_minor': 4500,
        'currency': 'CNY',
        'merchant_raw': '星巴克咖啡（国贸旗舰店）',
        'merchant_normalized': '星巴克',
        'occurred_on': '2026-10-22',
        'occurred_at': now,
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'second',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      });

      // Both transactions reside in active transactions
      final activeRows = await db.query(
        'transactions',
        where: 'deleted_at IS NULL AND amount_minor = 4500',
      );
      expect(activeRows.length, equals(2));
      final ids = activeRows.map((r) => r['id'] as String).toList();
      expect(ids, containsAll(['tx_fuzzy_base', secondTxId]));
    });

    test('4.6: Cross-year/month boundary: 2026-12-31 to 2027-01-01 correctly transitions +/- 1 calendar day window', () async {
      const now = '2026-12-31T23:30:00Z';
      await db.insert('transactions', {
        'id': 'tx_nye_party',
        'type': 'expense',
        'amount_minor': 9900,
        'currency': 'CNY',
        'merchant_raw': 'Hotel Bar',
        'occurred_on': '2026-12-31',
        'occurred_at': now,
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'second',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      });

      // New Year Day 2027-01-01 at 00:30:00Z (only 1 hour later!)
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: 'Hotel Bar',
        amountMinor: 9900,
        occurredOn: '2027-01-01',
        occurredAt: '2027-01-01T00:30:00Z',
      );

      expect(res.hasSuspectedDuplicates, isTrue);
      expect(res.candidateTransactionIds, contains('tx_nye_party'));
    });

    test('4.7: Timezone representation equivalence: UTC Z vs +08:00 offset ISO strings correctly compute diff', () async {
      // Base is at 2026-10-22T12:00:00Z
      // Candidate at 2026-10-22T20:30:00+08:00 (which is 12:30:00Z, 30 minutes later)
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4500,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T20:30:00+08:00',
      );

      expect(res.hasSuspectedDuplicates, isTrue);
      expect(res.candidateTransactionIds, contains('tx_fuzzy_base'));
    });
  });

  group('Adversarial Challenge: Architectural Edge Cases & Defensive Invariants', () {
    test('Image hash multi-job resolution: verify behavior when multiple jobs share content hash', () async {
      const sharedHash = 'hash_multi_job_test';
      const t1 = '2026-10-22T10:00:00Z';
      const t2 = '2026-10-22T11:00:00Z';

      // Job 1 (earlier): COMMITTED to tx_mj_1
      await db.insert('capture_jobs', {
        'id': 'job_mj_1',
        'content_hash': sharedHash,
        'source_kind': 'photoPicker',
        'imported_at': t1,
        'private_image_ref': 'captures/1.jpg',
        'state': 'COMMITTED',
        'attempt_count': 1,
        'created_at': t1,
        'updated_at': t1,
      });

      await db.insert('drafts', {
        'id': 'draft_mj_1',
        'capture_id': 'job_mj_1',
        'candidate_fields': '{}',
        'field_evidence': '{}',
        'validation_issues': '[]',
        'duplicate_candidates': '[]',
        'saved_transaction_id': 'tx_mj_1',
        'created_at': t1,
        'updated_at': t1,
      });

      await db.insert('transactions', {
        'id': 'tx_mj_1',
        'origin_draft_id': 'draft_mj_1',
        'type': 'expense',
        'amount_minor': 1500,
        'currency': 'CNY',
        'merchant_raw': 'Bakery',
        'occurred_on': '2026-10-22',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_dining',
        'created_at': t1,
        'updated_at': t1,
      });

      // Job 2 (later): IMPORTED without draft/tx
      await db.insert('capture_jobs', {
        'id': 'job_mj_2',
        'content_hash': sharedHash,
        'source_kind': 'photoPicker',
        'imported_at': t2,
        'private_image_ref': 'captures/2.jpg',
        'state': 'IMPORTED',
        'attempt_count': 0,
        'created_at': t2,
        'updated_at': t2,
      });

      final res = await engine.checkTier2ImageHash(sharedHash);

      // checkTier2ImageHash picks the most recent job (Job 2)
      expect(res.isMatched, isTrue);
      expect(res.existingJobId, equals('job_mj_2'));
    });
  });
}

