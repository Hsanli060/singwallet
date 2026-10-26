# DISPATCH — reviewer_m1a_1

## Task Assignment
Milestone M1-A Code Review: SQLite Data Layer, Schema, Relational Integrity & Transaction Manager.

## Mandatory Inputs (Read First)
1. `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`
2. `c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md`
3. `c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\report.md`
4. `c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\handoff.md`
5. `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`
6. `c:\Other\Projects\singwallet\test_docs_integrity.py`

## Review Scope
1. Examine `lib/data/database/schema.dart` & `app_database.dart`:
   - Verify all 12 tables and 11 indices match specifications exactly.
   - Verify `PRAGMA foreign_keys = ON;` is executed in `onConfigure`.
   - Verify `CHECK (amount_minor > 0)` and `origin_draft_id TEXT UNIQUE`.
   - Verify `FOREIGN KEY (original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE` on `refund_links`.
2. Examine `lib/data/database/transaction_manager.dart` & `soft_delete_manager.dart`:
   - Verify single SQLite transaction atomicity across all 7 affected tables with rollback on failure.
   - Verify 30-day trash bin and query filtering (`deleted_at IS NULL`).
3. Run verification commands:
   ```powershell
   $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
   $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   flutter analyze
   flutter test
   python test_docs_integrity.py
   ```
4. Provide verdict: APPROVE or REQUEST_CHANGES.
5. Write report to `c:\Other\Projects\singwallet\.agents\teamwork\reviewer_m1a_1\report.md` and `handoff.md`.

## 2026-10-22T11:25:38Z
Received dispatch from 0be8f589-cb64-4c3b-aed0-2d1a129de39c:
Milestone M1-A Code Review: SQLite Data Layer, Schema, Relational Integrity & Transaction Manager.
