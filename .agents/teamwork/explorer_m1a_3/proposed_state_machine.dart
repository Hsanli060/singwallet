import 'package:sqflite/sqflite.dart';

/// Represents the deterministic lifecycle states of an ingestion capture job.
enum CaptureJobState {
  /// Initial state when screenshot/image is ingested into the private sandbox.
  imported('IMPORTED'),

  /// OCR recognition and extraction pipeline is actively executing.
  recognizing('RECOGNIZING'),

  /// OCR and parsing succeeded; intermediate draft is created, waiting for user review.
  needsReview('NEEDS_REVIEW'),

  /// User confirmed the draft and it was committed to the formal ledger. Terminal state.
  committed('COMMITTED'),

  /// OCR recognition or parsing failed. Can be retried.
  failed('FAILED'),

  /// User explicitly discarded the draft or capture. Terminal state.
  discarded('DISCARDED');

  final String value;
  const CaptureJobState(this.value);

  /// Converts a database string value into a [CaptureJobState] enum.
  static CaptureJobState fromString(String val) {
    for (final state in CaptureJobState.values) {
      if (state.value == val) return state;
    }
    throw ArgumentError.value(val, 'val', 'Unknown CaptureJobState');
  }

  /// Whether this state is a terminal lifecycle state.
  bool get isTerminal => this == committed || this == discarded;
}

/// Thrown when an illegal state transition is attempted on a capture job.
class InvalidStateTransitionException implements Exception {
  final CaptureJobState from;
  final CaptureJobState to;
  final String? jobId;
  final String message;

  InvalidStateTransitionException({
    required this.from,
    required this.to,
    this.jobId,
    String? message,
  }) : message = message ??
            'Invalid state transition from "${from.value}" to "${to.value}"'
                '${jobId != null ? " for job ID: $jobId" : ""}';

  @override
  String toString() => 'InvalidStateTransitionException: $message';
}

/// Thrown when an operation targets a non-existent capture job.
class JobNotFoundException implements Exception {
  final String jobId;
  JobNotFoundException(this.jobId);

  @override
  String toString() => 'JobNotFoundException: Job with ID "$jobId" not found.';
}

/// Deterministic state machine governing ingestion capture jobs and startup crash recovery.
class CaptureJobStateMachine {
  CaptureJobStateMachine._();

  /// Explicit transition rules matrix: Source State -> Set of allowed Target States.
  static const Map<CaptureJobState, Set<CaptureJobState>> _allowedTransitions = {
    CaptureJobState.imported: {
      CaptureJobState.recognizing,
      CaptureJobState.discarded,
      CaptureJobState.failed,
    },
    CaptureJobState.recognizing: {
      CaptureJobState.needsReview,
      CaptureJobState.failed,
      CaptureJobState.imported, // Startup self-healing recovery
      CaptureJobState.discarded,
    },
    CaptureJobState.needsReview: {
      CaptureJobState.committed,
      CaptureJobState.discarded,
      CaptureJobState.recognizing, // User requests re-recognition
    },
    CaptureJobState.failed: {
      CaptureJobState.recognizing, // User or automated retry
      CaptureJobState.imported,    // Re-queue
      CaptureJobState.discarded,   // User gives up
    },
    CaptureJobState.committed: {}, // Terminal state - no further transitions permitted
    CaptureJobState.discarded: {}, // Terminal state - no further transitions permitted
  };

  /// Returns true if transitioning from [from] to [to] is permitted.
  static bool canTransition(CaptureJobState from, CaptureJobState to) {
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  /// Returns the set of valid destination states for a given [current] state.
  static Set<CaptureJobState> allowedNextStates(CaptureJobState current) {
    return _allowedTransitions[current] ?? const {};
  }

  /// Transitions a capture job to [targetState], validating rules and updating metadata.
  ///
  /// Increments `attempt_count` when entering [CaptureJobState.recognizing].
  /// Updates `updated_at` to the current UTC ISO-8601 timestamp.
  static Future<void> transition(
    DatabaseExecutor db,
    String jobId,
    CaptureJobState targetState, {
    DateTime? timestamp,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'capture_jobs',
      columns: ['state', 'attempt_count'],
      where: 'id = ?',
      whereArgs: [jobId],
    );

    if (rows.isEmpty) {
      throw JobNotFoundException(jobId);
    }

    final currentState = CaptureJobState.fromString(rows.first['state'] as String);
    final int currentAttempts = (rows.first['attempt_count'] as int?) ?? 0;

    if (!canTransition(currentState, targetState)) {
      throw InvalidStateTransitionException(
        from: currentState,
        to: targetState,
        jobId: jobId,
      );
    }

    final nowIso = (timestamp ?? DateTime.now().toUtc()).toIso8601String();
    final Map<String, Object?> updates = {
      'state': targetState.value,
      'updated_at': nowIso,
    };

    if (targetState == CaptureJobState.recognizing) {
      updates['attempt_count'] = currentAttempts + 1;
    }

    await db.update(
      'capture_jobs',
      updates,
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  /// Startup Crash Recovery: Scans for lingering tasks stuck in [CaptureJobState.recognizing]
  /// due to an unexpected OS kill, crash, or memory ejection.
  ///
  /// Resets jobs with `attempt_count < maxAttempts` back to [CaptureJobState.imported]
  /// so they can be retried cleanly.
  ///
  /// Transitions jobs with `attempt_count >= maxAttempts` to [CaptureJobState.failed]
  /// to prevent infinite retry loops.
  ///
  /// Returns the count of recovered jobs.
  static Future<int> recoverLingeringJobs(
    DatabaseExecutor db, {
    int maxAttempts = 3,
    DateTime? recoveryTimestamp,
  }) async {
    final List<Map<String, Object?>> lingering = await db.query(
      'capture_jobs',
      columns: ['id', 'attempt_count'],
      where: 'state = ?',
      whereArgs: [CaptureJobState.recognizing.value],
    );

    if (lingering.isEmpty) {
      return 0;
    }

    final nowIso = (recoveryTimestamp ?? DateTime.now().toUtc()).toIso8601String();
    int recoveredCount = 0;

    for (final row in lingering) {
      final String id = row['id'] as String;
      final int attempts = (row['attempt_count'] as int?) ?? 0;

      if (attempts >= maxAttempts) {
        // Exceeded limit: transition to FAILED
        await db.update(
          'capture_jobs',
          {
            'state': CaptureJobState.failed.value,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        // Recoverable: transition back to IMPORTED
        await db.update(
          'capture_jobs',
          {
            'state': CaptureJobState.imported.value,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      recoveredCount++;
    }

    return recoveredCount;
  }
}
