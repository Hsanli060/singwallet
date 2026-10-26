// lib/data/repositories/draft_repository.dart
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/state_machine.dart';
import '../database/transaction_manager.dart';
import '../models/models.dart';

typedef DraftEntry = Draft;

/// Detailed view model for a draft including its deserialized candidate fields,
/// OCR evidences, validation warnings, and parent ingestion job.
class DraftDetail {
  final Draft draft;
  final CaptureJob? captureJob;
  final Map<String, dynamic> candidateFields;
  final Map<String, dynamic> fieldEvidence;
  final List<String> validationIssues;
  final List<String> duplicateCandidates;

  const DraftDetail({
    required this.draft,
    this.captureJob,
    required this.candidateFields,
    required this.fieldEvidence,
    required this.validationIssues,
    required this.duplicateCandidates,
  });

  factory DraftDetail.fromDraftAndJob(Draft draft, CaptureJob? job) {
    Map<String, dynamic> candidateMap = {};
    try {
      final decoded = jsonDecode(draft.candidateFields);
      if (decoded is Map<String, dynamic>) {
        candidateMap = decoded;
      }
    } catch (_) {}

    Map<String, dynamic> evidenceMap = {};
    try {
      final decoded = jsonDecode(draft.fieldEvidence);
      if (decoded is Map<String, dynamic>) {
        evidenceMap = decoded;
      }
    } catch (_) {}

    List<String> issuesList = [];
    try {
      final decoded = jsonDecode(draft.validationIssues);
      if (decoded is List) {
        issuesList = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    List<String> dupsList = [];
    try {
      final decoded = jsonDecode(draft.duplicateCandidates);
      if (decoded is List) {
        dupsList = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return DraftDetail(
      draft: draft,
      captureJob: job,
      candidateFields: candidateMap,
      fieldEvidence: evidenceMap,
      validationIssues: issuesList,
      duplicateCandidates: dupsList,
    );
  }
}

/// Result of committing a draft to the formal financial ledger.
class CommitDraftResult {
  final bool success;
  final TransactionEntry? transaction;
  final String? errorMessage;
  final bool isHardDuplicate;
  final bool isTrashCollision;
  final String? collidingTransactionId;

  const CommitDraftResult({
    required this.success,
    this.transaction,
    this.errorMessage,
    this.isHardDuplicate = false,
    this.isTrashCollision = false,
    this.collidingTransactionId,
  });

  factory CommitDraftResult.ok(TransactionEntry tx) =>
      CommitDraftResult(success: true, transaction: tx);

  factory CommitDraftResult.hardDuplicate({
    required String message,
    required String existingTxId,
  }) =>
      CommitDraftResult(
        success: false,
        errorMessage: message,
        isHardDuplicate: true,
        collidingTransactionId: existingTxId,
      );

  factory CommitDraftResult.trashCollision({
    required String message,
    required String trashTxId,
  }) =>
      CommitDraftResult(
        success: false,
        errorMessage: message,
        isTrashCollision: true,
        collidingTransactionId: trashTxId,
      );

  factory CommitDraftResult.error(String message) =>
      CommitDraftResult(success: false, errorMessage: message);
}

/// Abstract contract for OCR draft management.
abstract class IDraftRepository {
  Future<List<DraftEntry>> getPendingDrafts();
  Future<DraftDetail?> getDraftDetail(String draftId);
  Future<CommitDraftResult> commitDraft(CommitDraftRequest request);
  Future<void> discardDraft(String draftId);
}

/// Production implementation of [IDraftRepository].
class DraftRepository implements IDraftRepository {
  final DatabaseExecutor _db;
  final TransactionManager _txManager;

  DraftRepository(
    DatabaseExecutor db, {
    TransactionManager? txManager,
  })  : _db = db,
        _txManager = txManager ?? TransactionManager();

  @override
  Future<List<DraftEntry>> getPendingDrafts() async {
    final rows = await _db.rawQuery('''
      SELECT d.*
      FROM drafts d
      JOIN capture_jobs cj ON d.capture_id = cj.id
      WHERE cj.state IN (?, ?)
        AND d.saved_transaction_id IS NULL
      ORDER BY d.created_at DESC
    ''', [CaptureJobState.needsReview.value, CaptureJobState.imported.value]);

    return rows.map(Draft.fromMap).toList();
  }

  @override
  Future<DraftDetail?> getDraftDetail(String draftId) async {
    final draftRows = await _db.query(
      'drafts',
      where: 'id = ?',
      whereArgs: [draftId],
      limit: 1,
    );

    if (draftRows.isEmpty) return null;
    final draft = Draft.fromMap(draftRows.first);

    final jobRows = await _db.query(
      'capture_jobs',
      where: 'id = ?',
      whereArgs: [draft.captureId],
      limit: 1,
    );

    final job = jobRows.isNotEmpty ? CaptureJob.fromMap(jobRows.first) : null;
    return DraftDetail.fromDraftAndJob(draft, job);
  }

  @override
  Future<CommitDraftResult> commitDraft(CommitDraftRequest request) async {
    try {
      final tx = await _txManager.commitDraft(request, customExecutor: _db);
      return CommitDraftResult.ok(tx);
    } on HardDuplicateException catch (e) {
      return CommitDraftResult.hardDuplicate(
        message: e.message,
        existingTxId: e.existingTransactionId,
      );
    } on TrashBinCollisionException catch (e) {
      return CommitDraftResult.trashCollision(
        message: e.message,
        trashTxId: e.trashTransactionId,
      );
    } catch (e) {
      return CommitDraftResult.error(e.toString());
    }
  }

  @override
  Future<void> discardDraft(String draftId) async {
    // If _db is a Database, use transaction. If it's already a Transaction or DatabaseExecutor:
    if (_db is Database) {
      await _db.transaction((txn) async {
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
    } else {
      final rows = await _db.query(
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
        _db,
        captureId,
        CaptureJobState.discarded,
      );
    }
  }
}
