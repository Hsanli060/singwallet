// test/deduplication/deduplication_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DeduplicationEngine engine;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    engine = DeduplicationEngine(db);

    // Seed category
    await db.insert('categories', {
      'id': 'cat_coffee',
      'name': '咖啡奶茶',
      'applicable_type': 'expense',
      'created_at': '2026-10-22T08:00:00Z',
      'updated_at': '2026-10-22T08:00:00Z',
    });

    // Seed Job 1
    await db.insert('capture_jobs', {
      'id': 'job_starbucks_1',
      'content_hash': 'sha256_starbucks_img_001',
      'source_kind': 'photoPicker',
      'imported_at': '2026-10-22T08:30:00Z',
      'private_image_ref': 'captures/sb1.jpg',
      'state': 'COMMITTED',
      'attempt_count': 1,
      'created_at': '2026-10-22T08:30:00Z',
      'updated_at': '2026-10-22T08:30:00Z',
    });

    // Seed Draft 1
    await db.insert('drafts', {
      'id': 'draft_starbucks_1',
      'capture_id': 'job_starbucks_1',
      'candidate_fields': '{"merchant":"星巴克","amountMinor":3800}',
      'field_evidence': '{}',
      'validation_issues': '[]',
      'duplicate_candidates': '[]',
      'saved_transaction_id': 'tx_starbucks_1',
      'created_at': '2026-10-22T08:30:00Z',
      'updated_at': '2026-10-22T08:30:00Z',
    });

    // Seed Transaction 1 (Active)
    await db.insert('transactions', {
      'id': 'tx_starbucks_1',
      'origin_draft_id': 'draft_starbucks_1',
      'type': 'expense',
      'amount_minor': 3800,
      'currency': 'CNY',
      'merchant_raw': '星巴克咖啡（三里屯店）',
      'merchant_normalized': '星巴克',
      'occurred_on': '2026-10-22',
      'occurred_at': '2026-10-22T08:30:00Z',
      'event_time_source': 'ocr_extracted',
      'event_time_precision': 'minute',
      'payment_channel': 'wechat',
      'category_id': 'cat_coffee',
      'created_at': '2026-10-22T08:30:00Z',
      'updated_at': '2026-10-22T08:30:00Z',
      'deleted_at': null,
    });

    // Seed Confirmed Identifier for Transaction 1
    await db.insert('confirmed_identifiers', {
      'namespace': 'wechat_pay',
      'identifier_type': 'platform_transaction_no',
      'complete_value': '4200001234567890',
      'stable_event_kind': 'payment',
      'transaction_id': 'tx_starbucks_1',
    });

    // Seed Job 2 & Draft 2 & Transaction 2 (Soft deleted in 30-day trash)
    await db.insert('capture_jobs', {
      'id': 'job_kfc_trash',
      'content_hash': 'sha256_kfc_trash_img',
      'source_kind': 'systemShare',
      'imported_at': '2026-10-20T12:00:00Z',
      'private_image_ref': 'captures/kfc.jpg',
      'state': 'COMMITTED',
      'attempt_count': 1,
      'created_at': '2026-10-20T12:00:00Z',
      'updated_at': '2026-10-20T12:00:00Z',
    });

    await db.insert('drafts', {
      'id': 'draft_kfc_trash',
      'capture_id': 'job_kfc_trash',
      'candidate_fields': '{"merchant":"肯德基","amountMinor":4500}',
      'field_evidence': '{}',
      'validation_issues': '[]',
      'duplicate_candidates': '[]',
      'saved_transaction_id': 'tx_trashed_kfc',
      'created_at': '2026-10-20T12:00:00Z',
      'updated_at': '2026-10-20T12:00:00Z',
    });

    await db.insert('transactions', {
      'id': 'tx_trashed_kfc',
      'origin_draft_id': 'draft_kfc_trash',
      'type': 'expense',
      'amount_minor': 4500,
      'currency': 'CNY',
      'merchant_raw': '肯德基',
      'merchant_normalized': '肯德基',
      'occurred_on': '2026-10-20',
      'occurred_at': '2026-10-20T12:00:00Z',
      'event_time_source': 'ocr_extracted',
      'event_time_precision': 'minute',
      'payment_channel': 'alipay',
      'category_id': 'cat_coffee',
      'created_at': '2026-10-20T12:00:00Z',
      'updated_at': '2026-10-21T09:00:00Z',
      'deleted_at': '2026-10-21T09:00:00Z', // In trash bin
    });

    await db.insert('confirmed_identifiers', {
      'namespace': 'alipay',
      'identifier_type': 'platform_transaction_no',
      'complete_value': '2026102022001400',
      'stable_event_kind': 'payment',
      'transaction_id': 'tx_trashed_kfc',
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('Tier 1: Technical Idempotence', () {
    test('Duplicate origin_draft_id returns existing transaction ID and active status', () async {
      final res = await engine.checkTier1Idempotence('draft_starbucks_1');
      expect(res.isMatched, isTrue);
      expect(res.existingTransactionId, equals('tx_starbucks_1'));
      expect(res.isInTrash, isFalse);
    });

    test('Duplicate origin_draft_id for trashed transaction flags isInTrash', () async {
      final res = await engine.checkTier1Idempotence('draft_kfc_trash');
      expect(res.isMatched, isTrue);
      expect(res.existingTransactionId, equals('tx_trashed_kfc'));
      expect(res.isInTrash, isTrue);
    });

    test('Unknown origin_draft_id returns miss', () async {
      final res = await engine.checkTier1Idempotence('draft_brand_new');
      expect(res.isMatched, isFalse);
      expect(res.existingTransactionId, isNull);
    });
  });

  group('Tier 2: Same-Image SHA-256 Hash Matching', () {
    test('Exact image SHA-256 hash match identifies existing job and transaction', () async {
      final res = await engine.checkTier2ImageHash('sha256_starbucks_img_001');
      expect(res.isMatched, isTrue);
      expect(res.existingJobId, equals('job_starbucks_1'));
      expect(res.jobState, equals('COMMITTED'));
      expect(res.existingDraftId, equals('draft_starbucks_1'));
      expect(res.existingTransactionId, equals('tx_starbucks_1'));
      expect(res.isTransactionInTrash, isFalse);
    });

    test('Different image hash returns miss and proceeds to Tier 3', () async {
      final res = await engine.checkTier2ImageHash('sha256_completely_different');
      expect(res.isMatched, isFalse);
      expect(res.existingJobId, isNull);
    });
  });

  group('Tier 3: Hard Platform Transaction Identifier Check', () {
    test('Matches active transaction and returns activeDuplicate to hard-block commit', () async {
      final id = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '4200001234567890',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.complete,
      );

      final res = await engine.checkTier3PlatformId(id);
      expect(res.isMatched, isTrue);
      expect(res.isInTrash, isFalse);
      expect(res.matchedTransactionId, equals('tx_starbucks_1'));
    });

    test('Matches soft-deleted transaction and returns trashBinDuplicate to prompt restore', () async {
      final id = PlatformIdentifier(
        namespace: 'alipay',
        identifierType: 'platform_transaction_no',
        completeValue: '2026102022001400',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.complete,
      );

      final res = await engine.checkTier3PlatformId(id);
      expect(res.isMatched, isTrue);
      expect(res.isInTrash, isTrue);
      expect(res.matchedTransactionId, equals('tx_trashed_kfc'));
    });

    test('Incomplete / masked / truncated identifiers MUST NOT trigger Tier 3', () async {
      final maskedId = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '420000****7890',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.masked, // Masked
      );

      final res = await engine.checkTier3PlatformId(maskedId);
      expect(res.isMatched, isFalse);
    });

    test('Distinct stable_event_kind (payment vs refund) does NOT collide', () async {
      final refundId = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '4200001234567890',
        stableEventKind: 'refund', // Different event kind
        completeness: IdentifierCompleteness.complete,
      );

      final res = await engine.checkTier3PlatformId(refundId);
      expect(res.isMatched, isFalse);
    });
  });

  group('Tier 4: Heuristic Fuzzy Matching', () {
    test('Same merchant + same amount + within 24h triggers soft duplicate warning', () async {
      // 2 hours later at Starbucks with identical amount 38.00 CNY
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克咖啡（三里屯店）',
        merchantNormalized: '星巴克',
        amountMinor: 3800,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T10:30:00Z',
      );

      expect(res.hasSuspectedDuplicates, isTrue);
      expect(res.candidateTransactionIds, contains('tx_starbucks_1'));
    });

    test('Different merchant with same amount and time does NOT match', () async {
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '瑞幸咖啡',
        merchantNormalized: '瑞幸咖啡',
        amountMinor: 3800,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T08:35:00Z',
      );

      expect(res.hasSuspectedDuplicates, isFalse);
      expect(res.candidateTransactionIds, isEmpty);
    });

    test('Same merchant with different amount does NOT match', () async {
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4200, // 42.00 vs 38.00
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T08:30:00Z',
      );

      expect(res.hasSuspectedDuplicates, isFalse);
      expect(res.candidateTransactionIds, isEmpty);
    });

    test('Same merchant and amount but time delta > 24 hours does NOT match', () async {
      // 48 hours later
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 3800,
        occurredOn: '2026-10-24',
        occurredAt: '2026-10-24T08:30:00Z',
      );

      expect(res.hasSuspectedDuplicates, isFalse);
      expect(res.candidateTransactionIds, isEmpty);
    });

    test('Consecutive purchases in same store can be manually confirmed and saved', () async {
      // User buys 2 coffees in the same morning at Starbucks (38.00 CNY each).
      // Tier 4 surfaces tx_starbucks_1 as a candidate soft warning.
      final res = await engine.checkTier4Fuzzy(
        merchantRaw: '星巴克咖啡（三里屯店）',
        merchantNormalized: '星巴克',
        amountMinor: 3800,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T09:00:00Z',
      );
      expect(res.hasSuspectedDuplicates, isTrue);
      expect(res.candidateTransactionIds.length, equals(1));

      // User confirms "This is another transaction" -> new transaction is cleanly recorded
      await db.insert('transactions', {
        'id': 'tx_starbucks_2',
        'type': 'expense',
        'amount_minor': 3800,
        'currency': 'CNY',
        'merchant_raw': '星巴克咖啡（三里屯店）',
        'merchant_normalized': '星巴克',
        'occurred_on': '2026-10-22',
        'occurred_at': '2026-10-22T09:00:00Z',
        'event_time_source': 'ocr_extracted',
        'event_time_precision': 'minute',
        'payment_channel': 'wechat',
        'category_id': 'cat_coffee',
        'created_at': '2026-10-22T09:00:00Z',
        'updated_at': '2026-10-22T09:00:00Z',
        'deleted_at': null,
      });

      final rows = await db.query(
        'transactions',
        where: 'deleted_at IS NULL AND category_id = ?',
        whereArgs: ['cat_coffee'],
      );
      expect(rows.length, equals(2));
      final ids = rows.map((r) => r['id'] as String).toList();
      expect(ids, containsAll(['tx_starbucks_1', 'tx_starbucks_2']));
    });
  });

  group('Aggregated Pipeline Evaluation', () {
    test('Aggregated evaluate flags hard duplicate when complete platform ID matches', () async {
      final eval = await engine.evaluate(
        originDraftId: 'draft_new_123',
        imageContentHash: 'hash_new_image',
        platformIdentifier: PlatformIdentifier(
          namespace: 'wechat_pay',
          identifierType: 'platform_transaction_no',
          completeValue: '4200001234567890',
          stableEventKind: 'payment',
        ),
        merchantRaw: '星巴克',
        amountMinor: 3800,
        occurredOn: '2026-10-22',
      );

      expect(eval.hasHardDuplicate, isTrue);
      expect(eval.tier3.isMatched, isTrue);
    });

    test('Aggregated evaluate flags soft duplicate warning for fuzzy match without platform ID', () async {
      final eval = await engine.evaluate(
        originDraftId: 'draft_receipt_only',
        imageContentHash: 'hash_different_receipt',
        merchantRaw: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 3800,
        occurredOn: '2026-10-22',
        occurredAt: '2026-10-22T10:00:00Z',
      );

      expect(eval.hasHardDuplicate, isFalse);
      expect(eval.hasSoftDuplicate, isTrue);
      expect(eval.tier4.candidateTransactionIds, contains('tx_starbucks_1'));
    });
  });
}
