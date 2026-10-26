# DISPATCH — worker_m1a_1

## Task Assignment
Milestone M1-A: Unified SQLite Data Layer, Core Ledger Transactions, 4-Tier Deduplication & State Machine.

## Mandatory Inputs (Read First)
1. `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`
2. `c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md`
3. Explorer Reports & Blueprints:
   - `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_1\report.md` (12 tables DDL, 11 indices, AppDatabase)
   - `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_2\report.md` (4-tier deduplication, transaction manager atomic commit)
   - `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_3\report.md` (state machine, soft deletes, unit tests)
   - `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_3\proposed_state_machine.dart`
   - `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_3\proposed_soft_delete_manager.dart`
   - `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_3\proposed_database_test.dart`
   - `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_3\proposed_deduplication_test.dart`
4. Documentation and Reference Specs:
   - `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`
   - `c:\Other\Projects\singwallet\test_docs_integrity.py`

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Exclusive Write File Ownership
- `lib/data/database/schema.dart`
- `lib/data/database/app_database.dart`
- `lib/data/database/transaction_manager.dart`
- `lib/data/database/state_machine.dart`
- `lib/data/database/soft_delete_manager.dart`
- `lib/data/models/` (all 12 entity models: `capture_job.dart`, `draft.dart`, `account.dart`, `category.dart`, `project.dart`, `tag.dart`, `transaction.dart`, `transaction_metadata.dart`, `transaction_tag.dart`, `refund_link.dart`, `classification_rule.dart`, `confirmed_identifier.dart`, `models.dart`)
- `lib/features/deduplication/deduplication_engine.dart`
- `test/database/database_test.dart`
- `test/deduplication/deduplication_test.dart`

## Key Implementation Requirements
1. **Schema & AppDatabase**:
   - 12 tables and 11 indices strictly matching `docs/跨平台架构与数据规范.md` and `test_docs_integrity.py`.
   - `PRAGMA foreign_keys = ON;` executed immediately in `onConfigure` before any table creation or query.
   - CHECK constraint `CHECK (amount_minor > 0)` and `origin_draft_id TEXT UNIQUE` on `transactions`.
   - `FOREIGN KEY (original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE` on `refund_links`.
   - Support for desktop headless execution via `sqflite_common_ffi` (`sqfliteFfiInit()` and `databaseFactoryFfi`) and in-memory test database support (`openInMemory()`).
2. **Entity Models**:
   - Implement `fromMap`, `toMap`, copyWith, and equality for all 12 tables with integer minor units (`amount_minor`).
3. **Transaction Manager**:
   - Single atomic transaction for draft commitment: insert into `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers` (and `refund_links` if refund), update `drafts.saved_transaction_id`, update `capture_jobs.state = 'COMMITTED'`.
   - Rollback on failure.
4. **State Machine & Soft Deletion**:
   - `CaptureJobStateMachine` with valid transitions and `recoverLingeringJobs` on startup.
   - `SoftDeleteManager` for 30-day trash bin, `deleted_at IS NULL` query filtering, cascade deletion, and refund unlinking.
5. **4-Tier Deduplication Engine**:
   - Tier 1: Technical Idempotence (`origin_draft_id UNIQUE`).
   - Tier 2: Same-Image Hash (`content_hash == image SHA-256`).
   - Tier 3: Hard Platform Identifier (`confirmed_identifiers` compound PK, complete values only, `stable_event_kind` distinction, handling active vs soft-deleted).
   - Tier 4: Heuristic Fuzzy Matching (same merchant + identical amount + within 24 hours).
6. **Automated Unit Tests**:
   - Implement `test/database/database_test.dart` (19 test cases) and `test/deduplication/deduplication_test.dart` (13 test cases).

## Verification Commands
```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
flutter analyze
flutter test
python test_docs_integrity.py
```
Ensure all verification commands pass with exit code 0.
