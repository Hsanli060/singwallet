# Handoff Report — Milestone M1-A Forensic Integrity Audit

**Date**: 2026-10-22  
**Sender**: `auditor_m1a_1` (Forensic Auditor, Critic, Specialist)  
**Recipient**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)  
**Type**: Hard Handoff (Audit Complete)  

---

## 1. Observation

1. **Schema & DDL Definition (`lib/data/database/schema.dart:26-247`)**:
   - `AppSchema.createTablesStatements` defines 12 core tables (`capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers`).
   - `AppSchema.createIndicesStatements` defines 11 indices (`idx_capture_jobs_hash`, `idx_capture_jobs_state`, `idx_drafts_saved_tx`, `idx_tx_occurred_on`, `idx_tx_category`, `idx_tx_deleted_at`, `idx_tx_project`, `idx_tx_account`, `idx_transaction_tags_tag`, `idx_refund_original`, `idx_confirmed_identifiers_tx`).
   - All 12 tables and 11 indices strictly match the specification in `docs/跨平台架构与数据规范.md:143-340`.

2. **Connection & Foreign Key Enforcement (`lib/data/database/app_database.dart:70, 106`)**:
   - `onConfigure` callback in both `open()` (line 70) and `openInMemory()` (line 106) executes `await db.execute('PRAGMA foreign_keys = ON;');`.

3. **Atomic Multi-Table Draft Commitment (`lib/data/database/transaction_manager.dart:107-272`)**:
   - `TransactionManager.commitDraft` wraps operations across 7 tables in `await db.transaction((txn) async { ... })`.
   - On constraint failure (e.g. `amount_minor = 0` violating CHECK constraint), all intermediate mutations are completely rolled back, leaving `transactions` uninserted, `drafts.saved_transaction_id` as `NULL`, and `capture_jobs.state` as `NEEDS_REVIEW`.

4. **State Machine & Soft Delete (`lib/data/database/state_machine.dart`, `soft_delete_manager.dart`)**:
   - `CaptureJobStateMachine` enforces the transition rules matrix (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED`).
   - `recoverLingeringJobs` safely resets interrupted jobs in `RECOGNIZING` state back to `IMPORTED` (if `attempts < max`) or `FAILED` (if `attempts >= max`).
   - `SoftDeleteManager` manages `deleted_at` marking, trash retention purge, and monthly summary aggregations strictly filtering `deleted_at IS NULL`.

5. **Deduplication Hierarchy (`lib/features/deduplication/deduplication_engine.dart:218-469`)**:
   - Tier 1: checks `transactions.origin_draft_id` uniqueness and flags active vs trash.
   - Tier 2: checks `capture_jobs.content_hash` matching image SHA-256.
   - Tier 3: checks `confirmed_identifiers` compound primary key (`namespace`, `identifier_type`, `complete_value`, `stable_event_kind`), ignoring masked/truncated IDs.
   - Tier 4: checks heuristic match (`merchant_raw`/`merchant_normalized`, `amount_minor`, 24-hour window) and returns a soft candidate warning without blocking legitimate consecutive purchases.

6. **Tautology & Assertion Audit (`test/database/`, `test/deduplication/`)**:
   - Grep search for `expect(true, isTrue)`: 0 occurrences.
   - Grep search for constant LHS in `expect(...)`: 0 occurrences.
   - Grep search for skipped tests (`skip: true`): 0 occurrences.
   - All 38 M1-A test cases assert non-trivial state changes against in-memory SQLite instances.

7. **Execution Verification**:
   - `flutter analyze`: exit code 0 (`No issues found! (ran in 7.5s)`).
   - `flutter test`: exit code 0 (`00:01 +99: All tests passed!`).
   - `flutter test test/database/database_test.dart`: exit code 0 (`00:00 +22: All tests passed!`).
   - `flutter test test/deduplication/deduplication_test.dart`: exit code 0 (`00:00 +16: All tests passed!`).
   - `python test_docs_integrity.py`: exit code 0 (`>>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<`).

---

## 2. Logic Chain

1. From **Observation 1**, `lib/data/database/schema.dart` implements the exact 12-table and 11-index schema mandated by the project data specification.
2. From **Observation 2**, `AppDatabase` guarantees that relational integrity and cascade rules (`ON DELETE CASCADE`, `ON DELETE SET NULL`, `ON DELETE RESTRICT`) are enforced at the SQLite engine level by executing `PRAGMA foreign_keys = ON;` on every connection.
3. From **Observation 3**, `TransactionManager.commitDraft` delivers true ACID transactional atomicity. A constraint failure mid-commit triggers a complete rollback without corrupting draft or capture job states.
4. From **Observation 4**, the state machine and trash bin managers handle ingestion life-cycles, crash self-healing, and monthly accounting with soft-delete filtering.
5. From **Observation 5**, the 4-tier deduplication engine implements all 4 distinct layers: technical idempotence, image hash match, platform identifier compound PK match, and 24-hour heuristic fuzzy warning.
6. From **Observation 6**, the test suite is genuine and substantive, containing zero tautological assertions, zero constant checks, and zero skipped tests.
7. From **Observation 7**, static code analysis is clean, all 99 tests pass, and the python documentation integrity suite passes 100%.
8. Therefore, the implementation is authentic, complete, robust, and free of integrity violations.

---

## 3. Caveats

1. **System SQLite DLL Binding on Windows**: The `hooks: user_defines: sqlite3: source: system, name: winsqlite3` in `pubspec.yaml` targets Windows desktop environments subject to AppLocker. Mobile platforms (iOS and Android) automatically bundle their native platform SQLite libraries.
2. **Milestone M1-B Boundary**: The OCR parsing engine (`ocr_pipeline.dart`) and classification rule engine matcher (`rule_matcher.dart`) are planned for Milestone M1-B. The data structures and database schema for them (`classification_rules`, `drafts.candidate_fields`, `drafts.field_evidence`) are fully established and validated in M1-A.

---

## 4. Conclusion

**Verdict**: **CLEAN**.  
Milestone M1-A passes all forensic audit and adversarial stress tests. The data layer, transaction manager, state machine, soft delete manager, and 4-tier deduplication engine are fully functional, production-ready, and approved for gate passage.

---

## 5. Verification Method

To independently reproduce the audit verification results:

```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path

# 1. Static code analysis (must report 0 issues)
flutter analyze

# 2. Complete test suite (must execute all 99 tests and pass)
flutter test

# 3. Database sub-suite (22 tests)
flutter test test/database/database_test.dart

# 4. Deduplication sub-suite (16 tests)
flutter test test/deduplication/deduplication_test.dart

# 5. Documentation & SQLite DDL integrity test suite (all 6 suites must pass)
python test_docs_integrity.py
```

### Invalidation Conditions
- Any exit code other than 0.
- Any test failures or skipped tests.
- Any reported static analysis warnings or errors.
- Any discrepancy in table or index names compared to `docs/跨平台架构与数据规范.md`.
