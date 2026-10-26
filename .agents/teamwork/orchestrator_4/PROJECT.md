# Project: SingWallet Milestone M2 (Core Business UI & Riverpod State Bus)

## Architecture
- **Architecture Pattern**: Layered Presentation Architecture with Riverpod 2.x State Bus.
- **Data Flow**:
  1. `SQLite Database (AppDatabase)` -> `TransactionManager`, `DeduplicationEngine`, `ClassificationRuleEngine`, `OcrParsingPipeline`.
  2. `Repositories (LedgerRepository, DraftRepository, RuleRepository)` provide typed queries, soft delete, and data seeding.
  3. `Riverpod Providers & Notifiers` expose reactive immutable UI states (`TransactionFilterState`, `TransactionListState`, `DraftsQueueState`, etc.) with strict typing (`strict-casts`, `strict-inference`, `strict-raw-types`).
  4. `Presentation Screens & Widgets` consume providers via `ConsumerWidget` and `ConsumerStatefulWidget`, updating UI reactively on ledger/draft state changes.
- **Visual Design**: Flutter Material 3 (`ThemeData(useMaterial3: true)`), seed color `0xFF6750A4`, responsive layout, dark/light theme ready.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Database Seeder | Default categories (food, transport, shopping, etc.) and accounts (wechat, alipay, bank, cash) satisfying FOREIGN KEY RESTRICT | M2-1 | explorer_m2_1 |
| 2 | Ledger & Draft Repositories | Typed query helpers for transactions, monthly summaries, drafts, rules, accounts, and projects | M2-1 | explorer_m2_1 |
| 3 | Core Riverpod DI Bus | Global typed providers for AppDatabase, TransactionManager, DeduplicationEngine, RuleEngine, OcrPipeline, Repositories | M2-1 | explorer_m2_2 |
| 4 | Reactive Presentation Notifiers | `TransactionListNotifier`, `TransactionFilterNotifier`, `DraftQueueNotifier`, `RuleListNotifier`, `AccountListNotifier` | M2-1 | spec_miner_m2_1 |
| 5 | App Navigation Scaffold | BottomNavigationBar / NavigationRail switching between Transactions, Drafts, and Rules/Config | M2-1 | spec_miner_m2_1 |
| 6 | Monthly Summary Card | Real-time monthly dashboard: total expense, total refund, net expense, and income formatted with `CurrencyUtils` | M2-2 | spec_miner_m2_1 |
| 7 | Daily Aggregated Transaction List | Grouped transactions by `occurred_on` with daily subtotal, category icon, merchant title, account capsule, project tag | M2-2 | spec_miner_m2_1 |
| 8 | Multi-Dimensional Filter Sheet | BottomSheet / dialog filtering by accounts, projects, categories, date ranges, transaction types, and keywords | M2-2 | spec_miner_m2_1 |
| 9 | Soft Delete & Undo SnackBar | Swipe / button soft delete setting `deleted_at`, immediate removal from list, and SnackBar with "Undo" restoration | M2-2 | spec_miner_m2_1 |
| 10 | 30-Day Recycling Bin Modal | View soft-deleted transactions, restore to active ledger, or permanently purge | M2-2 | spec_miner_m2_1 |
| 11 | Drafts Queue Screen | List of pending OCR captured drafts in `NEEDS_REVIEW` state with preview thumbnails and timestamps | M2-3 | spec_miner_m2_1 |
| 12 | Normalized BoundingBox Overlay | AspectRatio-preserving coordinate mapping for `[0.0, 1.0]` boxes onto image viewport without distortion or clipping | M2-3 | spec_miner_m2_1 |
| 13 | Interactive Touch-to-Fill | Tap OCR bounding box rectangle to autofill recognized text into merchant name or amount form fields | M2-3 | spec_miner_m2_1 |
| 14 | Smart Transaction Confirmation Form | 36pt prominent amount input, payment channel selector, status picker, merchant input, suggested category card with confidence % | M2-3 | spec_miner_m2_1 |
| 15 | Deduplication Interception Alerts | Tier 3 hard blocking dialog for active duplicates, Tier 3 amber restore dialog for trash duplicates, Tier 4 24h duplicate confirmation modal | M2-3 | spec_miner_m2_1 |
| 16 | Atomic Draft Commitment | One-click commit via `TransactionManager.commitDraft`, transitioning draft to `COMMITTED` and notifying ledger bus | M2-3 | spec_miner_m2_1 |
| 17 | 6-Tier Rules Management | List classification rules with priority ordering (`RuleMatcher.compareRules`), enable/disable toggle, add/edit rules | M2-4 | spec_miner_m2_1 |
| 18 | Non-Retroactive Re-Match Trigger | Re-evaluate pending drafts against current rule set without touching historical committed transactions | M2-4 | spec_miner_m2_1 |
| 19 | Accounts & Balances Center | Account list, balance overview, add/edit account names and initial balances | M2-4 | spec_miner_m2_1 |
| 20 | Projects Configuration | Project tags/labels list for orthogonal lifecycle event tracking (renovation, travel) | M2-4 | spec_miner_m2_1 |
| 21 | Refund Link Association Modal | Search and link refund transactions to original expense; verifies `refund_links ON DELETE CASCADE` integrity | M2-4 | spec_miner_m2_1 |
| 22 | Transactions Screen Widget Tests | Comprehensive tests for summary card, daily groups, filter sheet, soft delete & undo | M2-5 | explorer_m2_2 |
| 23 | Draft Confirmation Widget Tests | Tests for coordinate mapping, tap-to-autofill, Tier 3 blocking alert, Tier 4 confirmation modal, commit flow | M2-5 | explorer_m2_2 |
| 24 | Rules & Accounts Widget Tests | Tests for rule toggle, priority reordering, account creation, refund link picker modal | M2-5 | explorer_m2_2 |
| 25 | Full Regression & Integration Tests | 100% test pass on existing 297 tests + all new widget tests; zero issues on `flutter analyze` | M2-5 | explorer_m2_2 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M2-1 | Core Repositories, Seeder & Riverpod State Bus | Features #1 - #5: DatabaseSeeder, Repositories, DI providers, ViewModels/Notifiers, App Scaffold | M1 complete | DONE |
| M2-2 | Transactions Screen & Real-time Dashboard | Features #6 - #10: Summary card, grouped transaction list, filter panel, soft delete / undo, trash bin | M2-1 | DONE |
| M2-3 | Draft Confirmation Screen & OCR BoundingBox Overlay | Features #11 - #16: Draft queue, OCR bounding box mapping, touch-to-fill, smart form, 4-tier dedup alerts, commit | M2-1 | DONE |
| M2-4 | Classification Rules & Accounts/Projects Center | Features #17 - #21: 6-tier rule list, priority ordering, enable/disable, accounts & projects, refund link modal | M2-1 | DONE |
| M2-5 | Comprehensive Widget & E2E Test Suite | Features #22 - #25: Widget tests for all screens, deduplication intercept tests, refund cascade tests, zero analyzer issues | M2-1, M2-2, M2-3, M2-4 | DONE |

## Interface Contracts

### 1. Database & Repositories Contract
```dart
abstract class ILedgerRepository {
  Future<void> seedInitialDataIfEmpty();
  Future<MonthlyAccountingSummary> getMonthlySummary(String yearMonth);
  Future<List<TransactionGroup>> getGroupedTransactions(TransactionFilter filter);
  Future<void> softDeleteTransaction(String id);
  Future<void> restoreTransaction(String id);
  Future<void> permanentlyDeleteTransaction(String id);
  Future<List<TransactionEntry>> getTrashBinTransactions();
  Future<List<AccountEntry>> getAccounts();
  Future<List<CategoryEntry>> getCategories();
  Future<List<ProjectEntry>> getProjects();
  Future<void> linkRefund({required String refundTxId, required String originalExpenseTxId});
}

abstract class IDraftRepository {
  Future<List<DraftEntry>> getPendingDrafts();
  Future<DraftDetail?> getDraftDetail(String draftId);
  Future<CommitDraftResult> commitDraft(CommitDraftRequest request);
  Future<void> discardDraft(String draftId);
}

abstract class IRuleRepository {
  Future<List<ClassificationRule>> getAllRules();
  Future<void> setRuleEnabled(String ruleId, bool enabled);
  Future<void> updateRulePriority(String ruleId, int newPriority);
  Future<void> saveRule(ClassificationRule rule);
  Future<void> deleteRule(String ruleId);
}
```

### 2. Riverpod State & Providers Contract
```dart
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError());
final ledgerRepositoryProvider = Provider<ILedgerRepository>((ref) => ...);
final draftRepositoryProvider = Provider<IDraftRepository>((ref) => ...);
final ruleRepositoryProvider = Provider<IRuleRepository>((ref) => ...);
final transactionFilterProvider = NotifierProvider<TransactionFilterNotifier, TransactionFilter>(...);
final transactionListProvider = AsyncNotifierProvider<TransactionListNotifier, List<TransactionGroup>>(...);
final monthlySummaryProvider = FutureProvider<MonthlyAccountingSummary>(...);
final draftsQueueProvider = AsyncNotifierProvider<DraftsQueueNotifier, List<DraftEntry>>(...);
final rulesListProvider = AsyncNotifierProvider<RulesListNotifier, List<ClassificationRule>>(...);
final accountsListProvider = AsyncNotifierProvider<AccountsListNotifier, List<AccountEntry>>(...);
```

### 3. OCR Coordinate Mapping Contract
```dart
class BoundingBoxMapper {
  static Rect mapNormalizedToViewport({
    required OcrBoundingBox box,
    required Size imageSize,
    required Size viewportSize,
  }) {
    final double scale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    final double renderedWidth = imageSize.width * scale;
    final double renderedHeight = imageSize.height * scale;
    final double offsetX = (viewportSize.width - renderedWidth) / 2.0;
    final double offsetY = (viewportSize.height - renderedHeight) / 2.0;

    return Rect.fromLTWH(
      offsetX + (box.left * renderedWidth),
      offsetY + (box.top * renderedHeight),
      box.width * renderedWidth,
      box.height * renderedHeight,
    );
  }
}
```

## Code Layout
```text
lib/
├── main.dart                                       # Entry point with ProviderScope & Seeder initialization
├── core/
│   ├── constants/
│   ├── native/
│   └── utils/
├── data/
│   ├── database/                                   # Existing SQLite schema & TransactionManager
│   ├── models/                                     # Existing & new models (TransactionEntry, etc.)
│   ├── repositories/                               # New Repository Layer
│   │   ├── ledger_repository.dart
│   │   ├── draft_repository.dart
│   │   └── rule_repository.dart
│   └── seeder/
│       └── database_seeder.dart                    # Default categories & accounts seeder
├── features/
│   ├── classification/
│   ├── deduplication/
│   └── recognition/
└── presentation/
    ├── navigation/
    │   └── app_scaffold.dart                       # Bottom navigation bar / tab switcher
    ├── providers/
    │   ├── core_providers.dart                     # Database, engines, repositories DI
    │   ├── transaction_providers.dart              # Filter, transaction list, summary providers
    │   ├── draft_providers.dart                    # Drafts queue and draft confirmation providers
    │   └── rule_account_providers.dart             # Rules, accounts, projects providers
    ├── screens/
    │   ├── transactions/
    │   │   ├── transactions_screen.dart            # Main ledger screen
    │   │   └── widgets/
    │   │       ├── monthly_summary_card.dart
    │   │       ├── transaction_group_list.dart
    │   │       ├── transaction_tile.dart
    │   │       ├── transaction_filter_sheet.dart
    │   │       └── trash_bin_dialog.dart
    │   ├── drafts/
    │   │   ├── drafts_queue_screen.dart            # Drafts list
    │   │   ├── draft_confirmation_screen.dart      # OCR review & commit
    │   │   └── widgets/
    │   │       ├── ocr_bounding_box_overlay.dart   # Interactive normalized bounding box overlay
    │   │       ├── smart_transaction_form.dart     # Amount, merchant, channel, status inputs
    │   │       ├── category_suggestion_card.dart   # Suggestion with confidence %
    │   │       └── deduplication_dialogs.dart      # Tier 3 blocking & Tier 4 confirmation modals
    │   └── rules_accounts/
    │       ├── rules_accounts_screen.dart          # Tabbed center
    │       └── widgets/
    │           ├── classification_rules_tab.dart   # 6-tier rules list & drag-and-drop
    │           ├── accounts_tab.dart               # Accounts list & balances
    │           ├── projects_tab.dart               # Projects list & management
    │           └── refund_link_dialog.dart         # Refund association modal
    └── theme/
        └── app_theme.dart                          # Material 3 color schemes and typography
test/
├── core/
├── database/
├── deduplication/
├── recognition/
├── classification/
└── presentation/                                   # Milestone M2 Widget & Interaction Tests
    ├── test_helpers.dart                           # In-memory DB test harness & mock helpers
    ├── transactions_screen_test.dart               # R2 Widget tests
    ├── draft_confirmation_screen_test.dart         # R3 Widget tests (bounding box, dedup alerts)
    ├── rules_accounts_screen_test.dart             # R4 Widget tests (rules, accounts, refund cascade)
    └── riverpod_providers_test.dart                # R1 State & Notifiers tests
```
