# Handoff Report — Milestone M2-4: Classification Rules & Accounts/Projects Configuration Center

- **Author**: `worker_m2_4` (`teamwork_preview_worker`)
- **Recipient**: Parent Agent (`56fe935d-e88f-4b45-9b55-44ef0cd30d7b`)
- **Date**: 2026-10-23
- **Status**: Complete (Hard Handoff)

---

## 1. Observation

### 1.1 Direct Observations of Existing Codebase & Contracts
- `ORIGINAL_REQUEST.md` (lines 78-82) and `PROJECT.md` (lines 31-35, 47) defined Requirement R4:
  1. 6-Tier rules management: Display rule list with priority DESC ordering, active toggle switch (`Switch`), priority reordering, and draft re-matching.
  2. Accounts & project management: Total assets overview card, channel type icons (WeChat, Alipay, Bank Card, Cash), real-time calculated balances, initial balance setup, and orthogonal lifecycle project management (travel, renovation).
  3. Refund link modal: Search un-deleted expenses (`type == 'expense' AND deleted_at IS NULL`), link via `ledgerRepositoryProvider.linkRefund`, with explicit note on SQLite foreign key constraint `refund_links ON DELETE CASCADE`.
- `lib/data/repositories/rule_repository.dart` provided `getAllRules`, `setRuleEnabled`, `updateRulePriority`, `saveRule`, `deleteRule`, and `reorderRules` (which monotonically reassigns priorities descending in steps of 10).
- `lib/presentation/providers/rule_account_providers.dart` exposed `rulesListProvider`, `accountsListProvider`, `projectsListProvider`, `categoriesListProvider`, and `accountBalancesProvider`.
- SQLite schema in `lib/data/database/schema.dart` defined:
  - `classification_rules` table with columns `(id, priority, merchant_pattern, payment_channel, category_id, project_id, enabled, version, created_at, updated_at)`.
  - `refund_links` table with `FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE`.
  - `accounts` table with columns `(id, name, kind, card_last4, archived_at, created_at, updated_at)`.
  - `projects` table with columns `(id, name, archived_at, created_at, updated_at)`.
- `sqflite_common_ffi` isolate communication requirement: in `testWidgets`, awaiting database operations outside `tester.runAsync` blocks in fakeAsync zone causes isolate communication to block until test timeout.

### 1.2 Created Files (Exclusive Ownership)
1. `lib/presentation/screens/rules_accounts/rules_accounts_screen.dart` (New):
   - Material 3 container with `DefaultTabController(length: 3)` hosting "分类规则", "资产账户", "项目管理" tabs.
   - Includes integrated top-bar launcher for `RefundLinkDialog`.
2. `lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart` (New):
   - Consumes `rulesListProvider` and `categoriesListProvider`.
   - Displays rules sorted by `priority DESC`.
   - Rule card displays: `merchantPattern`, target category chip, priority score, version, priority up/down buttons, and active `Switch`.
   - Active switch toggling calls `ref.read(rulesListProvider.notifier).toggleRule(ruleId, enabled)`.
   - Drag-and-drop `ReorderableListView.builder` with `onReorderItem` and priority adjustment buttons calling `reorderRules(...)`.
   - "添加规则" dialog creates new rules with keyword, category, priority, and payment channel.
   - "重新匹配" (Re-match) button re-evaluates all pending drafts (`cj.state IN ('NEEDS_REVIEW', 'IMPORTED') AND d.saved_transaction_id IS NULL`) via `ClassificationRuleEngine.classify`, updating draft candidate fields without modifying committed transactions.
3. `lib/presentation/screens/rules_accounts/widgets/accounts_tab.dart` (New):
   - Consumes `accountsListProvider` and `accountBalancesProvider`.
   - Top card computes and displays Total Assets sum across all accounts (`totalAssetsMinor`) formatted with `CurrencyUtils.centsToYuanString`.
   - Account tiles display account name, channel type icon (`wechat`, `alipay`, `card`/`bank`, `cash`, `other`), channel label, card last 4 digits, and live calculated balance.
   - "添加账户" dialog inputs account name, channel kind, initial balance, and card last 4 digits; seeds initial balance transaction if initial balance > 0.
4. `lib/presentation/screens/rules_accounts/widgets/projects_tab.dart` (New):
   - Consumes `projectsListProvider`.
   - Displays lifecycle project cards with name, code/id, creation date, and status.
   - "添加项目" dialog inputs project name and code/id, refreshing the provider upon persistence.
5. `lib/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart` (New):
   - Searchable dialog to associate refund transactions with original expense records.
   - Searches transactions where `type == 'expense' AND deleted_at IS NULL`.
   - Links via `ledgerRepositoryProvider.linkRefund(refundTxId: ..., originalExpenseTxId: ...)`.
   - Displays foreign key cascade safety note: `refund_links ON DELETE CASCADE` ensures that purging the original expense unlinks the relationship without deleting the refund transaction itself.
6. `test/presentation/rules_accounts_screen_test.dart` (New):
   - 8 comprehensive widget and unit tests covering tab switching, rules list, priority reordering, active switch toggle, add rule dialog, non-retroactive draft rematching, Total Assets calculation, add account dialog, add project dialog, refund linking, and foreign key cascade deletion integrity.

---

## 2. Logic Chain

1. **Tabbed Architecture & State Bus Integration**:
   - `RulesAccountsScreen` sets up a responsive `DefaultTabController(length: 3)` coordinating `ClassificationRulesTab`, `AccountsTab`, and `ProjectsTab`.
   - The tabs consume Riverpod 2.x providers (`rulesListProvider`, `accountsListProvider`, `accountBalancesProvider`, `projectsListProvider`, `categoriesListProvider`). State modifications immediately trigger reactive UI updates.

2. **6-Tier Classification Rules Management & Monotonic Ordering**:
   - `RulesListNotifierExtension` equips `RulesListNotifier` with `toggleRule` and `reorderRules`.
   - `ClassificationRulesTab` sorts rules by `priority DESC`.
   - Toggling the active switch invokes `toggleRule(rule.id, enabled)`, which updates the SQLite `classification_rules.enabled` column and refreshes the list.
   - When rules are reordered via `ReorderableListView` or arrow buttons, `reorderRules` reassigns strictly descending priorities in steps of 10 (`(total - i) * 10`), guaranteeing monotonic matching precedence.

3. **Strictly Non-Retroactive Draft Rematching**:
   - When user clicks "重新匹配", the engine queries only pending drafts whose parent capture job is in `NEEDS_REVIEW` or `IMPORTED` state and where `saved_transaction_id IS NULL`.
   - Each pending draft is evaluated against active rules via `ClassificationRuleEngine.classify(...)`.
   - The draft's `candidate_fields` JSON is updated with `suggested_category_id`, `suggested_project_id`, and `confidence_score`.
   - Historical records in `transactions` are strictly never queried or altered, satisfying the non-retroactivity requirement.

4. **Asset Accounts & Real-Time Balance Aggregation**:
   - `AccountsTab` aggregates the Total Assets sum by reducing all balances from `accountBalancesProvider`.
   - Channel type icons map semantic channels to distinct icons and theme colors (`Icons.chat_bubble_outline` for WeChat, `Icons.account_balance_wallet_outlined` for Alipay, `Icons.credit_card_outlined` for bank cards, `Icons.payments_outlined` for cash).
   - "添加账户" dialog inserts the account into `accounts` and, if initial balance > 0, inserts an initial income transaction with `merchant_raw = '初始余额'` and `category_id = 'cat_income'`. This ensures `accountBalancesProvider` dynamically reflects the initial funds.

5. **Refund Association & Foreign Key Cascade Safety**:
   - `RefundLinkDialog` restricts candidates to `type = 'expense'` and `deleted_at IS NULL`.
   - Calling `ledgerRepositoryProvider.linkRefund` inserts into SQLite `refund_links`.
   - The UI includes an explicit safety banner informing the user of `refund_links ON DELETE CASCADE`.
   - Verified via unit test: permanently deleting the original expense transaction purges the entry in `refund_links`, unlinking the relationship while leaving the refund transaction in `transactions` completely intact.

6. **Strict Typing & Analyzer Cleanliness**:
   - All models, collections, callbacks, and parameters declare explicit types conforming to `strict-casts`, `strict-inference`, and `strict-raw-types`.
   - Context capturing before async gaps (`final navigator = Navigator.of(...)`, `final messenger = ScaffoldMessenger.of(...)`) ensures zero `use_build_context_synchronously` warnings.
   - Running `flutter analyze` on all M2-4 files produces `No issues found!`.

---

## 3. Caveats

- **Parallel Worker Test Files**: During analysis, unused imports in test files belonging to parallel workers (`test/presentation/transactions_screen_test.dart` and `test/presentation/draft_confirmation_screen_test.dart`) were observed. Our owned files (`lib/presentation/screens/rules_accounts/` and `test/presentation/rules_accounts_screen_test.dart`) are 100% clean with 0 issues.
- **SQLite FFI Isolate Concurrency**: In widget tests running against in-memory SQLite (`sqflite_common_ffi`), all database inserts, queries, and async provider pumps must be executed within `tester.runAsync(() async { ... })` to avoid blocking Flutter's `fakeAsync` zone.

---

## 4. Conclusion

Milestone M2-4 (Classification Rules & Accounts/Projects Configuration Center) has been implemented with genuine, complete, and fully tested logic:
- All 5 exclusive write ownership files created and verified.
- Static analysis check (`flutter analyze`) reports 0 errors, 0 warnings, 0 lints on all M2-4 files.
- Automated widget and unit test suite (`test/presentation/rules_accounts_screen_test.dart`) passes 8/8 tests in 8 seconds.
- Baseline presentation tests (`test/presentation/repositories_and_providers_test.dart`) continue to pass 10/10 tests without regression.

---

## 5. Verification Method

To independently verify the implementation:

```bash
# 1. Run static analysis on M2-4 files (expected: No issues found!)
flutter analyze lib/presentation/screens/rules_accounts/ test/presentation/rules_accounts_screen_test.dart

# 2. Run M2-4 widget and integration tests (expected: 8/8 passed, 0 failures)
flutter test test/presentation/rules_accounts_screen_test.dart

# 3. Run existing presentation repositories and providers tests (expected: 10/10 passed)
flutter test test/presentation/repositories_and_providers_test.dart
```
