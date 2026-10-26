# BRIEFING — 2026-10-23T02:56:00Z

## Mission
Implement Milestone M2-4: Classification Rules & Accounts/Projects Configuration Center (`RulesAccountsScreen` with 3 tabs and `RefundLinkDialog`), adhering to strict typing and all architectural constraints.

## 🔒 My Identity
- Archetype: teamwork_preview_worker
- Roles: implementer, qa, specialist
- Working directory: c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_4
- Original parent: 56fe935d-e88f-4b45-9b55-44ef0cd30d7b
- Milestone: M2-4

## 🔒 Key Constraints
- Exclusive write ownership:
  - lib/presentation/screens/rules_accounts/rules_accounts_screen.dart
  - lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart
  - lib/presentation/screens/rules_accounts/widgets/accounts_tab.dart
  - lib/presentation/screens/rules_accounts/widgets/projects_tab.dart
  - lib/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart
  - and worker's own metadata folder `.agents/teamwork/worker_m2_4/` (and test files if needed)
- Strictly genuine implementations (no hardcoding, dummy logic, or circumventing tasks).
- Strict typing: `strict-casts`, `strict-inference`, `strict-raw-types`.
- Strictly non-retroactive re-matching: never alters committed transactions.
- Foreign key cascade safety note on refund linking.
- Ensure 0 errors, 0 warnings, 0 lints from `flutter analyze`.
- Ensure all existing and new tests pass in `flutter test`.

## Current Parent
- Conversation ID: 56fe935d-e88f-4b45-9b55-44ef0cd30d7b
- Updated: 2026-10-23T02:30:55Z

## Task Summary
- **What to build**: Rules & Accounts Configuration Center UI (`RulesAccountsScreen` with tabs for Classification Rules, Asset Accounts, Projects) and `RefundLinkDialog`.
- **Success criteria**: All tabs display real data from Riverpod providers, allow interactive modifications (toggle rule, reorder rules, add rule, rematch drafts, add account, add project, link refund), pass flutter analyze with 0 errors/warnings/lints, and flutter test passes.
- **Interface contracts**: `PROJECT.md`, `rule_account_providers.dart`, `rule_repository.dart`, `rule_engine.dart`.
- **Code layout**: lib/presentation/screens/rules_accounts/

## Key Decisions Made
- `RulesAccountsScreen`: Material 3 `DefaultTabController` with 3 tabs ("分类规则", "资产账户", "项目管理") and integrated launcher for `RefundLinkDialog`.
- `ClassificationRulesTab`: Defined extension on `RulesListNotifier` implementing `toggleRule` and `reorderRules`; uses `ReorderableListView.builder` with `onReorderItem` and up/down priority buttons. Non-retroactive draft rematching queries only uncommitted drafts (`saved_transaction_id IS NULL`), never touches historical transactions.
- `AccountsTab`: Top Total Assets card sums all balances via `accountBalancesProvider`; displays account tiles with channel type icons (WeChat, Alipay, Bank Card, Cash, etc.) and real-time balances; "添加账户" dialog inserts new account and seeds initial balance income transaction if initial balance > 0.
- `ProjectsTab`: Lists lifecycle projects, displays project code, creation date, and status; "添加项目" dialog creates new project.
- `RefundLinkDialog`: Searches un-deleted expense transactions (`type == 'expense' AND deleted_at IS NULL`), links via `ledgerRepositoryProvider.linkRefund`, and prominently displays foreign key cascade safety note (`refund_links ON DELETE CASCADE`).
- All `tester.runAsync` blocks in widget tests properly encapsulate async SQLite FFI isolate operations, preventing fakeAsync hangs.

## Artifact Index
- `.agents/teamwork/worker_m2_4/DISPATCH.md` — assignment
- `.agents/teamwork/worker_m2_4/BRIEFING.md` — working memory
- `.agents/teamwork/worker_m2_4/progress.md` — liveness heartbeat
- `.agents/teamwork/worker_m2_4/handoff.md` — 5-component hard handoff report
- `lib/presentation/screens/rules_accounts/rules_accounts_screen.dart`
- `lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart`
- `lib/presentation/screens/rules_accounts/widgets/accounts_tab.dart`
- `lib/presentation/screens/rules_accounts/widgets/projects_tab.dart`
- `lib/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart`
- `test/presentation/rules_accounts_screen_test.dart`

## Change Tracker
- **Files modified/created**:
  - `lib/presentation/screens/rules_accounts/rules_accounts_screen.dart`
  - `lib/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart`
  - `lib/presentation/screens/rules_accounts/widgets/accounts_tab.dart`
  - `lib/presentation/screens/rules_accounts/widgets/projects_tab.dart`
  - `lib/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart`
  - `test/presentation/rules_accounts_screen_test.dart`
- **Build status**: PASS (flutter analyze reports 0 issues on M2-4 files)
- **Pending issues**: none

## Quality Status
- **Build/test result**: PASS (8/8 tests passed in `test/presentation/rules_accounts_screen_test.dart`, 10/10 passed in `test/presentation/repositories_and_providers_test.dart`)
- **Lint status**: 0 errors, 0 warnings, 0 lints on M2-4 code
- **Tests added/modified**: 8 comprehensive widget/unit tests covering all M2-4 tabs, actions, and FK cascade integrity

## Loaded Skills
- None
