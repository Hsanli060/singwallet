# Handoff Report: Milestone M1-A Relational Integrity & Transaction Adversarial Challenge

**Agent**: `challenger_m1a_2` (Empirical Challenger: critic, specialist)  
**Parent**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)  
**Timestamp**: 2026-10-22T11:33:00Z  
**Type**: Hard Handoff (Task Complete)  
**Verdict**: **APPROVE**  

---

## 1. Observation

1. **Python DDL & Docs Integrity Suite (`test_docs_integrity.py`)**:
   Command: `python test_docs_integrity.py`
   Result: Exit code `0`
   Verbatim output:
   ```text
   --- 3. Testing SQLite DDL, Constraints & Cascades ---
     SQLite DDL executed successfully!
     All 12 expected tables verified: 12 tables created.
     All 11 required performance indexes verified!
     Check constraint (amount_minor > 0) verified!
     Idempotence UNIQUE constraint (origin_draft_id) verified!
     Hard deduplication PRIMARY KEY constraint on confirmed_identifiers verified!
     Refund unlinking on permanent delete (ON DELETE CASCADE without deleting refund transaction) verified!
     classification_rules project_id ON DELETE SET NULL foreign key verified!
   =======================================================
   >>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<
   =======================================================
   ```

2. **Core Database Unit Tests (`test/database/database_test.dart`)**:
   Command: `flutter test test/database/database_test.dart`
   Result: Exit code `0`
   Output: `00:00 +22: All tests passed!`

3. **Adversarial Stress Test Suite (`test/database/relational_stress_test.dart`)**:
   Created dedicated 22-test adversarial harness directly attacking transaction rollback and foreign key cascades.
   Command: `flutter test test/database/relational_stress_test.dart`
   Result: Exit code `0`
   Output:
   ```text
   00:00 +0: Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections) 1.1 Fail on invalid Category FK in commitDraft -> Zero partial rows remain
   00:00 +1: Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections) 1.2 Fail on non-existent Tag FK (Step 6 failure) -> Zero partial rows remain
   00:00 +2: Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections) 1.3 Fail on duplicate confirmed_identifier (pre-commit check) -> Zero partial rows
   00:00 +3: Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections) 1.4 Fail on non-existent originalExpenseId in refund commitDraft -> Zero partial rows
   00:00 +4: Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections) 1.5 Fail when job is in illegal state (RECOGNIZING) -> Rejection and rollback
   00:00 +5: Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections) 1.6 Fail on duplicate tag in tagIds -> UNIQUE constraint failure and clean rollback
   00:00 +6: Stress Suite 1: Transaction Atomicity & Rollback (Intentional Injections) 1.7 Fail on TrashBinCollisionException -> Clean rollback
   00:00 +7: Stress Suite 2: Refund Cascade & Unlinking Multi-Case Testing 2.1 Permanently deleting original expense unlinks all refunds while preserving them intact
   00:00 +8: Stress Suite 2: Refund Cascade & Unlinking Multi-Case Testing 2.2 Permanently deleting a refund transaction unlinks its link but preserves original expense
   00:00 +9: Stress Suite 2: Refund Cascade & Unlinking Multi-Case Testing 2.3 Soft-deleting original expense preserves refund_links and enables trash recovery
   00:00 +10: Stress Suite 2: Refund Cascade & Unlinking Multi-Case Testing 2.4 Direct invalid insert into refund_links violates foreign key constraints
   00:00 +11: Stress Suite 2: Refund Cascade & Unlinking Multi-Case Testing 2.5 Purging expired trash transaction unlinks refund_links while preserving refund intact
   00:00 +12: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.1 Category ON DELETE RESTRICT blocks deletion of leaf and intermediate nodes
   00:00 +13: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.2 Category ON DELETE SET NULL cascades down hierarchical chain
   00:00 +14: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.3 Account ON DELETE SET NULL clears both account_id and transfer_to_account_id
   00:00 +15: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.4 Project ON DELETE SET NULL clears project_id in both transactions and classification_rules
   00:00 +16: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.5 Tag ON DELETE CASCADE cleans transaction_tags without deleting transaction
   00:00 +17: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.6 Transaction permanent delete cascades metadata, tags, and confirmed identifiers
   00:00 +18: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.7 CHECK (amount_minor > 0) strictly tested across INSERT and UPDATE
   00:00 +19: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.8 CaptureJob ON DELETE CASCADE cascades to drafts, and drafts unlinks origin_draft_id
   00:00 +20: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.9 Classification rule CASCADE deletion when referenced category has no transactions
   00:00 +21: Stress Suite 3: Foreign Key Cascades & Constraints Stress Testing 3.10 Category ON DELETE RESTRICT prevents cascade deletion of classification_rules when transaction exists
   00:00 +22: All tests passed!
   ```

4. **Static Code Analysis (`flutter analyze`)**:
   Command: `flutter analyze test/database/`
   Result: Exit code `0`
   Output: `No issues found! (ran in 3.7s)`

---

## 2. Logic Chain

1. **Transaction Atomicity Verification**:
   - In `TransactionManager.commitDraft`, operations are wrapped in `await db.transaction((txn) async { ... })` (`lib/data/database/transaction_manager.dart:118-271`).
   - Observations from tests 1.1 through 1.7 demonstrate that when exceptions are thrown at any stage (e.g. invalid category FK in Step 4, duplicate tag PK in Step 6, duplicate identifier in Step 3/7, invalid refund expense FK in Step 8, or invalid job state in Step 1):
     - All prior inserts into `transactions`, `transaction_metadata`, `transaction_tags`, and `confirmed_identifiers` are rolled back.
     - `drafts.saved_transaction_id` remains `NULL`.
     - `capture_jobs.state` remains unchanged.
   - Therefore, transaction rollback is 100% atomic and leaks zero partial rows.

2. **Refund Cascade and Unlinking Verification**:
   - Schema specification defines `refund_links` (`lib/data/database/schema.dart:170-178`):
     ```sql
     FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
     FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
     ```
   - Observations from tests 2.1, 2.2, 2.3, and 2.5 demonstrate that:
     - Deleting the original expense triggers `ON DELETE CASCADE` exclusively on `refund_links`.
     - The refund transaction record in `transactions` remains untouched with its original amount, date, and `type='refund'`.
     - Multiple partial refunds linked to a single expense all remain preserved when the original expense is permanently deleted or purged after 30 days.
   - Therefore, refund unlinking semantics are completely satisfied.

3. **Foreign Key Integrity Verification**:
   - Observations from tests 3.1 through 3.10 demonstrate:
     - Deletion of an active category referenced by a transaction is blocked by SQLite's `ON DELETE RESTRICT` (`lib/data/database/schema.dart:138`).
     - Hierarchical categories cascade `ON DELETE SET NULL` on `parent_id` (`schema.dart:84`).
     - Account and project foreign keys are set to `NULL` on deletion without corrupting transaction ledger entries.
     - `amount_minor <= 0` throws constraint violations on both inserts and updates (`schema.dart:134`).
   - Therefore, relational integrity constraints are fully robust.

---

## 3. Caveats

- **Concurrency Scope**: Tests evaluate SQLite transactions in the single-isolate FFI model used in SingWallet's current architecture. Multi-process concurrent write locking (SQLITE_BUSY contention under simultaneous external processes) is not currently part of the application design and was not tested.
- **No other caveats.**

---

## 4. Conclusion

**Verdict: APPROVE**

The SQLite data layer implementation for Milestone M1-A satisfies all relational integrity, transaction atomicity, cascade unlinking, and constraint requirements. No regressions or data anomalies were found.

---

## 5. Verification Method

Independent verification can be executed via:

```powershell
# 1. Docs and Schema DDL integrity suite
python test_docs_integrity.py

# 2. Database canonical unit test suite
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
flutter test test/database/database_test.dart

# 3. Adversarial stress test harness
flutter test test/database/relational_stress_test.dart

# 4. Static analysis
flutter analyze test/database/
```

**Invalidation Conditions**:
- Any transaction rollback leaving orphaned rows in `transactions`, `metadata`, `tags`, or `confirmed_identifiers`.
- Deletion of original expense leading to deletion of the refund transaction in `transactions`.
- Ability to insert or update `amount_minor <= 0`.
- Deletion of category referenced by active transaction without raising foreign key restriction.
