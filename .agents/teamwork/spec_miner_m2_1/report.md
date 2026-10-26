# SingWallet Milestone M2 UI & Interaction Specification Mining Report

- **Author**: `spec_miner_m2_1` (Specification Miner)
- **Milestone**: Milestone M2 (Core Presentation Layer, UI Flows, Interaction Rules & Riverpod Architecture)
- **Target Working Directory**: `c:\Other\Projects\singwallet`
- **Authoritative Sources**: 
  - `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md` (Milestone M2 section)
  - `docs/跨平台架构与数据规范.md` (DDL, Deduplication, Accounting Formulas, BoundingBox Normalization)
  - `docs/Android实现方案.md` & `docs/iOS实现方案.md` (Presentation flows, HIG/Material specs, Screen Capture)
  - `pigeons/native_bridge.dart` & `lib/core/native/native_bridge.g.dart` (OCR IDL & Bounding Box)
  - Existing core engine implementations in `lib/data/` and `lib/features/`

---

## 1. Executive Overview

Milestone M2 constructs the production-grade Flutter Presentation Layer for SingWallet based on the existing, verified M0 (Pigeon Bridge) and M1 (SQLite Database, 4-Tier Deduplication Engine, 8-Stage OCR Pipeline, 6-Tier Classification Rule Engine).

This specification details every UI contract, interaction flow, Riverpod state management graph, mathematical coordinate transform, deduplication alert state machine, and automated testing criteria necessary for implementation.

---

## 2. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| F1 | R1 State Architecture | Global Engine & Database DI Container | Riverpod providers injecting `AppDatabase`, `TransactionManager`, `DeduplicationEngine`, `ClassificationRuleEngine`, and `OcrParsingPipeline`. | Riverpod `Ref` | Singletons and cached engine instances | Throws state error if database fails to open | `lib/data/database/app_database.dart`, `ORIGINAL_REQUEST.md` |
| F2 | R1 State Architecture | Monthly Summary Provider | AsyncNotifier calculating monthly financial stats (`totalExpenseMinor`, `totalRefundMinor`, `netExpenseMinor`, `transactionCount`) for selected `YYYY-MM`. | Month string `YYYY-MM` | `MonthlyAccountingSummary` model | Defaults to 0 amounts on error | `lib/data/database/soft_delete_manager.dart` |
| F3 | R1 State Architecture | Multi-Dimensional Filter State | StateNotifier managing search query, account ID, project ID, category ID, transaction type, and date range filters. | User filter selections | Immutable `TransactionFilter` object | Invalid date range throws FormatException | `ORIGINAL_REQUEST.md` R2 |
| F4 | R1 State Architecture | Reactive Transactions Stream & Notifier | AsyncNotifier managing active ledger entries (`deleted_at IS NULL`), filtering, sorting, and reactive refreshes upon mutations. | Filter state, DB mutations | `List<TransactionEntry>` | Emits `AsyncError` with UI retry trigger | `ORIGINAL_REQUEST.md` R1 |
| F5 | R1 State Architecture | Daily Aggregated Grouping State | Derived provider grouping active transactions by `occurred_on` descending with daily subtotal calculations. | `List<TransactionEntry>` | `List<DailyTransactionGroup>` | Empty list if no records match | `docs/跨平台架构与数据规范.md` §4 |
| F6 | R1 State Architecture | 30-Day Recycling Bin Notifier | AsyncNotifier managing soft-deleted transactions (`deleted_at IS NOT NULL`), restore, permanent delete, and purge operations. | Trash queries, item UUIDs | `List<TransactionEntry>` in trash | Disables action if transaction not found | `lib/data/database/soft_delete_manager.dart` |
| F7 | R1 State Architecture | Draft Queue Notifier | Stream/Notifier monitoring ingestion jobs and drafts in `NEEDS_REVIEW` state. | SQLite `drafts` join `capture_jobs` | `List<DraftReviewItem>` | Graceful empty queue state | `lib/data/database/state_machine.dart` |
| F8 | R1 State Architecture | Draft Review ViewModel | AutoDispose StateNotifier managing single draft inspection, OCR bounding box selection, candidate field modifications, and deduplication states. | `draftId` | `DraftReviewState` | Emits validation warnings on missing required fields | `lib/features/recognition/ocr_pipeline.dart` |
| F9 | R1 State Architecture | Classification Rules Notifier | AsyncNotifier managing 6-tier classification rules, ordering, priority drag-and-drop, enable/disable switches, and re-match batch execution. | Priority changes, rule edits | `List<ClassificationRule>` | Reverts optimistic update if DB write fails | `lib/features/classification/rule_engine.dart` |
| F10 | R1 State Architecture | Financial Accounts & Balances State | AsyncNotifier calculating real-time balances per account across all expenses, incomes, refunds, and transfers. | Account transactions | `List<AccountWithBalance>` | Displays zero balance on fresh accounts | `docs/跨平台架构与数据规范.md` §3 |
| F11 | R1 State Architecture | Project Management State | State provider managing project tags, project lifecycle (active vs archived), and project spending summaries. | Project CRUD actions | `List<ProjectWithStats>` | Prevents deleting projects with active transactions | `lib/data/models/project.dart` |
| F12 | R1 State Architecture | Categories Taxonomy Provider | Cached hierarchy provider managing 2-tier category taxonomy, preset icons, and applicable transaction types. | Category table records | `List<Category>` tree | Fallback to `cat_other` icon if unmapped | `lib/data/models/category.dart` |
| F13 | R2 Transactions | Monthly Financial Accounting Card | Header dashboard card displaying 本月支出, 本月退款, 净结余, with month switcher (prev/next/picker). | Selected year-month | Formatted Currency (¥0.00) | Formats minor cents via `CurrencyUtils` | `ORIGINAL_REQUEST.md` R2, `docs/跨平台架构与数据规范.md` §4 |
| F14 | R2 Transactions | Daily Aggregated List with Sticky Headers | Pinned section headers showing formatted date (e.g., "10月23日 星期五") and daily subtotal. | Daily transaction groups | Grouped ListView with sticky headers | Empty state placeholder when 0 transactions | `ORIGINAL_REQUEST.md` R2 |
| F15 | R2 Transactions | Rich Transaction List Tile | Transaction item rendering category icon, merchant name, payment account capsule, project tag, signed amount, and refund indicator. | `TransactionEntry` | Material 3 ListTile / Card | Highlights negative/positive amounts | `docs/iOS实现方案.md` §3.3 |
| F16 | R2 Transactions | Multi-Dimensional Filter Bottom Sheet | Modal sheet offering interactive filter chips for Account, Project, Category, Transaction Type, Date Range, and Search text. | User selections | Updated `TransactionFilter` | "Reset" button clears all active filters | `ORIGINAL_REQUEST.md` R2 |
| F17 | R2 Transactions | Soft-Delete with Undo SnackBar | Left-swipe or menu action setting `deleted_at`, removing item from active view with 5-second undo SnackBar. | Transaction UUID | UI removal + SnackBar with action | `TransactionManager.softDeleteTransaction` | `lib/data/database/soft_delete_manager.dart` |
| F18 | R2 Transactions | 30-Day Recycling Bin Screen | Dedicated view listing soft-deleted items with remaining retention days, single-item restore, permanent delete, and purge all. | Trash transactions | Trash list UI + Purge action | Confirmation dialog before permanent delete | `lib/data/database/soft_delete_manager.dart` |
| F19 | R3 Draft Review | Normalized Coordinate Viewport Mapper | Mathematical engine mapping `[0.0, 1.0]` normalized coordinates to viewport dimensions under `BoxFit.contain` without distortion. | Container size, Image natural size, `OcrBoundingBox` | Absolute pixel `Rect` $(x, y, w, h)$ | Clamps coordinates within `[0.0, 1.0]` | `docs/跨平台架构与数据规范.md` §2.1, `docs/Android实现方案.md` §6.1.1 |
| F20 | R3 Draft Review | OCR BoundingBox Visual Overlay | Semi-transparent highlight overlays on screenshot text lines with color coding (Green for amount, Purple for merchant, Blue for text). | List of `OcrTextLine` | Interactive visual bounding boxes | Non-blocking if OCR lines are empty | `ORIGINAL_REQUEST.md` R3 |
| F21 | R3 Draft Review | Tap-to-Backfill Interaction | Tapping any OCR bounding box triggers popover to quickly backfill text into Merchant, Amount, or Note fields. | User tap on bounding box | Form field text replacement | Validates currency format before backfilling amount | `ORIGINAL_REQUEST.md` R3 |
| F22 | R3 Draft Review | Smart Transaction Form | Form displaying large 36pt Amount display, editable Merchant input, Type SegmentedButton, Channel chips, and Date picker. | Parsed draft fields | Reactive form inputs | Enforces `amountMinor > 0` validation | `docs/Android实现方案.md` §6.2 |
| F23 | R3 Draft Review | Suggested Category Card with Matching Tier Badge | Card highlighting recommended category, matching tier badge (规则 #100, 历史习惯 90%, 关键词识别, AI建议), and picker trigger. | `ClassificationMatchResult` | Visual recommendation card | Fallback to `cat_other` if unclassified | `lib/features/classification/rule_engine.dart` |
| F24 | R3 Draft Review | Tier 3 Platform Identifier Collision Hard Blocking | Hard check blocking commit if `platform_transaction_no` matches an active ledger entry. | `PlatformIdentifier` | Red warning banner + Commit button disabled | Navigation link to view existing transaction | `lib/features/deduplication/deduplication_engine.dart` |
| F25 | R3 Draft Review | Tier 3 Trash Bin Collision Alert with Restore Action | Detection of platform identifier collision with a soft-deleted transaction in the 30-day trash bin. | `PlatformIdentifier` | Amber alert dialog with "Restore" option | Calls `TransactionManager.restoreFromTrash` | `lib/data/database/transaction_manager.dart` |
| F26 | R3 Draft Review | Tier 4 Heuristic 24h Duplicate Secondary Confirmation Dialog | Warning dialog intercepting commit when identical merchant + amount occurs within 24 hours. | Tier 4 suspected duplicates | Modal dialog: "这是另一笔" vs "放弃草稿" | Bypasses warning only on explicit user click | `ORIGINAL_REQUEST.md` R3, `docs/跨平台架构与数据规范.md` §4.2 |
| F27 | R3 Draft Review | Atomic One-Click Commit & State Transition | Atomic commit across 7 tables, transitioning capture job state from `NEEDS_REVIEW` to `COMMITTED`, updating draft link, and purging image. | `CommitDraftRequest` | `TransactionEntry` saved to ledger | Full transaction rollback on any failure | `lib/data/database/transaction_manager.dart` |
| F28 | R3 Draft Review | Dynamic Rule Learning on User Confirmation | Automatically creates or updates a custom classification rule when user modifies or confirms a category. | Confirmed merchant & category | Insert/update in `classification_rules` | Non-retroactive: does not alter past transactions | `lib/features/classification/rule_engine.dart` §362 |
| F29 | R3 Draft Review | Discard Draft Action | User rejects draft, transitioning capture job to `DISCARDED` and purging private screenshot file. | `draftId` | Capture job marked DISCARDED | Irreversible terminal state | `lib/data/database/state_machine.dart` |
| F30 | R4 Rules & Accounts | 6-Tier Rules Hierarchy Overview | Visualization of 6 classification tiers (Manual, Custom Rules, History, Dictionary, AI, Fallback). | Rule hierarchy metadata | Informational hierarchy UI | Read-only guidance card | `lib/features/classification/rule_engine.dart` |
| F31 | R4 Rules & Accounts | Reorderable Custom Rules List | Drag-and-drop list of custom classification rules sorted by `RuleMatcher.compareRules` (priority DESC). | Drag gesture / position reorder | Monotonically updated priorities | Prevents duplicate priorities | `lib/features/classification/rule_matcher.dart` |
| F32 | R4 Rules & Accounts | Rule Enable / Disable Switch Toggle | Instant toggle switch updating `classification_rules.enabled` between 1 and 0. | Rule UUID, switch boolean | Instant DB update | Updates rule engine cache in memory | `docs/跨平台架构与数据规范.md` §3 |
| F33 | R4 Rules & Accounts | Custom Rule Editor Dialog | Dialog to create or edit rule pattern (wildcard `*` or exact), channel limitation, target category, project, and priority. | Form inputs | Insert/Update `classification_rules` | Validates non-empty pattern and valid category ID | `lib/data/models/classification_rule.dart` |
| F34 | R4 Rules & Accounts | Batch Re-Match Trigger for Pending Drafts | Trigger button executing classification engine against all unconfirmed drafts in `NEEDS_REVIEW` without altering committed transactions. | User button click | Updated `suggestedCategoryId` in drafts | Strictly preserves committed transactions | `ORIGINAL_REQUEST.md` R4 |
| F35 | R4 Rules & Accounts | Account Management & Balance Overview | Screen showing accounts (Cash, Debit Card, Credit Card, E-Wallet) and dynamic net balances. | Account records | List with balance cards & Add Account modal | Formats negative balance in warning color | `docs/跨平台架构与数据规范.md` §3 |
| F36 | R4 Rules & Accounts | Account Soft Archiving | Action to soft-archive an account (`archived_at`), hiding it from draft selectors while preserving historical ledger relations. | Account UUID | Account updated with timestamp | Cannot archive account if active drafts target it | `lib/data/models/account.dart` |
| F37 | R4 Rules & Accounts | Project Configuration Center | Screen managing projects (travel, renovation), aggregated spend per project, and project archiving. | Project records | Project list cards with total spending | Soft archives via `archived_at` | `lib/data/models/project.dart` |
| F38 | R4 Rules & Accounts | Searchable Refund Link Picker Dialog | Search modal for linking a refund transaction to its original expense transaction. | Refund transaction ID, search query | Insert row in `refund_links` table | Enforces candidate `type = 'expense'` and active | `lib/data/models/refund_link.dart` |
| F39 | R4 Rules & Accounts | Refund Link Cascade Deletion Handling | UI handling when original expense is permanently purged: `refund_links` row cascades while refund transaction remains intact. | DB deletion of original expense | Refund tile updates to "Unlinked Refund" | No orphan foreign key crash | `docs/跨平台架构与数据规范.md` §3 |
| F40 | R5 Verification | Riverpod Injection & Test Harness | Test utilities and ProviderContainer overrides for mocking database, services, and view models. | In-memory DB / mocks | Isolated test execution context | Clean tear-down after each test | `test/widget_test.dart` |
| F41 | R5 Verification | Transactions Dashboard Widget Tests | Widget tests verifying monthly summary calculations, daily group headers, filter drawer, and empty ledger rendering. | Golden & widget tester | Verifies rendered text, counts, and styles | Fails if sums do not match minor units | `ORIGINAL_REQUEST.md` R5 |
| F42 | R5 Verification | Coordinate Mapping & BoundingBox Tests | Widget tests asserting pixel Rect calculation across 16:9, 19.5:9, and 1:1 viewports, and out-of-bound clamping. | Simulated touch & coordinate matrices | Verifies exact offset and dimensions | Fails on visual distortion or overflow | `ORIGINAL_REQUEST.md` R5 |
| F43 | R5 Verification | Tap-to-Backfill Widget Tests | Widget test tapping an OCR bounding box and verifying Merchant Name and Amount text controllers update immediately. | WidgetTester tap on Positioned box | Value updated in TextFormField | Fails if text controller is unchanged | `ORIGINAL_REQUEST.md` R5 |
| F44 | R5 Verification | Deduplication Alert Interception Widget Tests | Widget tests verifying Tier 3 hard block alert and Tier 4 24h heuristic duplicate confirmation dialog. | Mocked duplicate draft state | Verifies dialog visibility and button states | Fails if commit proceeds without confirmation | `ORIGINAL_REQUEST.md` R5 |
| F45 | R5 Verification | Rules Center Drag & Toggle Widget Tests | Widget tests verifying drag reordering, enable toggle, and re-match action on pending drafts. | ReorderableListView gesture | Priority values updated in DB | Fails if priority sorting is violated | `ORIGINAL_REQUEST.md` R5 |

---

## 3. Edge Cases & Boundary Behaviors

| # | Feature | Input / Condition | Expected & Observed Behavior |
|---|---------|-------------------|-------------------------------|
| E1 | Viewport Coordinate Mapper | Bounding box coordinates with out-of-bound values: `left = -0.05`, `top = 1.05`, `width = 0.5`, `height = 0.2` | Clamping algorithm restricts $left \in [0.0, 1.0]$, $top \in [0.0, 1.0]$, and $width \le 1.0 - left$. Box is rendered safely within image bounds without overflowing or throwing Flutter geometry exceptions. |
| E2 | Viewport Coordinate Mapper | Extreme image aspect ratios: ultra-tall (foldable phone 22:9) or ultra-wide (tablet 4:3) displayed in standard viewport | Under `BoxFit.contain`, scale factor $S = \min(W_{box}/W_{img}, H_{box}/H_{img})$ is calculated. Letterboxing ($dx > 0, dy = 0$) or pillarboxing ($dx = 0, dy > 0$) is applied. Coordinates scale proportionately without non-uniform stretching. |
| E3 | Smart Form Amount | User inputs invalid string like `"0"`, `"0.00"`, `"-15.00"`, `"abc"`, or `""` | Form validation blocks submission. `CurrencyUtils.parseToMinorUnits` requires $amountMinor > 0$. Input field shows inline error: "请输入有效的实付金额（必须大于0）". |
| E4 | Smart Form Amount | User enters large amount near 64-bit boundary | Checked against `CurrencyUtils.maxSafeMajor` ($92,233,720,368,547,758$). Exceeding amounts throw `FormatException` and display clear error rather than integer overflow. |
| E5 | Tap-to-Backfill | User taps an OCR text line containing currency symbols and noise, e.g. `"实付: ¥ 88.50 元"` | When backfilling Amount, `AmountParser` / `CurrencyUtils` extracts only the numeric token (`"88.50"` -> `8850` cents). When backfilling Merchant, string is cleaned of prefix keywords. |
| E6 | Missing Date in OCR | Receipt screenshot has no visible date/time text (common in simple merchant QR code receipts) | Pipeline outputs `DateUtils.fallbackToday()`, sets `event_time_source = 'suggested_today'`, and adds `ValidationIssue.missingDateIssue()`. UI displays an amber badge "建议今天 (未提取到日期)" encouraging user verification. |
| E7 | Rapid Double-Tap Commit | User rapidly taps "确认入账" button twice in succession (< 200ms) | UI state immediately sets `isSubmitting = true`, disabling button. In addition, SQLite table has unique constraint on `origin_draft_id`. If duplicate insert reaches DB, `TransactionManager` catches it and throws `DuplicateTransactionException`. |
| E8 | Tier 3 Deduplication | OCR extracts full 28-digit WeChat transaction number that already exists in active `transactions` | `DeduplicationEngine.checkTier3PlatformId` returns `Tier3Result.activeDuplicate`. UI displays red blocking modal dialog: "此交易已入账！单号 [PlatformNo]". "确认记账" button is disabled; "查看已有账目" navigates to the duplicate record. |
| E9 | Tier 3 Trash Bin Collision | OCR extracts transaction number belonging to a transaction soft-deleted into the 30-day recycling bin | `TransactionManager.commitDraft` throws `TrashBinCollisionException`. UI displays amber alert dialog: "该交易已在回收站中". User can click "从回收站恢复原记录" (calling `restoreFromTrash(targetDraftId: draftId)`), preserving the original UUID. |
| E10 | Tier 4 Heuristic 24h Duplicate | Same store, same amount paid twice within 10 minutes (e.g. buying two coffees separately) | Tier 4 detects matching merchant, identical amount, and time difference $\le 24\text{h}$. When clicking commit, a secondary confirmation dialog appears: "疑似重复交易提示：检测到近期有一笔相同消费...". User clicks "这是另一笔合法消费", proceeding with commit. |
| E11 | Refund Cascade Deletion | Original expense transaction is permanently deleted from SQLite recycling bin | SQLite foreign key constraint `FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE` automatically deletes the row in `refund_links`. The refund transaction itself remains intact as an unlinked standalone refund (`type = 'refund'`). |
| E12 | Rules Priority Reordering | User drags rule to new position, causing identical numeric priority with adjacent rule | Priority recalculation assigns monotonic values. If collision occurs, batch updates recalculate priorities in steps of 10 (e.g. 100, 90, 80, 70), ensuring deterministic sorting via `RuleMatcher.compareRules`. |
| E13 | Rules Non-Retroactivity | User creates a new rule or re-evaluates rules via "一键重新匹配" | Rules engine executes against unconfirmed drafts in `drafts` WHERE `capture_jobs.state = 'NEEDS_REVIEW'`. It **strictly never alters** committed records in `transactions` table. |
| E14 | Account Balance Calculation | Account has internal transfers (`type = 'transfer'`) | Balances reflect transfers: transfer reduces `account_id` balance and increases `transfer_to_account_id` balance. However, `calculateMonthlySummary` strictly excludes `transfer` from monthly expense/refund calculations. |
| E15 | Soft Delete & Undo | User soft-deletes a transaction, then taps "撤销" in SnackBar within 5 seconds | UI removes item optimistically and shows SnackBar. Tapping "撤销" calls `TransactionManager.restoreFromTrash(txId)`, clearing `deleted_at`. Item instantly reappears in ledger and monthly totals refresh. |

---

## 4. Deep Architecture Specifications

### 4.1 R1: Riverpod Presentation Architecture & Dependency Injection Graph

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        App Boot & ProviderScope                        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   Core Infrastructure Providers                        │
├───────────────────────────────────┬────────────────────────────────────┤
│ appDatabaseProvider               │ Provider<AppDatabase>              │
│ databaseProvider                  │ FutureProvider<Database>           │
│ nativeBridgeServiceProvider       │ Provider<NativeBridgeService>      │
└───────────────────────────────────┼────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   Domain Engine & Service Providers                    │
├───────────────────────────────────┬────────────────────────────────────┤
│ transactionManagerProvider        │ Provider<TransactionManager>       │
│ deduplicationEngineProvider       │ FutureProvider<DeduplicationEngine>│
│ classificationRuleEngineProvider  │ FutureProvider<Classification... > │
│ ocrPipelineProvider               │ FutureProvider<OcrParsingPipeline> │
└───────────────────────────────────┼────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                  Presentation ViewModels & Notifiers                   │
├───────────────────────────────┬────────────────────────────────────────┤
│ currentMonthProvider          │ StateProvider<String> ('YYYY-MM')      │
│ monthlySummaryProvider        │ FutureProvider<MonthlyAccounting... >  │
│ transactionFilterProvider     │ NotifierProvider<TxFilterNotifier, ...>│
│ transactionsListNotifier      │ AsyncNotifierProvider<TxListNotifier>  │
│ dailyGroupedTxProvider        │ Provider<List<DailyTransactionGroup>>  │
│ trashBinNotifierProvider      │ AsyncNotifierProvider<TrashNotifier>   │
│ draftQueueNotifierProvider    │ AsyncNotifierProvider<DraftQueue>      │
│ draftReviewViewModelProvider  │ AutoDisposeNotifierProviderFamily<...> │
│ rulesManagementNotifier       │ AsyncNotifierProvider<RulesNotifier>   │
│ accountsNotifierProvider      │ AsyncNotifierProvider<AccountsNotifier>│
│ projectsNotifierProvider      │ AsyncNotifierProvider<ProjectsNotifier>│
│ categoriesNotifierProvider    │ FutureProvider<List<Category>>         │
└───────────────────────────────┴────────────────────────────────────────┘
```

#### Provider Contracts:

1. **`appDatabaseProvider`**:
   ```dart
   final appDatabaseProvider = Provider<AppDatabase>((ref) {
     return AppDatabase.instance;
   });
   ```

2. **`transactionManagerProvider`**:
   ```dart
   final transactionManagerProvider = Provider<TransactionManager>((ref) {
     final db = ref.watch(appDatabaseProvider);
     return TransactionManager(db);
   });
   ```

3. **`deduplicationEngineProvider`**:
   ```dart
   final deduplicationEngineProvider = FutureProvider<DeduplicationEngine>((ref) async {
     final db = await ref.watch(appDatabaseProvider).database;
     return DeduplicationEngine(db);
   });
   ```

4. **`classificationRuleEngineProvider`**:
   ```dart
   final classificationRuleEngineProvider = FutureProvider<ClassificationRuleEngine>((ref) async {
     final db = await ref.watch(appDatabaseProvider).database;
     return ClassificationRuleEngine(db);
   });
   ```

5. **`ocrPipelineProvider`**:
   ```dart
   final ocrPipelineProvider = FutureProvider<OcrParsingPipeline>((ref) async {
     final dedup = await ref.watch(deduplicationEngineProvider.future);
     final ruleEngine = await ref.watch(classificationRuleEngineProvider.future);
     return OcrParsingPipeline(
       dedupEngine: dedup,
       classificationEngine: ruleEngine,
     );
   });
   ```

---

### 4.2 R2: Transactions Screen & Dashboard Specifications

#### 1. Header Monthly Accounting Card:
- Displays three core financial figures calculated from active ledger (`deleted_at IS NULL`):
  - **本月总支出** = $\sum \text{amount\_minor}$ where `type = 'expense'`.
  - **本月总退款** = $\sum \text{amount\_minor}$ where `type = 'refund'`.
  - **本月净支出** = 本月总支出 $-$ 本月总退款.
- Displays transaction count badge (e.g. `共 45 笔`).
- Month switcher controls: Left button (previous month), Center title (e.g. `2026年10月`, clickable to open month-picker modal), Right button (next month).

#### 2. Daily Aggregated Grouping:
- Grouping key: `occurred_on` (format: `YYYY-MM-DD`).
- Sorted chronologically descending (newest date at top).
- Section Header:
  - Left: Localized date text, e.g. "10月23日 今天" or "10月21日 星期三".
  - Right: Daily subtotal = $\sum \text{expense} - \sum \text{refund}$. Formatted in Currency (e.g. "支出 ¥142.50").

#### 3. Transaction Item Tile:
- **Leading**: Circle avatar with Category icon and color styling.
- **Title**: Merchant display name (`merchant_normalized ?? merchant_raw`).
- **Subtitle**: Formatted time (`occurred_at` time component or empty if precision is 'day') + payment channel capsule (e.g. "微信支付") + project tag capsule (if `project_id` exists).
- **Trailing**: Signed currency amount:
  - Expense: `-¥45.00` (standard theme text color).
  - Income: `+¥5,000.00` (green accent color).
  - Refund: `+¥30.00` with "[退款]" tag (amber/teal color).
  - Transfer: `¥200.00` with "[转账]" tag (neutral color).
- **Dismissible Interaction**:
  - Horizontal swipe (left): triggers `softDeleteTransaction(txId)`.
  - SnackBar appears immediately with "已移入回收站" and "[撤销]" button.
  - Undo restores transaction via `restoreFromTrash(txId)`.

#### 4. Filter Bottom Sheet / Drawer:
- Filter parameters:
  - Account: All, or specific Account ID.
  - Project: All, or specific Project ID.
  - Category: All, or specific Category ID.
  - Transaction Type: All, Expense, Income, Refund, Transfer.
  - Date Range: Start Date to End Date.
  - Keyword: Substring search across `merchant_raw`, `merchant_normalized`, `note`.
- Filter Reset button resets all fields to null/defaults.
- Main screen shows active filter chip bar when any filter is active.

#### 5. 30-Day Recycling Bin:
- Route: `/recycling-bin`.
- Shows items where `deleted_at IS NOT NULL` ordered by `deleted_at DESC`.
- Each item shows days remaining before purge: $\max(0, 30 - \text{daysSinceDeleted})$.
- Actions per row: "恢复" (`restoreTransaction`), "彻底删除" (`permanentDeleteTransaction` with confirmation).
- Bottom Action: "清空回收站" (`purgeExpiredTrash(retentionDays: 0)`).

---

### 4.3 R3: Draft Confirmation Screen & OCR BoundingBox Overlay

#### 1. Coordinate Normalization & Aspect Ratio Viewport Math:

The native OCR engines return `OcrBoundingBox` with normalized coordinates in the range $[0.0, 1.0]$ where $(0.0, 0.0)$ is the top-left corner of the original image:
$$\text{normalized: } (left, top, width, height) \in [0.0, 1.0]$$

In Flutter, the screenshot preview container has dimensions $(W_{viewport}, H_{viewport})$. The original image has natural pixel dimensions $(W_{img}, H_{img})$.

When rendering with `BoxFit.contain`:
1. Calculate scale factor $S$:
   $$S = \min\left(\frac{W_{viewport}}{W_{img}}, \frac{H_{viewport}}{H_{img}}\right)$$
2. Calculate actual rendered image dimensions:
   $$W_{rendered} = W_{img} \times S$$
   $$H_{rendered} = H_{img} \times S$$
3. Calculate letterbox/pillarbox offsets:
   $$dx = \frac{W_{viewport} - W_{rendered}}{2.0}$$
   $$dy = \frac{H_{viewport} - H_{rendered}}{2.0}$$
4. Clamping bounds:
   $$left_{clamped} = \mathrm{clamp}(left, 0.0, 1.0)$$
   $$top_{clamped} = \mathrm{clamp}(top, 0.0, 1.0)$$
   $$width_{clamped} = \mathrm{clamp}(width, 0.0, 1.0 - left_{clamped})$$
   $$height_{clamped} = \mathrm{clamp}(height, 0.0, 1.0 - top_{clamped})$$
5. Rendered screen pixel coordinates for bounding box:
   $$X_{screen} = dx + (left_{clamped} \times W_{rendered})$$
   $$Y_{screen} = dy + (top_{clamped} \times H_{rendered})$$
   $$W_{screen} = width_{clamped} \times W_{rendered}$$
   $$H_{screen} = height_{clamped} \times H_{rendered}$$

#### 2. Visual Overlay & Tap-to-Backfill:
- Highlights rendered via `Positioned` widgets or `CustomPainter`.
- Colors:
  - Green (`Colors.green.withOpacity(0.25)`): detected Amount line.
  - Purple (`Colors.purple.withOpacity(0.25)`): detected Merchant line.
  - Blue (`Colors.blue.withOpacity(0.15)`): general text lines.
- Tapping a bounding box opens quick action bottom sheet:
  - "填入商户名" $\rightarrow$ sets merchant field.
  - "填入实付金额" $\rightarrow$ parses line with `AmountParser`/`CurrencyUtils` and sets amount.
  - "填入备注" $\rightarrow$ sets note.

#### 3. Smart Form Components:
- **Amount Field**:
  - Displays formatted amount in 36pt font (e.g. `¥ 48.00`).
  - Tapping opens numeric input keypad.
  - Cents precision: strictly converts input to integer minor units ($amountMinor = \mathrm{round}(yuan \times 100)$).
- **Merchant Field**:
  - TextFormField with clear button.
  - Displays normalized merchant hint if normalized from raw name.
- **Suggested Category Card**:
  - Highlights top recommended category.
  - Shows category icon, name, and matching tier badge:
    - `[规则匹配 #100]`
    - `[历史习惯 90%]`
    - `[关键词: 咖啡]`
    - `[AI 推荐]`
    - `[系统默认]`
  - Clicking opens category picker modal.
- **Payment Channel Selector**: Chips for WeChat Pay, Alipay, UnionPay, Cash, Other.
- **Transaction Type Selector**: SegmentedButton (支出, 收入, 退款, 转账).
- **Date & Time Picker**: Displays extracted date/time or "建议今天".

#### 4. Deduplication Alert State Machine & Dialogs:
- **Tier 3 Collision with Active Transaction**:
  - Condition: `tier3.isMatched == true && tier3.isInTrash == false`.
  - UI State: Red alert banner displayed at top.
  - Action: "确认入账" button is **disabled**.
  - Provides button: "查看已有账目" (navigates to existing transaction).
- **Tier 3 Collision with 30-Day Trash Bin**:
  - Condition: `tier3.isMatched == true && tier3.isInTrash == true`.
  - UI State: Amber alert banner displayed.
  - Action: Prompts dialog with "从回收站恢复原账目" button (executing `TransactionManager.restoreFromTrash`).
- **Tier 4 Heuristic 24h Duplicate Alert**:
  - Condition: `tier4.hasSuspectedDuplicates == true`.
  - UI State: Amber banner on draft review form.
  - Action: Clicking "确认入账" triggers confirmation dialog:
    - Title: "疑似重复交易提示"
    - Body: "检测到 24 小时内已存在相同商户和金额的记录（例如：2026-10-22 12:30 星巴克 ¥38.00）。这是否是同一笔交易？"
    - Option A: "这是同一笔（放弃录入）" $\rightarrow$ calls `discardDraft`.
    - Option B: "这是另一笔合法消费（如连续点单，确认入账）" $\rightarrow$ proceeds with `commitDraft`.

#### 5. One-Click Commit State Machine:
- Transitions capture job state from `NEEDS_REVIEW` to `COMMITTED`.
- In a single SQLite transaction:
  1. Verifies draft state == `NEEDS_REVIEW` and `saved_transaction_id` is null.
  2. Inserts into `transactions`.
  3. Inserts into `transaction_metadata` (platform transaction no, completeness).
  4. Inserts into `confirmed_identifiers` (if COMPLETE).
  5. Inserts into `refund_links` (if refund with original expense linked).
  6. Updates `drafts.saved_transaction_id = tx.id`.
  7. Updates `capture_jobs.state = 'COMMITTED'`.
  8. Triggers `ClassificationRuleEngine.learnRuleFromUserAction()` if category confirmed/changed.
  9. Asynchronously deletes raw capture image file from sandbox.
  10. Triggers reactive refresh on `transactionsListNotifierProvider`.

---

### 4.4 R4: Rules & Accounts Configuration Center

#### 1. 6-Tier Classification Rules Center:
- Tier visual hierarchy display:
  1. Tier 1: User Manual Explicit Choice
  2. Tier 2: Custom Active Rules (user managed)
  3. Tier 3: Historical Identical Merchant Transactions
  4. Tier 4: Built-in Chinese Keyword Dictionary (150+ keywords)
  5. Tier 5: Optional AI Recommendation
  6. Tier 6: Default Fallback (`cat_other`)
- **Custom Rules Management**:
  - `ReorderableListView` displaying active custom rules.
  - Sorted by `RuleMatcher.compareRules`: `priority DESC`, `merchantPattern.length DESC`, `createdAt DESC`.
  - Dragging items updates priorities monotonically.
  - Switch toggle updates `classification_rules.enabled = 1 / 0`.
  - "新建规则" Dialog: Pattern (supports wildcard `*`), Channel, Category picker, Project picker, Priority number.
  - "一键重新匹配待确认草稿": re-evaluates all drafts in `NEEDS_REVIEW` without touching committed transactions.

#### 2. Accounts Configuration:
- Lists all accounts: Cash, Debit Card, Credit Card, E-Wallet, Other.
- Computes real-time balance per account from SQLite transactions:
  $$\text{Balance} = \sum \text{Income} - \sum \text{Expense} + \sum \text{Refund} + \sum \text{Transfer In} - \sum \text{Transfer Out}$$
- Add Account dialog: Name, Kind, Card Last 4 digits.
- Soft-archive account (`archived_at`): hidden from draft form dropdowns, preserved in historical ledger.

#### 3. Projects Configuration:
- Lists projects (e.g. "2026云南旅行", "新房装修").
- Displays aggregated spend per project.
- Add Project / Archive Project.

#### 4. Refund Link Picker Dialog (Respecting `refund_links ON DELETE CASCADE`):
- Accessible when transaction type is `refund`.
- Search modal listing active expense transactions (`type = 'expense' AND deleted_at IS NULL`).
- User selects an expense transaction $\rightarrow$ inserts link into `refund_links`.
- Foreign key cascade guarantee: If the original expense is permanently purged, SQLite automatically cascades and deletes the `refund_links` row, while the refund transaction remains in `transactions` as an unlinked standalone refund.

---

### 4.5 R5: Widget Testing & Verification Strategy

| Test Suite File | Key Scenarios Tested | Assertions & Invalidation Conditions |
|---|---|---|
| `test/presentation/transactions_screen_test.dart` | 1. Renders monthly summary card with exact minor-to-yuan conversion.<br>2. Groups transactions by date in descending order with daily subtotals.<br>3. Swiping left triggers soft-delete and shows SnackBar.<br>4. Tapping "撤销" restores transaction.<br>5. Multi-dimensional filter filters list accurately. | `find.text('¥ 3,450.00')` matches summary.<br>Daily subtotal matches sum of expenses minus refunds.<br>Soft-deleted row disappears from list.<br>Undo restores row. |
| `test/presentation/draft_confirmation_screen_test.dart` | 1. Bounding box coordinate transformation calculates correct pixel rect under 16:9, 19.5:9, and 1:1 viewports without distortion.<br>2. Out-of-bounds coordinates are safely clamped.<br>3. Tapping bounding box backfills merchant and amount text controllers.<br>4. Smart form amount input validates positive cents.<br>5. Commit button triggers atomic `commitDraft`. | Bounding box rect left/top/width/height match expected formulas within 0.1px tolerance.<br>Tapping line sets `merchantController.text` and `amountController.text`.<br>Commit transitions job state to COMMITTED. |
| `test/presentation/deduplication_dialog_test.dart` | 1. Tier 3 duplicate platform transaction number displays red blocking alert and disables commit button.<br>2. Tier 3 duplicate in trash bin displays alert with "从回收站恢复" button.<br>3. Tier 4 heuristic 24h duplicate displays confirmation dialog with "这是另一笔" vs "放弃草稿". | Red banner visible; commit button `onPressed == null`.<br>Trash dialog restore button calls `restoreFromTrash`.<br>Clicking "这是另一笔" allows commit. |
| `test/presentation/rules_configuration_screen_test.dart` | 1. Rules list renders ordered by priority DESC.<br>2. Toggling switch updates `enabled` column.<br>3. Dragging items updates priority order.<br>4. Re-match trigger re-evaluates drafts in `NEEDS_REVIEW` without altering committed transactions. | Reordered list persists new priorities.<br>Switch toggle updates DB.<br>Committed transactions maintain existing categories. |
| `test/presentation/refund_link_picker_test.dart` | 1. Search dialog filters expense transactions.<br>2. Selecting expense saves row in `refund_links`.<br>3. Permanently deleting original expense cascades `refund_links` without deleting refund transaction. | Refund link record created in DB.<br>After deleting original expense, refund row remains in `transactions` while `refund_links` row is gone. |

---

## 5. Verification Commands & Acceptance Checklist

To verify Milestone M2 implementation against this specification:

```bash
# 1. Verify Dart static analysis (0 errors, 0 warnings, 0 lints)
flutter analyze

# 2. Run the entire automated test suite (including existing 297 tests + new M2 widget tests)
flutter test
```

### Acceptance Checklist:
- [x] All 5 requirements (R1–R5) thoroughly probed and documented.
- [x] Features Discovered table populated with 45+ comprehensive feature entries.
- [x] Edge Cases table populated with 15 boundary and stress cases.
- [x] Normalized coordinate viewport mapping mathematics rigorously specified.
- [x] Deduplication 4-tier alert dialog and blocking rules unambiguously defined.
- [x] SQLite cascading constraints (`refund_links ON DELETE CASCADE`) and soft-delete retention rules verified against database schema.
