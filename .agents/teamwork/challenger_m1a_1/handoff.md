# Handoff Report — challenger_m1a_1 (Milestone M1-A Adversarial Challenge)

## 1. Observation

1. **Target Files**:
   - `lib/features/deduplication/deduplication_engine.dart` (470 lines): Implements `DeduplicationEngine`, `PlatformIdentifier`, `IdentifierCompleteness`, `Tier1Result`, `Tier2Result`, `Tier3Result`, `Tier4Result`, and `DeduplicationEvaluation`.
   - `lib/data/database/transaction_manager.dart` (407 lines): Implements `TransactionManager.commitDraft`, `restoreFromTrash`, soft/permanent deletion, and rollback handling.
   - `lib/data/database/schema.dart` (225 lines): DDL defining `transactions.origin_draft_id TEXT UNIQUE` and `confirmed_identifiers PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind)`.
   - `test/deduplication/deduplication_test.dart` (369 lines): Baseline 16 unit tests created by `worker_m1a_1`.
2. **Adversarial Test Suite Created**:
   - `test/deduplication/deduplication_adversarial_test.dart` (1,122 lines, 24 test cases): Covers Tier 1 idempotence, concurrent race commits, Tier 2 image hashes, Tier 3 compound PK constraints, masked ID exclusion, refund vs payment coexistence, soft-delete restoration flow, Tier 4 24h minute-level boundaries (23h 59m vs 24h 01m), date-only +/- 1 day searches, consecutive store purchases, cross-year rollovers, and timezone equivalence.
3. **Verification Command Results**:
   - `flutter test test/deduplication/deduplication_adversarial_test.dart`:
     ```text
     00:00 +24: All tests passed! (exit code 0)
     ```
   - `flutter test`:
     ```text
     00:01 +145: All tests passed! (exit code 0)
     ```
   - `flutter analyze`:
     ```text
     Analyzing singwallet...
     No issues found! (ran in 7.3s) (exit code 0)
     ```
   - `python test_docs_integrity.py`:
     ```text
     >>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<< (exit code 0)
     ```

## 2. Logic Chain

1. **Tier 1 (Technical Idempotence)**:
   - Direct execution in `deduplication_adversarial_test.dart` (Test 1.1) verified that committing the same `origin_draft_id` twice via `TransactionManager.commitDraft` throws `DraftAlreadyCommittedException` and triggers an atomic transaction rollback.
   - Test 1.2 confirmed that direct raw SQLite inserts of duplicate `origin_draft_id` values are rejected by the database engine with `DatabaseException: UNIQUE constraint failed: transactions.origin_draft_id`.
   - Test 1.3 demonstrated that 5 parallel race conditions on the same `origin_draft_id` result in exactly 1 commit and 4 clean rollbacks.
2. **Tier 2 (Image SHA-256 Hash Matching)**:
   - Tests 2.1 - 2.4 verified that identical content hashes detect historical jobs, link to committed or trashed transactions, return clean misses on non-existent hashes, and order multi-job histories by `cj.created_at DESC`.
3. **Tier 3 (Hard Platform ID & Compound PK)**:
   - Test 3.1 confirmed that duplicate compound PK `(namespace, identifier_type, complete_value, stable_event_kind)` tuples are blocked by SQLite PRIMARY KEY constraint.
   - Test 3.2 verified that different namespaces (`wechat_pay` vs `alipay`) or identifier types with the same order number do not collide.
   - Test 3.3 verified that incomplete, masked, truncated, and unreliable identifiers are strictly excluded from Tier 3 hard deduplication (`isEligibleForHardDedup == false`).
   - Test 3.4 verified that a refund referencing the original transaction order number with `stable_event_kind = 'refund'` coexists cleanly with the original payment transaction (`stable_event_kind = 'payment'`), while subsequent duplicate refunds are rejected.
   - Test 3.5 verified that an incoming transaction matching an item in the 30-day trash bin (`deleted_at IS NOT NULL`) throws `TrashBinCollisionException` and enables `restoreFromTrash` to recover the original record without generating duplicates.
4. **Tier 4 (Heuristic Fuzzy Matching Boundaries)**:
   - Tests 4.1a - 4.1e verified the 24-hour boundary with minute precision: 23 hours 59 minutes matches (soft warning), 24 hours 00 minutes matches (boundary inclusive), 24 hours 01 minutes does not match (window exceeded). Backward time windows behave identically.
   - Test 4.2 proved bidirectional matching across raw and normalized merchant names, whitespace trimming, and case insensitivity.
   - Test 4.3 proved date-only transactions (`occurred_at == null`) safely query a +/- 1 calendar day window (`BETWEEN min_date AND max_date`), matching on days 0, -1, +1, and excluding days -2 and +2.
   - Tests 4.5 - 4.7 confirmed consecutive legitimate store purchases can be saved after user confirmation, cross-year rollovers (Dec 31 to Jan 1) are caught within 1 hour, and differing timezone representations of the same UTC epoch compute identical durations.

## 3. Caveats

- **Upstream Parser Obligation**: In `PlatformIdentifier`, `isEligibleForHardDedup` relies on `completeness == IdentifierCompleteness.complete`. Milestone M1-B parser implementation must classify any order number containing asterisks (`*`) or partial digits as `masked` or `truncated` prior to invoking the deduplication engine.

## 4. Conclusion

The 4-tier deduplication engine in `lib/features/deduplication/deduplication_engine.dart` and draft commitment transaction management in `lib/data/database/transaction_manager.dart` withstand all adversarial attacks, boundary conditions, and stress tests.

**Verdict**: **APPROVE**.

## 5. Verification Method

To independently verify all findings:
```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path

# 1. Run dedicated adversarial challenge suite (24 tests)
flutter test test/deduplication/deduplication_adversarial_test.dart

# 2. Run baseline deduplication suite (16 tests)
flutter test test/deduplication/deduplication_test.dart

# 3. Run entire test suite (145 tests)
flutter test

# 4. Run static analysis (0 issues)
flutter analyze

# 5. Run docs & schema integrity test suite
python test_docs_integrity.py
```
All commands must terminate with exit code 0.
