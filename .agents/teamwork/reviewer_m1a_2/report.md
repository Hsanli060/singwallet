# Milestone M1-A Code Review & Adversarial Challenge Report

**Reviewer**: `reviewer_m1a_2` (Roles: reviewer, critic)  
**Parent Orchestrator**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)  
**Target Milestone**: M1-A (Unified SQLite Data Layer & Core Ledger Transactions)  
**Date**: 2026-10-22  
**Verdict**: **APPROVE**

---

## 1. Review Summary

| Metric | Result | Status |
|---|---|---|
| **Integrity Violations** | 0 detected (no hardcoded cheats, facades, or shortcuts) | PASS |
| **Static Analysis (`flutter analyze`)** | 0 issues found | PASS |
| **Unit Test Suite (`flutter test`)** | 99/99 passed (61 M0 + 38 M1-A tests) | PASS |
| **Docs Integrity (`test_docs_integrity.py`)** | 6/6 test suites passed 100% | PASS |
| **4-Tier Deduplication Engine** | Tiers 1-4 fully verified with genuine DB operations | PASS |
| **State Machine & Crash Recovery** | Transition matrix & `recoverLingeringJobs` verified | PASS |
| **Overall Verdict** | **APPROVE** | PASS |

---

## 2. Review Dimensions & Detailed Findings

### 2.1 Deduplication Engine (`lib/features/deduplication/deduplication_engine.dart`)

- **Tier 1: Technical Idempotence (`checkTier1Idempotence`)**
  - **Verification**: Verified against `transactions(origin_draft_id UNIQUE)`. Matches existing transactions by `origin_draft_id`, differentiates active records from those in the 30-day trash bin via `deleted_at != null`, returning `Tier1Result.hit` with `isInTrash`.
  - **Correctness**: Guarantees identical draft ingestion cannot produce duplicate ledger transactions.

- **Tier 2: Same-Image Hash Check (`checkTier2ImageHash`)**
  - **Verification**: Queries `capture_jobs(content_hash)` using the `idx_capture_jobs_hash` B-tree index. Joins `drafts` and `transactions` to locate existing processing state or committed ledger entry.
  - **Correctness**: Correctly returns `existingJobId`, `jobState`, `existingDraftId`, and `existingTransactionId`, allowing caller to navigate directly to existing drafts or warn the user without repeating OCR computation.

- **Tier 3: Hard Platform Identifier Check (`checkTier3PlatformId`)**
  - **Verification**: Evaluates `PlatformIdentifier` against `confirmed_identifiers` compound primary key `(namespace, identifier_type, complete_value, stable_event_kind)`.
  - **Incomplete / Masked ID Filtering**: Verified `isEligibleForHardDedup` requires `completeness == IdentifierCompleteness.complete && completeValue.trim().isNotEmpty`. Masked values (e.g. `420000****7890`) evaluate to `false` and immediately return `Tier3Result.miss()`, avoiding false positive blocks.
  - **Trash Bin vs Active Separation**: Soft-deleted entries return `Tier3Result.trashBinDuplicate`, whereas active entries return `Tier3Result.activeDuplicate`.
  - **Event Kind Disambiguation**: Payments and refunds on the same order number are differentiated via `stable_event_kind`, preventing false collision.

- **Tier 4: Heuristic Fuzzy Matching (`checkTier4Fuzzy`)**
  - **Verification**: Queries active transactions (`deleted_at IS NULL`) matching exact `amount_minor` and `occurred_on BETWEEN ? AND ?` (within 24 hours of target date).
  - **Merchant Normalization**: Matches raw-to-raw, normalized-to-normalized, or raw-to-normalized, case-insensitively with trimming.
  - **Timestamp Refinement**: If both transactions provide fine-grained timestamps (`occurred_at`), computes `abs(candidateDateTime - dbDateTime)` and excludes candidates exceeding 24 hours.
  - **Consecutive Purchases**: Soft warning does not block commit; users can acknowledge and save consecutive identical purchases.

---

### 2.2 Task State Machine & Crash Recovery (`lib/data/database/state_machine.dart`)

- **Transition Rules Matrix**:
  - `IMPORTED` -> `RECOGNIZING`, `DISCARDED`, `FAILED`
  - `RECOGNIZING` -> `NEEDS_REVIEW`, `FAILED`, `IMPORTED` (recovery), `DISCARDED`
  - `NEEDS_REVIEW` -> `COMMITTED`, `DISCARDED`, `RECOGNIZING` (re-recognition)
  - `FAILED` -> `RECOGNIZING`, `IMPORTED`, `DISCARDED`
  - Terminal states `COMMITTED` and `DISCARDED` permit no outbound transitions.
  - Illegal transitions throw `InvalidStateTransitionException` with informative diagnostics.

- **Crash Recovery (`recoverLingeringJobs`)**:
  - Scans `capture_jobs` for jobs stuck in `RECOGNIZING` due to process kill, memory ejection, or crashes.
  - Jobs with `attempt_count < maxAttempts` (default 3) are safely reset to `IMPORTED` for retry.
  - Jobs with `attempt_count >= maxAttempts` are marked `FAILED` with timestamp update, preventing boot-crash loops.
  - `attempt_count` is incremented on each entry into `RECOGNIZING`.

---

### 2.3 Transaction Management & ACID Guarantees (`lib/data/database/transaction_manager.dart`)

- `TransactionManager.commitDraft` executes all mutations inside an atomic `db.transaction(...)` block across 7 tables:
  1. Draft state validation (`NEEDS_REVIEW`)
  2. Idempotence check on `origin_draft_id`
  3. Pre-commit collision check on `confirmed_identifiers`
  4. Insertion into `transactions`
  5. Insertion into `transaction_metadata`
  6. Insertion into `transaction_tags`
  7. Insertion into `confirmed_identifiers`
  8. Insertion into `refund_links` (if refund)
  9. Update `drafts.saved_transaction_id`
  10. Update `capture_jobs.state = 'COMMITTED'`
- Rollback test proves that an invalid transaction (e.g. `amount_minor = 0` violating CHECK constraint) rolls back all intermediate operations without leaving orphaned records.

---

## 3. Adversarial Challenges & Stress Testing

### Challenge 1: Date Boundary & Daylight Saving Time (DST) Handling in Tier 4
- **Assumption**: `DateTime.tryParse(occurredOn)` parses `YYYY-MM-DD` in local time.
- **Attack Scenario**: In timezones with Daylight Saving Time transitions, `candidateDate.subtract(const Duration(days: 1))` subtracts 24 hours. On a 25-hour fall-back day, this lands on 23:00 of the preceding day; on a 23-hour spring-forward day, it could theoretically shift hour alignment.
- **Risk Assessment**: Low in primary target region (`Asia/Shanghai` has no DST).
- **Mitigation Recommendation**: For future internationalization, parse date boundary calculations using UTC: `DateTime.tryParse('${occurredOn}T00:00:00Z')`.

### Challenge 2: Masked ID Defense-in-Depth in `TransactionManager`
- **Assumption**: Callers of `TransactionManager.commitDraft` only construct `request.identifier` when completeness is `COMPLETE`.
- **Attack Scenario**: If upstream OCR parser erroneously sets `request.identifier` with a masked order ID (e.g., `420000****7890`), `TransactionManager` checks `completeValue.trim().isNotEmpty` and inserts into `confirmed_identifiers`.
- **Blast Radius**: A masked ID in `confirmed_identifiers` could cause false-positive collision with other masked IDs from different transactions sharing the same prefix/suffix.
- **Mitigation Recommendation**: Add a defense-in-depth validator in `ConfirmedIdentifier` or `TransactionManager` asserting that `completeValue` does not contain mask characters (`*`, `%`, `_`).

### Challenge 3: Concurrent Lingering Job Recovery
- **Assumption**: `recoverLingeringJobs` is called during single-threaded app cold boot.
- **Attack Scenario**: If multiple background workers (e.g. WorkManager + UI cold boot) call `recoverLingeringJobs` simultaneously, jobs could be updated multiple times.
- **Mitigation Recommendation**: Wrap `recoverLingeringJobs` body in an explicit `db.transaction(...)` with atomic batch updates.

---

## 4. Verified Claims Matrix

| Claim from Worker M1-A | Verification Method | Result |
|---|---|---|
| 12 tables and 11 indices match spec | `python test_docs_integrity.py` Suite 3 & `database_test.dart` | VERIFIED |
| Foreign key cascades (`refund_links ON DELETE CASCADE`) unlinking works | SQLite test deleting original expense | VERIFIED |
| Currency units strictly integer cents (`amount_minor > 0`) | SQLite CHECK constraint rejection test | VERIFIED |
| Tier 1 idempotence prevents duplicate draft commits | Unit test querying `transactions(origin_draft_id)` | VERIFIED |
| Tier 2 image SHA-256 links to existing drafts/jobs | Unit test querying `capture_jobs(content_hash)` | VERIFIED |
| Tier 3 hard deduplication excludes masked/incomplete IDs | Unit test testing `IdentifierCompleteness.masked` | VERIFIED |
| Tier 4 heuristic fuzzy matching detects same merchant + amount in 24h | Unit test with 2h delta vs 48h delta | VERIFIED |
| Consecutive purchases in same store can be confirmed and saved | Unit test creating 2 consecutive transactions | VERIFIED |
| State machine enforces linear transitions and rejects invalid ones | Unit test asserting `InvalidStateTransitionException` | VERIFIED |
| Startup recovery resets `RECOGNIZING` jobs to `IMPORTED` (< 3) or `FAILED` (>= 3) | Unit test verifying lingering job recovery | VERIFIED |
| Atomic draft commit rolls back on any failure | Unit test committing invalid zero-amount draft | VERIFIED |
| 0 static analysis issues | `flutter analyze` | VERIFIED |
| 99 tests passing | `flutter test` | VERIFIED |

---

## 5. Coverage Gaps & Unverified Items

- **OCR Pipeline & Classification Engine**: Deferred to Milestone M1-B per project schedule.
- **SWBK Backup Container & CSV Export UI**: Deferred to Milestone M-Final / E2E per project schedule.
- **No Unexplored Dependencies**: All M1-A requirements and dependencies have been thoroughly verified.

---

## 6. Verdict

**APPROVE**. Milestone M1-A code is robust, cleanly architected, thoroughly tested, and completely free of integrity violations.
