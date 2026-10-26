// lib/features/deduplication/deduplication_engine.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Identifier completeness classification matching OCR and database spec
enum IdentifierCompleteness {
  none,
  complete,
  masked,
  truncated,
  unreliable,
}

extension IdentifierCompletenessExtension on IdentifierCompleteness {
  String toDbValue() {
    switch (this) {
      case IdentifierCompleteness.none:
        return 'NONE';
      case IdentifierCompleteness.complete:
        return 'COMPLETE';
      case IdentifierCompleteness.masked:
        return 'MASKED';
      case IdentifierCompleteness.truncated:
        return 'TRUNCATED';
      case IdentifierCompleteness.unreliable:
        return 'UNRELIABLE';
    }
  }

  static IdentifierCompleteness fromDbValue(String? value) {
    switch (value?.toUpperCase()) {
      case 'COMPLETE':
        return IdentifierCompleteness.complete;
      case 'MASKED':
        return IdentifierCompleteness.masked;
      case 'TRUNCATED':
        return IdentifierCompleteness.truncated;
      case 'UNRELIABLE':
        return IdentifierCompleteness.unreliable;
      case 'NONE':
      default:
        return IdentifierCompleteness.none;
    }
  }
}

/// Platform identifier data structure for Tier 3 hard deduplication
class PlatformIdentifier {
  final String namespace; // e.g. 'wechat_pay', 'alipay', 'unionpay'
  final String identifierType; // e.g. 'platform_transaction_no'
  final String completeValue; // Unmasked full platform order number
  final String stableEventKind; // 'payment' or 'refund'
  final IdentifierCompleteness completeness;

  PlatformIdentifier({
    required this.namespace,
    required this.identifierType,
    required this.completeValue,
    required this.stableEventKind,
    this.completeness = IdentifierCompleteness.complete,
  });

  bool get isEligibleForHardDedup =>
      completeness == IdentifierCompleteness.complete &&
      completeValue.trim().isNotEmpty;
}

/// Tier 1 Idempotence Evaluation Result
class Tier1Result {
  final bool isMatched;
  final String? existingTransactionId;
  final bool isInTrash;

  const Tier1Result({
    required this.isMatched,
    this.existingTransactionId,
    this.isInTrash = false,
  });

  factory Tier1Result.miss() => const Tier1Result(isMatched: false);

  factory Tier1Result.hit({
    required String transactionId,
    bool isInTrash = false,
  }) =>
      Tier1Result(
        isMatched: true,
        existingTransactionId: transactionId,
        isInTrash: isInTrash,
      );
}

/// Tier 2 Image Hash Evaluation Result
class Tier2Result {
  final bool isMatched;
  final String? existingJobId;
  final String? jobState;
  final String? existingDraftId;
  final String? existingTransactionId;
  final bool isTransactionInTrash;

  const Tier2Result({
    required this.isMatched,
    this.existingJobId,
    this.jobState,
    this.existingDraftId,
    this.existingTransactionId,
    this.isTransactionInTrash = false,
  });

  factory Tier2Result.miss() => const Tier2Result(isMatched: false);

  factory Tier2Result.hit({
    required String jobId,
    required String jobState,
    String? draftId,
    String? transactionId,
    bool isTransactionInTrash = false,
  }) =>
      Tier2Result(
        isMatched: true,
        existingJobId: jobId,
        jobState: jobState,
        existingDraftId: draftId,
        existingTransactionId: transactionId,
        isTransactionInTrash: isTransactionInTrash,
      );
}

/// Tier 3 Hard Platform Identifier Result
class Tier3Result {
  final bool isMatched;
  final String? matchedTransactionId;
  final Map<String, dynamic>? matchedTransaction;
  final bool isInTrash;

  const Tier3Result({
    required this.isMatched,
    this.matchedTransactionId,
    this.matchedTransaction,
    this.isInTrash = false,
  });

  factory Tier3Result.miss() => const Tier3Result(isMatched: false);

  factory Tier3Result.activeDuplicate({
    required String transactionId,
    required Map<String, dynamic> transaction,
  }) =>
      Tier3Result(
        isMatched: true,
        matchedTransactionId: transactionId,
        matchedTransaction: transaction,
        isInTrash: false,
      );

  factory Tier3Result.trashBinDuplicate({
    required String transactionId,
    required Map<String, dynamic> transaction,
  }) =>
      Tier3Result(
        isMatched: true,
        matchedTransactionId: transactionId,
        matchedTransaction: transaction,
        isInTrash: true,
      );
}

/// Tier 4 Heuristic Fuzzy Match Result
class Tier4Result {
  final bool hasSuspectedDuplicates;
  final List<String> candidateTransactionIds;
  final List<Map<String, dynamic>> candidateTransactions;

  const Tier4Result({
    required this.hasSuspectedDuplicates,
    required this.candidateTransactionIds,
    required this.candidateTransactions,
  });

  factory Tier4Result.clean() => const Tier4Result(
        hasSuspectedDuplicates: false,
        candidateTransactionIds: [],
        candidateTransactions: [],
      );

  factory Tier4Result.suspected({
    required List<String> ids,
    required List<Map<String, dynamic>> transactions,
  }) =>
      Tier4Result(
        hasSuspectedDuplicates: true,
        candidateTransactionIds: ids,
        candidateTransactions: transactions,
      );
}

/// Aggregated Evaluation Result across all 4 tiers
class DeduplicationEvaluation {
  final Tier1Result tier1;
  final Tier2Result tier2;
  final Tier3Result tier3;
  final Tier4Result tier4;

  const DeduplicationEvaluation({
    required this.tier1,
    required this.tier2,
    required this.tier3,
    required this.tier4,
  });

  bool get hasHardDuplicate =>
      tier1.isMatched || (tier3.isMatched && !tier3.isInTrash);
  bool get hasTrashDuplicate =>
      tier1.isInTrash || (tier3.isMatched && tier3.isInTrash);
  bool get hasSoftDuplicate => tier4.hasSuspectedDuplicates;
}

/// 4-Tier Deduplication Engine for SingWallet
class DeduplicationEngine {
  final DatabaseExecutor _db;

  DeduplicationEngine(this._db);

  /// Tier 1: Technical Idempotence Check
  /// Checks whether [originDraftId] has already been committed to an existing transaction.
  Future<Tier1Result> checkTier1Idempotence(String originDraftId) async {
    final rows = await _db.query(
      'transactions',
      columns: ['id', 'deleted_at'],
      where: 'origin_draft_id = ?',
      whereArgs: [originDraftId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return Tier1Result.miss();
    }

    final row = rows.first;
    final txId = row['id'] as String;
    final isInTrash = row['deleted_at'] != null;

    return Tier1Result.hit(transactionId: txId, isInTrash: isInTrash);
  }

  /// Tier 2: Same-Image Hash Check
  /// Checks whether [contentHash] matches any existing record in [capture_jobs].
  Future<Tier2Result> checkTier2ImageHash(String contentHash) async {
    const sql = '''
      SELECT cj.id AS job_id, cj.state, cj.imported_at,
             d.id AS draft_id, d.saved_transaction_id,
             t.id AS transaction_id, t.deleted_at
      FROM capture_jobs cj
      LEFT JOIN drafts d ON d.capture_id = cj.id
      LEFT JOIN transactions t ON (t.origin_draft_id = d.id OR t.id = d.saved_transaction_id)
      WHERE cj.content_hash = ?
      ORDER BY cj.created_at DESC
      LIMIT 1;
    ''';

    final rows = await _db.rawQuery(sql, [contentHash]);
    if (rows.isEmpty) {
      return Tier2Result.miss();
    }

    final row = rows.first;
    final jobId = row['job_id'] as String;
    final state = row['state'] as String;
    final draftId = row['draft_id'] as String?;
    final txId =
        (row['transaction_id'] ?? row['saved_transaction_id']) as String?;
    final isInTrash = row['deleted_at'] != null;

    return Tier2Result.hit(
      jobId: jobId,
      jobState: state,
      draftId: draftId,
      transactionId: txId,
      isTransactionInTrash: isInTrash,
    );
  }

  /// Tier 3: Hard Platform Identifier Match
  /// Matches against [confirmed_identifiers] table using compound PK.
  /// Only executes if [identifier.isEligibleForHardDedup] is true.
  Future<Tier3Result> checkTier3PlatformId(PlatformIdentifier identifier) async {
    if (!identifier.isEligibleForHardDedup) {
      return Tier3Result.miss();
    }

    const sql = '''
      SELECT ci.transaction_id, t.id, t.type, t.amount_minor, t.currency,
             t.merchant_raw, t.occurred_on, t.deleted_at
      FROM confirmed_identifiers ci
      JOIN transactions t ON ci.transaction_id = t.id
      WHERE ci.namespace = ?
        AND ci.identifier_type = ?
        AND ci.complete_value = ?
        AND ci.stable_event_kind = ?
      LIMIT 1;
    ''';

    final rows = await _db.rawQuery(sql, [
      identifier.namespace,
      identifier.identifierType,
      identifier.completeValue.trim(),
      identifier.stableEventKind,
    ]);

    if (rows.isEmpty) {
      return Tier3Result.miss();
    }

    final row = rows.first;
    final txId = row['id'] as String;
    final isInTrash = row['deleted_at'] != null;

    if (isInTrash) {
      return Tier3Result.trashBinDuplicate(
        transactionId: txId,
        transaction: row,
      );
    } else {
      return Tier3Result.activeDuplicate(
        transactionId: txId,
        transaction: row,
      );
    }
  }

  /// Tier 4: Heuristic Fuzzy Matching
  /// Checks for active transactions with:
  /// - Same merchant ([merchantRaw] or [merchantNormalized])
  /// - Identical [amountMinor]
  /// - Within 24-hour time window of [occurredOn] / [occurredAt]
  Future<Tier4Result> checkTier4Fuzzy({
    required String merchantRaw,
    String? merchantNormalized,
    required int amountMinor,
    required String occurredOn,
    String? occurredAt,
  }) async {
    final candidateDate = DateTime.tryParse(occurredOn);
    if (candidateDate == null) {
      return Tier4Result.clean();
    }

    final prevDate = candidateDate.subtract(const Duration(days: 1));
    final nextDate = candidateDate.add(const Duration(days: 1));

    final minDateStr = _formatDate(prevDate);
    final maxDateStr = _formatDate(nextDate);

    final rawMerchantTrimmed = merchantRaw.trim().toLowerCase();
    final normMerchantTrimmed = merchantNormalized?.trim().toLowerCase();

    const sql = '''
      SELECT id, type, amount_minor, currency, merchant_raw, merchant_normalized,
             occurred_on, occurred_at, payment_channel, category_id
      FROM transactions
      WHERE deleted_at IS NULL
        AND amount_minor = ?
        AND occurred_on BETWEEN ? AND ?;
    ''';

    final rows = await _db.rawQuery(sql, [amountMinor, minDateStr, maxDateStr]);

    if (rows.isEmpty) {
      return Tier4Result.clean();
    }

    final candidateDateTime =
        occurredAt != null ? DateTime.tryParse(occurredAt) : null;
    final List<Map<String, dynamic>> matchingRows = [];
    final List<String> matchingIds = [];

    for (final row in rows) {
      final dbRaw = (row['merchant_raw'] as String?)?.trim().toLowerCase() ?? '';
      final dbNorm =
          (row['merchant_normalized'] as String?)?.trim().toLowerCase();

      // Check merchant match: raw matches raw OR norm matches norm OR raw matches norm
      final merchantMatches = (dbRaw == rawMerchantTrimmed) ||
          (normMerchantTrimmed != null &&
              dbNorm != null &&
              dbNorm == normMerchantTrimmed) ||
          (normMerchantTrimmed != null && dbRaw == normMerchantTrimmed) ||
          (dbNorm != null && dbNorm == rawMerchantTrimmed);

      if (!merchantMatches) {
        continue;
      }

      // Time difference verification
      final dbOccurredAtStr = row['occurred_at'] as String?;
      final dbDateTime =
          dbOccurredAtStr != null ? DateTime.tryParse(dbOccurredAtStr) : null;

      if (candidateDateTime != null && dbDateTime != null) {
        final diff = candidateDateTime.difference(dbDateTime).abs();
        if (diff > const Duration(hours: 24)) {
          // Both have precise timestamps and difference exceeds 24h
          continue;
        }
      }

      matchingRows.add(row);
      matchingIds.add(row['id'] as String);
    }

    if (matchingIds.isEmpty) {
      return Tier4Result.clean();
    }

    return Tier4Result.suspected(
      ids: matchingIds,
      transactions: matchingRows,
    );
  }

  /// Aggregated pipeline evaluation across all 4 tiers
  Future<DeduplicationEvaluation> evaluate({
    String? originDraftId,
    String? imageContentHash,
    PlatformIdentifier? platformIdentifier,
    required String merchantRaw,
    String? merchantNormalized,
    required int amountMinor,
    required String occurredOn,
    String? occurredAt,
  }) async {
    Tier1Result t1 = Tier1Result.miss();
    if (originDraftId != null && originDraftId.isNotEmpty) {
      t1 = await checkTier1Idempotence(originDraftId);
    }

    Tier2Result t2 = Tier2Result.miss();
    if (imageContentHash != null && imageContentHash.isNotEmpty) {
      t2 = await checkTier2ImageHash(imageContentHash);
    }

    Tier3Result t3 = Tier3Result.miss();
    if (platformIdentifier != null) {
      t3 = await checkTier3PlatformId(platformIdentifier);
    }

    final t4 = await checkTier4Fuzzy(
      merchantRaw: merchantRaw,
      merchantNormalized: merchantNormalized,
      amountMinor: amountMinor,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
    );

    return DeduplicationEvaluation(
      tier1: t1,
      tier2: t2,
      tier3: t3,
      tier4: t4,
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
