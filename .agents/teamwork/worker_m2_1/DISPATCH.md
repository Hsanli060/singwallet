## 2026-10-23T01:28:21Z
Your working directory is c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_1.
You are worker_m2_1, a teamwork_preview_worker.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Read the authoritative user request at:
c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md (specifically see section ## 2026-10-23T01:15:17Z for Milestone M2).

Also read the architecture design and findings in:
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_4\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m2_1\report.md
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m2_2\report.md
- c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_m2_1\report.md

Task: Implement Milestone M2-1 (Core Repositories, Database Seeder & Riverpod State Bus).
Exclusive write ownership for this task:
- lib/data/seeder/database_seeder.dart
- lib/data/repositories/ledger_repository.dart
- lib/data/repositories/draft_repository.dart
- lib/data/repositories/rule_repository.dart
- lib/presentation/theme/app_theme.dart
- lib/presentation/providers/core_providers.dart
- lib/presentation/providers/transaction_providers.dart
- lib/presentation/providers/draft_providers.dart
- lib/presentation/providers/rule_account_providers.dart
- lib/presentation/navigation/app_scaffold.dart
- lib/main.dart

Detailed Implementation Requirements:
1. `DatabaseSeeder` (`lib/data/seeder/database_seeder.dart`):
   - Seeds default categories (`cat_food`, `cat_transport`, `cat_shopping`, `cat_entertainment`, `cat_bills`, `cat_medical`, `cat_other`) with Chinese names and icons.
   - Seeds default accounts (`acc_wechat`, `acc_alipay`, `acc_bank`, `acc_cash`) with initial balances and types.
   - Idempotent: checks if categories/accounts already exist before inserting.
2. `Repositories` (`lib/data/repositories/`):
   - `LedgerRepository`: query transactions with filtering (date range, accounts, categories, projects, keywords, types), group transactions by `occurred_on` date with subtotals, calculate monthly summary (total expense, total refund, net expense, income), soft delete, restore, permanently delete, get trash bin transactions, query accounts, categories, projects, link refunds.
   - `DraftRepository`: query pending drafts (in `NEEDS_REVIEW` or `IMPORTED`), fetch draft detail, commit draft via `TransactionManager.commitDraft`, discard draft.
   - `RuleRepository`: query rules ordered by priority, toggle enabled/disabled, update rule priority, save rule, delete rule.
3. `Theme` (`lib/presentation/theme/app_theme.dart`):
   - Material 3 theme data with primary seed color `0xFF6750A4`.
4. `Riverpod State Bus` (`lib/presentation/providers/`):
   - Strict typing compliant with `analysis_options.yaml` (`strict-casts`, `strict-inference`, `strict-raw-types`).
   - `core_providers.dart`: `databaseProvider`, `transactionManagerProvider`, `dedupEngineProvider`, `classificationRuleEngineProvider`, `ocrPipelineProvider`, and repository providers.
   - `transaction_providers.dart`: `transactionFilterProvider`, `transactionListProvider` (AsyncNotifier), `monthlySummaryProvider`.
   - `draft_providers.dart`: `draftsQueueProvider`.
   - `rule_account_providers.dart`: `rulesListProvider`, `accountsListProvider`, `projectsListProvider`.
5. `Navigation & Entry Point` (`lib/presentation/navigation/app_scaffold.dart` & `lib/main.dart`):
   - `AppScaffold`: Material 3 navigation scaffold with NavigationBar / NavigationRail for switching between Transactions, Drafts, Rules/Accounts.
   - `main.dart`: initialize SQLite, run `DatabaseSeeder.seedIfNeeded()`, wrap app in `ProviderScope` with `databaseProvider.overrideWithValue(db)`.

Verification:
- Run `flutter analyze` and ensure 0 errors, 0 warnings, 0 lints.
- Run `flutter test` and ensure all 297 existing tests pass with 0 failures.
- Document all implementation details, commands run, and results in `c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_1\handoff.md`.
- Send message to parent when done.
