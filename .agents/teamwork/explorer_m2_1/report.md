# SingWallet Milestone M2: Core Engine & Data Layer Investigation Report

**Date**: 2026-10-23  
**Investigator**: `explorer_m2_1` (`teamwork_preview_explorer`)  
**Target Repository**: `c:\Other\Projects\singwallet`  
**Test Baseline**: 297/297 Tests Passing (100% Pass, Exit Code 0), `flutter analyze` 0 issues  

---

## 1. Executive Summary & System Overview

SingWallet has completed Milestones M0 (Scaffold & Native Pigeon Bridge) and M1 (SQLite Core Data Layer, 4-Tier Deduplication, 8-Stage OCR Pipeline, 6-Tier Classification Rule Engine). All 297 backend unit and adversarial tests pass without failures, and the Dart codebase passes `flutter analyze` with 0 issues.

For Milestone M2 (Core Business UI & Riverpod State Bus), the underlying domain and data layers provide robust atomic operations, mathematical rigor for currency storage, and complete data modeling. However, **the data layer currently does not expose query abstractions or reactive streams for UI consumption**. All existing query logic is embedded within transaction lifecycle methods (`TransactionManager`), deduplication checks (`DeduplicationEngine`), classification checks (`ClassificationRuleEngine`), and soft delete utilities (`SoftDeleteManager`).

To deliver M2, a clean Repository / Service layer and Riverpod Notifier architecture must be built on top of the existing SQLite database and domain engines.

---

## 2. Dependencies & `pubspec.yaml` Status

Inspection of `pubspec.yaml` shows:
```yaml
environment:
  sdk: ">=3.2.0 <4.0.0"
  flutter: ">=3.16.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  sqflite: ^2.3.3+1
  sqflite_common_ffi: ^2.3.3
  crypto: ^3.0.3
  intl: ^0.19.0
  path: ^1.9.0
  path_provider: ^2.1.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  pigeon: ^22.7.0
```

### Dependency Findings:
1. **`flutter_riverpod: ^2.5.1`** is already present in `pubspec.yaml`, ready for immediate use. `main.dart` already wraps the application root in `ProviderScope`.
2. **`intl: ^0.19.0`** is installed for date formatting, numbers, and localization.
3. **`sqflite` & `sqflite_common_ffi`**: FFI initialization for desktop testing is completely established in `AppDatabase.initializeFfi()`.
4. No additional external packages are needed for M2 requirements (standard Flutter Material 3, Riverpod 2.5, SQLite, and Pigeon are fully available).

---

## 3. Exact Public APIs, Data Entities & Streams in `AppDatabase` & `TransactionManager`

### 3.1 Data Entities & SQLite Schema (`lib/data/database/schema.dart`)
There are **12 core database tables** and **11 performance B-tree indices** defined in `AppSchema`:

| # | Table Name | Entity Model | Primary Key & Key Constraints |
|---|---|---|---|
| 1 | `capture_jobs` | `CaptureJob` | `id TEXT PRIMARY KEY`, `state TEXT NOT NULL`, `content_hash TEXT` |
| 2 | `drafts` | `Draft` | `id TEXT PRIMARY KEY`, `capture_id TEXT UNIQUE` (FK -> `capture_jobs.id ON DELETE CASCADE`) |
| 3 | `accounts` | `Account` | `id TEXT PRIMARY KEY`, `kind TEXT NOT NULL` (`cash`, `debit_card`, `credit_card`, `e_wallet`, `other`) |
| 4 | `categories` | `Category` | `id TEXT PRIMARY KEY`, `parent_id` (FK -> `categories.id ON DELETE SET NULL`), `applicable_type TEXT` (`expense`, `income`, `both`), `sort_order INTEGER` |
| 5 | `projects` | `Project` | `id TEXT PRIMARY KEY`, `name TEXT NOT NULL`, `archived_at TEXT` |
| 6 | `tags` | `Tag` | `id TEXT PRIMARY KEY`, `name TEXT NOT NULL` |
| 7 | `transactions` | `TransactionEntry` | `id TEXT PRIMARY KEY`, `CHECK (amount_minor > 0)`, `origin_draft_id TEXT UNIQUE`, FK -> `categories(id) ON DELETE RESTRICT`, FK -> `accounts(id) ON DELETE SET NULL`, FK -> `projects(id) ON DELETE SET NULL` |
| 8 | `transaction_metadata` | `TransactionMetadata` | `transaction_id TEXT PRIMARY KEY` (FK -> `transactions.id ON DELETE CASCADE`) |
| 9 | `transaction_tags` | `TransactionTag` | `(transaction_id, tag_id)` COMPOUND PK (both FK ON DELETE CASCADE) |
| 10 | `refund_links` | `RefundLink` | `refund_transaction_id TEXT PRIMARY KEY` (FK -> `transactions.id ON DELETE CASCADE`), `original_expense_id TEXT` (FK -> `transactions.id ON DELETE CASCADE`) |
| 11 | `classification_rules` | `ClassificationRule` | `id TEXT PRIMARY KEY`, `priority INTEGER NOT NULL DEFAULT 100`, `enabled INTEGER NOT NULL DEFAULT 1`, FK -> `categories.id ON DELETE CASCADE` |
| 12 | `confirmed_identifiers` | `ConfirmedIdentifier` | `(namespace, identifier_type, complete_value, stable_event_kind)` COMPOUND PK (FK -> `transactions.id ON DELETE CASCADE`) |

#### Key Database Schema Rules:
- **Currency Storage**: `amount_minor` strictly stored in cents (`CHECK (amount_minor > 0)`). 0 and negative values are rejected at the database engine level.
- **Foreign Key Enforcement**: `PRAGMA foreign_keys = ON;` is strictly enforced on all connections. Attempting to insert a transaction with a non-existent `category_id` will trigger a SQLite foreign key error!
- **Indices Available**:
  - `idx_tx_occurred_on` on `transactions(occurred_on)`
  - `idx_tx_deleted_at` on `transactions(deleted_at)`
  - `idx_tx_category` on `transactions(category_id)`
  - `idx_tx_project` on `transactions(project_id)`
  - `idx_tx_account` on `transactions(account_id)`
  - `idx_confirmed_identifiers_tx` on `confirmed_identifiers(transaction_id)`
  - `idx_refund_original` on `refund_links(original_expense_id)`

---

### 3.2 `AppDatabase` Class (`lib/data/database/app_database.dart`)
`AppDatabase` is a thread-safe SQLite connection lifecycle manager.

- **Singleton instance**: `AppDatabase.instance`
- **Public APIs**:
  ```dart
  static void initializeFfi()
  Future<Database> get database async
  Future<Database> open({String? customPath})
  static Future<Database> openInMemory({DatabaseFactory? factory})
  Future<void> close()
  @visibleForTesting void setDatabaseFactory(DatabaseFactory factory)
  @visibleForTesting Future<void> reset()
  ```
- **Streams / Watches**: **None**.

---

### 3.3 `TransactionManager` Class (`lib/data/database/transaction_manager.dart`)
`TransactionManager` manages atomic financial commits, soft deletion, trash purging, and monthly calculations.

- **Constructor**: `TransactionManager([AppDatabase? db])`
- **Request Payload**:
  ```dart
  class CommitDraftRequest {
    final TransactionEntry transaction;
    final TransactionMetadata? metadata;
    final List<String>? tagIds;
    final ConfirmedIdentifier? identifier;
    final String? originalExpenseId;
    const CommitDraftRequest({...});
  }
  ```
- **Public Methods**:
  1. `Future<TransactionEntry> commitDraft(CommitDraftRequest request, {DatabaseExecutor? customExecutor})`
     - Atomically commits a draft across 7 core tables:
       1. Verifies draft existence and parent `capture_jobs.state == 'NEEDS_REVIEW'`.
       2. Verifies `origin_draft_id` idempotence (rejects duplicate commits).
       3. Queries `confirmed_identifiers` to check for active duplicates (`HardDuplicateException`) or 30-day trash duplicates (`TrashBinCollisionException`).
       4. Inserts into `transactions`.
       5. Inserts into `transaction_metadata` (if provided).
       6. Inserts into `transaction_tags` (if provided).
       7. Inserts into `confirmed_identifiers` (if provided).
       8. Inserts into `refund_links` (if `tx.type == 'refund'` and `originalExpenseId` provided).
       9. Updates `drafts.saved_transaction_id = tx.id`.
       10. Updates `capture_jobs.state = 'COMMITTED'`.
  2. `Future<void> discardDraft(String draftId)`:
     - Finds draft `capture_id`, transitions `capture_jobs` state to `DISCARDED`.
  3. `Future<bool> softDeleteTransaction(String transactionId, {DateTime? deletedAt, DatabaseExecutor? customExecutor})`:
     - Sets `transactions.deleted_at = now`, preserving all relations and identifiers for 30-day trash retention.
  4. `Future<bool> restoreFromTrash(String transactionId, {String? targetDraftId, DateTime? restoredAt, DatabaseExecutor? customExecutor})`:
     - Clears `transactions.deleted_at = null`. If `targetDraftId` provided, links `drafts.saved_transaction_id` and sets `capture_jobs.state = 'COMMITTED'`.
  5. `Future<bool> permanentDeleteTransaction(String transactionId, {DatabaseExecutor? customExecutor})`:
     - Hard deletes from `transactions`. Foreign key cascades delete metadata, tags, and confirmed identifiers. If it was an original expense, removes refund link while preserving refund transaction.
  6. `Future<int> purgeExpiredTrash({int retentionDays = 30, DateTime? referenceTime, DatabaseExecutor? customExecutor})`:
     - Hard deletes all transactions where `deleted_at < cutoff`.
  7. `Future<MonthlyAccountingSummary> getMonthlySummary(String yearMonth, {DatabaseExecutor? customExecutor})`:
     - Calculates `totalExpenseMinor`, `totalRefundMinor`, `netExpenseMinor`, and `transactionCount` for date range `[YYYY-MM-01, YYYY-MM-31]` where `deleted_at IS NULL`.
- **Streams / Watches**: **None**.

---

### 3.4 `SoftDeleteManager` Class (`lib/data/database/soft_delete_manager.dart`)
Utility class used internally by `TransactionManager`:
- `softDeleteTransaction(DatabaseExecutor db, String transactionId, {DateTime? deletedAt})`
- `restoreTransaction(DatabaseExecutor db, String transactionId, {DateTime? restoredAt})`
- `permanentDeleteTransaction(DatabaseExecutor db, String transactionId)`
- `purgeExpiredTrash(DatabaseExecutor db, {int retentionDays = 30, DateTime? referenceTime})`
- `getTrashBinTransactions(DatabaseExecutor db)` -> `Future<List<Map<String, Object?>>>`
- `calculateMonthlySummary(DatabaseExecutor db, {required String startDate, required String endDate})` -> `Future<MonthlyAccountingSummary>`

---

### 3.5 `CaptureJobStateMachine` Class (`lib/data/database/state_machine.dart`)
- **Lifecycle States**: `imported` -> `recognizing` -> `needsReview` -> `committed` / `discarded` (plus `failed`).
- **Public Methods**:
  - `bool canTransition(CaptureJobState from, CaptureJobState to)`
  - `Set<CaptureJobState> allowedNextStates(CaptureJobState current)`
  - `Future<void> transition(DatabaseExecutor db, String jobId, CaptureJobState targetState, {DateTime? timestamp})`
  - `Future<int> recoverLingeringJobs(DatabaseExecutor db, {int maxAttempts = 3, DateTime? recoveryTimestamp})`

---

## 4. Existing Query Methods vs. Missing Queries Required for M2

### 4.1 What Exists Today
- Fetching single draft's `saved_transaction_id`, `capture_id`, and `state` inside `TransactionManager.commitDraft()` and `discardDraft()`.
- Checking single platform identifier in `confirmed_identifiers` table.
- Fetching trash bin transactions (`SoftDeleteManager.getTrashBinTransactions(db)` returning raw `Map`).
- Monthly expense and refund aggregation (`SoftDeleteManager.calculateMonthlySummary()`).
- Active classification rules (`ClassificationRuleEngine._matchCustomRules()`).
- Historical transactions for merchant category mapping (`ClassificationRuleEngine._matchHistory()`).

### 4.2 Missing Queries Required for M2 UI & Providers

To satisfy Requirements R1 through R4, the following queries must be implemented in a dedicated repository/service layer:

#### 1. Transactions Ledger & Filtering (`TransactionRepository`)
- **`getTransactions({TransactionFilter? filter})`**:
  - Filter parameters:
    - `String? startDate`, `String? endDate` (`occurred_on BETWEEN ? AND ?`)
    - `String? accountId` (`account_id = ?`)
    - `String? projectId` (`project_id = ?`)
    - `String? categoryId` (`category_id = ?`)
    - `String? type` (`type = ?` e.g., 'expense', 'income', 'refund', 'transfer')
    - `String? keyword` (`merchant_raw LIKE ? OR note LIKE ?`)
    - `bool inTrash = false` (`deleted_at IS NULL` vs `deleted_at IS NOT NULL`)
  - Order: `ORDER BY occurred_on DESC, created_at DESC`
  - Return: `List<TransactionWithDetails>` (joined with category name/icon, account name, project name, refund status, and tags).
- **`getTransactionDetail(String id)`**:
  - Returns `TransactionEntry` + `TransactionMetadata` + `List<Tag>` + linked refund info.
- **`getMonthlyDashboard(String yearMonth)`**:
  - In addition to expense and refund, **income must be calculated**:
    - `total_income = SUM(amount_minor) WHERE type = 'income' AND deleted_at IS NULL`
    - `total_expense = SUM(amount_minor) WHERE type = 'expense' AND deleted_at IS NULL`
    - `total_refund = SUM(amount_minor) WHERE type = 'refund' AND deleted_at IS NULL`
    - `net_balance = total_income - (total_expense - total_refund)`
- **`getExpenseCandidatesForRefund({String? keyword, int limit = 50})`**:
  - Queries `transactions` where `type = 'expense' AND deleted_at IS NULL` for the refund link association modal.

#### 2. Screenshot Drafts Queue (`DraftRepository`)
- **`getPendingDrafts()`**:
  - Queries `drafts d JOIN capture_jobs cj ON d.capture_id = cj.id WHERE cj.state = 'NEEDS_REVIEW' AND d.saved_transaction_id IS NULL ORDER BY cj.created_at DESC`.
  - Deserializes JSON fields into `ParsedDraftResult`.
- **`getDraftById(String draftId)`**:
  - Returns full draft, raw capture job image path, parsed candidate fields, and visual evidence coordinates.

#### 3. Accounts & Projects Management (`AccountRepository` & `ProjectRepository`)
- **`getAccounts({bool includeArchived = false})`**:
  - Returns `List<Account>` where `archived_at IS NULL` (or all if `includeArchived`).
- **`getAccountBalances()`**:
  - Aggregates income, expense, and transfers per account to compute live balances.
- **`createAccount(Account account)`, `updateAccount(Account account)`, `archiveAccount(String id)`**.
- **`getProjects({bool includeArchived = false})`**, **`createProject(Project project)`, `updateProject(Project project)`, `archiveProject(String id)`**.

#### 4. Categories Management (`CategoryRepository`)
- **`getCategories({bool includeArchived = false})`**:
  - Returns `List<Category>` ordered by `sort_order ASC, name ASC`.
- **Default Database Seeding**:
  - **Crucial Finding**: `AppSchema.createTablesStatements` creates empty tables. Because `transactions.category_id` has `FOREIGN KEY(...) REFERENCES categories(id) ON DELETE RESTRICT`, attempting to confirm a draft with `category_id = 'cat_food'` will fail unless `cat_food` exists in `categories`!
  - Therefore, M2 must provide a seed function to initialize default categories (`cat_food`, `cat_transport`, `cat_shopping`, `cat_entertainment`, `cat_utilities`, `cat_medical`, `cat_income`, `cat_other`) and default accounts (e.g. `acc_wechat`, `acc_alipay`, `acc_cash`, `acc_bank`).

#### 5. Classification Rules Management (`RuleRepository`)
- **`getAllRules()`**:
  - Queries `classification_rules` ordered by `priority DESC, created_at DESC`.
- **`createRule(ClassificationRule rule)`**, **`updateRule(ClassificationRule rule)`**, **`deleteRule(String ruleId)`**.
- **`toggleRuleEnabled(String ruleId, bool enabled)`**.
- **`updateRulePriorities(List<ClassificationRule> reordered)`**:
  - Updates priorities sequentially when user drags and drops rules in the UI.

---

## 5. DeduplicationEngine Deep Dive: Tier 3 & Tier 4 Checks and UI Invocation

### 5.1 Architecture of DeduplicationEngine (`lib/features/deduplication/deduplication_engine.dart`)
`DeduplicationEngine` accepts a `DatabaseExecutor` (such as `Database` or `Transaction`) and defines 4 detection tiers:
- **Tier 1 (Technical Idempotence)**: checks `transactions.origin_draft_id = ?`.
- **Tier 2 (Same-Image Hash)**: checks `capture_jobs.content_hash = ?`.
- **Tier 3 (Hard Platform Identifier)**: checks `confirmed_identifiers` compound key.
- **Tier 4 (Heuristic Fuzzy Match)**: checks identical amount + same merchant + 24-hour time window.

### 5.2 How Tier 3 Hard Deduplication Works
```dart
Future<Tier3Result> checkTier3PlatformId(PlatformIdentifier identifier) async
```
1. **Prerequisite**:
   - `identifier.isEligibleForHardDedup`: requires `completeness == IdentifierCompleteness.complete` and `completeValue.trim().isNotEmpty`.
   - If order number is masked (e.g. `420000****1234`), truncated, or unreliable, Tier 3 **skips** (returns `Tier3Result.miss()`).
2. **Query**:
   ```sql
   SELECT ci.transaction_id, t.id, t.type, t.amount_minor, t.currency,
          t.merchant_raw, t.occurred_on, t.deleted_at
   FROM confirmed_identifiers ci
   JOIN transactions t ON ci.transaction_id = t.id
   WHERE ci.namespace = ?
     AND ci.identifier_type = ?
     AND ci.complete_value = ?
     AND ci.stable_event_kind = ?
   LIMIT 1;
   ```
3. **Outcomes**:
   - **Active Duplicate (`isInTrash == false`)**: `Tier3Result.activeDuplicate(...)`.
     - In UI: **Hard Intercept / Blocking Alert**. The user cannot commit. Alert: *"该交易单号已在账本中存在（[商户名] ¥[金额]），不可重复记账。"*
   - **Trash Duplicate (`isInTrash == true`)**: `Tier3Result.trashBinDuplicate(...)`.
     - In UI: **Recovery Dialog**. The transaction exists in the 30-day recycling bin. Dialog: *"该交易已存在于回收站中，是否直接恢复？"* (Actions: [恢复账目], [取消]).

### 5.3 How Tier 4 Heuristic Fuzzy Matching Works
```dart
Future<Tier4Result> checkTier4Fuzzy({
  required String merchantRaw,
  String? merchantNormalized,
  required int amountMinor,
  required String occurredOn,
  String? occurredAt,
}) async
```
1. **Query Strategy**:
   - Filters candidate transactions in SQLite:
     ```sql
     SELECT id, type, amount_minor, currency, merchant_raw, merchant_normalized,
            occurred_on, occurred_at, payment_channel, category_id
     FROM transactions
     WHERE deleted_at IS NULL
       AND amount_minor = ?
       AND occurred_on BETWEEN ? AND ?;
     ```
   - Range: `[occurredOn - 1 day, occurredOn + 1 day]`.
2. **In-Memory Verification**:
   - Merchant match: `dbRaw == candidateRaw` OR `dbNorm == candidateNorm` OR `dbRaw == candidateNorm` OR `dbNorm == candidateRaw` (case-insensitive).
   - Time window verification: if both transactions have `occurred_at` (ISO-8601 timestamps), verifies `|t1 - t2| <= 24 hours`.
3. **Outcome**:
   - Returns `Tier4Result.suspected(ids: matchingIds, transactions: matchingRows)` when duplicates found, else `Tier4Result.clean()`.
   - In UI: **Secondary Confirmation Dialog**. Soft warning: *"检测到 24 小时内有相同商户与金额的记账记录（[商户名] ¥[金额]），是否确认继续保存？"* (Actions: [继续保存], [查看已有交易], [放弃]).

### 5.4 How UI Can Invoke DeduplicationEngine
In the Draft Confirmation Screen ViewModel:
```dart
final dedupResult = await deduplicationEngine.evaluate(
  originDraftId: draft.id,
  platformIdentifier: platformIdentifier,
  merchantRaw: merchantRaw,
  merchantNormalized: merchantNormalized,
  amountMinor: amountMinor,
  occurredOn: occurredOn,
  occurredAt: occurredAt,
);

if (dedupResult.tier3.isMatched) {
  if (dedupResult.tier3.isInTrash) {
    // Show Restore-From-Trash Prompt
  } else {
    // Show Blocking Error Dialog (Prevent Commit)
    return;
  }
} else if (dedupResult.tier4.hasSuspectedDuplicates) {
  // Show Warning Confirmation Dialog
  final proceed = await showDuplicateWarningDialog(context, dedupResult.tier4);
  if (!proceed) return;
}

// Proceed to commitDraft
await transactionManager.commitDraft(...);
```

---

## 6. OcrPipeline Results Architecture & Mapping to Draft Models

### 6.1 `OcrBoundingBox` and Coordinate Normalization
- Defined in `lib/core/native/native_bridge.g.dart`:
  ```dart
  class OcrBoundingBox {
    double left;   // [0.0, 1.0]
    double top;    // [0.0, 1.0] - origin is TOP-LEFT
    double width;  // [0.0, 1.0]
    double height; // [0.0, 1.0]
  }
  ```
- **Origin**: strictly at the **TOP-LEFT** corner $(0.0, 0.0)$, matching Flutter's coordinate system.
- Android ML Kit and iOS Vision coordinates are already converted into this normalized [0.0, 1.0] system by the native host implementations.
- Stage 1 of `OcrParsingPipeline` clamps all bounding boxes:
  - `cLeft = left.clamp(0.0, 1.0)`
  - `cTop = top.clamp(0.0, 1.0)`
  - `cWidth = width.clamp(0.0, 1.0 - cLeft)`
  - `cHeight = height.clamp(0.0, 1.0 - cTop)`

### 6.2 `FieldEvidence` Structure (`lib/features/recognition/models/field_evidence.dart`)
```dart
class FieldEvidence {
  final String rawText;
  final String matchedSubstring;
  final OcrBoundingBox boundingBox;
  final double? confidence;
  final String source; // 'ocr_extracted', 'rule_inferred', 'geometry_heuristic'
}
```
`FieldEvidence` captures the exact text line, matched substring, normalized bounding box, and OCR confidence.

### 6.3 8-Stage OCR Pipeline Assembly (`lib/features/recognition/ocr_pipeline.dart`)
1. **Stage 1: Input Normalization**: clamps all bounding box values to $[0.0, 1.0]$.
2. **Stage 2: Noise Filtering**: eliminates status bars, dynamic islands, home bars, and action buttons.
3. **Stage 3: Channel & Status Parsing**: detects `wechat`, `alipay`, `unionpay`, etc., and status `SUCCESS`, `REFUNDED`, etc.
4. **Stage 4: Amount Extraction**: extracts paid amount, original price, discount, and fee.
5. **Stage 5: Merchant Normalization**: strips store branch suffixes, extracts raw and normalized merchant name.
6. **Stage 6: Date/Time Extraction**: parses strict calendar dates and ISO timestamps.
7. **Stage 7: Order ID Extraction**: extracts platform and merchant order IDs and grades completeness (`complete`, `masked`, `truncated`, `unreliable`).
8. **Stage 8: Classification & Deduplication Evaluation**: queries `ClassificationRuleEngine` and `DeduplicationEngine`.

### 6.4 `ParsedDraftResult` and SQLite Serialization
`OcrParsingPipeline.process()` outputs `ParsedDraftResult`. When persisting to the SQLite `drafts` table via `result.toDraftEntity(...)`:
- **`candidate_fields`**: JSON string containing `amountMinor`, `currency`, `merchantRaw`, `merchantNormalized`, `occurredOn`, `occurredAt`, `paymentChannel`, `paymentStatus`, `platformTransactionNo`, `suggestedCategoryId`, `suggestedProjectId`, `confidenceScore`.
- **`field_evidence`**: JSON map of `{ 'amount': FieldEvidence, 'merchant': FieldEvidence, 'occurred_at': FieldEvidence, 'platform_transaction_no': FieldEvidence, ... }`.
- **`validation_issues`**: JSON array of validation issue code strings.
- **`duplicate_candidates`**: JSON array of matching transaction IDs.

### 6.5 Mapping to UI Canvas & Touch-to-Fill
In the Draft Confirmation Screen:
1. **Image Rendering**: The screenshot is rendered in a container with known aspect ratio $(W, H)$.
2. **Bounding Box Overlay**: An overlay widget maps normalized $[0.0, 1.0]$ coordinates to canvas pixel coordinates:
   $$\text{rect} = \text{Rect.fromLTWH}(box.left \times W, box.top \times H, box.width \times W, box.height \times H)$$
3. **Interactive Touch-to-Fill**:
   - Each detected text box (from `fieldEvidence.values` or `OcrDocument.lines`) is drawn with a semi-transparent highlight (e.g. `Colors.purple.withOpacity(0.2)`).
   - Tapping a text box opens a context menu or directly populates either the **Merchant Name** or **Amount** input field based on content type.

---

## 7. Architectural Blueprint for Milestone M2

### 7.1 Riverpod State Architecture
```
┌───────────────────────────────────────────────────────────┐
│                    Presentation Layer                     │
│  TransactionsScreen  DraftConfirmScreen  RulesAccounts    │
└───────────────▲─────────────────▲─────────────────▲───────┘
                │                 │                 │
┌───────────────┴─────────────────┴─────────────────┴───────┐
│               Riverpod Notifiers & ViewModels             │
│  - transactionsNotifierProvider (StateNotifier/AsyncNotifier) │
│  - draftsQueueNotifierProvider                            │
│  - accountsNotifierProvider                               │
│  - categoriesNotifierProvider                             │
│  - classificationRulesNotifierProvider                    │
│  - transactionFilterProvider                              │
└───────────────▲─────────────────▲─────────────────▲───────┘
                │                 │                 │
┌───────────────┴─────────────────┴─────────────────┴───────┐
│               Repository & Domain Layer                   │
│  - TransactionRepository (filtering, CRUD, soft-delete)  │
│  - DraftRepository (pending drafts, detail parsing)       │
│  - AccountRepository & CategoryRepository (hierarchies)   │
│  - RuleRepository (drag-and-drop priority, matching)      │
│  - DeduplicationEngine & ClassificationRuleEngine         │
│  - TransactionManager & SoftDeleteManager                 │
└───────────────────────────────▲───────────────────────────┘
                                │
┌───────────────────────────────┴───────────────────────────┐
│                      SQLite Database                      │
│     AppDatabase.instance (WAL mode, PRAGMA foreign_keys)  │
└───────────────────────────────────────────────────────────┘
```

### 7.2 Database Seeding Recommendation
To prevent Foreign Key violations (`FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT`) when users confirm drafts or create transactions, an initial seeding routine should run on app startup if `categories` is empty:
- Default categories:
  - `cat_food`: 餐饮美食 (icon: `restaurant`)
  - `cat_transport`: 交通出行 (icon: `directions_subway`)
  - `cat_shopping`: 日用商超 (icon: `shopping_cart`)
  - `cat_entertainment`: 休闲娱乐 (icon: `sports_esports`)
  - `cat_utilities`: 水电账单 (icon: `bolt`)
  - `cat_medical`: 医疗保健 (icon: `medical_services`)
  - `cat_income`: 薪酬收入 (icon: `account_balance`)
  - `cat_other`: 其他支出 (icon: `category`)
- Default accounts:
  - `acc_wechat`: 微信支付 (`e_wallet`)
  - `acc_alipay`: 支付宝 (`e_wallet`)
  - `acc_cash`: 现金 (`cash`)
  - `acc_bank`: 银行卡 (`debit_card`)

### 7.3 Currency Display Formatting
All database transactions store `amount_minor` as integer cents.
Use `CurrencyUtils.centsToYuanString(tx.amountMinor)` to format display values (e.g. `2890` -> `¥28.90`), and `CurrencyUtils.parseToMinorUnits(input)` when user inputs or edits amounts in text fields.

---

## 8. Summary Table of Key Inspection Findings

| Topic | Current Status in Codebase | Required Action in M2 |
|---|---|---|
| **Riverpod** | `flutter_riverpod: ^2.5.1` installed; `ProviderScope` in `main.dart` | Build Notifiers for Transactions, Drafts, Categories, Accounts, Rules |
| **AppDatabase** | Thread-safe connection & DDL manager; no query helpers | Create repository layer for structured queries |
| **TransactionManager** | Atomic 7-table commit, soft delete, restore, monthly summary | Wire into Riverpod Notifiers and UI dialogs |
| **Streams / Watches** | None exist in database layer | Riverpod StateNotifiers manage reactivity and re-querying on mutation |
| **Ledger Queries** | Monthly expense/refund exists; filtering/income missing | Implement `TransactionRepository.getTransactions(...)` with multi-filters and income aggregation |
| **Deduplication** | 4-Tier engine fully implemented and tested | Draft Confirmation UI invokes Tier 3 (block/restore dialog) and Tier 4 (24h fuzzy warning dialog) |
| **OCR Results & Evidence** | `FieldEvidence` & `OcrBoundingBox` [0.0, 1.0] normalized; serialized in `Draft` | Build custom painter / interactive overlay widget for bounding boxes & touch-to-fill |
| **Category Seeding** | Schema has no seed data; foreign key RESTRICT is active | Implement database seeder for initial 8 default categories and 4 accounts |

---
*Report prepared for SingWallet Milestone M2 implementation team.*
