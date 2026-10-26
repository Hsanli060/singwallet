# Empirical Adversarial Challenge Handoff Report — Milestone M2

## 1. Observation

### Verification Commands & Results
- Command: `flutter test`
  - Output: `00:12 +353: All tests passed!` (Exit code 0, 100% pass across 353 test cases).
- Command: `flutter analyze`
  - Output: `No issues found! (ran in 3.0s)` (Exit code 0, 0 warnings, 0 errors, 0 lints).
- Command: `flutter test test/presentation/m2_adversarial_challenge_test.dart`
  - Output: `00:01 +13: All tests passed!` (13 newly authored empirical challenge scenarios passed).

### Source Code Observations

1. **Rules Reordering & Empty Rules**:
   - `lib/data/repositories/rule_repository.dart:96-114`:
     ```dart
     @override
     Future<void> reorderRules(List<ClassificationRule> reordered) async {
       final nowIso = DateTime.now().toUtc().toIso8601String();
       final total = reordered.length;

       for (var i = 0; i < total; i++) {
         final rule = reordered[i];
         // Assign strictly descending priorities in steps of 10
         final calculatedPriority = (total - i) * 10;
         await _db.update(
           'classification_rules',
           {
             'priority': calculatedPriority,
             'updated_at': nowIso,
           },
           where: 'id = ?',
           whereArgs: [rule.id],
         );
       }
     }
     ```
   - When `reordered.isEmpty` (`total = 0`), the loop iterates 0 times, cleanly avoiding DB updates or index exceptions.
   - For any list of $N$ rules, priority at index $i$ is $(N - i) \times 10$. For any $i < j$, $(N - i) \times 10 > (N - j) \times 10$ with step size 10, strictly monotonic. When queried with `ORDER BY priority DESC, created_at DESC`, order preservation is mathematically guaranteed.

2. **Rematching Pending Drafts Non-Retroactivity**:
   - `lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart:37-43`:
     ```sql
     SELECT d.*
     FROM drafts d
     JOIN capture_jobs cj ON d.capture_id = cj.id
     WHERE cj.state IN ('NEEDS_REVIEW', 'IMPORTED')
       AND d.saved_transaction_id IS NULL
     ```
   - Only uncommitted pending drafts (`state IN ('NEEDS_REVIEW', 'IMPORTED')` and `saved_transaction_id IS NULL`) are selected.
   - The rematching routine updates only table `drafts` (`UPDATE drafts SET candidate_fields = ?, updated_at = ? WHERE id = ?`).
   - ZERO updates or deletes are ever issued against table `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, or `refund_links`.

3. **Refund Links Foreign Key Cascades & Non-Corruption**:
   - `lib/data/database/schema.dart:171-179`:
     ```sql
     CREATE TABLE IF NOT EXISTS refund_links (
         refund_transaction_id TEXT PRIMARY KEY NOT NULL,
         original_expense_id TEXT NOT NULL,
         created_at TEXT NOT NULL,
         FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
         FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
     );
     ```
   - `lib/data/database/soft_delete_manager.dart:92-110`:
     - Permanent deletion of original expense (`DELETE FROM transactions WHERE id = ?`) cascades to remove rows in `refund_links` referencing `original_expense_id`.
     - The junction table `refund_links` references `transactions(id)` with `ON DELETE CASCADE`. The table `transactions` has no foreign key constraint pointing back to `refund_links`.
     - Soft deletion of original expense modifies `transactions.deleted_at` only, leaving the `refund_links` row intact during the 30-day recovery window.

4. **Monthly Summary Calculation, Negative/Zero Balances & Transfers**:
   - `lib/data/repositories/ledger_repository.dart:227-250`:
     ```sql
     SELECT
       COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor ELSE 0 END), 0) AS total_expense,
       COALESCE(SUM(CASE WHEN type = 'refund' THEN amount_minor ELSE 0 END), 0) AS total_refund,
       COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE 0 END), 0) AS total_income,
       COUNT(CASE WHEN type IN ('expense', 'refund') THEN 1 ELSE NULL END) AS tx_count
     FROM transactions
     WHERE deleted_at IS NULL
       AND occurred_on BETWEEN ? AND ?
     ```
   - Internal transfers (`type = 'transfer'`) evaluate to 0 in all CASE expressions and NULL in the count expression, ensuring strict exclusion from expense/refund/income monthly totals.
   - `netExpenseMinor = totalExpense - totalRefund`. When refunds exceed expenses, `netExpenseMinor` is negative (e.g. -6,500 minor units = -65.00 CNY).
   - `CurrencyUtils.centsToYuanString(-6500)` returns `"-65.00"`.
   - In `LedgerRepository.getAccountBalances()`:
     ```sql
     WHEN type = 'transfer' AND transfer_to_account_id = ? THEN amount_minor
     WHEN type = 'transfer' AND account_id = ? THEN -amount_minor
     ```
     Conserves total money across transferring accounts ($-X + X = 0$).

---

## 2. Logic Chain

1. **Rules Reordering**:
   - *Observation*: `RuleRepository.reorderRules` calculates `priority = (total - i) * 10`.
   - *Logic*: Given any ordered list of rules $R = [r_0, r_1, \dots, r_{k-1}]$, priority $P(r_i) = (k - i) \times 10$. Since $i < i+1 \implies k - i > k - (i+1)$, $P(r_i) - P(r_{i+1}) = 10 > 0$.
   - *Empirical test*: Tested in `test/presentation/m2_adversarial_challenge_test.dart` with 25 rules having colliding and negative initial priorities. Reordering reversed the list and produced priorities from 250 down to 10 in steps of 10. `getAllRules` returned the exact reversed order.
   - *Empty test*: Empty list input (`[]`) completed with 0 updates and 0 errors.

2. **Rematching Non-Retroactivity**:
   - *Observation*: `_rematchPendingDrafts()` queries only `state IN ('NEEDS_REVIEW', 'IMPORTED') AND d.saved_transaction_id IS NULL` and updates only `drafts`.
   - *Logic*: Committed transactions reside exclusively in table `transactions`. By filtering on `saved_transaction_id IS NULL`, committed drafts are skipped. By issuing no SQL writes to `transactions`, historical ledger records cannot be modified.
   - *Empirical test*: Tested with active expenses, refund transactions, trash transactions, and committed drafts. Before and after triggering `_rematchPendingDrafts()`, full SQLite transaction row maps were compared. Historical transactions were 100% byte-for-byte identical, committed drafts remained untouched, while pending drafts had their `suggested_category_id` updated to newly matched rules.

3. **Refund Cascade Integrity & Non-Corruption**:
   - *Observation*: SQLite foreign key constraint `FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE`.
   - *Logic*: When an original expense transaction is deleted from `transactions`, SQLite automatically removes all matching rows from `refund_links`. Because `transactions` does not have a foreign key cascading from `refund_links`, the refund transaction row in `transactions` remains unaffected.
   - *Empirical test*: Tested linking multiple partial refunds to an expense. Soft deleting the expense preserved the `refund_links` records. Restoring the expense verified link stability. Permanently deleting the original expense deleted all rows in `refund_links` for that expense, while all linked refund transaction rows in `transactions` remained intact with active status, correct `amount_minor`, and uncorrupted metadata.

4. **Monthly Summary Calculation**:
   - *Observation*: `getMonthlySummary` uses `COALESCE(SUM(CASE ...), 0)` and strictly filters `type IN ('expense', 'refund')`.
   - *Logic*: Transfers are excluded from monthly income and expense metrics. Negative net expense (when refunds exceed expenses) and zero transactions in a month are handled without null errors.
   - *Empirical test*: Tested internal transfer of 40,000 cents from bank to WeChat; monthly summary showed 0 expense, 0 refund, 0 income, 0 count, while account balances reflected -40,000 on bank and +40,000 on WeChat. Tested an empty month returning all zeroes. Tested a refund surplus month (1,500 expense, 8,000 refund) producing net expense -6,500 cents (-65.00 CNY) and net balance 56,500 cents (565.00 CNY). Tested date boundary checks excluding adjacent months and soft-deleted records.

---

## 3. Caveats

- **No caveats**: All 4 verification areas were directly implemented, executed, and validated against in-memory SQLite instances and Riverpod presentation widgets.

---

## 4. Conclusion & Verdict

**Verdict**: **APPROVE**

All four adversarial challenges passed without failure:
1. Rules reordering is strictly monotonic ($P(i) - P(i+1) = 10$) and safely handles empty input without exceptions.
2. Rematching pending drafts is strictly non-retroactive; historical transactions in SQLite remain completely immutable.
3. Deleting original expense cleanly cascades rows in `refund_links` via SQLite foreign keys without deleting or corrupting the refund transactions.
4. Monthly accounting summary correctly excludes internal transfers, supports negative net expense (refund surplus), zero-transaction months, and negative account overdraft balances.

---

## 5. Verification Method

### Execution Commands
```bash
# 1. Run all project tests (353 passed)
flutter test

# 2. Run dedicated M2 adversarial challenge test suite (13 passed)
flutter test test/presentation/m2_adversarial_challenge_test.dart

# 3. Verify static analysis cleanliness (0 issues found)
flutter analyze
```

### Invalidation Conditions
- Any failure in `flutter test test/presentation/m2_adversarial_challenge_test.dart`.
- Any historical transaction row in `transactions` being modified after calling `_rematchPendingDrafts()`.
- Any refund transaction row in `transactions` being deleted or corrupted when an original expense is purged.
- Any internal transfer showing up in monthly expense or income calculations.
