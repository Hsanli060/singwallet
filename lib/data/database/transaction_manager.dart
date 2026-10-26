// lib/data/database/transaction_manager.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/models.dart';
import 'app_database.dart';
import 'soft_delete_manager.dart';
import 'state_machine.dart';

/// Exception thrown when attempting to commit a non-existent draft.
class DraftNotFoundException implements Exception {
  final String draftId;
  DraftNotFoundException(this.draftId);

  @override
  String toString() => 'DraftNotFoundException: Draft "$draftId" does not exist.';
}

/// Exception thrown when a draft has already been saved to a transaction.
class DraftAlreadyCommittedException implements Exception {
  final String draftId;
  final String transactionId;
  DraftAlreadyCommittedException({
    required this.draftId,
    required this.transactionId,
  });

  @override
  String toString() =>
      'DraftAlreadyCommittedException: Draft "$draftId" was already committed to tx "$transactionId".';
}

/// Exception thrown when Tier 3 hard deduplication detects an active duplicate.
class HardDuplicateException implements Exception {
  final String message;
  final String existingTransactionId;
  HardDuplicateException({
    required this.message,
    required this.existingTransactionId,
  });

  @override
  String toString() =>
      'HardDuplicateException: $message (existing tx: $existingTransactionId)';
}

/// Exception thrown when Tier 3 hard deduplication detects duplicate in 30-day trash bin.
class TrashBinCollisionException implements Exception {
  final String message;
  final String trashTransactionId;
  TrashBinCollisionException({
    required this.message,
    required this.trashTransactionId,
  });

  @override
  String toString() =>
      'TrashBinCollisionException: $message (trash tx: $trashTransactionId)';
}

/// Exception thrown on duplicate origin draft ID commit attempt.
class DuplicateTransactionException implements Exception {
  final String originDraftId;
  DuplicateTransactionException(this.originDraftId);

  @override
  String toString() =>
      'DuplicateTransactionException: Transaction with origin_draft_id "$originDraftId" already exists.';
}

/// Request payload for atomic draft commitment.
class CommitDraftRequest {
  final TransactionEntry transaction;
  final TransactionMetadata? metadata;
  final List<String>? tagIds;
  final ConfirmedIdentifier? identifier;
  final String? originalExpenseId;

  const CommitDraftRequest({
    required this.transaction,
    this.metadata,
    this.tagIds,
    this.identifier,
    this.originalExpenseId,
  });
}

/// Manages atomic financial transactions, draft commitment across 7 tables,
/// soft deletion, trash recovery, and monthly summaries.
class TransactionManager {
  final AppDatabase _databaseHelper;

  TransactionManager([AppDatabase? db])
      : _databaseHelper = db ?? AppDatabase.instance;

  /// Executes atomic draft commitment across 7 core tables:
  /// 1. Verifies draft existence and state == NEEDS_REVIEW
  /// 2. Checks origin_draft_id idempotence
  /// 3. Checks Tier 3 hard platform identifier uniqueness
  /// 4. Inserts into `transactions`
  /// 5. Inserts into `transaction_metadata` (if provided)
  /// 6. Inserts into `transaction_tags` (if tags provided)
  /// 7. Inserts into `confirmed_identifiers` (if complete ID provided)
  /// 8. Inserts into `refund_links` (if refund with originalExpenseId)
  /// 9. Updates `drafts.saved_transaction_id`
  /// 10. Updates `capture_jobs.state = 'COMMITTED'`
  ///
  /// On ANY failure, SQLite rolls back all mutations atomically.
  Future<TransactionEntry> commitDraft(
    CommitDraftRequest request, {
    DatabaseExecutor? customExecutor,
  }) async {
    final db = customExecutor is Database
        ? customExecutor
        : await _databaseHelper.database;

    final tx = request.transaction;
    final draftId = tx.originDraftId;

    return await db.transaction((txn) async {
      String? captureJobId;

      // 1. If originDraftId is present, verify draft state & linkage
      if (draftId != null && draftId.isNotEmpty) {
        final draftRows = await txn.rawQuery('''
          SELECT d.saved_transaction_id, cj.id AS capture_id, cj.state
          FROM drafts d
          JOIN capture_jobs cj ON d.capture_id = cj.id
          WHERE d.id = ?
        ''', [draftId]);

        if (draftRows.isEmpty) {
          throw DraftNotFoundException(draftId);
        }

        final draftRow = draftRows.first;
        final savedTxId = draftRow['saved_transaction_id'] as String?;
        if (savedTxId != null && savedTxId.isNotEmpty) {
          throw DraftAlreadyCommittedException(
            draftId: draftId,
            transactionId: savedTxId,
          );
        }

        final jobState = draftRow['state'] as String;
        if (jobState != CaptureJobState.needsReview.value) {
          throw InvalidStateTransitionException(
            from: CaptureJobState.fromString(jobState),
            to: CaptureJobState.committed,
            jobId: draftRow['capture_id'] as String?,
            message:
                'Cannot commit draft when job is in "$jobState" state (expected NEEDS_REVIEW)',
          );
        }

        captureJobId = draftRow['capture_id'] as String;

        // 2. Check technical idempotence for origin_draft_id
        final existingTxRows = await txn.query(
          'transactions',
          columns: ['id'],
          where: 'origin_draft_id = ?',
          whereArgs: [draftId],
        );
        if (existingTxRows.isNotEmpty) {
          throw DuplicateTransactionException(draftId);
        }
      }

      // 3. Pre-commit check for confirmed identifier collision
      if (request.identifier != null &&
          request.identifier!.completeValue.trim().isNotEmpty) {
        final idRow = await txn.rawQuery('''
          SELECT ci.transaction_id, t.deleted_at
          FROM confirmed_identifiers ci
          JOIN transactions t ON ci.transaction_id = t.id
          WHERE ci.namespace = ?
            AND ci.identifier_type = ?
            AND ci.complete_value = ?
            AND ci.stable_event_kind = ?
        ''', [
          request.identifier!.namespace,
          request.identifier!.identifierType,
          request.identifier!.completeValue.trim(),
          request.identifier!.stableEventKind,
        ]);

        if (idRow.isNotEmpty) {
          final matchedTxId = idRow.first['transaction_id'] as String;
          final isTrash = idRow.first['deleted_at'] != null;

          if (isTrash) {
            throw TrashBinCollisionException(
              message:
                  'A transaction with identical platform identifier exists in the 30-day trash bin',
              trashTransactionId: matchedTxId,
            );
          } else {
            throw HardDuplicateException(
              message:
                  'Duplicate platform identifier detected in active transactions',
              existingTransactionId: matchedTxId,
            );
          }
        }
      }

      // 4. Insert into transactions
      await txn.insert('transactions', tx.toMap());

      // 5. Insert into transaction_metadata (if provided)
      if (request.metadata != null) {
        final meta = request.metadata!.copyWith(transactionId: tx.id);
        await txn.insert('transaction_metadata', meta.toMap());
      }

      // 6. Insert into transaction_tags (if provided)
      if (request.tagIds != null && request.tagIds!.isNotEmpty) {
        for (final tagId in request.tagIds!) {
          await txn.insert('transaction_tags', {
            'transaction_id': tx.id,
            'tag_id': tagId,
          });
        }
      }

      // 7. Insert into confirmed_identifiers (if provided)
      if (request.identifier != null &&
          request.identifier!.completeValue.trim().isNotEmpty) {
        final ident = request.identifier!.copyWith(transactionId: tx.id);
        await txn.insert('confirmed_identifiers', ident.toMap());
      }

      // 8. Insert into refund_links (if refund with originalExpenseId)
      if (tx.type == 'refund' &&
          request.originalExpenseId != null &&
          request.originalExpenseId!.isNotEmpty) {
        await txn.insert('refund_links', {
          'refund_transaction_id': tx.id,
          'original_expense_id': request.originalExpenseId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      // 9. Update drafts table with saved_transaction_id
      final nowIso = DateTime.now().toUtc().toIso8601String();
      if (draftId != null && draftId.isNotEmpty) {
        await txn.update(
          'drafts',
          {
            'saved_transaction_id': tx.id,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [draftId],
        );
      }

      // 10. Update capture_jobs table to COMMITTED state
      if (captureJobId != null) {
        await txn.update(
          'capture_jobs',
          {
            'state': CaptureJobState.committed.value,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [captureJobId],
        );
      }

      return tx;
    });
  }

  /// Discards a draft by transitioning its parent capture job to DISCARDED.
  Future<void> discardDraft(String draftId) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'drafts',
        columns: ['capture_id'],
        where: 'id = ?',
        whereArgs: [draftId],
      );
      if (rows.isEmpty) {
        throw DraftNotFoundException(draftId);
      }
      final captureId = rows.first['capture_id'] as String;
      await CaptureJobStateMachine.transition(
        txn,
        captureId,
        CaptureJobState.discarded,
      );
    });
  }

  /// Soft deletes a transaction into the 30-day trash bin.
  Future<bool> softDeleteTransaction(
    String transactionId, {
    DateTime? deletedAt,
    DatabaseExecutor? customExecutor,
  }) async {
    final db = customExecutor ?? await _databaseHelper.database;
    return await SoftDeleteManager.softDeleteTransaction(
      db,
      transactionId,
      deletedAt: deletedAt,
    );
  }

  /// Restores a soft-deleted transaction from the trash bin.
  /// If [targetDraftId] is provided, links the draft and sets job state to COMMITTED.
  Future<bool> restoreFromTrash(
    String transactionId, {
    String? targetDraftId,
    DateTime? restoredAt,
    DatabaseExecutor? customExecutor,
  }) async {
    final db = customExecutor is Database
        ? customExecutor
        : await _databaseHelper.database;

    return await db.transaction((txn) async {
      final restored = await SoftDeleteManager.restoreTransaction(
        txn,
        transactionId,
        restoredAt: restoredAt,
      );
      if (!restored) return false;

      if (targetDraftId != null && targetDraftId.isNotEmpty) {
        final nowIso = (restoredAt ?? DateTime.now().toUtc()).toIso8601String();
        await txn.update(
          'drafts',
          {
            'saved_transaction_id': transactionId,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [targetDraftId],
        );

        final draftRows = await txn.query(
          'drafts',
          columns: ['capture_id'],
          where: 'id = ?',
          whereArgs: [targetDraftId],
        );
        if (draftRows.isNotEmpty) {
          final captureId = draftRows.first['capture_id'] as String;
          await txn.update(
            'capture_jobs',
            {
              'state': CaptureJobState.committed.value,
              'updated_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: [captureId],
          );
        }
      }
      return true;
    });
  }

  /// Permanently removes a transaction from SQLite storage.
  /// Triggers cascades on metadata, tags, confirmed_identifiers, and unlinks refund_links.
  Future<bool> permanentDeleteTransaction(
    String transactionId, {
    DatabaseExecutor? customExecutor,
  }) async {
    final db = customExecutor ?? await _databaseHelper.database;
    return await SoftDeleteManager.permanentDeleteTransaction(
      db,
      transactionId,
    );
  }

  /// Purges transactions residing in the trash bin for longer than [retentionDays].
  Future<int> purgeExpiredTrash({
    int retentionDays = 30,
    DateTime? referenceTime,
    DatabaseExecutor? customExecutor,
  }) async {
    final db = customExecutor ?? await _databaseHelper.database;
    return await SoftDeleteManager.purgeExpiredTrash(
      db,
      retentionDays: retentionDays,
      referenceTime: referenceTime,
    );
  }

  /// Calculates monthly financial accounting summary for a given month ('YYYY-MM').
  Future<MonthlyAccountingSummary> getMonthlySummary(
    String yearMonth, {
    DatabaseExecutor? customExecutor,
  }) async {
    final db = customExecutor ?? await _databaseHelper.database;
    final startDate = '$yearMonth-01';
    final endDate = '$yearMonth-31';
    return await SoftDeleteManager.calculateMonthlySummary(
      db,
      startDate: startDate,
      endDate: endDate,
    );
  }
}
