# SingWallet Milestone M2 UI Setup & Testing Architecture Investigation Report

## Executive Summary
This report analyzes SingWallet's current codebase, database infrastructure, and test architecture to provide a concrete, production-ready blueprint for Milestone M2:
1. **Current UI & Lib Setup**: `lib/main.dart` already initializes `ProviderScope` with Material 3, but renders an M0 placeholder homepage. All underlying M1 core engines (`AppDatabase`, `TransactionManager`, `DeduplicationEngine`, `ClassificationRuleEngine`, `OcrParsingPipeline`) and data models are fully functional and pass 297 comprehensive unit/stress tests.
2. **Test Initialization Patterns**: Headless in-memory SQLite isolation is established via `AppDatabase.openInMemory()`, which executes FFI setup, WAL/foreign keys pragma, all 12 table creation DDLs, and 11 performance indices in <10ms.
3. **Riverpod 2.5.1 Clean Integration**: `analysis_options.yaml` enforces `strict-casts`, `strict-inference`, and `strict-raw-types`. All Riverpod providers and notifiers must declare explicit generic type parameters (`Provider<T>`, `NotifierProvider<N, S>`, `AsyncNotifierProvider<N, S>`). Injecting `Database` synchronously at the root via `ProviderScope(overrides: [databaseProvider.overrideWithValue(db)])` enables real SQLite execution in both production `main()` and widget tests.
4. **Presentation Code Layout**: A modular architecture under `lib/presentation/` cleanly separates concerns across `navigation/`, `theme/`, `providers/`, `state/`, `screens/`, and shared `widgets/`.
5. **Widget Test Architecture**: Test harness in `test/presentation/helpers/` leverages in-memory SQLite databases with deterministic test fixtures, guaranteeing 100% pass rate and 0 analyze issues across R1–R5 acceptance criteria.

---

## 1. Inspection of `lib/main.dart` and Existing Codebase

### 1.1 `lib/main.dart` Current State
```dart
// lib/main.dart (Current M0/M1 state)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: SingWalletApp(),
    ),
  );
}

class SingWalletApp extends StatelessWidget {
  const SingWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SingWallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      home: const SingWalletHomePage(),
    );
  }
}
```
**Key Observations**:
- `ProviderScope` is already wrapping the root widget, ensuring Riverpod is ready for full-scale state management.
- `useMaterial3: true` is configured with seed color `0xFF6750A4`.
- The current home page (`SingWalletHomePage`) is a static placeholder displaying "SingWallet Core Initialized - Milestone M0".

### 1.2 Evolution for M2
To support M2, `main()` should:
1. Call `AppDatabase.initializeFfi()` (ensuring seamless desktop execution on Windows/macOS/Linux).
2. Asynchronously open SQLite database: `final db = await AppDatabase.instance.database;`.
3. Perform startup crash recovery: `await CaptureJobStateMachine.recoverLingeringJobs(db);` (self-heals any ingestion jobs left in `RECOGNIZING` state).
4. Launch `ProviderScope` with `databaseProvider.overrideWithValue(db)`.
5. Point `home:` to `AppScaffold` (providing bottom navigation across Transactions, Drafts, and Management).

### 1.3 Existing Core Engines & Data Layer Inventory
- **Database & Transactions**:
  - `lib/data/database/app_database.dart`: Singleton `AppDatabase.instance`, headless FFI initialization, `openInMemory()` factory, `PRAGMA foreign_keys = ON;`.
  - `lib/data/database/transaction_manager.dart`: 7-table atomic draft commitment (`commitDraft`), soft-deletion (`softDeleteTransaction`), trash restoration (`restoreFromTrash`), permanent purge (`permanentDeleteTransaction`), monthly summary computation (`getMonthlySummary`).
    *Note*: In `TransactionManager.discardDraft(String draftId)`, line 275 calls `await _databaseHelper.database` directly without accepting a `DatabaseExecutor? customExecutor`. When building the repository layer, executing `discardDraft` via an executor or ensuring `AppDatabase.instance` is aligned with the active DB ensures complete consistency in test environments.
  - `lib/data/database/soft_delete_manager.dart`: Monthly aggregation (`calculateMonthlySummary`), 30-day retention filtering, active vs trash separation.
  - `lib/data/database/state_machine.dart`: `CaptureJobStateMachine` deterministic transition matrix (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `DISCARDED` / `FAILED`).
- **Features & Engines**:
  - `lib/features/deduplication/deduplication_engine.dart`: 4-tier deduplication engine (Tier 1 idempotence, Tier 2 image SHA-256, Tier 3 platform identifier hard match, Tier 4 24h heuristic duplicate candidate search).
  - `lib/features/classification/rule_engine.dart`: 6-tier classification hierarchy (Tier 1 user manual, Tier 2 custom rules, Tier 3 merchant history, Tier 4 Chinese keyword dictionary, Tier 5 AI, Tier 6 fallback). Dynamic rule learning via `learnRuleFromUserAction`.
  - `lib/features/recognition/ocr_pipeline.dart`: 8-stage parsing pipeline outputting `ParsedDraftResult`, field evidences with `OcrBoundingBox`, validation issues.
  - `lib/core/utils/currency_utils.dart`: Minor cent integer arithmetic (`centsToYuanString`, `parseToMinorUnits`, 64-bit overflow boundary protection).
  - `lib/core/utils/date_utils.dart`: Calendar-strict date parsing, leap-year validation, receipt timestamp extraction.
  - `lib/core/native/native_bridge_service.dart`: High-level wrapper around Pigeon host APIs (`pickSingleImage`, `recognizeCapture`, `readImageFromClipboard`, `getOrCreateDatabaseKey`).

---

## 2. Existing Test Architecture Inspection

### 2.1 Database & Engine Initialization in Tests
Inspecting `test/database/database_test.dart`, `test/deduplication/deduplication_test.dart`, `test/recognition/ocr_pipeline_test.dart`, and `test/classification/rule_engine_test.dart` reveals a clean and consistent testing pattern:
```dart
late Database db;
late TransactionManager txManager;
late DeduplicationEngine dedupEngine;
late ClassificationRuleEngine ruleEngine;
late OcrParsingPipeline pipeline;

setUp(() async {
  // 1. In-memory SQLite initialized in <10ms
  db = await AppDatabase.openInMemory();
  
  // 2. Engines accept Database / DatabaseExecutor
  txManager = TransactionManager();
  dedupEngine = DeduplicationEngine(db);
  ruleEngine = ClassificationRuleEngine(db);
  pipeline = OcrParsingPipeline(
    dedupEngine: dedupEngine,
    classificationEngine: ruleEngine,
  );
  
  // 3. Seed minimal fixtures (categories, accounts, projects)
  await db.insert('categories', {
    'id': 'cat_food',
    'name': '餐饮美食',
    'applicable_type': 'expense',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
});

tearDown(() async {
  await db.close();
});
```

### 2.2 Strengths for UI Testing
1. **Zero Filesystem Pollution**: In-memory database `:memory:` resides purely in RAM and is garbage-collected on `db.close()`.
2. **High-Speed Execution**: 297 existing backend unit and stress tests run in ~4 seconds total.
3. **True SQLite Verification**: By running tests against real SQLite (via `sqflite_common_ffi`), tests directly verify SQL statements, foreign key cascades (`refund_links ON DELETE CASCADE`), CHECK constraints (`amount_minor > 0`), and trigger-like state machines.

---

## 3. Riverpod Clean Integration Strategy (Zero Analyze Issues)

### 3.1 Strict Analyzer Enforcement
`analysis_options.yaml` enforces:
```yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```
This requires that:
1. **Explicit Generic Types**: Never omit generic arguments.
   - `Provider<Database>((ref) => ...)` (NOT `Provider((ref) => ...)`)
   - `NotifierProvider<TransactionFilterNotifier, TransactionFilterState>(TransactionFilterNotifier.new)`
   - `AsyncNotifierProvider<TransactionListNotifier, List<TransactionEntry>>(TransactionListNotifier.new)`
   - `FutureProvider.family<MonthlyAccountingSummary, String>((ref, ym) => ...)`
2. **Explicit Consumer Widget Typing**:
   - `Widget build(BuildContext context, WidgetRef ref)`
3. **No Dynamic / Untyped Data Passing**:
   - Filter criteria, draft confirmation forms, and summaries are encapsulated in immutable state classes.

### 3.2 Global Dependency Injection Architecture
```
                         ┌───────────────────┐
                         │  databaseProvider │
                         │ (Provider<Database>)
                         └─────────┬─────────┘
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         ▼                         ▼                         ▼
┌───────────────────┐    ┌───────────────────┐    ┌───────────────────┐
│ledgerRepoProvider │    │ dedupEngineProvider│   │ruleEngineProvider │
└────────┬──────────┘    └─────────┬─────────┘    └─────────┬─────────┘
         │                         │                        │
         │                         └───────────┬────────────┘
         │                                     ▼
         │                            ┌───────────────────┐
         │                            │ocrPipelineProvider│
         │                            └───────────────────┘
         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                       │
│  - transactionListNotifierProvider (watches filter & db)    │
│  - monthlySummaryProvider (family: 'YYYY-MM')              │
│  - draftQueueNotifierProvider (watches NEEDS_REVIEW jobs)   │
│  - draftConfirmationNotifierProvider (family: draftId)      │
│  - rulesNotifierProvider (watches & updates rules)          │
│  - accountsNotifierProvider (watches & calculates balances) │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Root Provider Definitions (`lib/presentation/providers/core_providers.dart`)
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/transaction_manager.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database instance provider. Overridden in main() and widget tests.
final databaseProvider = Provider<Database>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in ProviderScope');
});

/// TransactionManager provider
final transactionManagerProvider = Provider<TransactionManager>((ref) {
  return TransactionManager(AppDatabase.instance);
});

/// DeduplicationEngine provider
final deduplicationEngineProvider = Provider<DeduplicationEngine>((ref) {
  final db = ref.watch(databaseProvider);
  return DeduplicationEngine(db);
});

/// ClassificationRuleEngine provider
final classificationRuleEngineProvider = Provider<ClassificationRuleEngine>((ref) {
  final db = ref.watch(databaseProvider);
  return ClassificationRuleEngine(db);
});

/// OcrParsingPipeline provider
final ocrPipelineProvider = Provider<OcrParsingPipeline>((ref) {
  final dedup = ref.watch(deduplicationEngineProvider);
  final rule = ref.watch(classificationRuleEngineProvider);
  return OcrParsingPipeline(
    dedupEngine: dedup,
    classificationEngine: rule,
  );
});
```

---

## 4. Proposed Presentation Code Layout under `lib/presentation/`

```
lib/presentation/
├── app.dart                                # SingWalletApp root with MaterialApp & Theme
├── navigation/
│   ├── app_scaffold.dart                   # Bottom NavigationBar (流水 / 草稿箱 / 管理中心)
│   └── navigation_provider.dart            # Active navigation tab index notifier
├── theme/
│   ├── app_theme.dart                      # Material 3 light/dark theme data
│   └── app_colors.dart                     # Financial semantic colors (expense, income, warning, tags)
├── providers/
│   ├── core_providers.dart                 # database, engines, transactionManager
│   ├── repository_providers.dart           # ledgerRepositoryProvider
│   ├── filter_provider.dart                # transactionFilterProvider & state
│   ├── transaction_providers.dart          # transactionListNotifierProvider, monthlySummaryProvider
│   ├── draft_providers.dart                # draftQueueNotifierProvider, draftConfirmationNotifierProvider
│   └── management_providers.dart           # rulesNotifierProvider, accountsProvider, projectsProvider
├── state/
│   ├── transaction_filter_state.dart       # Search query, date range, account, project, category filters
│   ├── draft_confirmation_state.dart       # Form values, evidence mapping, dedup status, OCR lines
│   └── draft_queue_item.dart               # Joined CaptureJob + Draft summary item
├── screens/
│   ├── transactions/
│   │   ├── transactions_screen.dart        # [R2] Main ledger view with pull-to-refresh & floating actions
│   │   └── widgets/
│   │       ├── monthly_summary_card.dart   # [R2] Dynamic accounting dashboard (Expense, Refund, Net)
│   │       ├── transaction_group_header.dart# [R2] Sticky date group header with daily subtotal
│   │       ├── transaction_list_tile.dart  # [R2] Ledger item (category icon, merchant, badges, amount)
│   │       ├── transaction_filter_sheet.dart# [R2] Multi-dimensional filter modal bottom sheet
│   │       └── trash_bin_dialog.dart       # [R2] 30-day trash bin viewer & permanent purge dialog
│   ├── drafts/
│   │   ├── drafts_screen.dart              # [R3] Drafts queue list (NEEDS_REVIEW items)
│   │   ├── draft_confirmation_screen.dart  # [R3] Receipt preview + smart form + OCR overlay
│   │   └── widgets/
│   │       ├── ocr_bounding_box_overlay.dart# [R3] [0.0, 1.0] normalized interactive bounding box layer
│   │       ├── receipt_preview_card.dart   # [R3] Screenshot container with FittedBox & AspectRatio
│   │       ├── draft_smart_form.dart       # [R3] Amount input, merchant, channel, date/time pickers
│   │       ├── category_suggestion_card.dart# [R3] 6-tier suggestion badge with confidence score
│   │       └── dedup_alert_dialog.dart     # [R3] Tier 3 hard block & Tier 4 soft confirm dialogs
│   └── management/
│       ├── management_screen.dart          # [R4] Tabbed management hub (Rules, Accounts, Projects)
│       ├── tabs/
│       │   ├── rules_tab.dart              # [R4] Rule list, priority drag-reorder, enabled toggles
│       │   ├── accounts_tab.dart           # [R4] Accounts list & computed balance overview
│       │   └── projects_tab.dart           # [R4] Projects list & project transaction summary
│       └── widgets/
│           ├── rule_edit_dialog.dart       # [R4] Add / Edit rule modal dialog
│           ├── account_edit_dialog.dart    # [R4] Add / Edit account modal dialog
│           └── refund_link_dialog.dart     # [R4] Original expense search & refund link association
└── widgets/
    ├── amount_text.dart                    # Currency formatter (+¥xx.xx / -¥xx.xx with color coding)
    ├── channel_capsule.dart                # WeChat / Alipay / Card / Cash badge pill
    └── empty_view.dart                     # Reusable empty list and error state views
```

### 4.1 Detailed Design for Core Milestone Requirements (R1–R4)

#### R1: Data Repository Bridge (`LedgerRepository`)
To keep view models lightweight and decouple UI from raw SQL queries, a `LedgerRepository` under `lib/data/repositories/ledger_repository.dart` executes queries directly on `Database`:
- `getTransactions(TransactionFilterState filter)`: Builds dynamic SQL with parameters, sorts by `occurred_on DESC, occurred_at DESC`.
- `getMonthlySummary(String yearMonth)`: Calls `SoftDeleteManager.calculateMonthlySummary`.
- `getDraftQueue()`: Selects jobs in `NEEDS_REVIEW` joined with `drafts`.
- `getDraftWithCapture(String draftId)`: Fetches draft and its parent capture job.
- `commitDraft(CommitDraftRequest request)`: Calls `TransactionManager.commitDraft(request, customExecutor: db)`.
- `softDeleteTransaction(String id)`: Calls `TransactionManager.softDeleteTransaction(id, customExecutor: db)`.
- `restoreFromTrash(String id)`: Calls `TransactionManager.restoreFromTrash(id, customExecutor: db)`.
- `permanentDelete(String id)`: Calls `TransactionManager.permanentDeleteTransaction(id, customExecutor: db)`.
- `getRules()`, `updateRulePriority()`, `toggleRule()`: Direct SQL queries on `classification_rules`.
- `getAccountsWithBalances()`: Computes `income - expense` per account using SQL aggregation.
- `linkRefund(String refundId, String originalExpenseId)`: Inserts into `refund_links`.

#### R2: Transactions Screen (资产大盘与流水明细)
- **Top Dynamic Summary Card**:
  - Displays formatted totals: `本月支出 ¥xxx.xx`, `本月退款/收入 ¥xxx.xx`, `净支出 ¥xxx.xx`.
  - Left/right arrow buttons to navigate months (`2026-10`, `2026-09`), immediately refreshing the dashboard.
- **Date-Grouped Transaction List**:
  - Groups transactions by `occurred_on` (YYYY-MM-DD).
  - Displays localized date header: `10月22日 周四` with daily subtotal: `支出 ¥128.50`.
  - Transaction item displays:
    - Category icon with rounded container.
    - Merchant name (`merchant_raw` or `merchant_normalized`).
    - Note snippet (if present).
    - Payment channel capsule badge (微信支付 / 支付宝 / 现金).
    - Project badge (e.g. `[差旅]`).
    - Refund tag (e.g. `[退款]`) and green text if `type == 'refund'`.
    - Minor cents amount formatted with `CurrencyUtils.centsToYuanString`.
- **Soft-Delete & Undo Interaction**:
  - Dismissible swipe or menu action "删除".
  - Soft-deletes transaction, immediately updates list.
  - Pops SnackBar: `"已移至回收站"` with `"撤销"` action button.
  - Tapping "撤销" calls `restoreFromTrash` and restores the item instantly.
  - App bar icon to open "回收站 (Trash Bin)" modal, with "彻底清空 (Purge)" and individual "恢复 (Restore)" buttons.

#### R3: Draft Confirmation & OCR Bounding Box Overlay
- **Receipt Preview & Normalized Bounding Box Mapping**:
  - OCR lines have bounding box normalized coordinates in `[0.0, 1.0]`: `left`, `top`, `width`, `height`. Origin is top-left.
  - In `OcrBoundingBoxOverlay`:
    ```dart
    LayoutBuilder(
      builder: (context, constraints) {
        final W = constraints.maxWidth;
        final H = constraints.maxHeight;
        return Stack(
          children: [
            for (final line in ocrLines)
              Positioned(
                left: line.boundingBox.left.clamp(0.0, 1.0) * W,
                top: line.boundingBox.top.clamp(0.0, 1.0) * H,
                width: line.boundingBox.width.clamp(0.0, 1.0 - line.boundingBox.left) * W,
                height: line.boundingBox.height.clamp(0.0, 1.0 - line.boundingBox.top) * H,
                child: HighlightBox(
                  text: line.text,
                  isSelected: line.text == activeEvidenceText,
                  onTap: () => onBoxTapped(line),
                ),
              ),
          ],
        );
      },
    );
    ```
  - **Click-to-Autofill**: Tapping an OCR bounding box opens a fast action sheet or direct menu: `[填入商户名]`, `[填入金额]`. Selecting updates the form field immediately.
- **Smart Form**:
  - Prominent amount editor with large typography.
  - Channel selector chips (微信支付, 支付宝, 银行卡, 现金).
  - Transaction type toggle (支出, 收入, 退款).
  - Merchant name field with clear button.
  - Category suggestion card displaying the suggested category name, match tier (规则命中 / 历史频次 / 词典匹配 / AI), and confidence score badge.
  - Account and Project dropdown pickers.
- **4-Tier Deduplication Interception**:
  - On clicking "确认入账", calls `DeduplicationEngine.evaluate(...)`.
  - **Tier 3 Collision**: If matching `PlatformIdentifier` exists in active transactions, displays hard blocking dialog:
    `"检测到重复订单号：该交易已于 YYYY-MM-DD 记账 (ID: tx_xxx)，系统禁止重复入账！"`. Commit is blocked.
  - **Tier 4 Soft Duplicate**: If matching amount and merchant found within 24h, displays secondary confirmation dialog:
    `"疑似重复交易提示：24小时内已存在相同商户与金额的交易（¥xx.xx，商户: xxx）。是否仍要保存？"`.
    `[取消]` -> stays on draft; `[仍然入账]` -> proceeds with commit.
- **Atomic Commit**: Calls `TransactionManager.commitDraft`, transitioning `capture_jobs.state` from `NEEDS_REVIEW` to `COMMITTED`, saves transaction, invalidates home transactions provider, and navigates back.

#### R4: Rules Management & Accounts/Projects Center
- **Rules Tab**:
  - Lists classification rules ordered by priority descending.
  - Displays rule merchant pattern, target category icon/name, priority badge, and payment channel constraint.
  - `Switch` widget to toggle rule enabled/disabled (`enabled = 1 / 0`).
  - `ReorderableListView` allowing drag-to-reorder, updating rule priorities in SQLite.
  - Floating action button to open "添加规则 (Add Rule)" dialog.
  - "一键重新匹配 (Re-match)" button to re-evaluate drafts with updated rules.
- **Accounts & Projects Tab**:
  - Accounts list showing name, kind (debit card, e-wallet, cash), card last 4, and computed balance.
  - Projects list with transaction count and total spend.
  - Dialogs to add/edit accounts and projects.
- **Refund Link Dialog**:
  - When creating or editing a refund transaction:
  - Button "关联原消费账目 (Link Original Expense)" opens modal.
  - Searchable list of past expenses (`type == 'expense' AND deleted_at IS NULL`).
  - User selects the expense; `refund_links` record is created.
  - Refund card displays linked original expense info with unlinking option.

---

## 5. Proposed Widget Test Architecture & Test Cases under `test/presentation/`

### 5.1 Test Harness & Helpers
1. `test/presentation/helpers/test_database_helper.dart`:
   - `createTestDatabase({bool seedFixtures = true})`: Creates in-memory SQLite database, inserts default categories (`cat_food`, `cat_transport`, `cat_shopping`, `cat_other`), accounts (`acc_wechat`, `acc_alipay`, `acc_card`), and projects (`proj_travel`).
2. `test/presentation/helpers/widget_test_wrapper.dart`:
   - `createWidgetUnderTest({required Widget child, required Database database, List<Override> overrides = const []})`:
     Wraps widget in `ProviderScope` with `databaseProvider.overrideWithValue(database)` and `MaterialApp`.

### 5.2 Widget Test Suites Matrix

| Test Suite File | Tested Component / Feature | Acceptance Criteria Verified |
|---|---|---|
| `test/presentation/widgets/ocr_bounding_box_overlay_test.dart` | `OcrBoundingBoxOverlay` | **R3, AC 2**: Normalized `[0.0, 1.0]` coordinate mapping to pixel dimensions, clamping, tap detection |
| `test/presentation/screens/transactions_screen_test.dart` | `TransactionsScreen`, `MonthlySummaryCard` | **R2, AC 4**: Dynamic accounting summary calculation, date-grouped list rendering, multi-dimensional filtering, soft-delete & undo SnackBar |
| `test/presentation/screens/draft_confirmation_screen_test.dart` | `DraftConfirmationScreen`, `DedupAlertDialog` | **R3, AC 2, AC 3**: OCR click-to-autofill, Tier 3 hard duplicate block dialog, Tier 4 24h soft duplicate confirm dialog, atomic commit & job state transition |
| `test/presentation/screens/drafts_screen_test.dart` | `DraftsScreen` | **R3**: Draft queue list rendering, badge counters, navigation to confirmation screen |
| `test/presentation/screens/rules_tab_test.dart` | `RulesTab`, `RuleEditDialog` | **R4**: Rule list rendering, enable/disable toggle, priority reordering, add rule |
| `test/presentation/screens/accounts_tab_test.dart` | `AccountsTab`, `RefundLinkDialog` | **R4, AC 5**: Account balance calculation, refund candidate search, refund link association, foreign key cascade verification |
| `test/presentation/navigation/app_navigation_test.dart` | `AppScaffold` | **R1–R4**: Bottom navigation bar tab switching (流水 -> 草稿箱 -> 管理) |

### 5.3 Concrete Test Case Specifications

#### Suite 1: `ocr_bounding_box_overlay_test.dart`
- **Case 1.1: Exact pixel coordinate mapping**:
  - Feed bounding box `left: 0.1, top: 0.2, width: 0.5, height: 0.1` inside a 400x600 container.
  - Verify Positioned widget has `left: 40.0, top: 120.0, width: 200.0, height: 60.0`.
- **Case 1.2: Boundary clamping**:
  - Feed out-of-range coordinates `left: -0.05, top: 1.05, width: 1.2, height: 0.5`.
  - Verify layout does not overflow and coordinates clamp within `[0.0, 1.0]`.
- **Case 1.3: Tap interaction**:
  - Tap on the bounding box widget.
  - Verify `onBoxTapped` callback is invoked with the corresponding text line.

#### Suite 2: `draft_confirmation_screen_test.dart`
- **Case 2.1: Bounding box click autofills merchant name**:
  - Tap bounding box containing "瑞幸咖啡".
  - Verify the Merchant `TextFormField` updates its value to "瑞幸咖啡".
- **Case 2.2: Tier 3 Hard Duplicate blocks submission**:
  - Seed an existing transaction with platform identifier `alipay_trade_2026102201`.
  - Open draft confirmation with identical platform identifier.
  - Tap "确认入账".
  - Verify `DedupAlertDialog` appears with title "检测到重复订单号" and message prohibiting duplicate entry.
  - Verify no new transaction is inserted into SQLite.
- **Case 2.3: Tier 4 Heuristic Duplicate triggers secondary confirmation**:
  - Seed transaction with merchant "麦当劳" and amount 3500 cents on today's date.
  - Open draft confirmation with merchant "麦当劳" and amount 3500 cents.
  - Tap "确认入账".
  - Verify secondary confirmation dialog appears: "疑似重复交易提示".
  - Tap "取消" -> dialog closes, draft remains uncommitted.
  - Tap "确认入账" again, tap "仍然入账" -> draft commits, `capture_jobs.state` becomes `COMMITTED`.
- **Case 2.4: Clean draft commitment**:
  - Tap "确认入账" on clean draft.
  - Verify `transactions` table has new row, `capture_jobs.state == 'COMMITTED'`, and `saved_transaction_id` is populated.

#### Suite 3: `transactions_screen_test.dart`
- **Case 3.1: Monthly summary calculation**:
  - Seed expense of ¥120.50 (12050 cents) and refund of ¥20.50 (2050 cents).
  - Verify `MonthlySummaryCard` displays "本月支出: ¥120.50", "本月退款: ¥20.50", "净支出: ¥100.00".
- **Case 3.2: Date-grouped rendering with daily subtotal**:
  - Seed two transactions on 2026-10-22 (¥30.00 and ¥25.00).
  - Verify date header "10月22日" is present with daily subtotal "支出 ¥55.00".
- **Case 3.3: Multi-dimensional filter application**:
  - Open filter sheet, select category "餐饮美食".
  - Verify list only displays transactions with `category_id == 'cat_food'`.
- **Case 3.4: Soft delete and Undo SnackBar**:
  - Trigger delete on first transaction.
  - Verify transaction disappears from active list, and SnackBar appears with "已移至回收站" and "撤销".
  - Tap "撤销" -> transaction reappears in the list.

#### Suite 4: `rules_tab_test.dart` & `accounts_tab_test.dart`
- **Case 4.1: Rule toggle updates database**:
  - Toggle rule switch from enabled to disabled.
  - Query SQLite: verify `classification_rules.enabled == 0`.
- **Case 4.2: Rule priority drag-reorder**:
  - Reorder rules in `ReorderableListView`.
  - Verify priorities are updated accordingly in the database.
- **Case 4.3: Account balance aggregation**:
  - Seed income of ¥500.00 and expense of ¥150.00 for `acc_wechat`.
  - Verify `AccountsTab` renders WeChat wallet balance as "¥350.00".
- **Case 4.4: Refund link association & FK cascade**:
  - Link refund transaction to original expense.
  - Verify row in `refund_links`.
  - Permanently delete original expense -> verify `refund_links` row is cascade deleted, but refund transaction remains intact.

---

## 6. Verification Plan & Commands

To verify zero analyzer issues and 100% test pass rate throughout M2:
1. **Static Analysis**:
   ```powershell
   flutter analyze
   ```
   *Expected*: `No issues found! (ran in ~6s)` with exit code 0.
2. **Backend Regression Test**:
   ```powershell
   flutter test test/core test/database test/deduplication test/recognition test/classification
   ```
   *Expected*: All 297 existing tests pass with exit code 0.
3. **New Presentation Widget Tests**:
   ```powershell
   flutter test test/presentation
   ```
   *Expected*: All UI widget tests pass with exit code 0.
4. **Full Test Suite Execution**:
   ```powershell
   flutter test
   ```
   *Expected*: 100% test pass rate across unit, relational stress, and widget tests.
