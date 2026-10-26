# Adversarial Challenge Report: 4-Tier Deduplication Engine

**Target**: `lib/features/deduplication/deduplication_engine.dart` & `lib/data/database/transaction_manager.dart`  
**Challenger**: `challenger_m1a_1` (Critic & Specialist)  
**Date**: 2026-10-22  
**Final Verdict**: **APPROVE**  
**Overall Risk Assessment**: **LOW**

---

## 1. Executive Summary

An adversarial empirical verification of the 4-tier deduplication engine was conducted against the canonical architecture specification in `docs/跨平台架构与数据规范.md`. 

A dedicated adversarial test harness comprising 24 stress tests was designed and executed in `test/deduplication/deduplication_adversarial_test.dart` alongside the worker's test suite and project test suites.

All 145 automated tests passed (Exit code 0), and static analysis passed with zero errors or warnings (`flutter analyze`: No issues found).

---

## 2. Adversarial Challenge Dimensions & Empirical Results

### Tier 1: Technical Idempotence
- **Challenge 1.1 (Commit Duplication)**: Attempted committing the identical `origin_draft_id` twice via `TransactionManager.commitDraft`.
  - *Result*: 1st commit succeeds; 2nd commit throws `DraftAlreadyCommittedException` and triggers an atomic SQLite rollback. State integrity preserved. [PASS]
- **Challenge 1.2 (Direct SQLite UNIQUE Constraint)**: Directly executed raw SQL `INSERT` of two transactions with identical `origin_draft_id`.
  - *Result*: Blocked at the SQLite database engine level by `UNIQUE constraint failed: transactions.origin_draft_id`. [PASS]
- **Challenge 1.3 (Concurrency & Race Stress)**: Dispatched 5 concurrent asynchronous `commitDraft` requests for the same `origin_draft_id`.
  - *Result*: Exactly 1 transaction succeeded, 4 failed gracefully with rollback. Exactly 1 transaction recorded in SQLite. [PASS]
- **Challenge 1.4 (Manual Entries with Null Draft ID)**: Verified multiple transactions with `origin_draft_id == null`.
  - *Result*: SQLite allows multiple nulls in UNIQUE column per SQL standard without collision. [PASS]

### Tier 2: Same-Image SHA-256 Hash Matching
- **Challenge 2.1 (Multi-Job Content Hash Match)**: Verified exact SHA-256 hash match identifies existing job and committed transaction.
  - *Result*: Correctly located existing job `job_hash_1` and linked transaction `tx_hash_1`. [PASS]
- **Challenge 2.2 (Image Hash for Trashed Item)**: Image hash matching when target transaction was soft-deleted (`deleted_at IS NOT NULL`).
  - *Result*: `isTransactionInTrash` evaluates to `true`, allowing UI to offer recovery. [PASS]
- **Challenge 2.3 (Unseen Image Hash)**: Non-existent image hash query.
  - *Result*: Returns clean miss (`isMatched == false`, `existingJobId == null`). [PASS]
- **Challenge 2.4 (Multi-Job Ordering)**: Evaluated behavior when multiple jobs share the same content hash.
  - *Result*: Query orders by `cj.created_at DESC LIMIT 1`, retrieving the most recent ingestion job. [PASS]

### Tier 3: Hard Platform Identifier & Compound PK Uniqueness
- **Challenge 3.1 (Compound PK SQLite Constraint)**: Verified compound primary key `(namespace, identifier_type, complete_value, stable_event_kind)`.
  - *Result*: Duplicate compound PK throws `DatabaseException(PRIMARY KEY constraint failed)`. [PASS]
- **Challenge 3.2 (Namespace & Identifier Type Segregation)**: Identical order number across different namespaces (`wechat_pay` vs `alipay`) or identifier types (`platform_transaction_no` vs `merchant_order_no`).
  - *Result*: No collision. SQLite compound PK permits coexistence. [PASS]
- **Challenge 3.3 (Incomplete / Masked / Truncated Identifier Exclusion)**:
  - *Result*: Identifiers with `IdentifierCompleteness.masked`, `truncated`, `unreliable`, or `none` return `isEligibleForHardDedup == false` and `Tier3Result.miss()`. Masked order IDs with `*` never trigger false hard-duplicate blocks. [PASS]
- **Challenge 3.4 (Refund vs Payment Distinction)**: Tested incoming refund referencing the original payment transaction's order number.
  - *Result*: Payment (`stable_event_kind = 'payment'`) and refund (`stable_event_kind = 'refund'`) do NOT collide. Both can be committed and linked via `refund_links`. A duplicate refund for the same order number is blocked. [PASS]
- **Challenge 3.5 (Soft-Deleted Item Detection & Restoration)**: Incoming transaction matches an item in the 30-day trash bin (`deleted_at IS NOT NULL`).
  - *Result*: `checkTier3PlatformId` returns `Tier3Result.trashBinDuplicate` with `isInTrash = true`. `commitDraft` throws `TrashBinCollisionException`. `restoreFromTrash` restores the original transaction, updates draft link, and avoids duplicate creation. [PASS]

### Tier 4: Heuristic Fuzzy Matching Boundary
- **Challenge 4.1 (24-Hour Boundary Precision)**:
  - Base transaction at `2026-10-22T12:00:00Z`.
  - Candidate at `2026-10-23T11:59:00Z` (23h 59m later): **MATCHES** (soft warning). [PASS]
  - Candidate at `2026-10-23T12:00:00Z` (24h 00m later): **MATCHES** (boundary inclusive). [PASS]
  - Candidate at `2026-10-23T12:01:00Z` (24h 01m later): **DOES NOT MATCH** (outside window). [PASS]
  - Candidate at `2026-10-21T12:01:00Z` (23h 59m earlier): **MATCHES** (backward window). [PASS]
  - Candidate at `2026-10-21T11:59:00Z` (24h 01m earlier): **DOES NOT MATCH** (outside window). [PASS]
- **Challenge 4.2 (Merchant Matching Logic)**:
  - Exact raw merchant: **MATCHES**. [PASS]
  - Normalized merchant match with different branch raw name: **MATCHES**. [PASS]
  - Candidate raw matches DB normalized: **MATCHES**. [PASS]
  - Case-insensitive & trimmed whitespace: **MATCHES**. [PASS]
  - Different merchants (e.g. Starbucks vs Luckin Coffee): **DOES NOT MATCH**. [PASS]
- **Challenge 4.3 (Date-Only Transaction Safety)**:
  - Transactions without second-level precision (`occurred_at == null`) search `occurred_on BETWEEN prev_date AND next_date` (+/- 1 calendar day).
  - Same day, -1 day, +1 day: **MATCHES**. [PASS]
  - -2 days, +2 days: **DOES NOT MATCH**. [PASS]
- **Challenge 4.4 (Trash Bin Exclusion)**: Soft-deleted transactions (`deleted_at IS NOT NULL`) are strictly excluded from Tier 4 candidate lists. [PASS]
- **Challenge 4.5 (Consecutive Legitimate Purchases)**: User makes 2 rapid coffee purchases at the same store with the same amount.
  - Tier 4 surfaces soft warning without crashing or blocking. User confirmation enables clean commit of both transactions. [PASS]
- **Challenge 4.6 (Calendar Rollover Boundaries)**: Tested 2026-12-31 to 2027-01-01 rollover.
  - +/- 1 day string bounds (`'2026-12-31'` to `'2027-01-02'`) correctly catch 1-hour delta across New Year. [PASS]
- **Challenge 4.7 (Timezone Representation)**: Tested ISO-8601 with UTC `Z` vs `+08:00` offset representing identical epochs.
  - Correctly resolved to 30-minute delta and flagged as fuzzy match. [PASS]

---

## 3. Stress Test Results Summary

| Challenge ID | Scenario | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|---|
| T1-1 | Re-committing same origin_draft_id | Blocked, throws exception, rolls back | `DraftAlreadyCommittedException` thrown, 1 tx in DB | **PASS** |
| T1-2 | Direct raw SQL insert duplicate draft_id | Blocked by SQLite UNIQUE constraint | `DatabaseException(UNIQUE constraint failed)` | **PASS** |
| T1-3 | 5 parallel race commitDraft requests | Exactly 1 succeeds, 4 rollback | 1 success, 4 caught, 1 tx in DB | **PASS** |
| T1-4 | Multiple manual transactions (draft_id=null) | Coexist without collision | 3 transactions created successfully | **PASS** |
| T2-1 | Identical SHA-256 image hash match | Matches existing job and tx | Returned `job_hash_1` & `tx_hash_1` | **PASS** |
| T2-2 | Image hash of trashed transaction | Matches and flags isTransactionInTrash | `isTransactionInTrash == true` | **PASS** |
| T2-3 | Non-existent image hash | Clean miss | `isMatched == false` | **PASS** |
| T2-4 | Multi-job image hash resolution | Most recent job returned | Returned `job_mj_2` (latest) | **PASS** |
| T3-1 | Compound PK duplicate insertion | Blocked by PRIMARY KEY constraint | `DatabaseException(PRIMARY KEY constraint failed)` | **PASS** |
| T3-2 | Same ID, different namespace/type | Coexist without collision | 3 records coexist cleanly | **PASS** |
| T3-3 | Incomplete / masked completeness enum | Strictly excluded from Tier 3 | `isMatched == false` for all | **PASS** |
| T3-4 | Refund referencing payment order number | No collision; payment & refund coexist | Coexist in DB, refund link established | **PASS** |
| T3-5 | Trashed item hard ID collision & restore | Prompt restore, restores original ID | `TrashBinCollisionException` -> `restoreFromTrash` OK | **PASS** |
| T4-1a | 23h 59m later (same merchant & amount) | Matches (within 24h window) | `hasSuspectedDuplicates == true` | **PASS** |
| T4-1b | Exactly 24h 00m later | Matches (inclusive boundary) | `hasSuspectedDuplicates == true` | **PASS** |
| T4-1c | 24h 01m later | Does NOT match (> 24h window) | `hasSuspectedDuplicates == false` | **PASS** |
| T4-1d | 23h 59m earlier (backward boundary) | Matches (within 24h window) | `hasSuspectedDuplicates == true` | **PASS** |
| T4-1e | 24h 01m earlier (backward boundary) | Does NOT match (> 24h window) | `hasSuspectedDuplicates == false` | **PASS** |
| T4-2 | Normalized vs raw merchant matching | Matches bidirectionally | `hasSuspectedDuplicates == true` | **PASS** |
| T4-3 | Date-only transaction +/- 1 calendar day | Matches within 1 day, misses at 2 days | Matches 0, -1, +1; misses -2, +2 | **PASS** |
| T4-4 | Trashed transaction in Tier 4 | Excluded from fuzzy duplicate candidates | `hasSuspectedDuplicates == false` | **PASS** |
| T4-5 | Consecutive store purchases | Soft warning, manual confirm succeeds | 2 transactions saved successfully | **PASS** |
| T4-6 | Cross-year rollover (2026-12-31 -> 2027-01-01) | Correctly catches 1h delta across year | `hasSuspectedDuplicates == true` | **PASS** |
| T4-7 | Timezone offset equivalence (Z vs +08:00) | Correct epoch difference calculation | `hasSuspectedDuplicates == true` | **PASS** |

---

## 4. Observations & Defensive Recommendations for Subsequent Milestones

1. **Parser-to-Identifier Completeness Enforcement (Milestone M1-B)**:
   - In `DeduplicationEngine`, `isEligibleForHardDedup` checks `completeness == IdentifierCompleteness.complete`.
   - *Recommendation*: Milestone M1-B's OCR parsing pipeline (`order_id_parser.dart`) must strictly mark any platform identifier containing asterisks (`*`), truncation markers, or partial lengths as `IdentifierCompleteness.masked` or `truncated` to prevent erroneous entry into `confirmed_identifiers`.
2. **Tier 2 Ingestion Hook**:
   - `checkTier2ImageHash` should be invoked immediately upon image ingestion before creating a new `capture_jobs` record, allowing immediate redirection to existing drafts if an identical screenshot is re-shared.

---

## 5. Final Verdict

**APPROVE** — The 4-tier deduplication engine in `lib/features/deduplication/deduplication_engine.dart` and `TransactionManager` in `lib/data/database/transaction_manager.dart` fulfill all requirements of Milestone M1-A with production-level robustness, mathematical rigor, and zero regressions.
