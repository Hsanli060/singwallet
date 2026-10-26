# Milestone M1-A Adversarial Challenge Report: Relational Integrity, Cascades & Transaction Rollback

**Agent**: `challenger_m1a_2` (Empirical Challenger: Critic, Specialist)  
**Parent**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)  
**Date**: 2026-10-22  
**Target Under Review**: Unified SQLite Data Layer (`lib/data/database/`, `lib/data/models/`, `test/database/database_test.dart`)  
**Verdict**: **APPROVE**

---

## 1. Challenge Summary

**Overall Risk Assessment**: **LOW**

An extensive empirical adversarial evaluation was conducted against the SQLite relational schema, transaction management, cascade deletions, unlinking semantics, and integrity constraints implemented in Milestone M1-A.

We developed and executed a dedicated stress harness (`test/database/relational_stress_test.dart`) containing **22 deep adversarial tests** attacking the persistence layer from multiple failure angles. Every failure mode was empirically verified on real SQLite in-memory and file-based FFI engines (`PRAGMA foreign_keys = ON;`).

The database engine demonstrated 100% adherence to all canonical specifications, zero state leakage across partial rollback failures, resilient refund unlinking, strict constraint enforcement, and zero regression against existing test suites.

---

## 2. Adversarial Challenges & Empirical Findings

### Challenge 1: Transaction Atomicity & Rollback Integrity on Multi-Table Mutations
- **Assumption Challenged**: `TransactionManager.commitDraft` spans up to 7 SQLite tables (`transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, `refund_links`, `drafts`, `capture_jobs`). If an operation fails deep in the pipeline (e.g., at Step 6 tag insertion or Step 7 platform identifier insertion), partial rows could leak or draft state could become inconsistent.
- **Attack Scenario**:
  1. Inserted a transaction referencing a non-existent category foreign key (`cat_NON_EXISTENT`).
  2. Inserted a transaction referencing a non-existent tag foreign key (`tag_GHOST`) after successful transaction and metadata inserts.
  3. Committed a transaction with duplicate `tagIds` (`['tag_1', 'tag_1']`) causing a primary key conflict on `transaction_tags`.
  4. Injected duplicate platform identifiers triggering `HardDuplicateException` and `TrashBinCollisionException`.
  5. Injected non-existent `originalExpenseId` in refund commits triggering foreign key failure on `refund_links`.
  6. Attempted to commit a draft whose capture job was in an invalid state (`RECOGNIZING`).
- **Empirical Observation**:
  - In all 7 attack scenarios, SQLite transaction rollback was immediate and absolute.
  - Zero rows remained in `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, or `refund_links`.
  - `drafts.saved_transaction_id` remained strictly `NULL`.
  - `capture_jobs.state` remained strictly in `NEEDS_REVIEW` (or its pre-commit state).
- **Result**: **PASS**. Zero partial state leakage.

---

### Challenge 2: Refund Cascade Deletion, Unlinking & Multi-Refund Integrity
- **Assumption Challenged**: When an original expense transaction is permanently deleted, foreign key `ON DELETE CASCADE` on `refund_links` must sever the link without deleting the refund transaction itself, even across multiple partial refunds or 30-day trash purges.
- **Attack Scenario**:
  1. Linked two separate partial refunds (30.00 CNY and 20.00 CNY) to a single 100.00 CNY expense via `refund_links`.
  2. Permanently deleted the original expense.
  3. Reverse test: permanently deleted one refund transaction.
  4. Soft-delete test: soft-deleted original expense to ensure `refund_links` is preserved during trash bin retention and properly restored.
  5. 30-day trash purge test: purged expired trash containing original expense and verified cascade unlinking.
  6. Constraint attack: attempted direct insert of invalid foreign keys into `refund_links`.
- **Empirical Observation**:
  - Permanent deletion of original expense deleted all corresponding rows in `refund_links` via `ON DELETE CASCADE`.
  - Both refund transactions in `transactions` remained 100% intact with unaltered amounts, dates, and types.
  - Reverse deletion cleanly deleted only the target refund link while preserving the original expense.
  - Soft-deleting preserved `refund_links`, excluded the expense from monthly summary while retaining the refund, and restored cleanly.
  - 30-day trash purge cascade-deleted `refund_links` and left refund transactions intact.
  - Invalid direct inserts to `refund_links` failed with `DatabaseException`.
- **Result**: **PASS**. Canonical unlinking behavior perfectly satisfied.

---

### Challenge 3: Foreign Key Cascades, Set Null & Restrict Integrity
- **Assumption Challenged**: Foreign key constraints must enforce relational invariants:
  - Deleting an active category referenced by transactions must be rejected (`ON DELETE RESTRICT`).
  - Deleting a parent category must set child category `parent_id` to `NULL` (`ON DELETE SET NULL`) without affecting deeper descendants.
  - Deleting an account or project must set transaction foreign keys to `NULL`.
  - Deleting a category must cascade-delete classification rules ONLY if no transactions reference the category.
  - Amount minor unit must be strictly positive (`CHECK (amount_minor > 0)`).
- **Attack Scenario**:
  1. Attempted deletion of category `cat_lvl3` referenced by an active transaction.
  2. Tested 3-level hierarchical category chain (`cat_lvl1` -> `cat_lvl2` -> `cat_lvl3`) and deleted `cat_lvl1`.
  3. Deleted accounts referenced by `account_id` and `transfer_to_account_id`.
  4. Deleted project referenced by both a transaction and a classification rule.
  5. Deleted tag referenced by `transaction_tags`.
  6. Inserted and updated transactions with `amount_minor = 0`, `-100`, and `-9999`.
  7. Deleted a category referenced only by classification rules vs referenced by both transactions and rules.
- **Empirical Observation**:
  - Active category deletion failed with SQLite RESTRICT `DatabaseException`.
  - Parent category deletion set child `parent_id` to `NULL`; grandchild `parent_id` remained pointing to child.
  - Account deletion set both `account_id` and `transfer_to_account_id` to `NULL` while preserving the transaction.
  - Project deletion set `project_id` to `NULL` in both `transactions` and `classification_rules`.
  - Tag deletion cleanly cascade-deleted join rows in `transaction_tags` without deleting the transaction.
  - Category deletion cascade-deleted classification rules when no transactions were attached, but was blocked by RESTRICT when a transaction was attached.
  - `amount_minor <= 0` was rejected on both `INSERT` and `UPDATE` statements.
- **Result**: **PASS**. All foreign key behaviors and constraints verified.

---

## 3. Stress Test Results Matrix

| # | Stress Test Scenario | Expected Outcome | Actual Outcome | Status |
|---|----------------------|------------------|----------------|--------|
| 1.1 | Invalid category FK in `commitDraft` | Throws `DatabaseException`, 0 partial rows, draft/job untouched | Throws `DatabaseException`, 0 partial rows | **PASS** |
| 1.2 | Invalid tag FK in `commitDraft` (Step 6) | Throws `DatabaseException`, rolls back earlier tx/meta inserts | Throws `DatabaseException`, 0 rows in any table | **PASS** |
| 1.3 | Duplicate confirmed_identifier (pre-commit) | Throws `HardDuplicateException`, 0 partial rows | Throws `HardDuplicateException`, clean rollback | **PASS** |
| 1.4 | Non-existent originalExpenseId in refund commit | Throws `DatabaseException` on `refund_links`, 0 rows | Throws `DatabaseException`, clean rollback | **PASS** |
| 1.5 | Job in illegal state (`RECOGNIZING`) | Throws `InvalidStateTransitionException`, no tx inserted | Throws `InvalidStateTransitionException` | **PASS** |
| 1.6 | Duplicate tag in `tagIds` (`['tag_1', 'tag_1']`) | Throws `DatabaseException` (PK conflict), clean rollback | Throws `DatabaseException`, clean rollback | **PASS** |
| 1.7 | Identifier collision with 30-day trash bin | Throws `TrashBinCollisionException`, clean rollback | Throws `TrashBinCollisionException` | **PASS** |
| 2.1 | Permanent delete of original expense (multi-refund) | Cascade deletes `refund_links`, keeps all refunds intact | All refund links removed, all refunds intact | **PASS** |
| 2.2 | Permanent delete of refund transaction | Deletes target refund link, preserves original expense | Link removed, original expense untouched | **PASS** |
| 2.3 | Soft delete & restore of original expense | Preserves `refund_links`, monthly summary excludes trash | Links preserved, accurate net calculations | **PASS** |
| 2.4 | Invalid FK insert into `refund_links` | Throws `DatabaseException` on invalid or duplicate FK | Throws `DatabaseException` | **PASS** |
| 2.5 | 30-day trash purge of original expense | Unlinks `refund_links` automatically, preserves refund | Expired tx purged, link unlinked, refund intact | **PASS** |
| 3.1 | Category deletion with active transaction | Throws `DatabaseException` (ON DELETE RESTRICT) | Throws `DatabaseException` | **PASS** |
| 3.2 | Category deletion in 3-level hierarchy | Sets child `parent_id` to NULL, grandchild untouched | `parent_id` NULL on child, grandchild valid | **PASS** |
| 3.3 | Account deletion on transfer transaction | Sets both `account_id` and `transfer_to_account_id` NULL | Both fields set to NULL, tx preserved | **PASS** |
| 3.4 | Project deletion on tx and classification rule | Sets `project_id` to NULL in both tables | Both fields set to NULL | **PASS** |
| 3.5 | Tag deletion on join table | Deletes `transaction_tags` rows, keeps tx intact | Join rows removed, tx intact | **PASS** |
| 3.6 | Transaction deletion cascade | Cascades metadata, join tags, confirmed identifiers | All child rows cascade deleted | **PASS** |
| 3.7 | CHECK constraint on `amount_minor <= 0` | Rejects <= 0 on both INSERT and UPDATE | All zero/negative attempts rejected | **PASS** |
| 3.8 | CaptureJob deletion cascade to drafts | Deletes draft, unlinks `transactions.origin_draft_id` | Draft deleted, `origin_draft_id` SET NULL | **PASS** |
| 3.9 | Classification rule cascade on category delete | Cascades rule when category has no transactions | Rule deleted cleanly | **PASS** |
| 3.10 | Classification rule protected when category restricted | RESTRICT blocks category deletion, rule preserved | Category deletion blocked, rule intact | **PASS** |

---

## 4. Test Suite Execution Log

1. **Docs & DDL Integrity Suite (`python test_docs_integrity.py`)**:
   - Exit code: `0`
   - All 6 deep verification test suites passed 100% (Markdown links, Pigeon contract, SQLite DDL/indexes/constraints, SWBK v1 crypto, CSV sanitization, OCR coordinate math).
2. **Canonical Database Test Suite (`flutter test test/database/database_test.dart`)**:
   - Exit code: `0`
   - All 22 tests passed.
3. **Adversarial Stress Test Suite (`flutter test test/database/relational_stress_test.dart`)**:
   - Exit code: `0`
   - All 22 tests passed.
4. **Static Analysis (`flutter analyze test/database/`)**:
   - Exit code: `0`
   - No issues found.

---

## 5. Unchallenged Areas

- **Multi-isolate concurrent write transactions**: SingWallet currently uses a unified singleton `AppDatabase` on Flutter's main thread via SQLite FFI with WAL mode and immediate connection serialization. Multiprocess / multi-isolate concurrent database contention was not evaluated as it is outside M1-A single-process architecture.

---

## 6. Final Recommendation & Verdict

**Verdict**: **APPROVE**

The relational data layer designed and implemented by `worker_m1a_1` demonstrates production-ready quality:
- Strict atomicity and complete rollback without artifact leakage.
- Precise foreign key cascade, set null, and restrict mechanics.
- Flawless refund unlinking semantics.
- Full integer minor unit precision.

The database persistence layer is ready for Milestone M1-B integration.
