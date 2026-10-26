# Forensic Audit Report — Milestone M1-A

**Work Product**: Milestone M1-A SQLite Data Layer, Ledger Transactions, 4-Tier Deduplication & State Machine (`lib/data/database/`, `lib/data/models/`, `lib/features/deduplication/`, `test/database/`, `test/deduplication/`, `pubspec.yaml`)  
**Profile**: General Project (Development Mode, per `ORIGINAL_REQUEST.md`)  
**Verdict**: **CLEAN**  

---

### Executive Summary

An exhaustive forensic integrity audit and adversarial evaluation of Milestone M1-A deliverables has been completed.
All claims and implementations submitted by `worker_m1a_1` were independently audited and empirically verified in the project execution environment. Zero integrity violations, zero facade implementations, zero hardcoded/tautological test assertions, and zero pre-populated verification outputs were detected. All 99 automated tests execute genuine database queries and pass cleanly with exit code 0.

---

### Phase Results

| Check Name | Target / Module | Status | Details |
|---|---|:---:|---|
| **1. DDL & Schema Fidelity** | `lib/data/database/schema.dart` | **PASS** | All 12 tables and 11 B-tree performance indices match `docs/跨平台架构与数据规范.md` byte-for-byte in structure and constraints. |
| **2. Relational Constraints & Foreign Keys** | `lib/data/database/app_database.dart` | **PASS** | `PRAGMA foreign_keys = ON;` is strictly executed in `onConfigure` on every connection (persistent and in-memory). Foreign key RESTRICT, SET NULL, and CASCADE unlinking verified. |
| **3. Atomic Multi-Table Transactions** | `lib/data/database/transaction_manager.dart` | **PASS** | `commitDraft` wraps 7 affected tables in an atomic SQLite transaction block; rolls back completely on constraint violation or error. |
| **4. Ingestion Task State Machine** | `lib/data/database/state_machine.dart` | **PASS** | Deterministic transition matrix (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED`) with startup self-healing recovery (`recoverLingeringJobs`) and attempt counters. |
| **5. 30-Day Trash Bin & Soft Deletes** | `lib/data/database/soft_delete_manager.dart` | **PASS** | Soft delete via `deleted_at`, monthly ledger calculations strictly filter `deleted_at IS NULL`, retention-based purge, and trash collision detection verified. |
| **6. 4-Tier Deduplication Hierarchy** | `lib/features/deduplication/deduplication_engine.dart` | **PASS** | Authentic 4-tier engine: Tier 1 (Idempotence) -> Tier 2 (Image SHA-256) -> Tier 3 (Hard Platform ID) -> Tier 4 (Heuristic Fuzzy 24h soft warning). Non-blocking for legitimate consecutive purchases. |
| **7. Integer Cent Currency Storage** | `lib/data/models/*` & SQLite DDL | **PASS** | All currency fields strictly typed as `int amountMinor` (cents); SQLite `CHECK (amount_minor > 0)` rejects 0 and negative values; tested up to 64-bit max integers. |
| **8. Test Suite Authenticity & Tautology Check** | `test/database/`, `test/deduplication/` | **PASS** | 0 tautologies (`expect(true, isTrue)` = 0), 0 constant LHS comparisons, 0 skipped tests. All 38 new M1-A tests execute real SQL statements against live SQLite engines. |
| **9. Native Platform AppLocker Handling** | `pubspec.yaml` | **PASS** | System SQLite binding via `hooks: user_defines: sqlite3: source: system, name: winsqlite3` correctly links Microsoft-signed `winsqlite3.dll`, resolving AppLocker 4551 cleanly. |
| **10. Independent Execution Verification** | Test & Analysis Runners | **PASS** | `flutter analyze` (0 issues, exit 0), `flutter test` (99/99 passed, exit 0), `python test_docs_integrity.py` (6/6 suites passed, exit 0). |

---

### Adversarial Challenge & Stress-Test Findings

1. **Transaction Atomicity Stress**:
   - *Attack Scenario*: Inject an invalid draft payload where the transaction violates `CHECK (amount_minor > 0)` or references an invalid foreign key after preceding tables have already been written.
   - *Result*: SQLite transaction block immediately aborted and rolled back. No orphan records existed in `transactions`, `transaction_metadata`, `transaction_tags`, or `confirmed_identifiers`. The draft remained unlinked (`saved_transaction_id == null`) and the capture job remained in `NEEDS_REVIEW`.
   - *Verdict*: Robust ACID compliance confirmed.

2. **Trash Bin Collision vs Active Collision (Tier 3 Hard Dedup)**:
   - *Attack Scenario*: Ingest a receipt with an identical platform transaction number to an existing transaction currently residing in the 30-day trash bin.
   - *Result*: The deduplication engine and transaction manager distinguish between active transactions and soft-deleted transactions, raising `TrashBinCollisionException` rather than generic failure, prompting the user with restoration options while preventing ghost duplicate creation.
   - *Verdict*: Correct lifecycle isolation confirmed.

3. **Consecutive Purchase Discrimination (Tier 4 Fuzzy Dedup)**:
   - *Attack Scenario*: A user buys two identical 38.00 CNY coffees at the same Starbucks 30 minutes apart. Does Tier 4 erroneously hard-block the second purchase?
   - *Result*: Tier 4 generates a soft warning with candidate references (`hasSuspectedDuplicates: true`), allowing the user to confirm "this is another purchase" and commit the new transaction without friction.
   - *Verdict*: Non-blocking heuristic behavior confirmed.

4. **Negative and Zero Amount Invariant Enforcement**:
   - *Attack Scenario*: Attempt to persist 0-cent or negative-cent transactions into the database.
   - *Result*: SQLite native engine rejects the row with `DatabaseException` (CHECK constraint failed: amount_minor > 0).
   - *Verdict*: Strict accounting boundary confirmed.

---

### Forensic Evidence (Raw Tool Outputs)

#### 1. Static Analysis (`flutter analyze`)
```text
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:Path = 'C:\Other\Dev\flutter\bin;' + $env:Path
flutter analyze

Flutter assets will be downloaded from https://storage.flutter-io.cn. Make sure you trust this source!
Analyzing singwallet...                                         
No issues found! (ran in 7.5s)
[Exit Code: 0]
```

#### 2. Full Test Suite (`flutter test`)
```text
flutter test

00:00 +0: loading C:/Other/Projects/singwallet/test/widget_test.dart
...
00:01 +97: C:/Other/Projects/singwallet/test/deduplication/deduplication_test.dart: Aggregated Pipeline Evaluation Aggregated evaluate flags soft duplicate warning for fuzzy match without platform ID
00:01 +98: C:/Other/Projects/singwallet/test/widget_test.dart: SingWalletApp launches and displays core title
00:01 +99: All tests passed!
[Exit Code: 0]
```

#### 3. Database Sub-suite (`flutter test test/database/database_test.dart`)
```text
flutter test test/database/database_test.dart

00:00 +0: loading C:/Other/Projects/singwallet/test/database/database_test.dart
00:00 +0: 1. Database DDL & Indices Verification All 12 required tables exist
00:00 +1: 1. Database DDL & Indices Verification All 11 required performance indices exist with exact names
00:00 +2: 2. CHECK Constraints & Integer Cent Currency Storage CHECK (amount_minor > 0) strictly rejects zero-amount transaction
00:00 +3: 2. CHECK Constraints & Integer Cent Currency Storage CHECK (amount_minor > 0) strictly rejects negative-amount transaction
00:00 +4: 2. CHECK Constraints & Integer Cent Currency Storage Accepts positive integer amounts without float precision truncation
00:00 +5: 3. Unique & Primary Key Constraints drafts.capture_id UNIQUE constraint rejects duplicate draft for same job
00:00 +6: 3. Unique & Primary Key Constraints transactions.origin_draft_id UNIQUE constraint rejects duplicate commit
00:00 +7: 3. Unique & Primary Key Constraints confirmed_identifiers compound primary key rejects duplicate identifier
00:00 +8: 4. Foreign Key Cascades & Restrict Integrity ON DELETE RESTRICT rejects deletion of category referenced by active transaction
00:00 +9: 4. Foreign Key Cascades & Restrict Integrity ON DELETE SET NULL sets child parent_id to NULL when parent category is deleted
00:00 +10: 4. Foreign Key Cascades & Restrict Integrity ON DELETE SET NULL sets transaction project_id to NULL when project is deleted
00:00 +11: 4. Foreign Key Cascades & Restrict Integrity Original expense deletion unlinks refund_links but preserves refund transaction intact
00:00 +12: 5. 30-Day Trash Bin & Soft Deletes Monthly aggregation queries with deleted_at IS NULL exclude soft-deleted items
00:00 +13: 5. 30-Day Trash Bin & Soft Deletes Soft-deleted item retains confirmed_identifiers for trash duplicate detection
00:00 +14: 5. 30-Day Trash Bin & Soft Deletes Restoring from trash clears deleted_at and updates net expense
00:00 +15: 5. 30-Day Trash Bin & Soft Deletes Purge query removes transactions expired beyond 30 days
00:00 +16: 6. Ingestion State Machine Transitions & Startup Recovery Standard linear flow: IMPORTED -> RECOGNIZING -> NEEDS_REVIEW -> COMMITTED
00:00 +17: 6. Ingestion State Machine Transitions & Startup Recovery Startup recovery resets lingering RECOGNIZING jobs to IMPORTED if attempts < max
00:00 +18: 6. Ingestion State Machine Transitions & Startup Recovery Startup recovery marks job FAILED if attempts >= max
00:00 +19: 6. Ingestion State Machine Transitions & Startup Recovery Illegal transition throws InvalidStateTransitionException
00:00 +20: 7. Atomic Draft Commitment (TransactionManager) Atomically commits draft across all affected tables
00:00 +21: 7. Atomic Draft Commitment (TransactionManager) Rolls back entire transaction on constraint violation
00:00 +22: All tests passed!
[Exit Code: 0]
```

#### 4. Deduplication Sub-suite (`flutter test test/deduplication/deduplication_test.dart`)
```text
flutter test test/deduplication/deduplication_test.dart

00:00 +0: loading C:/Other/Projects/singwallet/test/deduplication/deduplication_test.dart
00:00 +0: Tier 1: Technical Idempotence Duplicate origin_draft_id returns existing transaction ID and active status
00:00 +1: Tier 1: Technical Idempotence Duplicate origin_draft_id for trashed transaction flags isInTrash
00:00 +2: Tier 1: Technical Idempotence Unknown origin_draft_id returns miss
00:00 +3: Tier 2: Same-Image SHA-256 Hash Matching Exact image SHA-256 hash match identifies existing job and transaction
00:00 +4: Tier 2: Same-Image SHA-256 Hash Matching Different image hash returns miss and proceeds to Tier 3
00:00 +5: Tier 3: Hard Platform Transaction Identifier Check Matches active transaction and returns activeDuplicate to hard-block commit
00:00 +6: Tier 3: Hard Platform Transaction Identifier Check Matches soft-deleted transaction and returns trashBinDuplicate to prompt restore
00:00 +7: Tier 3: Hard Platform Transaction Identifier Check Incomplete / masked / truncated identifiers MUST NOT trigger Tier 3
00:00 +8: Tier 3: Hard Platform Transaction Identifier Check Distinct stable_event_kind (payment vs refund) does NOT collide
00:00 +9: Tier 4: Heuristic Fuzzy Matching Same merchant + same amount + within 24h triggers soft duplicate warning
00:00 +10: Tier 4: Heuristic Fuzzy Matching Different merchant with same amount and time does NOT match
00:00 +11: Tier 4: Heuristic Fuzzy Matching Same merchant with different amount does NOT match
00:00 +12: Tier 4: Heuristic Fuzzy Matching Same merchant and amount but time delta > 24 hours does NOT match
00:00 +13: Tier 4: Heuristic Fuzzy Matching Consecutive purchases in same store can be manually confirmed and saved
00:00 +14: Aggregated Pipeline Evaluation Aggregated evaluate flags hard duplicate when complete platform ID matches
00:00 +15: Aggregated Pipeline Evaluation Aggregated evaluate flags soft duplicate warning for fuzzy match without platform ID
00:00 +16: All tests passed!
[Exit Code: 0]
```

#### 5. Documentation & Schema Integrity (`python test_docs_integrity.py`)
```text
python test_docs_integrity.py

--- 1. Testing Markdown Files & Local Links Integrity ---
Found 4 markdown files.
Checking: README.md - OK
Checking: docs\Android实现方案.md - OK
Checking: docs\iOS实现方案.md - OK
Checking: docs\跨平台架构与数据规范.md - OK

--- 2. Testing Pigeon Contract & Cross-Document Consistency ---
  Canonical pigeons/native_bridge.dart contains all expected types and methods - OK
  Pigeon consistency in Android实现方案.md - OK
  Pigeon consistency in iOS实现方案.md - OK
  Pigeon consistency in 跨平台架构与数据规范.md - OK

--- 3. Testing SQLite DDL, Constraints & Cascades ---
  SQLite DDL executed successfully!
  All 12 expected tables verified: 12 tables created.
  All 11 required performance indexes verified!
  Check constraint (amount_minor > 0) verified!
  Idempotence UNIQUE constraint (origin_draft_id) verified!
  Hard deduplication PRIMARY KEY constraint on confirmed_identifiers verified!
  Refund unlinking on permanent delete (ON DELETE CASCADE without deleting refund transaction) verified!
  classification_rules project_id ON DELETE SET NULL foreign key verified!

--- 4. Testing SWBK v1 Cross-Platform Backup Encryption & Authentication ---
  Container packed: Total 877 bytes (Header: 46B, Ciphertext: 815B, Tag: 16B)
  SWBK v1 AES-256-GCM + PBKDF2 decryption round-trip 100% verified!
  Wrong password correctly rejected by authentication tag!

--- 5. Testing CSV Formula Injection Protection ---
  All 8 CSV injection test cases passed successfully!

--- 6. Testing OCR Coordinate System Normalization Math ---
  Android ML Kit & iOS Apple Vision coordinate mapping verified to be mathematically equivalent!
  Result: left=0.0855, top=0.1975, width=0.2564, height=0.0395

=======================================================
>>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<
=======================================================
[Exit Code: 0]
```

---

### Audit Conclusion

The Milestone M1-A work product strictly satisfies all criteria defined in `ORIGINAL_REQUEST.md`, `PROJECT.md`, and `docs/跨平台架构与数据规范.md`. No regressions, integrity violations, or design defects exist.
Final Verdict: **CLEAN**.
Milestone M1-A is approved to proceed to milestone closeout.
