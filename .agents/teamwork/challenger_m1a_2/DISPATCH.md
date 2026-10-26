# DISPATCH — challenger_m1a_2

## 2026-10-22T11:25:38Z
## Task Assignment
Milestone M1-A Adversarial Challenge: Relational Integrity, Cascade Deletions & Transaction Rollback.

## Mandatory Inputs (Read First)
1. `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`
2. `c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md`
3. `c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\report.md`
4. `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`
5. `c:\Other\Projects\singwallet\test_docs_integrity.py`

## Challenge Mission
Adversarially challenge relational integrity and transactions:
1. **Transaction Atomicity & Rollback**:
   - Inject intentional failures into `commitDraft` (e.g. invalid foreign key, invalid amount <= 0, or duplicate identifier).
   - Verify that upon rollback, ZERO partial rows remain in `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, and that `capture_jobs.state` and `drafts.saved_transaction_id` remain unchanged.
2. **Refund Cascade & Unlinking**:
   - Create an original expense transaction and a refund transaction linked via `refund_links`.
   - Permanently delete the original expense transaction.
   - Verify `refund_links` is cascade deleted (`ON DELETE CASCADE`), while the refund transaction in `transactions` remains intact as an unlinked refund.
3. **Foreign Key Cascade and Restrict**:
   - Test category deletion: active category deletion must be restricted if transactions exist referencing it.
   - Parent category deletion: verify child category's `parent_id` is set to NULL (`ON DELETE SET NULL`).
   - CHECK constraint: verify `amount_minor <= 0` throws an `IntegrityError` / SQLite exception.
4. Run `flutter test test/database/database_test.dart` and `python test_docs_integrity.py`.
5. Provide verdict: APPROVE or REQUEST_CHANGES.
6. Write report to `c:\Other\Projects\singwallet\.agents\teamwork\challenger_m1a_2\challenge_report.md` and `handoff.md`.
