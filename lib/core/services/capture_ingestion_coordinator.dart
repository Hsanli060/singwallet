// lib/core/services/capture_ingestion_coordinator.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../data/database/state_machine.dart';
import '../../data/models/capture_job.dart';
import '../../data/models/draft.dart';
import '../../features/recognition/ocr_pipeline.dart';
import '../native/native_bridge.g.dart';
import '../native/native_bridge_service.dart';

/// Coordinates end-to-end ingestion of external screenshots (Back-Tap `ScreenshotContentObserver`,
/// Android System Share Sheet, Clipboard, or Shortcuts) from [NativeBridgeService] into SQLite
/// `capture_jobs` and `drafts`.
class CaptureIngestionCoordinator {
  final DatabaseExecutor _db;
  final NativeBridgeService _bridge;
  final OcrParsingPipeline _pipeline;
  final Set<String> _inFlightCaptureIds = <String>{};

  CaptureIngestionCoordinator({
    required DatabaseExecutor db,
    required NativeBridgeService bridge,
    required OcrParsingPipeline pipeline,
  })  : _db = db,
        _bridge = bridge,
        _pipeline = pipeline;

  /// Scans and processes any pending screenshots stored in native private `pending_captures/`
  /// directory (e.g. cold-launch shares or background captures queued prior to engine readiness).
  Future<List<Draft>> syncPendingExternalCaptures() async {
    final createdDrafts = <Draft>[];
    List<CaptureResult> pending;
    try {
      pending = await _bridge.fetchPendingExternalCaptures();
    } catch (_) {
      // Gracefully no-op in desktop/test environments without native host channel
      return createdDrafts;
    }

    for (final capture in pending) {
      final draft = await ingestCapture(capture);
      if (draft != null) {
        createdDrafts.add(draft);
      }
    }
    return createdDrafts;
  }

  /// Ingests a single [CaptureResult], executes native offline OCR & 8-stage parsing,
  /// and persists the synthesized [Draft] in `NEEDS_REVIEW` state.
  ///
  /// Returns the newly created [Draft], or `null` if deduplicated or failed.
  Future<Draft?> ingestCapture(CaptureResult capture) async {
    final captureId = capture.captureId;
    if (captureId.isEmpty || _inFlightCaptureIds.contains(captureId)) {
      return null;
    }

    _inFlightCaptureIds.add(captureId);
    try {
      // 1. Check if this exact captureId already exists in capture_jobs
      final existingById = await _db.query(
        'capture_jobs',
        columns: ['id', 'state'],
        where: 'id = ?',
        whereArgs: [captureId],
        limit: 1,
      );

      if (existingById.isNotEmpty) {
        final stateStr = existingById.first['state'] as String? ?? '';
        if (stateStr == CaptureJobState.needsReview.value ||
            stateStr == CaptureJobState.committed.value ||
            stateStr == CaptureJobState.discarded.value ||
            stateStr == CaptureJobState.recognizing.value) {
          return null;
        }
      } else {
        // 2. Deduplicate by SHA-256 content_hash against active/committed jobs
        if (capture.contentHash.isNotEmpty) {
          final existingByHash = await _db.query(
            'capture_jobs',
            columns: ['id', 'state'],
            where: 'content_hash = ? AND state IN (?, ?, ?)',
            whereArgs: [
              capture.contentHash,
              CaptureJobState.needsReview.value,
              CaptureJobState.committed.value,
              CaptureJobState.recognizing.value,
            ],
            limit: 1,
          );
          if (existingByHash.isNotEmpty) {
            await _safeDeleteRedundantImage(captureId);
            return null;
          }
        }

        // 3. Create initial IMPORTED capture_job record
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final job = CaptureJob(
          id: captureId,
          contentHash: capture.contentHash,
          sourceKind: capture.sourceKind.name,
          importedAt: nowIso,
          privateImageRef: capture.localFilePath,
          state: CaptureJobState.imported.value,
          attemptCount: 0,
          parserVersion: 1,
          createdAt: nowIso,
          updatedAt: nowIso,
        );
        await _db.insert('capture_jobs', job.toMap());
      }

      // 4. Transition to RECOGNIZING (increments attempt_count)
      await CaptureJobStateMachine.transition(
        _db,
        captureId,
        CaptureJobState.recognizing,
      );

      // 5. Execute native offline OCR & 8-stage bill extraction pipeline
      final ocrDoc = await _bridge.recognizeCapture(captureId);
      final draftId = 'draft_$captureId';
      final parsed = await _pipeline.process(
        ocrDoc,
        contentHash: capture.contentHash,
        draftId: draftId,
      );

      final draft = parsed.toDraftEntity(
        draftId: draftId,
        captureId: captureId,
      );

      await _db.insert(
        'drafts',
        draft.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 6. Transition to NEEDS_REVIEW so DraftsQueueScreen displays it immediately
      await CaptureJobStateMachine.transition(
        _db,
        captureId,
        CaptureJobState.needsReview,
      );

      return draft;
    } catch (_) {
      try {
        await CaptureJobStateMachine.transition(
          _db,
          captureId,
          CaptureJobState.failed,
        );
      } catch (_) {}
      return null;
    } finally {
      _inFlightCaptureIds.remove(captureId);
    }
  }

  Future<void> _safeDeleteRedundantImage(String captureId) async {
    try {
      await _bridge.deleteCaptureImage(captureId);
    } catch (_) {}
  }
}
