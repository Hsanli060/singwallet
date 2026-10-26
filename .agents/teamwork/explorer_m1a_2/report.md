# SingWallet Technical Specification Report: 4-Tier Deduplication & Atomic Commitment (M1-A)

**Target Milestone**: M1-A (Unified SQLite Data Layer & Core Ledger Transactions)  
**Author**: `explorer_m1a_2`  
**Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_2`  
**Parent Agent**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)  
**Mandatory Inputs Analyzed**:
- `ORIGINAL_REQUEST.md` (R2: Unified SQLite Data Layer & Transaction Management)
- `orchestrator_1/PROJECT.md` (F11-F16: 4-tier deduplication, transaction manager, state transitions)
- `spec_miner_survey_2/report.md` (DDL, cascade rules, indices, deduplication rules)
- `docs/跨平台架构与数据规范.md` (Sections 3 & 4: Schema, 4-tier deduplication flow, integer currency math)
- `docs/Android实现方案.md` & `docs/iOS实现方案.md` (Transaction boundaries, trash bin, refund handling)
- `test_docs_integrity.py` (Schema & constraint verification suite)

---

## 1. Executive Summary

Milestone M1-A establishes the foundational ledger integrity of SingWallet. Within this milestone, two critical subsystems are entrusted to this specification:
1. **The 4-Tier Deduplication Engine (`lib/features/deduplication/deduplication_engine.dart`)**:
   A multi-layered defense pipeline preventing double-booking, ghost duplicates, and race conditions, while supporting legitimate consecutive payments at the same merchant:
   - **Tier 1 (Technical Idempotence)**: `origin_draft_id UNIQUE` constraint & draft-to-transaction lookup.
   - **Tier 2 (Same-Image SHA-256 Check)**: Matches ingested image `content_hash` against `capture_jobs(content_hash)`.
   - **Tier 3 (Hard Platform Transaction ID Check)**: Exact match against the `confirmed_identifiers` table using compound PK `(namespace, identifier_type, complete_value, stable_event_kind)`. Strictly restricted to complete, unmasked IDs. Distinguishes active records from 30-day trash bin items.
   - **Tier 4 (Heuristic Fuzzy Matching)**: Soft duplicate warning for same merchant (raw/normalized) + identical `amount_minor` + within 24-hour window, populating `drafts.duplicate_candidates` without blocking legitimate consecutive transactions.
2. **The Atomic Draft Commitment Transaction Manager (`lib/data/database/transaction_manager.dart`)**:
   Guarantees strict ACID consistency during draft promotion to formal ledger entries:
   - Executes inside a single SQLite transaction (`db.transaction((txn) async { ... })`).
   - Atomically inserts into `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, and optional `refund_links`.
   - Atomically updates `drafts.saved_transaction_id` and sets `capture_jobs.state = 'COMMITTED'`.
   - Guarantees immediate, clean rollback on any constraint violation (`amount_minor <= 0`, duplicate ID, FK failure), leaving the draft in `NEEDS_REVIEW` and database clean.

---

## 2. Conceptual & Relational Model Mapping

The deduplication engine and transaction manager orchestrate operations across 7 core tables:

```text
  [capture_jobs] (id, content_hash, state, ...)
        │
        ▼ 1:1 (ON DELETE CASCADE)
     [drafts] (id, capture_id, validation_issues, duplicate_candidates, saved_transaction_id)
        │
        ▼ 1:1 (transactions.origin_draft_id UNIQUE, ON DELETE SET NULL)
  [transactions] (id, origin_draft_id, amount_minor, merchant_raw, occurred_on, occurred_at, deleted_at)
   ├── 1:1 (ON DELETE CASCADE) ──► [transaction_metadata]
   ├── N:M (ON DELETE CASCADE) ──► [transaction_tags] ◄── [tags]
   ├── 1:N (ON DELETE CASCADE) ──► [confirmed_identifiers] (Hard dedup index)
   └── 1:N (ON DELETE CASCADE) ──► [refund_links] (Unlinking without deleting refund)
```

### Relational Constraints Enforced
1. `transactions.amount_minor > 0`: SQLite CHECK constraint guarantees zero-amount and negative-amount transactions are rejected at the storage engine level.
2. `transactions.origin_draft_id UNIQUE`: Prevents a draft from spawning more than one formal transaction.
3. `confirmed_identifiers` Compound Primary Key `(namespace, identifier_type, complete_value, stable_event_kind)`: Enforces database-level uniqueness for complete platform order numbers.
4. `refund_links ON DELETE CASCADE` on `original_expense_id`: When the original expense is permanently deleted, the row in `refund_links` is cascade-deleted, but the refund transaction in `transactions` remains intact.
5. Foreign Key Enforcement: Every SQLite connection must execute `PRAGMA foreign_keys = ON;`.

### Performance Indices Utilized
- `idx_capture_jobs_hash`: `capture_jobs(content_hash)` — Accelerates Tier 2 same-image hash queries.
- `idx_capture_jobs_state`: `capture_jobs(state)` — Accelerates querying pending/review jobs.
- `idx_drafts_saved_tx`: `drafts(saved_transaction_id)` — Accelerates checking draft-to-transaction linkage.
- `idx_confirmed_identifiers_tx`: `confirmed_identifiers(transaction_id)` — Accelerates reverse lookup of identifiers for a transaction.
- `idx_tx_occurred_on`: `transactions(occurred_on)` — Accelerates Tier 4 fuzzy matching time range queries and monthly aggregations.
- `idx_tx_deleted_at`: `transactions(deleted_at)` — Accelerates active vs trash-bin filtering.

---

## 3. The 4-Tier Deduplication Engine

### 3.1 Overview of Decision Pipeline

```text
[新截图导入 / 草稿生成 / 入账提交]
     │
     ▼
[第 1 层：技术幂等性 (Tier 1: Technical Idempotence)]
   ├─ 检查: 重复 Intent / 任务重试 / 已存在 captureId / transactions.origin_draft_id
   └─ 命中: 返回现有交易 ID / 草稿 ID，避免重复建任务或重复记账
      │ 未命中
      ▼
[第 2 层：同图 SHA-256 检查 (Tier 2: Same-Image Hash Check)]
   ├─ 检查: capture_jobs.content_hash == 计算出的图片 SHA-256 (idx_capture_jobs_hash)
   └─ 命中: 提示用户该截图已导入过，定位到已有任务 / 草稿 / 账目
      │ 未命中
      ▼
[第 3 层：完整官方单号唯一检查 (Tier 3: Hard Platform Identifier Check)]
   ├─ 参与条件: identifier_completeness == 'COMPLETE' (打码/截断号严禁参与)
   ├─ 检查: confirmed_identifiers (namespace, type, complete_value, stable_event_kind)
   ├─ 命中 (活跃交易): 硬拦截！抛出 HardDuplicateException，展示已有流水，禁止重复记账
   └─ 命中 (回收站交易): 提示该交易在 30 天回收站内，支持一键恢复原 ID 记录
      │ 未命中
      ▼
[第 4 层：启发式模糊比对 (Tier 4: Heuristic Fuzzy Matching)]
   ├─ 检查: 同商户 (raw / normalized) + 同金额 (amount_minor) + 24小时内 (occurred_on/at)
   ├─ 命中: 软警告！填充 drafts.duplicate_candidates，添加 DUPLICATE_SUSPECTED 异常
   │         ├─ 用户操作 A:「查看已有记录」-> 用户放弃当前草稿
   │         └─ 用户操作 B:「确认这是另一笔交易」-> 正常放行入账（如连续买两杯同价咖啡）
   └─ 未命中: 正常生成待确认草稿 (NEEDS_REVIEW)
```

---

### 3.2 Tier 1: Technical Idempotence (技术幂等)

#### Objectives
1. Prevent duplicate job creation when Android Intent or iOS Shortcuts sends the same external capture trigger repeatedly.
2. Prevent duplicate transaction creation when a draft confirmation request is retried or sent concurrently.

#### Query & Logic
```sql
-- Check if a transaction has already been committed for this draft
SELECT id, type, amount_minor, merchant_raw, occurred_on, deleted_at
FROM transactions
WHERE origin_draft_id = ?
LIMIT 1;
```

#### Behavior & Output
- If found:
  - If `deleted_at IS NULL`: Returns `Tier1Result.hit(transactionId: row['id'], isTrash: false)`.
  - If `deleted_at IS NOT NULL`: Returns `Tier1Result.hit(transactionId: row['id'], isTrash: true)`.
- If not found: Returns `Tier1Result.miss()`.
- **Database Safety Net**: `transactions.origin_draft_id` is defined as `UNIQUE`. If two concurrent requests attempt to commit the same `origin_draft_id`, SQLite raises an `IntegrityError: UNIQUE constraint failed: transactions.origin_draft_id`. The second transaction will automatically fail and rollback.

---

### 3.3 Tier 2: Same-Image Hash Check (同图 SHA-256 检测)

#### Objectives
Prevent duplicate OCR processing and duplicate task pipeline creation when a user imports the identical screenshot file multiple times via Photo Picker, Share Extension, or Clipboard.

#### Hash Computation
The image SHA-256 hash `content_hash` is computed as a lowercase hex string (64 characters):
```dart
String computeContentHash(Uint8List imageBytes) {
  return sha256.convert(imageBytes).toString();
}
```
*(In Pigeon M0, `CaptureResult.contentHash` is generated natively or computed at ingestion).*

#### Query & Logic
```sql
-- Query capture_jobs using index idx_capture_jobs_hash
SELECT cj.id AS job_id, cj.state, cj.imported_at, cj.private_image_ref,
       d.id AS draft_id, d.saved_transaction_id,
       t.id AS transaction_id, t.deleted_at
FROM capture_jobs cj
LEFT JOIN drafts d ON d.capture_id = cj.id
LEFT JOIN transactions t ON (t.origin_draft_id = d.id OR t.id = d.saved_transaction_id)
WHERE cj.content_hash = ?
ORDER BY cj.created_at DESC
LIMIT 1;
```

#### Behavior & Output
- If match found:
  - `job_id`: Existing job ID.
  - `state`: Current state of existing job (`IMPORTED`, `RECOGNIZING`, `NEEDS_REVIEW`, `COMMITTED`, etc.).
  - `draft_id`: Associated draft ID if already parsed.
  - `transaction_id`: Associated ledger transaction ID if already committed.
  - `isTrash`: `true` if `t.deleted_at IS NOT NULL`.
- Action:
  - Prevents spawning a duplicate OCR pipeline.
  - UI can prompt: *"该截图已于 [imported_at] 导入过"*, and offer navigation directly to the existing draft or transaction.

---

### 3.4 Tier 3: Hard Platform Transaction Identifier Check (完整官方单号唯一检查)

#### Objectives
Definitively intercept duplicate payments and duplicate refunds based on globally unique platform transaction numbers (e.g., WeChat Pay 28-32 digit transaction number, Alipay 28-32 digit trade number).

#### Critical Business & Data Rules
1. **Strict Participation Filter (`identifier_completeness == COMPLETE`)**:
   - Only complete, unmasked, high-confidence identifiers may participate in Tier 3 check and insertion into `confirmed_identifiers`.
   - If `identifier_completeness` is `MASKED` (e.g., `420000****1234`), `TRUNCATED`, `UNRELIABLE`, or `NONE`:
     **STRICTLY FORBIDDEN** from querying Tier 3 as a hard duplicate blocker, and **MUST NEVER** be written to `confirmed_identifiers`.
     *Rationale*: A masked ID like `420000****1234` would falsely collide with thousands of completely unrelated transactions!
2. **Compound Scope**:
   - `namespace`: Platform identifier (`'wechat_pay'`, `'alipay'`, `'unionpay'`).
   - `identifier_type`: Identifier kind (`'platform_transaction_no'`, `'merchant_order_no'`). Note: Merchant order numbers must be scoped with merchant identifier; if unscoped, they must degrade to Tier 4.
   - `complete_value`: Full unmasked string.
   - `stable_event_kind`: `'payment'` or `'refund'`.
     *Rationale*: A refund transaction usually references the original payment order, but has its own refund platform transaction ID. Keeping `stable_event_kind` in the compound PK ensures that a refund event doesn't collide with the original payment event.
3. **Compound Primary Key in SQLite**:
   `PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind)`
   Any duplicate insert raises SQLite `IntegrityError`.

#### Query & Logic
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

#### Behavior & Output
- **Case 1: Hit Active Transaction (`deleted_at IS NULL`)**:
  - **HARD INTERCEPT**: Duplicate transaction detected in active ledger!
  - Draft validation adds `DUPLICATE_SUSPECTED`.
  - Transaction manager pre-commit check throws `HardDuplicateException`.
  - UI strictly blocks duplicate commitment and displays link to existing transaction.
- **Case 2: Hit Soft-Deleted Transaction (`deleted_at IS NOT NULL`)**:
  - Transaction exists in 30-day trash bin.
  - Returns `Tier3Result.trashBinDuplicate(existingTransaction)`.
  - UI prompts user: *"该交易已在回收站中，是否恢复？"*
  - User can restore the original transaction ID with 1-click restore.
- **Case 3: No Hit**:
  - Returns `Tier3Result.clean()`. Proceed to Tier 4.

---

### 3.5 Tier 4: Heuristic Fuzzy Matching (启发式模糊比对)

#### Objectives
Detect suspected duplicate entries when screenshots do not contain a complete platform transaction ID (e.g., summary notifications, partial receipts, scanned paper slips).

#### Matching Criteria
A transaction is flagged as a suspected duplicate if ALL three conditions hold:
1. **Merchant Match**:
   `LOWER(TRIM(tx.merchant_raw)) == LOWER(TRIM(candidate.merchant_raw))`
   OR (if `candidate.merchant_normalized` is present)
   `tx.merchant_normalized == candidate.merchant_normalized`.
2. **Identical Amount**:
   `tx.amount_minor == candidate.amount_minor`.
3. **Within 24-Hour Time Window (`AppConstants.fuzzyDedupWindow = Duration(hours: 24)`)**:
   Handling timestamp precision:
   - **Both have precise timestamps (`occurred_at`)**:
     Compare precise duration:
     `|candidate.occurredAt - tx.occurredAt| <= 24 hours (86,400,000 ms)`.
   - **Either transaction has only date (`occurred_on` with `event_time_precision == 'day'`)**:
     As mandated by `Android实现方案.md:467`:
     *"只有日期、没有时分秒时不能按分钟级时间窗口判断。"*
     Candidate range is $\pm 1$ calendar day:
     `candidate.occurredOn - 1 day <= tx.occurredOn <= candidate.occurredOn + 1 day`.
     *(Because a purchase on 2026-10-22 at 01:00 and 2026-10-21 at 23:00 are within 2 hours of each other)*.

#### Query & Logic
```sql
SELECT id, type, amount_minor, currency, merchant_raw, merchant_normalized,
       occurred_on, occurred_at, payment_channel, category_id
FROM transactions
WHERE deleted_at IS NULL
  AND amount_minor = ?
  AND (
    LOWER(TRIM(merchant_raw)) = LOWER(TRIM(?))
    OR (? IS NOT NULL AND merchant_normalized IS NOT NULL AND LOWER(TRIM(merchant_normalized)) = LOWER(TRIM(?)))
  )
  AND occurred_on BETWEEN ? AND ?;
```
*(Where date range parameters are `candidate.occurredOn - 1 day` and `candidate.occurredOn + 1 day`).*

In Dart memory:
If both transactions have precise `occurred_at` timestamps, calculate the exact `difference.abs() <= Duration(hours: 24)`. If both have timestamps and the difference exceeds 24 hours, the candidate is discarded.

#### Soft Duplicate Behavior & Legitimate Consecutive Purchases
- **NON-BLOCKING**: Tier 4 is a **soft warning**, NEVER a hard block!
- Populates `drafts.duplicate_candidates` with list of matching transaction IDs (`["tx_123", ...]`).
- Adds validation issue `DUPLICATE_SUSPECTED` to `drafts.validation_issues`.
- **Handling Legitimate Double Purchases (同店同金额连续买两次)**:
  - Example: User buys two cups of coffee at Starbucks for 28.00 RMB within 15 minutes.
  - UI presents:
    - Button 1: *"查看已有记录"* (View Existing Record)
    - Button 2: *"确认这是另一笔交易"* (Confirm this is another transaction)
  - When user clicks Button 2, `TransactionManager.commitDraft(...)` proceeds to commit without hindrance.

---

## 4. The Atomic Draft Commitment Transaction Manager

### 4.1 Architecture & ACID Boundaries

The draft commitment manager (`lib/data/database/transaction_manager.dart`) guarantees that promoting a draft to a formal financial transaction is **100% atomic**. 

```text
               ┌────────────────────────────────────────────────────────┐
               │           SQLite Database Transaction (txn)            │
               │                                                        │
Draft Payload ─┼──► 1. Verify Draft & Job State == NEEDS_REVIEW         │
               │    2. Verify origin_draft_id Not Already Committed     │
               │    3. Pre-commit Tier 3 Hard ID Check on confirmed_ids │
               │    4. INSERT INTO transactions                         │
               │    5. INSERT INTO transaction_metadata                 │
               │    6. INSERT INTO transaction_tags (multi-tag)         │
               │    7. INSERT INTO confirmed_identifiers (if COMPLETE)  │
               │    8. INSERT INTO refund_links (if refund + origId)    │
               │    9. UPDATE drafts.saved_transaction_id = tx.id       │
               │   10. UPDATE capture_jobs.state = 'COMMITTED'          │
               │                                                        │
               │         COMMIT (All changes become permanent)          │
               └────────────────────────────────────────────────────────┘
                                      │
                   On ANY Failure (Constraint violation, etc.)
                                      ▼
               ┌────────────────────────────────────────────────────────┐
               │               ROLLBACK (Zero side-effects)             │
               │  - transactions reverted                               │
               │  - drafts.saved_transaction_id remains NULL            │
               │  - capture_jobs remains in NEEDS_REVIEW                │
               │  - Clean exception re-thrown to caller                 │
               └────────────────────────────────────────────────────────┘
```

### 4.2 Step-by-Step Commit Sequence

Inside `db.transaction((txn) async { ... })`:

1. **State Machine Pre-Check**:
   ```sql
   SELECT cj.state, d.saved_transaction_id
   FROM drafts d
   JOIN capture_jobs cj ON d.capture_id = cj.id
   WHERE d.id = ?;
   ```
   - If row not found: throw `DraftNotFoundException`.
   - If `saved_transaction_id != null`: throw `DraftAlreadyCommittedException`.
   - If `cj.state != 'NEEDS_REVIEW'`: throw `InvalidStateTransitionException`.

2. **Idempotence & Concurrency Defense**:
   ```sql
   SELECT id FROM transactions WHERE origin_draft_id = ?;
   ```
   - If row found: throw `DuplicateTransactionException(originDraftId)`.

3. **In-Transaction Tier 3 Platform Identifier Lock**:
   If request has a complete platform identifier:
   ```sql
   SELECT ci.transaction_id, t.deleted_at
   FROM confirmed_identifiers ci
   JOIN transactions t ON ci.transaction_id = t.id
   WHERE ci.namespace = ?
     AND ci.identifier_type = ?
     AND ci.complete_value = ?
     AND ci.stable_event_kind = ?;
   ```
   - If row found and `deleted_at IS NULL`: throw `HardDuplicateException`.
   - If row found and `deleted_at IS NOT NULL`: throw `TrashBinCollisionException`.

4. **Insert into `transactions`**:
   ```sql
   INSERT INTO transactions (
     id, origin_draft_id, type, amount_minor, currency,
     merchant_raw, merchant_normalized, occurred_on, occurred_at,
     event_timezone, event_time_source, event_time_precision,
     payment_channel, account_id, transfer_to_account_id,
     category_id, project_id, note, created_at, updated_at
   ) VALUES (
     ?, ?, ?, ?, ?,
     ?, ?, ?, ?,
     ?, ?, ?,
     ?, ?, ?,
     ?, ?, ?, ?, ?
   );
   ```
   *(SQLite CHECK constraint `amount_minor > 0` rejects any <= 0 value).*

5. **Insert into `transaction_metadata`**:
   If metadata is provided:
   ```sql
   INSERT INTO transaction_metadata (
     transaction_id, original_amount_minor, discount_minor, fee_minor,
     payment_status, platform_transaction_no, merchant_order_no,
     identifier_completeness, payment_method_label
   ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
   ```

6. **Insert into `transaction_tags`**:
   For each `tagId` in `request.tagIds`:
   ```sql
   INSERT INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?);
   ```

7. **Insert into `confirmed_identifiers`**:
   If `identifier_completeness == 'COMPLETE'` and `platform_transaction_no != null`:
   ```sql
   INSERT INTO confirmed_identifiers (
     namespace, identifier_type, complete_value, stable_event_kind, transaction_id
   ) VALUES (?, ?, ?, ?, ?);
   ```

8. **Insert into `refund_links` (if applicable)**:
   If `request.type == 'refund'` and `request.originalExpenseId != null`:
   ```sql
   INSERT INTO refund_links (
     refund_transaction_id, original_expense_id, created_at
   ) VALUES (?, ?, ?);
   ```

9. **Update `drafts`**:
   ```sql
   UPDATE drafts
   SET saved_transaction_id = ?, updated_at = ?
   WHERE id = ?;
   ```

10. **Update `capture_jobs`**:
    ```sql
    UPDATE capture_jobs
    SET state = 'COMMITTED', updated_at = ?
    WHERE id = ?;
    ```

11. **Return Committed Transaction Entity**:
    Returns fully populated `TransactionEntity`.

---

### 4.3 Lifecycle & Trash Bin Management Methods

In addition to `commitDraft`, the `TransactionManager` provides atomic methods for draft and ledger lifecycle:

1. **`discardDraft(String draftId)`**:
   - Executes inside transaction:
     - Verifies `capture_jobs.state == 'NEEDS_REVIEW'`.
     - Updates `capture_jobs.state = 'DISCARDED'`, `updated_at = datetime('now')`.
   - Caller handles asynchronous image deletion outside the DB transaction.

2. **`softDeleteTransaction(String transactionId)`**:
   - Updates `transactions SET deleted_at = ?, updated_at = ? WHERE id = ?`.
   - Preserves `confirmed_identifiers` rows during the 30-day trash period.

3. **`restoreFromTrash(String transactionId, {String? targetDraftId})`**:
   - Updates `transactions SET deleted_at = NULL, updated_at = ? WHERE id = ?`.
   - If `targetDraftId` specified: updates `drafts.saved_transaction_id = transactionId` and `capture_jobs.state = 'COMMITTED'`.

4. **`permanentDeleteTransaction(String transactionId)`**:
   - Deletes from `transactions WHERE id = ?`.
   - Automatic SQLite cascading deletes:
     - `confirmed_identifiers` rows purged (releasing platform order ID).
     - `transaction_metadata` row purged.
     - `transaction_tags` rows purged.
     - `refund_links` row purged (if original expense deleted: unlinks refund without deleting refund transaction; if refund deleted: unlinks refund).
     - Any referencing drafts have `saved_transaction_id` retained or set null; `origin_draft_id` FK is `ON DELETE SET NULL`.

---

## 5. Concrete Dart Code Formulations

Below are the complete, production-ready formulations for the two target files.

### 5.1 Formulation: `lib/features/deduplication/deduplication_engine.dart`

```dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/app_constants.dart';

/// Identifier completeness classification matching OCR and database spec
enum IdentifierCompleteness {
  none,
  complete,
  masked,
  truncated,
  unreliable,
}

extension IdentifierCompletenessExtension on IdentifierCompleteness {
  String toDbValue() {
    switch (this) {
      case IdentifierCompleteness.none:
        return 'NONE';
      case IdentifierCompleteness.complete:
        return 'COMPLETE';
      case IdentifierCompleteness.masked:
        return 'MASKED';
      case IdentifierCompleteness.truncated:
        return 'TRUNCATED';
      case IdentifierCompleteness.unreliable:
        return 'UNRELIABLE';
    }
  }

  static IdentifierCompleteness fromDbValue(String? value) {
    switch (value?.toUpperCase()) {
      case 'COMPLETE':
        return IdentifierCompleteness.complete;
      case 'MASKED':
        return IdentifierCompleteness.masked;
      case 'TRUNCATED':
        return IdentifierCompleteness.truncated;
      case 'UNRELIABLE':
        return IdentifierCompleteness.unreliable;
      case 'NONE':
      default:
        return IdentifierCompleteness.none;
    }
  }
}

/// Platform identifier data structure for Tier 3 hard deduplication
class PlatformIdentifier {
  final String namespace; // e.g. 'wechat_pay', 'alipay', 'unionpay'
  final String identifierType; // e.g. 'platform_transaction_no'
  final String completeValue; // Unmasked full platform order number
  final String stableEventKind; // 'payment' or 'refund'
  final IdentifierCompleteness completeness;

  PlatformIdentifier({
    required this.namespace,
    required this.identifierType,
    required this.completeValue,
    required this.stableEventKind,
    this.completeness = IdentifierCompleteness.complete,
  });

  bool get isEligibleForHardDedup =>
      completeness == IdentifierCompleteness.complete &&
      completeValue.trim().isNotEmpty;
}

/// Tier 1 Idempotence Evaluation Result
class Tier1Result {
  final bool isMatched;
  final String? existingTransactionId;
  final bool isInTrash;

  const Tier1Result({
    required this.isMatched,
    this.existingTransactionId,
    this.isInTrash = false,
  });

  factory Tier1Result.miss() => const Tier1Result(isMatched: false);

  factory Tier1Result.hit({
    required String transactionId,
    bool isInTrash = false,
  }) =>
      Tier1Result(
        isMatched: true,
        existingTransactionId: transactionId,
        isInTrash: isInTrash,
      );
}

/// Tier 2 Image Hash Evaluation Result
class Tier2Result {
  final bool isMatched;
  final String? existingJobId;
  final String? jobState;
  final String? existingDraftId;
  final String? existingTransactionId;
  final bool isTransactionInTrash;

  const Tier2Result({
    required this.isMatched,
    this.existingJobId,
    this.jobState,
    this.existingDraftId,
    this.existingTransactionId,
    this.isTransactionInTrash = false,
  });

  factory Tier2Result.miss() => const Tier2Result(isMatched: false);

  factory Tier2Result.hit({
    required String jobId,
    required String jobState,
    String? draftId,
    String? transactionId,
    bool isTransactionInTrash = false,
  }) =>
      Tier2Result(
        isMatched: true,
        existingJobId: jobId,
        jobState: jobState,
        existingDraftId: draftId,
        existingTransactionId: transactionId,
        isTransactionInTrash: isTransactionInTrash,
      );
}

/// Tier 3 Hard Platform Identifier Result
class Tier3Result {
  final bool isMatched;
  final String? matchedTransactionId;
  final Map<String, dynamic>? matchedTransaction;
  final bool isInTrash;

  const Tier3Result({
    required this.isMatched,
    this.matchedTransactionId,
    this.matchedTransaction,
    this.isInTrash = false,
  });

  factory Tier3Result.miss() => const Tier3Result(isMatched: false);

  factory Tier3Result.activeDuplicate({
    required String transactionId,
    required Map<String, dynamic> transaction,
  }) =>
      Tier3Result(
        isMatched: true,
        matchedTransactionId: transactionId,
        matchedTransaction: transaction,
        isInTrash: false,
      );

  factory Tier3Result.trashBinDuplicate({
    required String transactionId,
    required Map<String, dynamic> transaction,
  }) =>
      Tier3Result(
        isMatched: true,
        matchedTransactionId: transactionId,
        matchedTransaction: transaction,
        isInTrash: true,
      );
}

/// Tier 4 Heuristic Fuzzy Match Result
class Tier4Result {
  final bool hasSuspectedDuplicates;
  final List<String> candidateTransactionIds;
  final List<Map<String, dynamic>> candidateTransactions;

  const Tier4Result({
    required this.hasSuspectedDuplicates,
    required this.candidateTransactionIds,
    required this.candidateTransactions,
  });

  factory Tier4Result.clean() => const Tier4Result(
        hasSuspectedDuplicates: false,
        candidateTransactionIds: [],
        candidateTransactions: [],
      );

  factory Tier4Result.suspected({
    required List<String> ids,
    required List<Map<String, dynamic>> transactions,
  }) =>
      Tier4Result(
        hasSuspectedDuplicates: true,
        candidateTransactionIds: ids,
        candidateTransactions: transactions,
      );
}

/// Aggregated Evaluation Result across all 4 tiers
class DeduplicationEvaluation {
  final Tier1Result tier1;
  final Tier2Result tier2;
  final Tier3Result tier3;
  final Tier4Result tier4;

  const DeduplicationEvaluation({
    required this.tier1,
    required this.tier2,
    required this.tier3,
    required this.tier4,
  });

  bool get hasHardDuplicate => tier1.isMatched || (tier3.isMatched && !tier3.isInTrash);
  bool get hasTrashDuplicate => tier1.isInTrash || (tier3.isMatched && tier3.isInTrash);
  bool get hasSoftDuplicate => tier4.hasSuspectedDuplicates;
}

/// 4-Tier Deduplication Engine for SingWallet
class DeduplicationEngine {
  final DatabaseExecutor _db;

  DeduplicationEngine(this._db);

  /// Tier 1: Technical Idempotence Check
  /// Checks whether [originDraftId] has already been committed to an existing transaction.
  Future<Tier1Result> checkTier1Idempotence(String originDraftId) async {
    final rows = await _db.query(
      'transactions',
      columns: ['id', 'deleted_at'],
      where: 'origin_draft_id = ?',
      whereArgs: [originDraftId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return Tier1Result.miss();
    }

    final row = rows.first;
    final txId = row['id'] as String;
    final isInTrash = row['deleted_at'] != null;

    return Tier1Result.hit(transactionId: txId, isInTrash: isInTrash);
  }

  /// Tier 2: Same-Image Hash Check
  /// Checks whether [contentHash] matches any existing record in [capture_jobs].
  Future<Tier2Result> checkTier2ImageHash(String contentHash) async {
    const sql = '''
      SELECT cj.id AS job_id, cj.state, cj.imported_at,
             d.id AS draft_id, d.saved_transaction_id,
             t.id AS transaction_id, t.deleted_at
      FROM capture_jobs cj
      LEFT JOIN drafts d ON d.capture_id = cj.id
      LEFT JOIN transactions t ON (t.origin_draft_id = d.id OR t.id = d.saved_transaction_id)
      WHERE cj.content_hash = ?
      ORDER BY cj.created_at DESC
      LIMIT 1;
    ''';

    final rows = await _db.rawQuery(sql, [contentHash]);
    if (rows.isEmpty) {
      return Tier2Result.miss();
    }

    final row = rows.first;
    final jobId = row['job_id'] as String;
    final state = row['state'] as String;
    final draftId = row['draft_id'] as String?;
    final txId = (row['transaction_id'] ?? row['saved_transaction_id']) as String?;
    final isInTrash = row['deleted_at'] != null;

    return Tier2Result.hit(
      jobId: jobId,
      jobState: state,
      draftId: draftId,
      transactionId: txId,
      isTransactionInTrash: isInTrash,
    );
  }

  /// Tier 3: Hard Platform Identifier Match
  /// Matches against [confirmed_identifiers] table using compound PK.
  /// Only executes if [identifier.isEligibleForHardDedup] is true.
  Future<Tier3Result> checkTier3PlatformId(PlatformIdentifier identifier) async {
    if (!identifier.isEligibleForHardDedup) {
      return Tier3Result.miss();
    }

    const sql = '''
      SELECT ci.transaction_id, t.id, t.type, t.amount_minor, t.currency,
             t.merchant_raw, t.occurred_on, t.deleted_at
      FROM confirmed_identifiers ci
      JOIN transactions t ON ci.transaction_id = t.id
      WHERE ci.namespace = ?
        AND ci.identifier_type = ?
        AND ci.complete_value = ?
        AND ci.stable_event_kind = ?
      LIMIT 1;
    ''';

    final rows = await _db.rawQuery(sql, [
      identifier.namespace,
      identifier.identifierType,
      identifier.completeValue.trim(),
      identifier.stableEventKind,
    ]);

    if (rows.isEmpty) {
      return Tier3Result.miss();
    }

    final row = rows.first;
    final txId = row['id'] as String;
    final isInTrash = row['deleted_at'] != null;

    if (isInTrash) {
      return Tier3Result.trashBinDuplicate(
        transactionId: txId,
        transaction: row,
      );
    } else {
      return Tier3Result.activeDuplicate(
        transactionId: txId,
        transaction: row,
      );
    }
  }

  /// Tier 4: Heuristic Fuzzy Matching
  /// Checks for active transactions with:
  /// - Same merchant ([merchantRaw] or [merchantNormalized])
  /// - Identical [amountMinor]
  /// - Within 24-hour time window of [occurredOn] / [occurredAt]
  Future<Tier4Result> checkTier4Fuzzy({
    required String merchantRaw,
    String? merchantNormalized,
    required int amountMinor,
    required String occurredOn,
    String? occurredAt,
  }) async {
    // 1. Calculate calendar day search bounds (occurredOn +- 1 day)
    final candidateDate = DateTime.tryParse(occurredOn);
    if (candidateDate == null) {
      return Tier4Result.clean();
    }

    final prevDate = candidateDate.subtract(const Duration(days: 1));
    final nextDate = candidateDate.add(const Duration(days: 1));

    final minDateStr = _formatDate(prevDate);
    final maxDateStr = _formatDate(nextDate);

    final normalizedVal = (merchantNormalized != null && merchantNormalized.trim().isNotEmpty)
        ? merchantNormalized.trim().toLowerCase()
        : null;
    final rawVal = merchantRaw.trim().toLowerCase();

    const sql = '''
      SELECT id, type, amount_minor, currency, merchant_raw, merchant_normalized,
             occurred_on, occurred_at, payment_channel, category_id
      FROM transactions
      WHERE deleted_at IS NULL
        AND amount_minor = ?
        AND (
          LOWER(TRIM(merchant_raw)) = ?
          OR (? IS NOT NULL AND merchant_normalized IS NOT NULL AND LOWER(TRIM(merchant_normalized)) = ?)
        )
        AND occurred_on BETWEEN ? AND ?;
    ''';

    final rows = await _db.rawQuery(sql, [
      amountMinor,
      rawVal,
      normalizedVal,
      normalizedVal,
      minDateStr,
      maxDateStr,
    ]);

    if (rows.isEmpty) {
      return Tier4Result.clean();
    }

    // 2. Precise 24-hour window verification in Dart memory
    DateTime? candidatePreciseTime;
    if (occurredAt != null) {
      candidatePreciseTime = DateTime.tryParse(occurredAt);
    }

    final matchedIds = <String>[];
    final matchedRows = <Map<String, dynamic>>[];

    for (final row in rows) {
      final existingOccurredAt = row['occurred_at'] as String?;
      if (candidatePreciseTime != null && existingOccurredAt != null) {
        final existingTime = DateTime.tryParse(existingOccurredAt);
        if (existingTime != null) {
          final diff = candidatePreciseTime.difference(existingTime).abs();
          if (diff > AppConstants.fuzzyDedupWindow) {
            // Precise time difference exceeds 24 hours
            continue;
          }
        }
      }

      matchedIds.add(row['id'] as String);
      matchedRows.add(row);
    }

    if (matchedIds.isEmpty) {
      return Tier4Result.clean();
    }

    return Tier4Result.suspected(ids: matchedIds, transactions: matchedRows);
  }

  /// Full 4-Tier Pipeline Evaluation
  Future<DeduplicationEvaluation> evaluateAll({
    String? originDraftId,
    String? contentHash,
    PlatformIdentifier? platformIdentifier,
    required String merchantRaw,
    String? merchantNormalized,
    required int amountMinor,
    required String occurredOn,
    String? occurredAt,
  }) async {
    // Tier 1
    final t1 = originDraftId != null
        ? await checkTier1Idempotence(originDraftId)
        : Tier1Result.miss();

    // Tier 2
    final t2 = contentHash != null
        ? await checkTier2ImageHash(contentHash)
        : Tier2Result.miss();

    // Tier 3
    final t3 = platformIdentifier != null
        ? await checkTier3PlatformId(platformIdentifier)
        : Tier3Result.miss();

    // Tier 4 (only if Tier 3 did not yield a hard active duplicate)
    Tier4Result t4;
    if (t3.isMatched && !t3.isInTrash) {
      t4 = Tier4Result.clean();
    } else {
      t4 = await checkTier4Fuzzy(
        merchantRaw: merchantRaw,
        merchantNormalized: merchantNormalized,
        amountMinor: amountMinor,
        occurredOn: occurredOn,
        occurredAt: occurredAt,
      );
    }

    return DeduplicationEvaluation(tier1: t1, tier2: t2, tier3: t3, tier4: t4);
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
```

---

### 5.2 Formulation: `lib/data/database/transaction_manager.dart`

```dart
import 'package:sqflite/sqflite.dart';
import '../../features/deduplication/deduplication_engine.dart';

/// Request DTO for committing a draft to the formal financial ledger
class DraftCommitRequest {
  final String draftId;
  final String transactionId; // Generated UUID for formal transaction
  final String type; // 'expense', 'income', 'refund', 'transfer'
  final int amountMinor; // Stored in cents (分), strictly > 0
  final String currency; // Default 'CNY'
  final String merchantRaw;
  final String? merchantNormalized;
  final String occurredOn; // YYYY-MM-DD
  final String? occurredAt; // UTC ISO-8601
  final String eventTimezone; // Default 'Asia/Shanghai'
  final String eventTimeSource; // 'ocr_extracted', 'suggested_today', 'user_selected'
  final String eventTimePrecision; // 'second', 'minute', 'day'
  final String paymentChannel; // 'wechat', 'alipay', 'unionpay', 'cash', 'other'
  final String? accountId;
  final String? transferToAccountId; // Only for transfer type
  final String? categoryId;
  final String? projectId;
  final String? note;

  // Metadata fields
  final int? originalAmountMinor;
  final int? discountMinor;
  final int? feeMinor;
  final String paymentStatus; // 'SUCCESS', 'REFUNDED', etc.
  final String? platformTransactionNo;
  final String? merchantOrderNo;
  final IdentifierCompleteness identifierCompleteness;
  final String? paymentMethodLabel;

  // Tag associations
  final List<String> tagIds;

  // Dedicated Hard Deduplication Identifier
  final PlatformIdentifier? platformIdentifier;

  // Refund link (optional)
  final String? originalExpenseId;

  DraftCommitRequest({
    required this.draftId,
    required this.transactionId,
    required this.type,
    required this.amountMinor,
    this.currency = 'CNY',
    required this.merchantRaw,
    this.merchantNormalized,
    required this.occurredOn,
    this.occurredAt,
    this.eventTimezone = 'Asia/Shanghai',
    required this.eventTimeSource,
    required this.eventTimePrecision,
    required this.paymentChannel,
    this.accountId,
    this.transferToAccountId,
    this.categoryId,
    this.projectId,
    this.note,
    this.originalAmountMinor,
    this.discountMinor,
    this.feeMinor,
    this.paymentStatus = 'SUCCESS',
    this.platformTransactionNo,
    this.merchantOrderNo,
    this.identifierCompleteness = IdentifierCompleteness.none,
    this.paymentMethodLabel,
    this.tagIds = const [],
    this.platformIdentifier,
    this.originalExpenseId,
  });
}

/// Domain Exceptions for Transaction Commitment
class TransactionCommitException implements Exception {
  final String message;
  final Object? cause;
  TransactionCommitException(this.message, [this.cause]);

  @override
  String toString() => 'TransactionCommitException: $message';
}

class DraftNotFoundException extends TransactionCommitException {
  DraftNotFoundException(String draftId) : super('Draft with id "$draftId" was not found.');
}

class DraftAlreadyCommittedException extends TransactionCommitException {
  final String existingTransactionId;
  DraftAlreadyCommittedException(String draftId, this.existingTransactionId)
      : super('Draft "$draftId" is already committed to transaction "$existingTransactionId".');
}

class InvalidStateTransitionException extends TransactionCommitException {
  final String currentState;
  InvalidStateTransitionException(this.currentState)
      : super('Cannot commit draft. Current job state is "$currentState", expected "NEEDS_REVIEW".');
}

class HardDuplicateException extends TransactionCommitException {
  final String existingTransactionId;
  HardDuplicateException(this.existingTransactionId, String msg)
      : super('Hard platform duplicate intercepted: $msg (existing tx: $existingTransactionId)');
}

class TrashBinCollisionException extends TransactionCommitException {
  final String existingTransactionId;
  TrashBinCollisionException(this.existingTransactionId)
      : super('Transaction with same platform ID exists in trash bin: $existingTransactionId');
}

/// Atomic Transaction Manager for SingWallet
class TransactionManager {
  final Database _database;

  TransactionManager(this._database);

  /// Atomically commits a draft into the formal SQLite database ledger.
  ///
  /// Guarantees all-or-nothing atomicity:
  /// - Inserts into [transactions]
  /// - Inserts into [transaction_metadata]
  /// - Inserts into [transaction_tags]
  /// - Inserts into [confirmed_identifiers] (if COMPLETE platform ID exists)
  /// - Inserts into [refund_links] (if refund + originalExpenseId provided)
  /// - Updates [drafts.saved_transaction_id]
  /// - Updates [capture_jobs.state] to 'COMMITTED'
  ///
  /// On any failure (CHECK constraint violation, duplicate key, etc.), the entire
  /// transaction rolls back and throws a typed [TransactionCommitException].
  Future<void> commitDraft(DraftCommitRequest request) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _database.transaction((txn) async {
      // 1. Verify Draft and Ingestion Job State
      const draftJobSql = '''
        SELECT d.id AS draft_id, d.saved_transaction_id, cj.id AS job_id, cj.state
        FROM drafts d
        JOIN capture_jobs cj ON d.capture_id = cj.id
        WHERE d.id = ?;
      ''';
      final draftRows = await txn.rawQuery(draftJobSql, [request.draftId]);
      if (draftRows.isEmpty) {
        throw DraftNotFoundException(request.draftId);
      }

      final draftRow = draftRows.first;
      final savedTxId = draftRow['saved_transaction_id'] as String?;
      final jobState = draftRow['state'] as String;
      final jobId = draftRow['job_id'] as String;

      if (savedTxId != null) {
        throw DraftAlreadyCommittedException(request.draftId, savedTxId);
      }

      if (jobState != 'NEEDS_REVIEW') {
        throw InvalidStateTransitionException(jobState);
      }

      // 2. Concurrency Defense: Check Tier 1 Idempotence in Transaction
      final existingTx = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'origin_draft_id = ?',
        whereArgs: [request.draftId],
        limit: 1,
      );
      if (existingTx.isNotEmpty) {
        throw DraftAlreadyCommittedException(
          request.draftId,
          existingTx.first['id'] as String,
        );
      }

      // 3. Concurrency Defense: In-Transaction Tier 3 Hard ID Check
      final platformId = request.platformIdentifier;
      if (platformId != null && platformId.isEligibleForHardDedup) {
        const idCheckSql = '''
          SELECT ci.transaction_id, t.deleted_at
          FROM confirmed_identifiers ci
          JOIN transactions t ON ci.transaction_id = t.id
          WHERE ci.namespace = ?
            AND ci.identifier_type = ?
            AND ci.complete_value = ?
            AND ci.stable_event_kind = ?;
        ''';
        final idRows = await txn.rawQuery(idCheckSql, [
          platformId.namespace,
          platformId.identifierType,
          platformId.completeValue.trim(),
          platformId.stableEventKind,
        ]);

        if (idRows.isNotEmpty) {
          final matchedRow = idRows.first;
          final matchedTxId = matchedRow['transaction_id'] as String;
          final isInTrash = matchedRow['deleted_at'] != null;

          if (isInTrash) {
            throw TrashBinCollisionException(matchedTxId);
          } else {
            throw HardDuplicateException(
              matchedTxId,
              'Platform identifier ${platformId.completeValue} already exists.',
            );
          }
        }
      }

      // 4. Insert into transactions table
      await txn.insert('transactions', {
        'id': request.transactionId,
        'origin_draft_id': request.draftId,
        'type': request.type,
        'amount_minor': request.amountMinor,
        'currency': request.currency,
        'merchant_raw': request.merchantRaw,
        'merchant_normalized': request.merchantNormalized,
        'occurred_on': request.occurredOn,
        'occurred_at': request.occurredAt,
        'event_timezone': request.eventTimezone,
        'event_time_source': request.eventTimeSource,
        'event_time_precision': request.eventTimePrecision,
        'payment_channel': request.paymentChannel,
        'account_id': request.accountId,
        'transfer_to_account_id': request.transferToAccountId,
        'category_id': request.categoryId,
        'project_id': request.projectId,
        'note': request.note,
        'created_at': nowIso,
        'updated_at': nowIso,
        'deleted_at': null,
      });

      // 5. Insert into transaction_metadata table
      await txn.insert('transaction_metadata', {
        'transaction_id': request.transactionId,
        'original_amount_minor': request.originalAmountMinor,
        'discount_minor': request.discountMinor,
        'fee_minor': request.feeMinor,
        'payment_status': request.paymentStatus,
        'platform_transaction_no': request.platformTransactionNo,
        'merchant_order_no': request.merchantOrderNo,
        'identifier_completeness': request.identifierCompleteness.toDbValue(),
        'payment_method_label': request.paymentMethodLabel,
      });

      // 6. Insert into transaction_tags join table
      for (final tagId in request.tagIds) {
        await txn.insert('transaction_tags', {
          'transaction_id': request.transactionId,
          'tag_id': tagId,
        });
      }

      // 7. Insert into confirmed_identifiers index table (if eligible)
      if (platformId != null && platformId.isEligibleForHardDedup) {
        await txn.insert('confirmed_identifiers', {
          'namespace': platformId.namespace,
          'identifier_type': platformId.identifierType,
          'complete_value': platformId.completeValue.trim(),
          'stable_event_kind': platformId.stableEventKind,
          'transaction_id': request.transactionId,
        });
      }

      // 8. Insert into refund_links table (if refund and original expense given)
      if (request.type == 'refund' && request.originalExpenseId != null) {
        await txn.insert('refund_links', {
          'refund_transaction_id': request.transactionId,
          'original_expense_id': request.originalExpenseId,
          'created_at': nowIso,
        });
      }

      // 9. Update drafts table with saved transaction reference
      await txn.update(
        'drafts',
        {
          'saved_transaction_id': request.transactionId,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [request.draftId],
      );

      // 10. Update capture_jobs table state to COMMITTED
      await txn.update(
        'capture_jobs',
        {
          'state': 'COMMITTED',
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [jobId],
      );
    });
  }

  /// Discards a draft and marks its associated capture job as DISCARDED.
  Future<void> discardDraft(String draftId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT capture_id FROM drafts WHERE id = ?;',
        [draftId],
      );
      if (rows.isEmpty) {
        throw DraftNotFoundException(draftId);
      }
      final captureId = rows.first['capture_id'] as String;

      await txn.update(
        'capture_jobs',
        {'state': 'DISCARDED', 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: [captureId],
      );
    });
  }

  /// Soft deletes a transaction (moves to 30-day trash bin).
  Future<void> softDeleteTransaction(String transactionId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _database.update(
      'transactions',
      {'deleted_at': nowIso, 'updated_at': nowIso},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  /// Restores a transaction from the 30-day trash bin.
  Future<void> restoreFromTrash(String transactionId, {String? targetDraftId}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      await txn.update(
        'transactions',
        {'deleted_at': null, 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: [transactionId],
      );

      if (targetDraftId != null) {
        await txn.update(
          'drafts',
          {'saved_transaction_id': transactionId, 'updated_at': nowIso},
          where: 'id = ?',
          whereArgs: [targetDraftId],
        );
        // Also update capture_jobs state
        final rows = await txn.rawQuery(
          'SELECT capture_id FROM drafts WHERE id = ?;',
          [targetDraftId],
        );
        if (rows.isNotEmpty) {
          final captureId = rows.first['capture_id'] as String;
          await txn.update(
            'capture_jobs',
            {'state': 'COMMITTED', 'updated_at': nowIso},
            where: 'id = ?',
            whereArgs: [captureId],
          );
        }
      }
    });
  }

  /// Permanently deletes a transaction, triggering foreign key cascades.
  Future<void> permanentDeleteTransaction(String transactionId) async {
    await _database.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }
}
```

---

## 6. Comprehensive Test Specifications for M1-A

To ensure robust implementation, the test suite (`test/deduplication/deduplication_test.dart` and `test/database/transaction_manager_test.dart`) must cover the following test scenarios:

### Test Suite: 4-Tier Deduplication Engine

1. **Test: Tier 1 Technical Idempotence**:
   - Save transaction with `origin_draft_id = 'draft_001'`.
   - Call `checkTier1Idempotence('draft_001')`.
   - Assert `isMatched == true` and `existingTransactionId == 'tx_001'`.
   - Call `checkTier1Idempotence('draft_unused')`.
   - Assert `isMatched == false`.

2. **Test: Tier 2 Same-Image Hash Check**:
   - Insert `capture_jobs` with `content_hash = 'sha256_abcdef123456'`.
   - Call `checkTier2ImageHash('sha256_abcdef123456')`.
   - Assert `isMatched == true` and `existingJobId` matches.
   - Query for unseen hash -> assert `isMatched == false`.

3. **Test: Tier 3 Hard Platform ID Match (Active Record)**:
   - Insert `confirmed_identifiers` with `namespace = 'wechat_pay'`, `complete_value = '4200001234567890'`.
   - Call `checkTier3PlatformId` with identical complete platform ID.
   - Assert `isMatched == true`, `isInTrash == false`, and `matchedTransactionId` matches.

4. **Test: Tier 3 Hard Platform ID Match (Trash Bin Record)**:
   - Soft-delete transaction (`deleted_at = '2026-10-22T10:00:00Z'`).
   - Call `checkTier3PlatformId` with same platform ID.
   - Assert `isMatched == true` and `isInTrash == true` (prompts restore).

5. **Test: Tier 3 Non-Complete ID Bypass**:
   - Create `PlatformIdentifier` with `completeness = IdentifierCompleteness.masked` and value `'420000****7890'`.
   - Call `checkTier3PlatformId`.
   - Assert `isMatched == false` (masked ID does not trigger Tier 3).

6. **Test: Tier 4 Heuristic Fuzzy Match (Soft Warning)**:
   - Insert transaction: merchant `'麦当劳'`, amount `2890`, date `'2026-10-22'`.
   - Call `checkTier4Fuzzy` with merchant `'麦当劳'`, amount `2890`, date `'2026-10-22'`.
   - Assert `hasSuspectedDuplicates == true` and list contains transaction ID.

7. **Test: Tier 4 Time Boundary Filtering**:
   - Insert transaction on `'2026-10-20'` (2 days prior).
   - Call `checkTier4Fuzzy` with date `'2026-10-22'`.
   - Assert `hasSuspectedDuplicates == false` (outside 24h / 1-day window).

8. **Test: Tier 4 Legitimate Consecutive Purchase Override**:
   - User has duplicate suspected warning for Starbucks.
   - User explicitly submits `DraftCommitRequest`.
   - System commits successfully without blocking.

---

### Test Suite: Atomic Transaction Manager

1. **Test: Successful Multi-Table Atomic Commit**:
   - Create draft in `NEEDS_REVIEW` with `capture_jobs`.
   - Execute `commitDraft(request)` with metadata, 2 tags, complete platform ID.
   - Verify:
     - `transactions` row created with integer cents.
     - `transaction_metadata` row created.
     - `transaction_tags` has 2 rows.
     - `confirmed_identifiers` has 1 row.
     - `drafts.saved_transaction_id` updated to transaction ID.
     - `capture_jobs.state` updated to `COMMITTED`.

2. **Test: Rollback on Invalid Amount (`amount_minor <= 0`)**:
   - Submit `DraftCommitRequest` with `amountMinor: 0`.
   - Await `commitDraft(request)`.
   - Assert throws exception.
   - Verify `transactions` has 0 rows.
   - Verify `drafts.saved_transaction_id` is still `null`.
   - Verify `capture_jobs.state` remains `NEEDS_REVIEW`.

3. **Test: Rollback on Duplicate Origin Draft ID**:
   - Commit draft once successfully.
   - Attempt to commit same draft ID again.
   - Assert throws `DraftAlreadyCommittedException`.

4. **Test: Rollback on Duplicate Hard Platform ID**:
   - Commit transaction with platform ID `4200001234`.
   - Create second draft in `NEEDS_REVIEW`.
   - Attempt to commit second draft with same platform ID `4200001234`.
   - Assert throws `HardDuplicateException`.
   - Verify second draft remains in `NEEDS_REVIEW` and no second transaction exists.

5. **Test: Refund Link Cascading Unlink**:
   - Commit original expense `tx_orig`.
   - Commit refund `tx_refund` linked to `tx_orig`.
   - Permanently delete `tx_orig`.
   - Assert `refund_links` row deleted.
   - Assert `tx_refund` in `transactions` remains intact.

---

## 7. Verification Method

To verify the formulations independently:
1. Review the Dart class interfaces against `spec_miner_survey_2/report.md` and `docs/跨平台架构与数据规范.md`.
2. Verify that all SQL column names and table names match the exact DDL in `docs/跨平台架构与数据规范.md`.
3. Check that `PRAGMA foreign_keys = ON;` is respected.
4. Execute test suite once implemented using `flutter test test/deduplication/` and `flutter test test/database/`.

---

## 8. Summary & Next Steps for Worker M1-A

1. `worker_m1a_1` will implement the DDL and `app_database.dart` according to `explorer_m1a_1`'s specification.
2. `worker_m1a_2` will implement `lib/features/deduplication/deduplication_engine.dart` and `lib/data/database/transaction_manager.dart` exactly following the formulations in Section 5 of this report.
3. `worker_m1a_3` will implement `lib/data/database/state_machine.dart` and the comprehensive automated unit test suites specified in Section 6.
