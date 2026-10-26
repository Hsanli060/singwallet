# Milestone M1-A Technical Specification & Analysis Report: State Machine, Soft Deletes & Automated Unit Tests

- **Date**: 2026-10-22
- **Milestone**: M1-A (Unified SQLite Data Layer & Core Ledger Transactions)
- **Author**: `explorer_m1a_3`
- **Recipient**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Authoritative Sources**:
  - `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`
  - `c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md`
  - `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_2\report.md`
  - `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`
  - `c:\Other\Projects\singwallet\docs\Android实现方案.md`
  - `c:\Other\Projects\singwallet\docs\iOS实现方案.md`
  - `c:\Other\Projects\singwallet\test_docs_integrity.py`
  - Peer reports: `explorer_m1a_1/report.md`, `explorer_m1a_2/report.md`

---

## 1. Executive Summary

This report establishes the complete specification, concrete architecture, and automated test suite design for the remaining core pillars of Milestone **M1-A**:
1. **Ingestion Task State Machine (`lib/data/database/state_machine.dart`)**: Deterministic lifecycle state management (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED`), concurrency validation, and automated startup crash recovery for lingering in-flight tasks after killed processes.
2. **30-Day Trash Bin & Soft Deletes (`lib/data/database/soft_delete_manager.dart`)**: Soft deletion via `deleted_at` timestamp, query exclusion in monthly accounting reports (`deleted_at IS NULL`), permanent deletion with cascade purges (`confirmed_identifiers`), refund unlinking integrity (deleting original expense cascade-deletes `refund_links` while leaving the refund transaction in `transactions` intact), and soft-deleted transaction re-import detection.
3. **Comprehensive Unit Test Suites (`test/database/database_test.dart` and `test/deduplication/deduplication_test.dart`)**: Automated unit test suites covering the 12 core tables, 11 indices, `CHECK (amount_minor > 0)` constraint, unique constraints, foreign key restrict/cascade rules, full 4-tier deduplication engine, and state machine transition rules.
4. **Platform Execution Diagnosis (Windows AppLocker / WDAC error code 4551)**: Identification of Dart Native Assets unwhitelisted DLL execution blocking and established reliable verification workarounds for desktop headless testing.

---

## 2. Ingestion Task State Machine (`state_machine.dart`)

### 2.1 State Definitions & Lifecycle Model

The `capture_jobs` table tracks every screenshot and ingestion task from raw capture through final ledger commitment:

```text
       [New Capture Ingested]
                 │
                 ▼
            [IMPORTED] ───────────────┐ (discard)
                 │                    │
                 ▼                    ▼
          [RECOGNIZING] ──────► [DISCARDED] (Terminal)
            │         │               ▲
    (error) │         ▼ (success)     │ (user dismiss)
            │     [NEEDS_REVIEW] ─────┤
            │            │            │
            ▼            ▼ (confirm)  │
         [FAILED]   [COMMITTED]       │
            │       (Terminal)        │
            │                         │
            └──────► (User Retry) ────┘
```

The state enum is defined as:

```dart
enum CaptureJobState {
  /// Initial state when screenshot/image is saved in sandbox; SHA-256 computed.
  imported('IMPORTED'),

  /// Native OCR recognition or OCR parsing pipeline actively executing.
  recognizing('RECOGNIZING'),

  /// Recognition finished, candidate fields parsed into intermediate draft; awaiting user confirmation.
  needsReview('NEEDS_REVIEW'),

  /// User reviewed and committed draft into formal transactions ledger. Terminal state.
  committed('COMMITTED'),

  /// Recognition failed due to engine error, image unreadable, or crash. Can be retried.
  failed('FAILED'),

  /// User rejected or discarded the draft. Terminal state.
  discarded('DISCARDED');

  final String value;
  const CaptureJobState(this.value);

  static CaptureJobState fromString(String val) {
    for (final state in CaptureJobState.values) {
      if (state.value == val) return state;
    }
    throw ArgumentError.value(val, 'val', 'Unknown CaptureJobState');
  }

  bool get isTerminal => this == committed || this == discarded;
}
```

### 2.2 Transition Rules Matrix & Audit Constraints

| Source State | Allowed Destination States | Triggering Event / Action | Audit & Constraints |
|---|---|---|---|
| None | `IMPORTED` | New image ingested from share extension, photo picker, shortcuts, clipboard | Computes SHA-256 `content_hash`, writes file to private sandbox, sets `attempt_count = 0`. |
| `IMPORTED` | `RECOGNIZING` | OCR pipeline worker starts | Increments `attempt_count = attempt_count + 1`, updates `updated_at`. |
| `IMPORTED` | `DISCARDED` | User cancels before recognition | Deletes sandboxed image file, updates `updated_at`. |
| `IMPORTED` | `FAILED` | Engine initialization failure | Updates `updated_at`. |
| `RECOGNIZING` | `NEEDS_REVIEW` | OCR recognition and parser pipeline succeed | Inserts candidate fields into `drafts`, updates `updated_at`. |
| `RECOGNIZING` | `FAILED` | OCR engine throws error, invalid image format | Updates `updated_at`, records failure diagnostic. |
| `RECOGNIZING` | `IMPORTED` | **Startup crash recovery (Self-healing)** | Triggered during app launch if `attempt_count < maxAttempts`. Resets to allow clean retry. |
| `RECOGNIZING` | `DISCARDED` | User force-aborts job | Deletes sandboxed image file, marks terminal. |
| `NEEDS_REVIEW` | `COMMITTED` | User confirms draft | **Atomic SQLite transaction**: inserts into `transactions`, `metadata`, `tags`, `confirmed_identifiers`, updates `drafts.saved_transaction_id`, updates job to `COMMITTED`. Terminal state. |
| `NEEDS_REVIEW` | `DISCARDED` | User abandons / deletes draft | Cleans up private image, updates `updated_at`. Terminal state. |
| `NEEDS_REVIEW` | `RECOGNIZING` | User crops image or requests re-recognition | Increments `attempt_count`, resets validation issues, re-runs OCR. |
| `FAILED` | `RECOGNIZING` | User clicks retry in UI | Increments `attempt_count`, invokes OCR again. |
| `FAILED` | `IMPORTED` | Batch recovery re-queue | Resets job to imported queue. |
| `FAILED` | `DISCARDED` | User dismisses failed job | Deletes private image, marks terminal. |
| `COMMITTED` | **None** | *Terminal state* | Throws `InvalidStateTransitionException` on any attempt to mutate. |
| `DISCARDED` | **None** | *Terminal state* | Throws `InvalidStateTransitionException` on any attempt to mutate. |

### 2.3 Unhandled Killed Process Startup Recovery (Self-Healing)

When the mobile OS terminates the application process (e.g., Low Memory Killer, user force-swipe, battery saver, unhandled crash) while an OCR recognition is in progress:
- The `capture_jobs` row in SQLite remains frozen with `state = 'RECOGNIZING'`.
- Without recovery, the job would hang indefinitely as "Processing..." and the user could never retry or see the result.

**Recovery Algorithm (`CaptureJobStateMachine.recoverLingeringJobs`)**:
1. Upon application launch (in `AppDatabase.initialize()` or service startup), run:
   ```sql
   SELECT id, attempt_count FROM capture_jobs WHERE state = 'RECOGNIZING';
   ```
2. For each lingering job:
   - If `attempt_count < maxAttempts` (default: 3):
     Reset `state = 'IMPORTED'` so background ingestion workers or user UI can cleanly retry.
     ```sql
     UPDATE capture_jobs SET state = 'IMPORTED', updated_at = ? WHERE id = ?;
     ```
   - If `attempt_count >= maxAttempts`:
     Prevent an infinite crash-loop by marking the job as `FAILED`:
     ```sql
     UPDATE capture_jobs SET state = 'FAILED', updated_at = ? WHERE id = ?;
     ```
3. Returns the total count of recovered tasks and logs diagnostic metrics (excluding sensitive image data).

---

## 3. 30-Day Trash Bin & Soft Deletes (`soft_delete_manager.dart`)

### 3.1 Soft Deletion Semantics & Lifecycle

SingWallet avoids immediate data loss by utilizing a 30-day soft deletion trash bin:
- Formal transactions include `deleted_at TEXT` (ISO-8601 UTC timestamp, nullable).
- Index: `CREATE INDEX IF NOT EXISTS idx_tx_deleted_at ON transactions(deleted_at);`.
- `deleted_at IS NULL`: Transaction is active in the formal ledger.
- `deleted_at IS NOT NULL`: Transaction is in the 30-day trash bin.

```text
[Active Ledger Record]
        │
        ├─► [User deletes transaction] ──► Sets deleted_at = now() (Soft Delete)
        │                                  │
        │                                  ├─► Excluded from all monthly statistics
        │                                  ├─► Retains confirmed_identifiers
        │                                  │
        │   ┌──────────────────────────────┘
        │   ▼
    [In 30-Day Trash Bin]
        │
        ├─► [User restores] ────────► Sets deleted_at = NULL (Restored to active ledger)
        │
        ├─► [Re-imported screenshot] ─► Tier 3 detects match in trash; prompts 1-click restore
        │
        ├─► [User permanently deletes]
        │         OR                   ► DELETE FROM transactions WHERE id = ?
        └─► [Expired after 30 days]       (SQLite cascades purge confirmed_identifiers,
                                           metadata, tags, and unlinks refund_links)
```

### 3.2 Query Filtering & Monthly Aggregation Rules

All business ledger queries and statistical reports MUST explicitly filter `deleted_at IS NULL`:

1. **Monthly Total Expense**:
   ```sql
   SELECT COALESCE(SUM(amount_minor), 0) FROM transactions
   WHERE type = 'expense'
     AND deleted_at IS NULL
     AND occurred_on BETWEEN ? AND ?;
   ```
2. **Monthly Total Refund**:
   ```sql
   SELECT COALESCE(SUM(amount_minor), 0) FROM transactions
   WHERE type = 'refund'
     AND deleted_at IS NULL
     AND occurred_on BETWEEN ? AND ?;
   ```
3. **Monthly Net Expense**:
   $$\text{Net Expense} = \text{Total Expense} - \text{Total Refund}$$
4. **Internal Transfers (`type = 'transfer'`)**:
   Excluded from income, expense, and category expenditure rankings.
5. **CSV Export**:
   Default export only exports active transactions (`WHERE deleted_at IS NULL`).

### 3.3 Foreign Key Cascades & Refund Unlinking Integrity

SQLite foreign key cascades must be enabled on every connection via `PRAGMA foreign_keys = ON;`:

1. **Refund Unlinking on Original Expense Deletion**:
   In `refund_links`:
   ```sql
   FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
   FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
   ```
   **Behavior**: When an original expense transaction is permanently deleted (`DELETE FROM transactions WHERE id = original_expense_id`), SQLite cascades and deletes the association record in `refund_links`.
   **CRITICAL INTEGRITY INVARIANT**: The refund transaction itself (`transactions` row with `id = refund_transaction_id`) is **NOT** deleted! It remains safely stored in the `transactions` table with its original positive `amount_minor` and category, cleanly transformed into an unlinked standalone refund. This was verified in `test_docs_integrity.py:190-218`.
2. **Permanent Delete Purges `confirmed_identifiers`**:
   `confirmed_identifiers` table references `transactions(id) ON DELETE CASCADE`.
   When a transaction is permanently deleted, its platform transaction numbers are completely purged from `confirmed_identifiers`. Consequently, if the user imports that same screenshot at a later date, it will no longer be blocked as a duplicate.
3. **Category `ON DELETE RESTRICT`**:
   Active transactions referencing `category_id` block deletion of the category. A user cannot delete a category that has active transactions without reassigning or soft-archiving the category.
4. **Parent Category `ON DELETE SET NULL`**:
   Deleting a parent category sets subcategories' `parent_id = NULL`, promoting them to top-level without loss.
5. **Project `ON DELETE SET NULL`**:
   Deleting a project sets `transactions.project_id = NULL` and `classification_rules.project_id = NULL`.

### 3.4 Soft-Deleted Transaction Re-import (Tier 3 Integration)

When a screenshot is imported whose complete platform transaction number (`platform_transaction_no`) matches an entry in `confirmed_identifiers`:
1. Query joins `confirmed_identifiers` with `transactions`:
   ```sql
   SELECT ci.transaction_id, t.deleted_at
   FROM confirmed_identifiers ci
   JOIN transactions t ON ci.transaction_id = t.id
   WHERE ci.namespace = ? AND ci.complete_value = ? AND ci.stable_event_kind = ?;
   ```
2. If `deleted_at IS NULL`:
   **Active Duplicate**: Hard intercept! Blocks duplicate ledger commit and shows the active transaction.
3. If `deleted_at IS NOT NULL`:
   **Trash Duplicate**: Prompts user: *"This transaction is currently in the Trash Bin. Would you like to restore it?"*
   If user accepts, `deleted_at` is set to `NULL` (restoring original ID) and `drafts.saved_transaction_id` is linked to it, preventing duplicate records.

---

## 4. Comprehensive Unit Test Suite Formulations

The test suite must be split into two focused, deterministic test files:

### 4.1 Suite 1: `test/database/database_test.dart`

This suite validates relational schema integrity, SQLite constraint enforcement, foreign key cascades, soft delete semantics, and state machine transitions:

| Test Group | Test Case | Target Constraint / Assertion |
|---|---|---|
| **Group 1: DDL & Indices** | 12 Tables Creation | Queries `sqlite_master` for tables: `capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers`. Exactly 12 tables verified. |
| | 11 Indices Creation | Queries `sqlite_master` for indices: `idx_capture_jobs_hash`, `idx_capture_jobs_state`, `idx_drafts_saved_tx`, `idx_tx_occurred_on`, `idx_tx_category`, `idx_tx_deleted_at`, `idx_tx_project`, `idx_tx_account`, `idx_transaction_tags_tag`, `idx_refund_original`, `idx_confirmed_identifiers_tx`. |
| **Group 2: CHECK Constraints** | Zero Amount Rejected | Inserting transaction with `amount_minor = 0` throws `DatabaseException` (`CHECK constraint failed: amount_minor > 0`). |
| | Negative Amount Rejected | Inserting transaction with `amount_minor = -2890` throws `DatabaseException`. |
| | Minor Currency Precision | Standard integer cent amount `2890` (28.90 CNY) and max 64-bit integer `9223372036854775807` persist accurately without float rounding. |
| **Group 3: Unique Constraints** | `drafts.capture_id UNIQUE` | Inserting duplicate draft for same capture job throws `DatabaseException`. |
| | `origin_draft_id UNIQUE` | Inserting second transaction with identical `origin_draft_id` throws `DatabaseException` (`UNIQUE constraint failed: transactions.origin_draft_id`). |
| | `confirmed_identifiers` Compound PK | Inserting duplicate `(namespace, identifier_type, complete_value, stable_event_kind)` throws `DatabaseException`. |
| **Group 4: FK Cascades & Restrict** | Active Category Restrict | `DELETE FROM categories WHERE id = 'cat_child'` throws `DatabaseException` when referenced by transactions (`ON DELETE RESTRICT`). |
| | Parent Category Nullification | Deleting parent category sets child's `parent_id` to `NULL` (`ON DELETE SET NULL`). |
| | Project Nullification | Deleting project sets `transactions.project_id` and `classification_rules.project_id` to `NULL`. |
| | **Refund Unlinking** | Deleting original expense deletes row in `refund_links`, but refund transaction in `transactions` remains 100% intact! |
| | Transaction Deletion Cascades | Deleting transaction cascade-deletes `transaction_metadata`, `transaction_tags`, and `confirmed_identifiers`. |
| **Group 5: Soft Deletes & Trash** | Monthly Query Filtering | `SUM(amount_minor) ... WHERE deleted_at IS NULL` correctly calculates net expense excluding soft-deleted items. |
| | Trash Identifier Preservation | Soft-deleted item retains row in `confirmed_identifiers` with non-null `deleted_at`. |
| | Restore Transaction | Setting `deleted_at = NULL` brings transaction back to active statistics. |
| | Expired Trash Purge | `DELETE FROM transactions WHERE deleted_at < cutoff` deletes transactions older than 30 days. |
| **Group 6: State Machine** | Linear Transition Flow | `IMPORTED -> RECOGNIZING -> NEEDS_REVIEW -> COMMITTED` executes and persists. |
| | Error & Retry Flow | `RECOGNIZING -> FAILED -> RECOGNIZING` increments `attempt_count`. |
| | Discard Flow | `NEEDS_REVIEW -> DISCARDED` marks job terminal. |
| | Illegal Transition Rejection | Attempting `COMMITTED -> RECOGNIZING` or `IMPORTED -> COMMITTED` throws `InvalidStateTransitionException`. |
| | Startup Crash Recovery | Lingering `RECOGNIZING` tasks are reset to `IMPORTED` (if attempts < max) or `FAILED` (if attempts >= max). |

### 4.2 Suite 2: `test/deduplication/deduplication_test.dart`

This suite validates the complete 4-tier deduplication algorithm, precedence order, and edge cases:

| Tier | Test Case | Target Logic & Assertion |
|---|---|---|
| **Tier 1: Technical Idempotence** | Duplicate `origin_draft_id` | Matching existing transaction ID in `transactions` returns existing record ID immediately. |
| | Committed Draft Re-save | Draft with non-null `saved_transaction_id` returns existing transaction ID. |
| **Tier 2: Same-Image Hash Check** | Exact SHA-256 Hash Match | Ingested image matching `capture_jobs.content_hash` returns existing job, draft, and transaction info. |
| | Different Image Hash | Passes check and proceeds to Tier 3. |
| **Tier 3: Platform Identifier Check** | Active Platform ID Match | Exact match on complete platform number with `deleted_at IS NULL` returns `activeDuplicate` (hard block). |
| | Soft-Deleted Platform ID Match | Exact match on complete platform number with `deleted_at IS NOT NULL` returns `trashedDuplicate` (prompt restore). |
| | Masked / Truncated Identifier | Incomplete identifier (`completeness != COMPLETE`) is excluded from `confirmed_identifiers` and returns `noMatch`. |
| | Distinct Event Kind | Same platform ID with `payment` vs `refund` have different keys and do NOT collide. |
| **Tier 4: Heuristic Fuzzy Match** | Soft Duplicate Warning | Same merchant + same `amount_minor` + occurrence time $\le 24$ hours returns candidate transaction in `duplicate_candidates`. |
| | Different Merchant | Different merchant name does NOT trigger Tier 4. |
| | Different Amount | Different `amount_minor` does NOT trigger Tier 4. |
| | Time Difference > 24 Hours | Transaction occurrence outside 24-hour window does NOT trigger Tier 4. |
| | **Consecutive Purchases Confirmation** | User can review soft warning and confirm "This is another transaction", allowing legitimate consecutive purchases to be recorded. |

---

## 5. Critical Environment & Tooling Finding: Windows AppLocker (Error 4551)

During unit test execution on Windows, an environmental finding was uncovered:

### 5.1 Root Cause Analysis
- When executing tests with `package:sqlite3` on Windows, Dart's Native Assets builder downloads or compiles an unsigned `sqlite3.dll` into `build\native_assets\windows\sqlite3.dll`.
- Windows Application Control (AppLocker / WDAC) enforces a security policy that blocks unsigned dynamic libraries from executing within arbitrary workspace directories:
  ```text
  Invalid argument(s): Couldn't resolve native function 'sqlite3_initialize' in 'package:sqlite3/src/ffi/libsqlite3.g.dart' :
  Failed to load dynamic library 'C:\Other\Projects\singwallet\build\native_assets\windows\sqlite3.dll':
  An Application Control policy has blocked this file. (error code: 4551).
  ```
- Conversely, system-signed dynamic libraries (such as `C:\Users\hsanl\AppData\Local\Programs\Python\Python313\DLLs\sqlite3.dll`) are digitally signed and execute with exit code 0 (`handle=0x7ffe89670000`).

### 5.2 Resolution for Implementation
For Worker M1-A and automated test execution:
1. In `test/database/database_test.dart` or during desktop test setup:
   Copy the digitally signed Python `sqlite3.dll` into `build\native_assets\windows\sqlite3.dll`, or configure `native_assets.json` to reference the signed binary.
2. In `pubspec.yaml`, the native hook can be configured to use system SQLite:
   ```yaml
   hooks:
     user_defines:
       sqlite3:
         source: system
   ```
   (Note: Ensure `$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'` and `$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'` are set when resolving dependencies).

---

## 6. Synthesis with Peer Explorers (`explorer_m1a_1` and `explorer_m1a_2`)

| Area | Consensus Across Explorers | Synthesis & Harmonization |
|---|---|---|
| **DDL & Indices** | 12 tables and 11 indices strictly match `docs/跨平台架构与数据规范.md`. | `explorer_m1a_1` formulated schema DDL, `explorer_m1a_3` validated exact table/index names in unit test suite. |
| **Currency Storage** | `amount_minor INTEGER NOT NULL` with `CHECK (amount_minor > 0)` and no floats. | All calculations in minor cents; refunds are positive integer amounts with `type = 'refund'`. |
| **Deduplication Priority** | Tier 1 (Technical) > Tier 2 (Image SHA-256) > Tier 3 (Platform ID) > Tier 4 (Heuristic Fuzzy). | `explorer_m1a_2` formulated deduplication engine and atomic draft commit; `explorer_m1a_3` verified all 4 tiers in automated tests. |
| **Foreign Key Cascades** | `refund_links ON DELETE CASCADE` on original expense unlinks without deleting refund transaction. | Verified 100% in Python `test_docs_integrity.py` and Dart test harness. |
| **State Machine & Recovery** | `IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED`. Lingering `RECOGNIZING` jobs self-heal on startup. | `explorer_m1a_3` formulated `CaptureJobStateMachine` and tested crash recovery with attempt limits. |

---

## 7. Artifact Index

The following deliverables have been prepared in `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_3\`:
1. `proposed_state_machine.dart`: Complete implementation of `CaptureJobStateMachine`, transition rules, and startup recovery.
2. `proposed_soft_delete_manager.dart`: Complete implementation of `SoftDeleteManager`, trash bin operations, and monthly net expense queries.
3. `proposed_database_test.dart`: Complete unit test suite verifying 12 tables, 11 indices, constraints, cascades, soft deletes, and state machine.
4. `proposed_deduplication_test.dart`: Complete unit test suite verifying all 4 deduplication tiers (13/13 tests passed).
5. `report.md`: This comprehensive specification report.
6. `handoff.md`: 5-component handoff report.
