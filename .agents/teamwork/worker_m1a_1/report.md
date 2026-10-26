# Milestone M1-A Completion Report: Unified SQLite Data Layer, Core Ledger Transactions, 4-Tier Deduplication & State Machine

**Date**: 2026-10-22  
**Worker**: `worker_m1a_1` (Implementer, QA, Specialist)  
**Parent Orchestrator**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)  
**Status**: 100% COMPLETE & VERIFIED  

---

## 1. Executive Summary

Milestone **M1-A: Unified SQLite Data Layer & Core Ledger Transactions** has been implemented, validated, and hardened to production-readiness standards.

All requirements specified in `ORIGINAL_REQUEST.md`, `PROJECT.md`, `DISPATCH.md`, and `docs/跨平台架构与数据规范.md` have been fulfilled with genuine implementations:
1. **Schema & AppDatabase**: 12 relational SQLite tables and 11 B-tree performance indices matching the canonical specification, with immediate `PRAGMA foreign_keys = ON;` enforcement on all connections and desktop headless testing via `openInMemory()`.
2. **Entity Models**: All 12 entity models created in `lib/data/models/` with `fromMap`, `toMap`, `copyWith`, `==`, `hashCode`, and strict integer minor currency units (`amountMinor` in cents).
3. **Transaction Manager**: `TransactionManager.commitDraft` executes an atomic SQLite transaction across 7 affected tables with automatic rollback on any failure or constraint violation.
4. **Task State Machine**: `CaptureJobStateMachine` strictly enforces lifecycle states (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED`) and features startup self-healing recovery (`recoverLingeringJobs`) for crash recovery.
5. **Soft Delete & Trash Bin**: `SoftDeleteManager` manages the 30-day trash bin lifecycle, monthly financial calculations adhering strictly to `deleted_at IS NULL` and `occurred_on`, foreign key cascades, and refund unlinking (deleting original expense cascade-deletes the link while preserving the refund transaction intact).
6. **4-Tier Deduplication Engine**: `DeduplicationEngine` implements the complete 4-tier anti-duplicate hierarchy:
   - Tier 1: Technical Idempotence (`origin_draft_id UNIQUE`).
   - Tier 2: Same-Image Hash (`content_hash == image SHA-256`).
   - Tier 3: Hard Platform Identifier (compound PK `namespace, identifier_type, complete_value, stable_event_kind`, complete IDs only, active vs trash separation).
   - Tier 4: Heuristic Fuzzy Matching (same merchant + identical amount + within 24h soft warning without blocking legitimate consecutive purchases).
7. **Comprehensive Unit Test Suites**: 38 new unit tests across `test/database/database_test.dart` (22 tests) and `test/deduplication/deduplication_test.dart` (16 tests).
8. **Native Windows AppLocker Resolution**: Cleanly configured system SQLite (`winsqlite3`) in `pubspec.yaml` via Dart native hooks, resolving Windows AppLocker error 4551 without modifying project security boundaries.

---

## 2. File Ownership & Deliverables

| File Path | Description | Lines / Tests |
|---|---|---|
| `pubspec.yaml` | Added hooks user_defines for native system SQLite binding | Updated |
| `lib/data/database/schema.dart` | Authoritative 12 tables DDL and 11 indices | 225 lines |
| `lib/data/database/app_database.dart` | Database helper, PRAGMA foreign keys, WAL mode, FFI, `openInMemory()` | 136 lines |
| `lib/data/database/state_machine.dart` | `CaptureJobState`, transition matrix, attempt increment, startup self-healing | 215 lines |
| `lib/data/database/soft_delete_manager.dart` | `SoftDeleteManager`, 30-day trash bin, monthly calculations, cascade purge | 172 lines |
| `lib/data/database/transaction_manager.dart` | Atomic draft commit across 7 tables, rollback, discard, trash restore | 305 lines |
| `lib/data/models/capture_job.dart` | Ingestion task log model | 115 lines |
| `lib/data/models/draft.dart` | OCR recognition draft model | 105 lines |
| `lib/data/models/account.dart` | Financial account model | 95 lines |
| `lib/data/models/category.dart` | Transaction category model | 115 lines |
| `lib/data/models/project.dart` | Project grouping model | 80 lines |
| `lib/data/models/tag.dart` | Orthogonal tag model | 80 lines |
| `lib/data/models/transaction.dart` | Formal financial ledger transaction entry model | 175 lines |
| `lib/data/models/transaction_metadata.dart` | Extended transaction metadata model | 115 lines |
| `lib/data/models/transaction_tag.dart` | Transaction-tag join table model | 55 lines |
| `lib/data/models/refund_link.dart` | Refund relationship link model | 65 lines |
| `lib/data/models/classification_rule.dart` | Merchant classification rule model | 115 lines |
| `lib/data/models/confirmed_identifier.dart` | Hard deduplication platform identifier model | 75 lines |
| `lib/data/models/models.dart` | Barrel export for all 12 models | 16 lines |
| `lib/features/deduplication/deduplication_engine.dart` | 4-tier deduplication engine and evaluation pipeline | 315 lines |
| `test/database/database_test.dart` | Unit test suite covering DDL, constraints, cascades, soft deletes, state machine, atomic commit | 22 tests (770 lines) |
| `test/deduplication/deduplication_test.dart` | Unit test suite covering all 4 deduplication tiers, consecutive purchases, aggregated evaluation | 16 tests (375 lines) |

---

## 3. Verification Commands & Results

All verification commands executed cleanly with exit code 0:

### 3.1 Static Analysis (`flutter analyze`)
```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
flutter analyze
```
**Output**:
```text
Analyzing singwallet...
No issues found! (ran in 7.4s)
```
*Exit code*: `0`

### 3.2 Automated Test Suite (`flutter test`)
```powershell
flutter test
```
**Output**:
```text
00:01 +99: All tests passed!
```
*Total Tests*: 99 (61 pre-existing M0 tests + 22 database tests + 16 deduplication tests).  
*Exit code*: `0`

### 3.3 Docs & Schema Integrity Suite (`python test_docs_integrity.py`)
```powershell
python test_docs_integrity.py
```
**Output**:
```text
--- 1. Testing Markdown Files & Local Links Integrity ---
Found 4 markdown files. - OK
--- 2. Testing Pigeon Contract & Cross-Document Consistency ---
  Canonical pigeons/native_bridge.dart contains all expected types and methods - OK
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
  SWBK v1 AES-256-GCM + PBKDF2 decryption round-trip 100% verified!
--- 5. Testing CSV Formula Injection Protection ---
  All 8 CSV injection test cases passed successfully!
--- 6. Testing OCR Coordinate System Normalization Math ---
  Android ML Kit & iOS Apple Vision coordinate mapping verified to be mathematically equivalent!
=======================================================
>>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<
=======================================================
```
*Exit code*: `0`
