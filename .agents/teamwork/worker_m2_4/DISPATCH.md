## 2026-10-23T01:53:24Z
Your working directory is c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_4.
You are worker_m2_4, a teamwork_preview_worker.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Read the authoritative user request at:
c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md (specifically see section ## 2026-10-23T01:15:17Z for Milestone M2, Requirement R4).

Also read the architecture design and repository/provider contracts in:
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_4\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_1\handoff.md
- lib/data/repositories/rule_repository.dart
- lib/presentation/providers/rule_account_providers.dart
- lib/features/classification/rule_engine.dart

Task: Implement Milestone M2-4 (Classification Rules & Accounts/Projects Configuration Center).
Exclusive write ownership for this task:
- lib/presentation/screens/rules_accounts/rules_accounts_screen.dart
- lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart
- lib/presentation/screens/rules_accounts/widgets/accounts_tab.dart
- lib/presentation/screens/rules_accounts/widgets/projects_tab.dart
- lib/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart

Implementation Requirements:
1. `RulesAccountsScreen` (`lib/presentation/screens/rules_accounts/rules_accounts_screen.dart`):
   - Tabbed container with 3 tabs: "分类规则", "资产账户", "项目管理".
2. `ClassificationRulesTab` (`lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart`):
   - Consumes `rulesListProvider`.
   - Lists rules sorted by priority DESC.
   - Each rule card shows: Rule pattern/keyword, target category chip, priority score, active switch (`Switch`).
   - Toggling active switch calls `ref.read(rulesListProvider.notifier).toggleRule(ruleId, enabled)`.
   - Drag-and-drop (`ReorderableListView`) or priority adjustment buttons calling `reorderRules(...)` to adjust matching order monotonically.
   - "添加规则" button: Dialog to create keyword/pattern rule with target category and priority.
   - "重新匹配" (Re-match) button: re-evaluates all pending drafts against current rule set (strictly non-retroactive: never alters committed transactions).
3. `AccountsTab` (`lib/presentation/screens/rules_accounts/widgets/accounts_tab.dart`):
   - Consumes `accountsListProvider` and `accountBalancesProvider`.
   - Card showing Total Assets sum at top.
   - Account tiles: Account name, channel type icon (WeChat, Alipay, Bank Card, Cash), current calculated balance.
   - "添加账户" button: Dialog to input account name, channel type, initial balance.
4. `ProjectsTab` (`lib/presentation/screens/rules_accounts/widgets/projects_tab.dart`):
   - Consumes `projectsListProvider`.
   - Lists lifecycle projects (e.g. Travel, Renovation).
   - "添加项目" button: Dialog to create new project name/code.
5. `RefundLinkDialog` (`lib/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart`):
   - Dialog allowing user to select a refund transaction and link it to an original expense transaction.
   - Searches transactions of type `expense` with `deleted_at IS NULL`.
   - Links via `ledgerRepositoryProvider.linkRefund(refundTxId: ..., originalExpenseTxId: ...)`.
   - Shows foreign key cascade safety note: `refund_links ON DELETE CASCADE` ensures that purging the original expense unlinks the relationship without deleting the refund transaction itself.
6. Strict Typing:
   - Adhere to `strict-casts`, `strict-inference`, and `strict-raw-types`.

Verification:
- Run `flutter analyze` and ensure 0 errors, 0 warnings, 0 lints.
- Run `flutter test` and ensure all existing tests pass with 0 failures.
- Document implementation details and test commands in `c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_4\handoff.md`.
- Send message to parent when done.

## 2026-10-23T02:30:55Z
**Context**: Milestone M2-4 Implementation Status Check
**Content**: Please report your current execution status. Are tests or analysis running?
**Action**: Send an update on your progress and estimated time to handoff.

## 2026-10-23T02:51:20Z
**Context**: Fix for test timeout in rules_accounts_screen_test.dart
**Content**: In `test/presentation/rules_accounts_screen_test.dart`, all `await db.insert(...)` and `await db.query(...)` calls MUST be placed INSIDE `await tester.runAsync(() async { ... })`!
Because `sqflite_common_ffi` communicates with a background isolate, awaiting any `db` operation outside `tester.runAsync` inside `testWidgets` fakeAsync zone hangs for 10 minutes until test timeout.
If task-155 is currently hung, kill it via `manage_task(Action="kill", TaskId="f11d93ff-db50-4f0a-a358-b16cc94ff1e7/task-155")`, move all `db.insert`/`db.query` calls into the `tester.runAsync` block for each test, and re-run `flutter test test/presentation/rules_accounts_screen_test.dart`.
**Action**: Kill hung task-155, wrap all db operations in `tester.runAsync`, re-test, and submit handoff.md.
