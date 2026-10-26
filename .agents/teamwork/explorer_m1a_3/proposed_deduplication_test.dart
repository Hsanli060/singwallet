import 'package:flutter_test/flutter_test.dart';

// In actual implementation, these models and engines are imported from:
// import 'package:singwallet/data/database/app_database.dart';
// import 'package:singwallet/features/deduplication/deduplication_engine.dart';

/// Identifier completeness enum.
enum IdentifierCompleteness {
  none,
  complete,
  masked,
  truncated,
  unreliable,
}

/// Representation of a verified platform transaction identifier.
class PlatformIdentifier {
  final String namespace; // e.g. 'wechat_pay', 'alipay'
  final String identifierType; // e.g. 'platform_transaction_no'
  final String completeValue;
  final String stableEventKind; // 'payment' or 'refund'
  final IdentifierCompleteness completeness;

  PlatformIdentifier({
    required this.namespace,
    required this.identifierType,
    required this.completeValue,
    required this.stableEventKind,
    this.completeness = IdentifierCompleteness.complete,
  });
}

/// Result of Tier 3 hard deduplication check.
enum Tier3MatchStatus {
  noMatch,
  activeDuplicate,  // Transaction is active in formal ledger -> HARD INTERCEPT
  trashedDuplicate, // Transaction is in 30-day trash bin -> PROMPT RESTORE
}

class Tier3MatchResult {
  final Tier3MatchStatus status;
  final String? existingTransactionId;

  const Tier3MatchResult._(this.status, this.existingTransactionId);

  factory Tier3MatchResult.none() =>
      const Tier3MatchResult._(Tier3MatchStatus.noMatch, null);

  factory Tier3MatchResult.active(String txId) =>
      Tier3MatchResult._(Tier3MatchStatus.activeDuplicate, txId);

  factory Tier3MatchResult.trashed(String txId) =>
      Tier3MatchResult._(Tier3MatchStatus.trashedDuplicate, txId);

  bool get isDuplicate => status != Tier3MatchStatus.noMatch;
}

/// Simulated in-memory test harness representing SQLite tables for deduplication logic verification.
class MockDeduplicationStore {
  final Map<String, Map<String, dynamic>> captureJobs = {};
  final Map<String, Map<String, dynamic>> drafts = {};
  final Map<String, Map<String, dynamic>> transactions = {};
  final Map<String, Map<String, dynamic>> confirmedIdentifiers = {};

  // Tier 1: Technical Idempotence
  String? checkTier1Idempotence({String? originDraftId, String? captureId}) {
    // Check if originDraftId already exists in transactions
    if (originDraftId != null) {
      for (final tx in transactions.values) {
        if (tx['origin_draft_id'] == originDraftId) {
          return tx['id'] as String;
        }
      }
      // Check if draft already has saved_transaction_id
      final draft = drafts[originDraftId];
      if (draft != null && draft['saved_transaction_id'] != null) {
        return draft['saved_transaction_id'] as String;
      }
    }
    // Check if capture job already has draft with saved transaction
    if (captureId != null) {
      for (final draft in drafts.values) {
        if (draft['capture_id'] == captureId && draft['saved_transaction_id'] != null) {
          return draft['saved_transaction_id'] as String;
        }
      }
    }
    return null;
  }

  // Tier 2: Same-Image Hash Check
  Map<String, dynamic>? checkTier2ImageHash(String contentHash) {
    for (final job in captureJobs.values) {
      if (job['content_hash'] == contentHash) {
        // Find associated draft and transaction
        String? draftId;
        String? txId;
        for (final draft in drafts.values) {
          if (draft['capture_id'] == job['id']) {
            draftId = draft['id'] as String;
            txId = draft['saved_transaction_id'] as String?;
            break;
          }
        }
        return {
          'job': job,
          'draftId': draftId,
          'savedTransactionId': txId,
        };
      }
    }
    return null;
  }

  // Tier 3: Hard Platform Identifier Check
  Tier3MatchResult checkTier3PlatformId(PlatformIdentifier identifier) {
    // CRITICAL: Only COMPLETE identifiers can participate in hard deduplication!
    if (identifier.completeness != IdentifierCompleteness.complete) {
      return Tier3MatchResult.none();
    }
    if (identifier.completeValue.trim().isEmpty) {
      return Tier3MatchResult.none();
    }

    final key =
        '${identifier.namespace}#${identifier.identifierType}#${identifier.completeValue}#${identifier.stableEventKind}';
    final entry = confirmedIdentifiers[key];
    if (entry == null) {
      return Tier3MatchResult.none();
    }

    final txId = entry['transaction_id'] as String;
    final tx = transactions[txId];
    if (tx == null) {
      return Tier3MatchResult.none();
    }

    if (tx['deleted_at'] != null) {
      // In 30-day trash bin
      return Tier3MatchResult.trashed(txId);
    } else {
      // Active formal transaction
      return Tier3MatchResult.active(txId);
    }
  }

  // Tier 4: Heuristic Fuzzy Matching (Same merchant + same amount + within 24h)
  List<Map<String, dynamic>> checkTier4Fuzzy({
    required String merchant,
    String? merchantNormalized,
    required int amountMinor,
    required DateTime occurredAt,
  }) {
    final List<Map<String, dynamic>> candidates = [];

    for (final tx in transactions.values) {
      // Must not be in trash bin
      if (tx['deleted_at'] != null) continue;

      // Amount must match exactly in cents
      if (tx['amount_minor'] != amountMinor) continue;

      // Merchant match (raw or normalized)
      final txRaw = (tx['merchant_raw'] as String?) ?? '';
      final txNorm = tx['merchant_normalized'] as String?;
      final bool merchantMatches = txRaw == merchant ||
          (merchantNormalized != null && txNorm != null && txNorm == merchantNormalized) ||
          (txNorm != null && txNorm == merchant) ||
          (merchantNormalized != null && txRaw == merchantNormalized);

      if (!merchantMatches) continue;

      // Time difference must be <= 24 hours
      final txTime = DateTime.parse(tx['occurred_at'] as String);
      final difference = (occurredAt.difference(txTime)).abs();
      if (difference <= const Duration(hours: 24)) {
        candidates.add(tx);
      }
    }

    return candidates;
  }
}

void main() {
  late MockDeduplicationStore store;

  setUp(() {
    store = MockDeduplicationStore();

    // Populate base active transaction
    store.transactions['tx_starbucks_1'] = {
      'id': 'tx_starbucks_1',
      'origin_draft_id': 'draft_starbucks_1',
      'type': 'expense',
      'amount_minor': 3800, // 38.00 CNY
      'merchant_raw': '星巴克咖啡（三里屯店）',
      'merchant_normalized': '星巴克',
      'occurred_on': '2026-10-22',
      'occurred_at': '2026-10-22T08:30:00Z',
      'payment_channel': 'wechat',
      'deleted_at': null,
    };

    store.confirmedIdentifiers['wechat_pay#platform_transaction_no#4200001234567890#payment'] = {
      'namespace': 'wechat_pay',
      'identifier_type': 'platform_transaction_no',
      'complete_value': '4200001234567890',
      'stable_event_kind': 'payment',
      'transaction_id': 'tx_starbucks_1',
    };

    // Soft-deleted transaction in trash bin
    store.transactions['tx_trashed_kfc'] = {
      'id': 'tx_trashed_kfc',
      'origin_draft_id': 'draft_kfc_old',
      'type': 'expense',
      'amount_minor': 4500,
      'merchant_raw': '肯德基',
      'merchant_normalized': '肯德基',
      'occurred_on': '2026-10-20',
      'occurred_at': '2026-10-20T12:00:00Z',
      'payment_channel': 'alipay',
      'deleted_at': '2026-10-21T09:00:00Z',
    };

    store.confirmedIdentifiers['alipay#platform_transaction_no#2026102022001400#payment'] = {
      'namespace': 'alipay',
      'identifier_type': 'platform_transaction_no',
      'complete_value': '2026102022001400',
      'stable_event_kind': 'payment',
      'transaction_id': 'tx_trashed_kfc',
    };
  });

  group('Tier 1: Technical Idempotence', () {
    test('Duplicate origin_draft_id returns existing transaction ID', () {
      final existingTxId = store.checkTier1Idempotence(originDraftId: 'draft_starbucks_1');
      expect(existingTxId, equals('tx_starbucks_1'));
    });

    test('Unknown origin_draft_id returns null, allowing pipeline to proceed', () {
      final existingTxId = store.checkTier1Idempotence(originDraftId: 'draft_brand_new');
      expect(existingTxId, isNull);
    });
  });

  group('Tier 2: Same-Image SHA-256 Hash Matching', () {
    setUp(() {
      store.captureJobs['job_img_100'] = {
        'id': 'job_img_100',
        'content_hash': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'state': 'COMMITTED',
      };
      store.drafts['draft_100'] = {
        'id': 'draft_100',
        'capture_id': 'job_img_100',
        'saved_transaction_id': 'tx_starbucks_1',
      };
    });

    test('Exact image SHA-256 hash match identifies existing job and transaction', () {
      final match = store.checkTier2ImageHash('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(match, isNotNull);
      expect(match!['draftId'], equals('draft_100'));
      expect(match['savedTransactionId'], equals('tx_starbucks_1'));
    });

    test('Different image hash returns null and proceeds to Tier 3', () {
      final match = store.checkTier2ImageHash('abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890');
      expect(match, isNull);
    });
  });

  group('Tier 3: Hard Platform Transaction Identifier Check', () {
    test('Matches active transaction and returns activeDuplicate to hard-block commit', () {
      final id = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '4200001234567890',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.complete,
      );

      final result = store.checkTier3PlatformId(id);
      expect(result.status, equals(Tier3MatchStatus.activeDuplicate));
      expect(result.existingTransactionId, equals('tx_starbucks_1'));
    });

    test('Matches soft-deleted transaction and returns trashedDuplicate to prompt restore', () {
      final id = PlatformIdentifier(
        namespace: 'alipay',
        identifierType: 'platform_transaction_no',
        completeValue: '2026102022001400',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.complete,
      );

      final result = store.checkTier3PlatformId(id);
      expect(result.status, equals(Tier3MatchStatus.trashedDuplicate));
      expect(result.existingTransactionId, equals('tx_trashed_kfc'));
    });

    test('Incomplete / masked / truncated identifiers MUST NOT trigger Tier 3', () {
      final maskedId = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '420000****7890',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.masked, // Masked!
      );

      final result = store.checkTier3PlatformId(maskedId);
      expect(result.status, equals(Tier3MatchStatus.noMatch));
    });

    test('Distinct stable_event_kind (payment vs refund) does NOT collide', () {
      final refundId = PlatformIdentifier(
        namespace: 'wechat_pay',
        identifierType: 'platform_transaction_no',
        completeValue: '4200001234567890',
        stableEventKind: 'refund', // Different event kind!
        completeness: IdentifierCompleteness.complete,
      );

      final result = store.checkTier3PlatformId(refundId);
      expect(result.status, equals(Tier3MatchStatus.noMatch));
    });
  });

  group('Tier 4: Heuristic Fuzzy Matching', () {
    test('Same merchant + same amount + within 24h triggers soft duplicate warning', () {
      // Another Starbucks transaction 2 hours later with identical amount 38.00 CNY
      final candidates = store.checkTier4Fuzzy(
        merchant: '星巴克咖啡（三里屯店）',
        merchantNormalized: '星巴克',
        amountMinor: 3800,
        occurredAt: DateTime.parse('2026-10-22T10:30:00Z'),
      );

      expect(candidates.length, equals(1));
      expect(candidates.first['id'], equals('tx_starbucks_1'));
    });

    test('Different merchant with same amount and time does NOT match', () {
      final candidates = store.checkTier4Fuzzy(
        merchant: '瑞幸咖啡',
        merchantNormalized: '瑞幸咖啡',
        amountMinor: 3800,
        occurredAt: DateTime.parse('2026-10-22T08:35:00Z'),
      );
      expect(candidates, isEmpty);
    });

    test('Same merchant with different amount does NOT match', () {
      final candidates = store.checkTier4Fuzzy(
        merchant: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 4200, // 42.00 CNY vs 38.00 CNY
        occurredAt: DateTime.parse('2026-10-22T08:30:00Z'),
      );
      expect(candidates, isEmpty);
    });

    test('Same merchant and amount but time delta > 24 hours does NOT match', () {
      // 48 hours later
      final candidates = store.checkTier4Fuzzy(
        merchant: '星巴克',
        merchantNormalized: '星巴克',
        amountMinor: 3800,
        occurredAt: DateTime.parse('2026-10-24T08:30:00Z'),
      );
      expect(candidates, isEmpty);
    });

    test('Consecutive purchases in same store can be manually confirmed by user', () {
      // User buys 2 coffees in the same morning at Starbucks (38.00 CNY each).
      // Tier 4 surfaces tx_starbucks_1 as a candidate soft warning.
      final candidates = store.checkTier4Fuzzy(
        merchant: '星巴克',
        amountMinor: 3800,
        occurredAt: DateTime.parse('2026-10-22T09:00:00Z'),
      );
      expect(candidates.length, equals(1));

      // User confirms "This is another transaction" -> new transaction is cleanly recorded
      store.transactions['tx_starbucks_2'] = {
        'id': 'tx_starbucks_2',
        'origin_draft_id': 'draft_starbucks_2',
        'type': 'expense',
        'amount_minor': 3800,
        'merchant_raw': '星巴克咖啡（三里屯店）',
        'merchant_normalized': '星巴克',
        'occurred_on': '2026-10-22',
        'occurred_at': '2026-10-22T09:00:00Z',
        'payment_channel': 'wechat',
        'deleted_at': null,
      };

      expect(store.transactions.length, equals(3));
      expect(store.transactions['tx_starbucks_2']!['id'], equals('tx_starbucks_2'));
    });
  });
}
