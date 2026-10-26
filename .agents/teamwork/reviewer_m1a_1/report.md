# Milestone M1-A Review & Adversarial Challenge Report

**Reviewer**: `reviewer_m1a_1` (Roles: reviewer, critic)  
**Date**: 2026-10-22  
**Target Milestone**: M1-A (Unified SQLite Data Layer, Schema, Relational Integrity & Transaction Manager)  
**Worker Under Review**: `worker_m1a_1`  
**Parent Orchestrator**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)  

---

## 1. Review Summary

**Verdict**: **APPROVE**

Milestone M1-A has been thoroughly reviewed and stress-tested against the authoritative architecture specification (`docs/跨平台架构与数据规范.md`), project requirements (`PROJECT.md`, `ORIGINAL_REQUEST.md`), and the deep integrity test suite (`test_docs_integrity.py`).

The implementation exhibits high production quality:
- All 12 SQLite tables and 11 specialized B-tree indices conform to specifications.
- Relational integrity (`PRAGMA foreign_keys = ON;` in `onConfigure`) is guaranteed across all SQLite connections.
- Foreign key cascades, restrict constraints, integer cent currency math (`CHECK (amount_minor > 0)`), and unique draft idempotence constraints are strictly implemented and verified.
- Draft commitment operates within an atomic SQLite transaction spanning 7 affected tables with verified rollback on failure.
- Soft-delete trash bin operations, state machine transitions, crash recovery, and 4-tier deduplication operate with ACID consistency.
- No integrity violations, facade implementations, or hardcoded dummy outputs were detected.

---

## 2. Integrity Audit & Attestation

As an adversarial reviewer, active integrity checks were conducted across the entire delivery:
1. **No Hardcoded Test Results**:
   - `lib/data/database/transaction_manager.dart`, `app_database.dart`, `soft_delete_manager.dart`, `state_machine.dart`, and `lib/features/deduplication/deduplication_engine.dart` were scrutinized. All database queries are dynamic, parameterized SQL queries executing against real in-memory/on-disk SQLite instances.
2. **No Facade or Dummy Implementations**:
   - DDL statements in `schema.dart` define actual SQLite schema structures.
   - `TransactionManager.commitDraft` executes real multi-table inserts/updates within `db.transaction(...)`.
   - `DeduplicationEngine` performs genuine SQLite queries checking draft idempotence, content hashes, platform compound keys, and heuristic date/amount windows.
3. **No Shortcuts or Bypasses**:
   - The solution utilizes standard Flutter/Dart SQLite FFI bindings (`sqflite_common_ffi` with system `winsqlite3` on Windows), passing all unit tests cleanly without disabling foreign keys, relaxations of constraints, or mocking out database internals.
4. **Independent Verification**:
   - Independent verification commands were run directly on the host environment:
     - `flutter analyze` -> 0 issues found (ran in 8.0s, exit code 0).
     - `flutter test` -> 99/99 tests passed (61 pre-existing + 38 M1-A tests, exit code 0).
     - `python test_docs_integrity.py` -> 6/6 deep test suites passed 100% (exit code 0).

**Integrity Finding**: **CLEAN — NO INTEGRITY VIOLATION DETECTED.**

---

## 3. Detailed Review Findings

### 3.1 Schema & Table Definitions (`lib/data/database/schema.dart`)
- **12 Tables**: `capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers`. All column names, nullability constraints, defaults, foreign key definitions, and table names match `docs/跨平台架构与数据规范.md` lines 143–340.
- **11 Performance Indices**: Verified exact matching of all 11 required indices:
  1. `idx_capture_jobs_hash` ON `capture_jobs(content_hash)`
  2. `idx_capture_jobs_state` ON `capture_jobs(state)`
  3. `idx_drafts_saved_tx` ON `drafts(saved_transaction_id)`
  4. `idx_tx_occurred_on` ON `transactions(occurred_on)`
  5. `idx_tx_category` ON `transactions(category_id)`
  6. `idx_tx_deleted_at` ON `transactions(deleted_at)`
  7. `idx_tx_project` ON `transactions(project_id)`
  8. `idx_tx_account` ON `transactions(account_id)`
  9. `idx_transaction_tags_tag` ON `transaction_tags(tag_id)`
  10. `idx_refund_original` ON `refund_links(original_expense_id)`
  11. `idx_confirmed_identifiers_tx` ON `confirmed_identifiers(transaction_id)`
- **Constraints**:
  - `CHECK (amount_minor > 0)` enforced on `transactions`.
  - `origin_draft_id TEXT UNIQUE` enforced on `transactions`.
  - `capture_id TEXT NOT NULL UNIQUE` enforced on `drafts`.
  - Primary Key `(namespace, identifier_type, complete_value, stable_event_kind)` enforced on `confirmed_identifiers`.
  - Primary Key `(transaction_id, tag_id)` enforced on `transaction_tags`.

### 3.2 Database Initialization & Connection (`lib/data/database/app_database.dart`)
- `PRAGMA foreign_keys = ON;` is executed in `onConfigure` for both persistent `open()` and in-memory `openInMemory()`. In SQLite, `onConfigure` runs immediately upon connection creation before any table queries, guaranteeing that foreign key enforcement is active from the first statement.
- WAL mode (`PRAGMA journal_mode = WAL;`) and `PRAGMA synchronous = NORMAL;` are properly applied on disk-backed databases.
- Headless testing via `sqflite_common_ffi` works seamlessly.

### 3.3 Transaction Manager & Atomicity (`lib/data/database/transaction_manager.dart`)
- `commitDraft` wraps 7 tables in a single SQLite transaction callback (`db.transaction((txn) async { ... })`):
  1. `transactions` (insert new record)
  2. `transaction_metadata` (insert if metadata supplied)
  3. `transaction_tags` (insert tag relations)
  4. `confirmed_identifiers` (insert complete platform ID)
  5. `refund_links` (insert link if refund type and originalExpenseId provided)
  6. `drafts` (update `saved_transaction_id`)
  7. `capture_jobs` (update state to `COMMITTED`)
- All database calls inside the closure correctly pass `txn`, preventing connection deadlocks and ensuring atomic rollback upon any thrown exception.
- Rollback was explicitly stress-tested by injecting constraint failures (e.g. `amount_minor = 0`); all intermediate table mutations were verified to be rolled back cleanly.

### 3.4 Soft Delete & Trash Bin (`lib/data/database/soft_delete_manager.dart`)
- Soft delete marks `deleted_at = nowIso` while retaining the row and its associated `confirmed_identifiers` to prevent duplicate re-ingestion during the 30-day trash retention window.
- Recovery from trash bin (`restoreTransaction`) resets `deleted_at = NULL`.
- Monthly financial queries (`calculateMonthlySummary`) strictly filter `deleted_at IS NULL` and aggregate `occurred_on BETWEEN ? AND ?`, properly computing `netExpense = totalExpense - totalRefund`.
- Purge query (`purgeExpiredTrash`) removes records where `deleted_at < (now - retentionDays)` with automatic cascade deletion of metadata, tags, and confirmed identifiers.

### 3.5 Deduplication Engine (`lib/features/deduplication/deduplication_engine.dart`)
- Fully implements the 4-tier deduplication hierarchy:
  - **Tier 1 (Technical Idempotence)**: `origin_draft_id` uniqueness check against active and trashed transactions.
  - **Tier 2 (Same-Image Hash)**: SHA-256 image content hash matching in `capture_jobs`.
  - **Tier 3 (Platform Identifier)**: Hard deduplication using compound key, gated strictly on complete identifiers (`completeness == IdentifierCompleteness.complete`), distinguishing active vs trash duplicates.
  - **Tier 4 (Heuristic Fuzzy Match)**: Same merchant + identical amount + within 24h time delta surfaces soft warning candidates without blocking manual confirmation.

---

## 4. Adversarial Challenges & Stress-Testing

### Challenge 1: Trash Bin Collision vs. Duplicate Platform ID
- **Assumption**: A user soft-deletes a transaction and later re-scans the same transaction screenshot.
- **Attack Scenario**: If Tier 3 checked only `transactions.deleted_at IS NULL`, the re-imported screenshot would be accepted, creating duplicate ledger entries or violating `confirmed_identifiers` primary key on insert.
- **Observed Behavior**:
  - `DeduplicationEngine.checkTier3PlatformId` queries both active and trashed transactions.
  - If a match is found in trash (`deleted_at IS NOT NULL`), it returns `Tier3Result.trashBinDuplicate(...)`.
  - `TransactionManager.commitDraft` throws `TrashBinCollisionException`, giving the UI a clear mechanism to prompt: "A matching transaction is in the trash bin. Restore it instead?"
- **Assessment**: **PASSED**. Robust design avoids silent duplication and PK conflict.

### Challenge 2: Date String Range in Monthly Aggregations
- **Assumption**: `SoftDeleteManager.calculateMonthlySummary` uses `'$yearMonth-01'` and `'$yearMonth-31'`.
- **Attack Scenario**: For months with fewer than 31 days (April, June, September, November, February), does lexicographical comparison `'YYYY-MM-01' <= occurred_on <= 'YYYY-MM-31'` miss days or include days from the next month?
- **Analysis**:
  - For standard ISO-8601 `YYYY-MM-DD` strings, `'2026-04-30' < '2026-04-31'` and `'2026-05-01' > '2026-04-31'`.
  - Thus, lexicographical comparison accurately bounds all days within the target month and strictly excludes subsequent months.
  - *Advisory Note (Minor)*: Callers must ensure `occurred_on` strictly adheres to `YYYY-MM-DD` (with 2-digit zero-padded months and days) to maintain lexicographical ordering invariant.

### Challenge 3: Windows AppLocker and Native SQLite Linking
- **Assumption**: Headless test execution on Windows developer workstations may encounter Application Control policy blocks (AppLocker error 4551) when loading dynamic libraries built into the project directory.
- **Verification**:
  - The worker configured `pubspec.yaml` with `hooks: user_defines: sqlite3: { source: system, name: winsqlite3 }`.
  - This dynamically links against Microsoft-signed `C:\Windows\System32\winsqlite3.dll`, fully compliant with enterprise AppLocker policies.
  - The configuration was verified by running `flutter test` directly; all 99 tests executed in ~1 second.

---

## 5. Verified Claims Summary

| Item | Claim | Verification Method | Result |
|---|---|---|---|
| 1 | 12 tables and 11 indices match spec | Code inspection & `test_docs_integrity.py` Suite 3 | PASS |
| 2 | `PRAGMA foreign_keys = ON;` in `onConfigure` | Inspected `app_database.dart` lines 70 & 106 | PASS |
| 3 | `CHECK (amount_minor > 0)` constraint | `database_test.dart` Group 2 & integrity test | PASS |
| 4 | `origin_draft_id TEXT UNIQUE` constraint | `database_test.dart` Group 3 & integrity test | PASS |
| 5 | `refund_links` unlinking on original expense deletion | `database_test.dart` Group 4 & integrity test | PASS |
| 6 | Single transaction atomicity across 7 tables | `database_test.dart` Group 7 | PASS |
| 7 | Rollback on failure | `database_test.dart` test line 730 | PASS |
| 8 | 30-day trash bin and `deleted_at IS NULL` filtering | `database_test.dart` Group 5 | PASS |
| 9 | 4-tier deduplication engine | `deduplication_test.dart` (16 test cases) | PASS |
| 10 | Static analysis zero issues | `flutter analyze` executed directly | PASS |
| 11 | Full test suite passes | `flutter test` (99/99 tests passed) | PASS |
| 12 | Docs integrity suite passes | `python test_docs_integrity.py` (6/6 suites) | PASS |

---

## 6. Verdict & Recommendation

**Verdict**: **APPROVE**

Milestone M1-A is production-ready, correctly architected, fully verified, and free of defects or integrity issues. The team can proceed to Milestone M1-B (OCR Transaction Parsing Pipeline & Classification Rule Engine).
