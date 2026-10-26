# Handoff Report — Milestone M2-1: Core Repositories, Database Seeder & Riverpod State Bus

- **Author**: `worker_m2_1` (`teamwork_preview_worker`)
- **Recipient**: Parent Agent (`56fe935d-e88f-4b45-9b55-44ef0cd30d7b`)
- **Date**: 2026-10-23
- **Status**: Complete (Hard Handoff)

---

## 1. Observation

### 1.1 Direct Observations of Existing Codebase
- `pubspec.yaml` contained `flutter_riverpod: ^2.5.1`, `sqflite: ^2.3.3+1`, `sqflite_common_ffi: ^2.3.3`, `intl: ^0.19.0`, and `analysis_options.yaml` enforcing `strict-casts: true`, `strict-inference: true`, and `strict-raw-types: true`.
- SQLite schema in `lib/data/database/schema.dart` defined 12 tables and 11 performance B-tree indices. `transactions.category_id` has `FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT`, requiring default category records before any transaction can be committed.
- `lib/data/database/soft_delete_manager.dart` and `TransactionManager` provided low-level database operations, but no high-level repository abstraction, data seeding, or reactive state management existed for UI consumption.
- Baseline test suite consisted of 297 tests in `test/`, all passing with exit code 0.

### 1.2 Created & Modified File Set
All modifications strictly respected exclusive write ownership:
1. `lib/data/seeder/database_seeder.dart` (New): Idempotent seeder for categories, accounts, and projects.
2. `lib/data/repositories/ledger_repository.dart` (New): Typed ledger query, filtering, date grouping, monthly summary, soft delete, and account balance operations.
3. `lib/data/repositories/draft_repository.dart` (New): OCR draft queue queries, detail deserialization, atomic commit, and draft discarding.
4. `lib/data/repositories/rule_repository.dart` (New): 6-tier classification rules CRUD, toggle, priority updates, and reordering.
5. `lib/presentation/theme/app_theme.dart` (New): Material 3 light/dark theme data with seed color `0xFF6750A4`.
6. `lib/presentation/providers/core_providers.dart` (New): Global dependency injection for Database, TransactionManager, DeduplicationEngine, RuleEngine, OcrPipeline, and repositories.
7. `lib/presentation/providers/transaction_providers.dart` (New): Reactive notifiers for `transactionFilterProvider`, `transactionListProvider`, `selectedMonthProvider`, `monthlySummaryProvider`, and `trashBinListProvider`.
8. `lib/presentation/providers/draft_providers.dart` (New): Notifiers for `draftsQueueProvider`, `pendingDraftsCountProvider`, and `draftDetailProvider`.
9. `lib/presentation/providers/rule_account_providers.dart` (New): Notifiers for `rulesListProvider`, `accountsListProvider`, `projectsListProvider`, `categoriesListProvider`, and `accountBalancesProvider`.
10. `lib/presentation/navigation/app_scaffold.dart` (New): Material 3 navigation scaffold with responsive NavigationBar / NavigationRail.
11. `lib/main.dart` (Modified): Initialized SQLite FFI, ran self-healing recovery, executed database seeder, and injected SQLite database into `ProviderScope`.
12. `test/presentation/repositories_and_providers_test.dart` (New): 10 comprehensive unit and widget tests covering all new features.

---

## 2. Logic Chain

1. **Category & Account Foreign Key Integrity**:
   - `transactions` enforces `FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT`. Committing any draft or transaction without pre-existing categories throws a SQLite constraint violation.
   - `DatabaseSeeder.seedIfNeeded` inserts default categories (`cat_food`, `cat_transport`, `cat_shopping`, `cat_entertainment`, `cat_bills`, `cat_medical`, `cat_other`, `cat_income`) and accounts (`acc_wechat`, `acc_alipay`, `acc_bank`, `acc_cash`) only after checking existing entity IDs, making the seeder safe for startup and repeated runs.
   - Initial balances are supported by inserting initial income transactions with `merchant_raw = '初始余额'`.

2. **Repository Abstraction Layer**:
   - `LedgerRepository` translates `TransactionFilter` into dynamic parameterized SQL queries (`WHERE occurred_on BETWEEN ...`, `merchant_raw LIKE ...`, `deleted_at IS NULL`), preventing SQL injection.
   - `getGroupedTransactions` groups query results by calendar day (`occurred_on`) and calculates daily net subtotals ($\sum \text{expense} - \sum \text{refund}$).
   - `getMonthlySummary` computes total expense, total refund, net expense, and total income within the specified calendar month.
   - `linkRefund` persists refund relationships in `refund_links`, which cascades when the original expense is permanently purged while preserving the refund transaction.
   - `getAccountBalances` calculates real-time account balances considering expenses, incomes, refunds, and internal transfers.

3. **Draft Lifecycle & Atomic Commit**:
   - `DraftRepository.getPendingDrafts` queries drafts whose capture jobs are in `NEEDS_REVIEW` or `IMPORTED` state.
   - `commitDraft` delegates to `TransactionManager.commitDraft`, converting `HardDuplicateException` into `CommitDraftResult.hardDuplicate` and `TrashBinCollisionException` into `CommitDraftResult.trashCollision` for clean UI error handling.
   - `discardDraft` transitions the underlying capture job state to `DISCARDED`.

4. **Rule Management**:
   - `RuleRepository` provides priority-sorted queries (`ORDER BY priority DESC, created_at DESC`), enables/disables rules, updates rule priorities, and supports drag-and-drop batch reordering by reassigning descending priorities in steps of 10.

5. **Riverpod 2.x Strict Typing**:
   - All providers declare explicit type parameters (`Provider<T>`, `NotifierProvider<N, S>`, `AsyncNotifierProvider<N, S>`, `FutureProvider<T>`), satisfying `analysis_options.yaml`'s `strict-casts`, `strict-inference`, and `strict-raw-types`.
   - `databaseProvider` is defined as `Provider<Database>` with an `UnimplementedError` fallback, overridden at the application root in `main.dart` and during tests with real in-memory SQLite databases.
   - Mutating actions on notifiers (e.g., `softDelete`, `restore`, `commit`, `toggleEnabled`) automatically trigger reactive invalidation and refreshes across dependent UI providers.

6. **Navigation Scaffold & Smoke Test Compatibility**:
   - `AppScaffold` provides responsive switching between `NavigationBar` (compact screens) and `NavigationRail` (wide tablet/desktop viewports).
   - `AppScaffold` retains `Text('SingWallet')` and `Text('SingWallet Core Initialized')`, ensuring existing `test/widget_test.dart` passes out-of-the-box.

---

## 3. Caveats

- **Full Screen Implementations**: `AppScaffold` currently contains placeholder cards for Tab 0 (Transactions), Tab 1 (Drafts), and Tab 2 (Rules & Accounts). These tabs are ready to receive the full screens to be built by downstream workers (`worker_m2_2`, `worker_m2_3`, `worker_m2_4`).
- **FakeAsync Isolation in Widget Tests**: When writing widget tests that execute against `sqflite_common_ffi`, `fake_async` does not advance real isolate time unless `tester.runAsync()` is used or providers querying background isolates are mocked/overridden.

---

## 4. Conclusion

Milestone M2-1 (Core Repositories, Database Seeder & Riverpod State Bus) has been completely implemented and verified:
- Genuine logic implemented across all 11 exclusive ownership files.
- Static analysis check (`flutter analyze`) reports 0 issues (0 errors, 0 warnings, 0 lints).
- Full automated test suite (`flutter test`) passes 307/307 tests (297 existing backend tests + 10 new comprehensive unit and widget tests).
- Downstream workers (`worker_m2_2`, `worker_m2_3`, `worker_m2_4`) now have a fully functional repository layer and Riverpod state bus to bind their UI screens.

---

## 5. Verification Method

To independently verify the implementation:

```bash
# 1. Run static analysis (expected: No issues found!)
flutter analyze

# 2. Run new M2-1 repository, seeder, and state bus tests
flutter test test/presentation/repositories_and_providers_test.dart

# 3. Run full automated test suite (expected: 307/307 passed)
flutter test
```
