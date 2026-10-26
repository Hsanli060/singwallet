# SingWallet Specification Mining Report: SQLite Data Layer & Transaction Management (R2 / M1)

**Date**: 2026-10-22  
**Target Milestone**: M1 (Core SQLite Data Layer & Transaction Engine)  
**Author / Archetype**: `spec_miner_survey_2` (Specification Miner)  
**Authoritative Sources**:
- `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`
- `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`
- `c:\Other\Projects\singwallet\docs\Android实现方案.md`
- `c:\Other\Projects\singwallet\docs\iOS实现方案.md`
- `c:\Other\Projects\singwallet\pigeons\native_bridge.dart`
- `c:\Other\Projects\singwallet\test_docs_integrity.py`

---

## Executive Summary

This specification mining report covers **R2. 统一 SQLite 数据层与事务管理（M1）**. It defines the exact technical contract, data models, relational constraints, four-tier deduplication engine, and transaction state machine required to implement the SingWallet persistence layer on top of SQLite / SQLCipher.

The core design mandates 100% logic alignment across Android and iOS by anchoring all schema, foreign keys, cascade rules, indexing, transaction boundaries, and deduplication logic within the unified Flutter / SQLite layer, backed by hardware-protected SQLCipher AES-256 encryption.

---

## Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | DDL / Core Schema | `capture_jobs` Table | Stores screenshot capture and ingestion job metadata, including image SHA-256 hash, ingestion source, parser version, retry attempts, and state. | Job UUID, content hash, source kind, ISO timestamp, file ref | Persisted capture job record | Fails on duplicate ID or NULL non-null columns | `docs/跨平台架构与数据规范.md:147` |
| 2 | DDL / Core Schema | `drafts` Table | Stores intermediate OCR candidate fields, evidence bounding boxes, validation issues, and duplicate candidate lists (1:1 with `capture_jobs`). | Draft UUID, capture ID, candidate fields JSON, evidence JSON, issue array JSON, duplicate array JSON | Persisted draft record | Enforces UNIQUE `capture_id`; cascades delete on job deletion | `docs/跨平台架构与数据规范.md:165` |
| 3 | DDL / Core Schema | `accounts` Table | Manages asset and payment source accounts (debit, credit, e-wallet, cash) with soft-archiving support. | Account UUID, name, kind, optional card last 4 digits | Account entity | Fails on duplicate ID or missing mandatory fields | `docs/跨平台架构与数据规范.md:182` |
| 4 | DDL / Core Schema | `categories` Table | Hierarchical transaction categories (parent-child relationship) with application type filter (`expense`, `income`, `both`). | Category UUID, name, optional parent ID, applicable type, icon key, sort order | Category entity | Self-referential FK `ON DELETE SET NULL` on parent deletion | `docs/跨平台架构与数据规范.md:195` |
| 5 | DDL / Core Schema | `projects` Table | Project entity for multi-transaction grouping (e.g., travel, home decoration). | Project UUID, project name | Project record | Fails on null name or duplicate ID | `docs/跨平台架构与数据规范.md:211` |
| 6 | DDL / Core Schema | `tags` Table | Multi-dimensional tags for labeling transactions (orthogonal to categories and projects). | Tag UUID, tag name | Tag record | Fails on null name or duplicate ID | `docs/跨平台架构与数据规范.md:222` |
| 7 | DDL / Core Schema | `transactions` Table | Core formal financial ledger table. Enforces positive integer amounts (`amount_minor > 0`), origin draft idempotence, date attribution, and channel. | Transaction fields: ID, draft ID, type, amount (分), currency, merchant, occurred_on, channel, etc. | Ledger transaction row | Rejects non-positive amount (`amount_minor <= 0`) via CHECK; rejects duplicate `origin_draft_id` | `docs/跨平台架构与数据规范.md:233`, `test_docs_integrity.py:124` |
| 8 | DDL / Core Schema | `transaction_metadata` Table | Auxiliary metadata for ledger records: original amount, discounts, fees, payment status, raw platform transaction IDs, and order numbers. | Transaction ID, discount/fee minors, payment status, platform order numbers, completeness enum | Extended metadata row | Fails if `transaction_id` does not exist; cascades delete on transaction deletion | `docs/跨平台架构与数据规范.md:271` |
| 9 | DDL / Core Schema | `transaction_tags` Table | Many-to-many relationship join table linking transactions and tags. | Compound PK: `(transaction_id, tag_id)` | Association record | Cascades delete if either transaction or tag is deleted | `docs/跨平台架构与数据规范.md:287` |
| 10 | DDL / Core Schema | `refund_links` Table | Unidirectional link connecting a refund transaction to its original expense transaction. | Refund transaction ID (PK), original expense ID, created_at | Refund link record | Cascades delete on either transaction deletion; unlinks cleanly if original expense is deleted without deleting refund | `docs/跨平台架构与数据规范.md:299`, `test_docs_integrity.py:189` |
| 11 | DDL / Core Schema | `classification_rules` Table | Merchant pattern matching rules with priority, channel condition, category assignment, and optional project. | Rule UUID, priority, merchant pattern (wildcard/regex), category ID, optional project ID | Rule configuration row | Category deletion cascades; project deletion sets `project_id = NULL` | `docs/跨平台架构与数据规范.md:311`, `test_docs_integrity.py:218` |
| 12 | DDL / Core Schema | `confirmed_identifiers` Table | Dedicated index table for hard deduplication of complete payment and refund platform transaction IDs. | Compound PK: `(namespace, identifier_type, complete_value, stable_event_kind)`, transaction ID | Hard deduplication index | Rejects duplicates on primary key conflict; cascades delete on transaction removal | `docs/跨平台架构与数据规范.md:329`, `test_docs_integrity.py:175` |
| 13 | Indexing | 11 Performance Indices | Specialized B-tree indices covering content hashes, job states, drafts saved link, transaction dates, categories, soft-delete flag, projects, accounts, tags, refund links, and identifier lookups. | Table columns | B-tree index structures | Handled by SQLite query optimizer | `docs/跨平台架构与数据规范.md:159-338`, `test_docs_integrity.py:114` |
| 14 | Currency / Storage | Integer Cent Storage (`amount_minor`) | All monetary amounts stored strictly as signed 64-bit integers in minor units (分, cents). Floats/doubles forbidden. | Monetary inputs in cents | Accurate integer storage | CHECK constraint rejects `<= 0` on transaction creation | `docs/跨平台架构与数据规范.md:237,347` |
| 15 | Deduplication | Tier 1: Technical Idempotence | Avoids duplicate processing of duplicate intents, task retries, or re-saving the same draft. | `captureId`, `draftId` | Existing draft / transaction | Bypasses creation, routes to existing record | `docs/跨平台架构与数据规范.md:363` |
| 16 | Deduplication | Tier 2: Same-Image Hash Check | Computes SHA-256 `content_hash` of ingested image and matches against `capture_jobs(content_hash)`. | Image SHA-256 hash | Existing job/draft/transaction reference | Blocks duplicate task pipeline, prompts user with existing draft | `docs/跨平台架构与数据规范.md:365` |
| 17 | Deduplication | Tier 3: Hard Platform Transaction Identifier Check | Exact match on complete platform transaction number via `confirmed_identifiers` table. | Complete identifier, namespace, event kind | Match result / existing transaction | Hard intercept: displays existing ledger record, blocks duplicate commit | `docs/跨平台架构与数据规范.md:368` |
| 18 | Deduplication | Tier 4: Heuristic Fuzzy Matching | Fuzzy check: same merchant + identical amount + occurrence time within 24 hours. | Merchant name, `amount_minor`, `occurred_on`/`occurred_at` | `duplicate_candidates` populated in draft | Soft warning: prompts user to confirm whether it is a duplicate or another valid transaction | `docs/跨平台架构与数据规范.md:371` |
| 19 | Lifecycle / State Machine | Ingestion Job State Transitions | Manages lifecycle: `IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `DISCARDED` / `FAILED`. | State change events (OCR complete, user confirm, failure) | Updated `state` and `updated_at` | Fails on invalid transition; unhandled killed process auto-recovers on next app startup | `docs/跨平台架构与数据规范.md:153`, `docs/Android实现方案.md:486`, `docs/iOS实现方案.md:520` |
| 20 | Transaction Management | Atomic Draft Commitment | Atomic commit of draft into `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, updating `drafts` and `capture_jobs`. | Draft confirmed payload | Atomic commit in single SQLite transaction | Rollback on any failure; leaves draft in `NEEDS_REVIEW` | `docs/Android实现方案.md:493` |
| 21 | Lifecycle / Soft Delete | 30-Day Trash Bin (`deleted_at`) | Soft delete transactions by populating `deleted_at`; preserves `confirmed_identifiers` during trash period; permanent delete purges cascade. | Transaction ID, delete action (soft vs permanent) | `deleted_at` timestamp set | Excluded from monthly aggregations; re-import prompts restoring existing record | `docs/Android实现方案.md:469` |
| 22 | Accounting Rules | Monthly Date Attribution (`occurred_on`) | Monthly financial reporting strictly attributes transactions by `occurred_on` (not `imported_at`). Refunds offset current month net expense without altering historical reports. | Date filter `occurred_on BETWEEN ? AND ?`, `deleted_at IS NULL` | Monthly Total Expense, Total Refund, Net Expense | Transfers excluded from income/expense statistics | `docs/跨平台架构与数据规范.md:350` |
| 23 | Database Encryption | SQLCipher Hardware-Backed DB Key | Encrypts full SQLite database using AES-256 via SQLCipher with key derived from hardware Keystore / Keychain. | 256-bit key from Pigeon `getOrCreateDatabaseKey()` | Encrypted DB file | Access denied / decrypt failure if key invalid | `docs/跨平台架构与数据规范.md:127,141` |

---

## Edge Cases

| # | Feature | Input | Observed Behavior |
|---|---------|-------|-------------------|
| 1 | `amount_minor > 0` CHECK | Attempt to insert transaction with `amount_minor = 0` or negative. | SQLite raises `sqlite3.IntegrityError: CHECK constraint failed: amount_minor > 0`. Zero-amount and negative-amount ledger entries are strictly rejected. |
| 2 | `origin_draft_id UNIQUE` | Attempt to insert two transactions referencing the same `origin_draft_id`. | SQLite raises `sqlite3.IntegrityError: UNIQUE constraint failed: transactions.origin_draft_id`. Ensures absolute technical idempotence. |
| 3 | `confirmed_identifiers` PK | Attempt to insert duplicate compound key `(namespace, identifier_type, complete_value, stable_event_kind)`. | SQLite raises `sqlite3.IntegrityError: UNIQUE constraint failed: confirmed_identifiers...`. Prevents concurrent duplicate entry of the same platform bill. |
| 4 | Refund Unlinking on Delete | Delete an original expense transaction that has an entry in `refund_links`. | `refund_links` row is cascade-deleted, but the refund transaction itself (`transactions` row with `type = 'refund'`) remains intact and unmodified. |
| 5 | Deletion of Category in Use | Delete a category that is referenced by active transactions (`category_id`). | SQLite raises `sqlite3.IntegrityError: FOREIGN KEY constraint failed` due to `ON DELETE RESTRICT`. Prevents orphan transactions without category. |
| 6 | Deletion of Parent Category | Delete a parent category referenced by a subcategory (`categories.parent_id`). | Subcategory's `parent_id` is set to `NULL` via `ON DELETE SET NULL`. Subcategory becomes a top-level category without data loss. |
| 7 | Deletion of Project in Use | Delete a project referenced by `transactions.project_id` or `classification_rules.project_id`. | Referenced columns in `transactions` and `classification_rules` are set to `NULL` via `ON DELETE SET NULL`. Transactions and rules remain valid. |
| 8 | Consecutive Purchases Same Store | Two consecutive transactions at the exact same merchant with identical amount, but distinct platform order numbers. | Tier 3 recognizes distinct complete order numbers in `confirmed_identifiers`; both transactions are recorded cleanly without false collision. |
| 9 | Consecutive Purchases No Order Number | Two consecutive purchases at same store with same amount, but screenshot lacks complete order number. | Tier 4 flags soft duplicate warning in `duplicate_candidates`. User confirms "This is another transaction", allowing user to commit without being blocked. |
| 10 | Soft-Deleted Transaction Re-import | User imports screenshot of a transaction that was soft-deleted (`deleted_at IS NOT NULL`). | Tier 3 matches `confirmed_identifiers`. System detects transaction exists in trash bin, displays prompt to restore existing transaction with original ID. |
| 11 | Permanent Delete and Re-import | User permanently deletes a transaction, then re-imports the same screenshot later. | All cascade rows in `confirmed_identifiers` and `refund_links` were purged during permanent deletion. The screenshot is treated as a brand new transaction. |
| 12 | App Killed During OCR | System terminates app process while `capture_jobs.state == 'RECOGNIZING'`. | On subsequent app launch, startup recovery query finds jobs in `RECOGNIZING` state and automatically resets them to `IMPORTED` or `FAILED` for retry. |
| 13 | Cross-Month Refund Calculation | September expense of 10000 分, refunded 3000 分 in October. | September report remains total expense 10000 分, net expense 10000 分. October report shows refund 3000 分, net expense reduced by 3000 分. September is not mutated. |
| 14 | Internal Transfer Between Accounts | User records transfer of 50000 分 from account A to account B (`type = 'transfer'`). | Both `account_id` and `transfer_to_account_id` populated. Transfer is excluded from monthly total income, total expense, and category rankings. |
| 15 | Abnormal Payment Status in OCR | Screenshot contains "待付款" (pending) or "支付失败" (failed). | Parser identifies abnormal status; draft marks issue `STATUS_ABNORMAL`. System forbids direct commit to formal expense ledger without user manual override. |

---

## Detailed Investigation Points

### 1. Exact DDL for the 12 Core Tables

The database schema is defined identically across Android and iOS using the following 12 tables.

#### Table 1: `capture_jobs` (Ingestion Task Log)
```sql
CREATE TABLE IF NOT EXISTS capture_jobs (
    id TEXT PRIMARY KEY NOT NULL,                -- Task UUID
    content_hash TEXT NOT NULL,                 -- Image SHA-256 hex string
    source_kind TEXT NOT NULL,                  -- share_extension, photo_picker, shortcuts, clipboard, etc.
    imported_at TEXT NOT NULL,                  -- UTC ISO-8601 timestamp
    private_image_ref TEXT NOT NULL,            -- Relative path in app private sandbox
    state TEXT NOT NULL,                        -- IMPORTED, RECOGNIZING, NEEDS_REVIEW, COMMITTED, FAILED, DISCARDED
    attempt_count INTEGER NOT NULL DEFAULT 0,   -- Retry attempt counter
    parser_version INTEGER NOT NULL DEFAULT 1,  -- Parsing rule extractor version
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

#### Table 2: `drafts` (OCR Recognition Drafts)
```sql
CREATE TABLE IF NOT EXISTS drafts (
    id TEXT PRIMARY KEY NOT NULL,                -- Draft UUID
    capture_id TEXT NOT NULL UNIQUE,            -- Associated capture_jobs.id (1-to-1)
    candidate_fields TEXT NOT NULL,             -- JSON string: candidate amounts, merchants, times, channels
    field_evidence TEXT NOT NULL,               -- JSON string: OCR lines and normalized bounding box coordinates
    validation_issues TEXT NOT NULL,            -- JSON array: validation issues (e.g. ["MISSING_DATE", "MULTIPLE_AMOUNTS"])
    duplicate_candidates TEXT NOT NULL,         -- JSON array: suspected duplicate transaction IDs
    saved_transaction_id TEXT,                  -- Formal transaction ID if saved, otherwise NULL
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(capture_id) REFERENCES capture_jobs(id) ON DELETE CASCADE
);
```

#### Table 3: `accounts` (Financial Accounts)
```sql
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY NOT NULL,                -- Account UUID
    name TEXT NOT NULL,                         -- Account name (e.g. '招商银行储蓄卡')
    kind TEXT NOT NULL,                         -- cash, debit_card, credit_card, e_wallet, other
    card_last4 TEXT,                            -- Last 4 digits for identification, nullable
    archived_at TEXT,                           -- Soft archive timestamp, NULL if active
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

#### Table 4: `categories` (Transaction Categories)
```sql
CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY NOT NULL,                -- Category UUID
    name TEXT NOT NULL,                         -- Category name (e.g. '餐饮美食')
    parent_id TEXT,                             -- Parent category ID for 2-tier tree, NULL for top-level
    applicable_type TEXT NOT NULL,              -- expense, income, both
    icon_key TEXT,                              -- Built-in icon identifier
    sort_order INTEGER NOT NULL DEFAULT 0,      -- Display sort order
    archived_at TEXT,                           -- Soft archive timestamp
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(parent_id) REFERENCES categories(id) ON DELETE SET NULL
);
```

#### Table 5: `projects` (Project Grouping)
```sql
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY NOT NULL,                -- Project UUID
    name TEXT NOT NULL,                         -- Project name (e.g. '2026云南旅行')
    archived_at TEXT,                           -- Soft archive timestamp
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

#### Table 6: `tags` (Orthogonal Tags)
```sql
CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY NOT NULL,                -- Tag UUID
    name TEXT NOT NULL,                         -- Tag name (e.g. '可报销', '朋友聚餐')
    archived_at TEXT,                           -- Soft archive timestamp
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

#### Table 7: `transactions` (Formal Ledger Entries)
```sql
CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY NOT NULL,                -- Transaction UUID
    origin_draft_id TEXT UNIQUE,                -- Origin draft ID (hard idempotence constraint)
    type TEXT NOT NULL,                         -- expense, income, refund, transfer
    amount_minor INTEGER NOT NULL,              -- Amount in minor units (分), strictly > 0
    currency TEXT NOT NULL DEFAULT 'CNY',       -- ISO currency code
    merchant_raw TEXT NOT NULL,                 -- Raw OCR / user entered merchant name
    merchant_normalized TEXT,                   -- Canonical merchant name
    occurred_on TEXT NOT NULL,                  -- Accounting date (YYYY-MM-DD)
    occurred_at TEXT,                           -- UTC ISO-8601 precise timestamp, nullable
    event_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
    event_time_source TEXT NOT NULL,            -- ocr_extracted, suggested_today, user_selected
    event_time_precision TEXT NOT NULL,         -- second, minute, day
    payment_channel TEXT NOT NULL,              -- wechat, alipay, unionpay, cash, other
    account_id TEXT,                            -- Outflow / inflow account ID
    transfer_to_account_id TEXT,                -- Inflow account ID (only for transfer type)
    category_id TEXT,                           -- Main category ID
    project_id TEXT,                            -- Associated project ID
    note TEXT,                                  -- User note / remarks
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,                            -- Soft-delete timestamp (30-day trash bin)
    CHECK (amount_minor > 0),
    FOREIGN KEY(origin_draft_id) REFERENCES drafts(id) ON DELETE SET NULL,
    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE SET NULL,
    FOREIGN KEY(transfer_to_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
    FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT,
    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
);
```

#### Table 8: `transaction_metadata` (Transaction Extended Metadata)
```sql
CREATE TABLE IF NOT EXISTS transaction_metadata (
    transaction_id TEXT PRIMARY KEY NOT NULL,   -- Foreign key to transactions.id
    original_amount_minor INTEGER,              -- Original price before discounts (分)
    discount_minor INTEGER,                     -- Total discount / subsidy (分)
    fee_minor INTEGER,                          -- Service fee (分)
    payment_status TEXT NOT NULL DEFAULT 'SUCCESS', -- SUCCESS, REFUNDED, PARTIAL_REFUNDED
    platform_transaction_no TEXT,               -- Official WeChat Pay / Alipay full order ID
    merchant_order_no TEXT,                     -- Merchant internal order ID
    identifier_completeness TEXT NOT NULL DEFAULT 'NONE', -- NONE, COMPLETE, MASKED, TRUNCATED, UNRELIABLE
    payment_method_label TEXT,                  -- UI payment label (e.g. '招商银行储蓄卡(1234)')
    FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
);
```

#### Table 9: `transaction_tags` (Transaction-Tag Join Table)
```sql
CREATE TABLE IF NOT EXISTS transaction_tags (
    transaction_id TEXT NOT NULL,               -- Foreign key to transactions.id
    tag_id TEXT NOT NULL,                       -- Foreign key to tags.id
    PRIMARY KEY (transaction_id, tag_id),
    FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
    FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
);
```

#### Table 10: `refund_links` (Refund Relationship Table)
```sql
CREATE TABLE IF NOT EXISTS refund_links (
    refund_transaction_id TEXT PRIMARY KEY NOT NULL, -- Refund transaction ID
    original_expense_id TEXT NOT NULL,               -- Original expense transaction ID
    created_at TEXT NOT NULL,
    FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
    FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
);
```

#### Table 11: `classification_rules` (Classification Rule Engine)
```sql
CREATE TABLE IF NOT EXISTS classification_rules (
    id TEXT PRIMARY KEY NOT NULL,                -- Rule UUID
    priority INTEGER NOT NULL DEFAULT 100,      -- Matching priority (higher value evaluated first)
    merchant_pattern TEXT NOT NULL,             -- Matching pattern (glob / regex)
    payment_channel TEXT,                       -- Optional channel filter (wechat / alipay)
    category_id TEXT NOT NULL,                  -- Target category ID on match
    project_id TEXT,                            -- Optional target project ID on match
    enabled INTEGER NOT NULL DEFAULT 1,         -- 1 = enabled, 0 = disabled
    version INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
);
```

#### Table 12: `confirmed_identifiers` (Unique Identifier Index for Hard Deduplication)
```sql
CREATE TABLE IF NOT EXISTS confirmed_identifiers (
    namespace TEXT NOT NULL,                    -- Platform namespace (e.g. 'wechat_pay', 'alipay')
    identifier_type TEXT NOT NULL,              -- Identifier kind (e.g. 'platform_transaction_no')
    complete_value TEXT NOT NULL,               -- Full, unmasked identifier string
    stable_event_kind TEXT NOT NULL,            -- 'payment' or 'refund'
    transaction_id TEXT NOT NULL,               -- Target formal transaction ID
    PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind),
    FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
);
```

---

### 2. Complete Cascade Rules and Constraint Analysis

Foreign key constraints in SQLite must be explicitly enabled via `PRAGMA foreign_keys = ON;`. The system implements specific cascade behaviors tailored for ledger integrity:

| Foreign Key | Referenced Table & Column | Cascade Action | Rationale & Behavioral Effect |
|-------------|---------------------------|----------------|-------------------------------|
| `drafts(capture_id)` | `capture_jobs(id)` | `ON DELETE CASCADE` | When an ingestion job is purged, its draft and OCR candidate cache are deleted. |
| `categories(parent_id)` | `categories(id)` | `ON DELETE SET NULL` | When a parent category is deleted, child categories are detached and promoted to top-level. |
| `transactions(origin_draft_id)` | `drafts(id)` | `ON DELETE SET NULL` | When drafts / OCR cache are cleaned up, committed transactions persist with origin set to NULL. |
| `transactions(account_id)` | `accounts(id)` | `ON DELETE SET NULL` | Deleting an account detaches the transaction without deleting historical ledger records. |
| `transactions(transfer_to_account_id)` | `accounts(id)` | `ON DELETE SET NULL` | Deleting destination account detaches destination field; ledger entry remains. |
| `transactions(category_id)` | `categories(id)` | `ON DELETE RESTRICT` | **Critical safety constraint**: Categories in active use cannot be deleted. Users must reclassify transactions or archive the category. |
| `transactions(project_id)` | `projects(id)` | `ON DELETE SET NULL` | Deleting a project retains all member transactions, setting `project_id = NULL`. |
| `transaction_metadata(transaction_id)` | `transactions(id)` | `ON DELETE CASCADE` | Metadata lifecycle is 1:1 bound to transaction lifecycle. |
| `transaction_tags(transaction_id)` | `transactions(id)` | `ON DELETE CASCADE` | Removing a transaction purges all associated tag bindings. |
| `transaction_tags(tag_id)` | `tags(id)` | `ON DELETE CASCADE` | Removing a tag purges association rows from join table without modifying transactions. |
| `refund_links(refund_transaction_id)` | `transactions(id)` | `ON DELETE CASCADE` | Deleting a refund transaction purges the refund link. |
| `refund_links(original_expense_id)` | `transactions(id)` | `ON DELETE CASCADE` | **Crucial unlinking mechanism**: When the original expense is permanently deleted, SQLite cascade-deletes the row in `refund_links`. However, the refund transaction itself (`transactions` row with `id = refund_transaction_id`) is **NOT** deleted. The refund transaction simply becomes an unlinked standalone refund. |
| `classification_rules(category_id)` | `categories(id)` | `ON DELETE CASCADE` | Deleting a category purges all automated classification rules mapping into it. |
| `classification_rules(project_id)` | `projects(id)` | `ON DELETE SET NULL` | Deleting a project clears project assignment from rules without deleting the rule. |
| `confirmed_identifiers(transaction_id)` | `transactions(id)` | `ON DELETE CASCADE` | Permanent deletion of a transaction releases its platform transaction ID, allowing it to be recorded anew if ever re-imported. |

---

### 3. Exact DDL for the 11 Performance Indices

The following 11 indices are verified in `test_docs_integrity.py` and must be created identically:

```sql
-- 1. Accelerates Tier 2 same-image hash duplicate lookup
CREATE INDEX IF NOT EXISTS idx_capture_jobs_hash ON capture_jobs(content_hash);

-- 2. Accelerates querying pending jobs (e.g. IMPORTED, RECOGNIZING) during startup recovery
CREATE INDEX IF NOT EXISTS idx_capture_jobs_state ON capture_jobs(state);

-- 3. Accelerates checking if a draft has already been committed to a transaction
CREATE INDEX IF NOT EXISTS idx_drafts_saved_tx ON drafts(saved_transaction_id);

-- 4. Accelerates monthly report date-range queries (occurred_on BETWEEN ? AND ?)
CREATE INDEX IF NOT EXISTS idx_tx_occurred_on ON transactions(occurred_on);

-- 5. Accelerates category-based transaction filtering and monthly category breakdown
CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);

-- 6. Accelerates filtering active transactions (deleted_at IS NULL) and trash bin management
CREATE INDEX IF NOT EXISTS idx_tx_deleted_at ON transactions(deleted_at);

-- 7. Accelerates project ledger filtering
CREATE INDEX IF NOT EXISTS idx_tx_project ON transactions(project_id);

-- 8. Accelerates account transaction filtering and balance aggregation
CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);

-- 9. Accelerates reverse lookup of transactions associated with a tag
CREATE INDEX IF NOT EXISTS idx_transaction_tags_tag ON transaction_tags(tag_id);

-- 10. Accelerates finding all refunds linked to a specific original expense
CREATE INDEX IF NOT EXISTS idx_refund_original ON refund_links(original_expense_id);

-- 11. Accelerates querying all registered platform IDs for a transaction
CREATE INDEX IF NOT EXISTS idx_confirmed_identifiers_tx ON confirmed_identifiers(transaction_id);
```

---

### 4. Integer Currency Storage Rules (`amount_minor`)

1. **Storage Unit**:
   - Stored in smallest currency units (cents/分, where 1 CNY = 100 分).
   - Target field: `transactions.amount_minor INTEGER NOT NULL`.
   - Supplementary fields: `transaction_metadata.original_amount_minor`, `discount_minor`, `fee_minor`.
2. **Positive Value Enforcement**:
   - Enforced by SQLite `CHECK (amount_minor > 0)`.
   - Zero-amount (`0`) and negative amounts (`< 0`) are rejected at the database engine level.
   - Refunds are recorded with positive `amount_minor > 0` and `type = 'refund'`.
3. **Strict Elimination of Float / Double**:
   - Floating-point representations (`REAL`, `FLOAT`, `DOUBLE`) are strictly forbidden in database persistence and business calculations.
   - UI formatting is handled via integer operations:
     ```dart
     // Formatting integer minor units to display string:
     String formatAmount(int amountMinor) {
       final int yuan = amountMinor ~/ 100;
       final int cents = (amountMinor % 100).abs();
       return '$yuan.${cents.toString().padLeft(2, '0')}';
     }
     ```
4. **Aggregation Specifications**:
   - Monthly Total Expense:
     ```sql
     SELECT COALESCE(SUM(amount_minor), 0) FROM transactions
     WHERE type = 'expense' AND deleted_at IS NULL AND occurred_on BETWEEN ? AND ?;
     ```
   - Monthly Total Refund:
     ```sql
     SELECT COALESCE(SUM(amount_minor), 0) FROM transactions
     WHERE type = 'refund' AND deleted_at IS NULL AND occurred_on BETWEEN ? AND ?;
     ```
   - Monthly Net Expense:
     $$\text{Net Expense} = \text{Total Expense} - \text{Total Refund}$$
   - Internal Transfers (`type = 'transfer'`): Excluded from both expense and income statistics.

---

### 5. Database Initialization, Transaction Management, and Migration Mechanism

#### 5.1 Initialization Flow
1. **Key Acquisition**:
   The Flutter database manager requests the 256-bit database master key from the native platform host via Pigeon `NativeCaptureHostApi.getOrCreateDatabaseKey()`. The key is retrieved from Android Keystore or iOS Keychain.
2. **SQLCipher Connection**:
   Database opened using SQLCipher with the 256-bit key.
3. **Connection PRAGMAs**:
   Every database connection must execute:
   ```sql
   PRAGMA key = "x'<64-char-hex-key>'";
   PRAGMA foreign_keys = ON;
   PRAGMA journal_mode = WAL;
   PRAGMA synchronous = NORMAL;
   ```

#### 5.2 Transaction Management
All state transitions involving multi-table consistency must execute inside an explicit SQLite transaction (`BEGIN IMMEDIATE TRANSACTION ... COMMIT`):
- **Draft Confirmation Transaction**:
  1. Verify draft is in `NEEDS_REVIEW` state.
  2. Insert into `transactions`.
  3. Insert into `transaction_metadata` (if metadata exists).
  4. Insert into `transaction_tags` (if tags selected).
  5. If complete platform order number exists, insert into `confirmed_identifiers`.
  6. If transaction is a refund and original expense selected, insert into `refund_links`.
  7. Update `drafts` setting `saved_transaction_id = tx.id`.
  8. Update `capture_jobs` setting `state = 'COMMITTED'`, `updated_at = datetime('now')`.
  9. Commit transaction.
  *Failure handling*: If any step encounters an integrity constraint violation (e.g. duplicate key in `confirmed_identifiers` or duplicate `origin_draft_id`), the entire transaction rolls back; the draft remains in `NEEDS_REVIEW` and error is displayed.

#### 5.3 Migration Framework
1. **Version Tracking**:
   Tracked using SQLite's built-in `PRAGMA user_version;`.
2. **Version Execution**:
   Each migration step runs in its own transaction:
   ```sql
   BEGIN TRANSACTION;
   -- Execute DDL / DML for version N
   PRAGMA user_version = N;
   COMMIT;
   ```
3. **Idempotence**:
   All migration scripts must use `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS`.

---

### 6. The Exact Four-Tier Anti-Duplicate Mechanism (四层防重)

```text
[新截图导入]
     │
     ▼
[第 1 层：技术幂等性 (Technical Idempotence)]
  ├─ 检查: 重复 Intent / 任务重试 / 已存在 captureId / transactions.origin_draft_id
  └─ 命中: 直接返回并定位到已存在草稿或已入账流水
     │ 未命中
     ▼
[第 2 层：同图 SHA-256 检查 (Same-Image Hash Check)]
  ├─ 检查: capture_jobs.content_hash == 计算出的图片 SHA-256
  └─ 命中: 提示用户该截图已导入过，定位到已有任务 / 草稿 / 账目
     │ 未命中
     ▼
[第 3 层：完整官方单号唯一检查 (Hard Platform Identifier Check)]
  ├─ 检查: confirmed_identifiers (namespace, type, complete_value, stable_event_kind)
  ├─ 规则: 仅完整可信单号参与硬拦截；截断、打码号严禁写入
  ├─ 命中 (活跃交易): 硬拦截！展示已有流水，禁止重复记账
  └─ 命中 (已在回收站): 提示用户该记录在回收站，支持一键恢复原 ID 记录
     │ 未命中
     ▼
[第 4 层：启发式模糊比对 (Heuristic Fuzzy Matching)]
  ├─ 检查: 同商户 (raw 或 normalized) + 同金额 (amount_minor) + 24小时内 (occurred_on/at)
  ├─ 命中: 软警告！填充 drafts.duplicate_candidates，提示用户确认
  │         ├─ 选项 A:「查看已有记录」
  │         └─ 选项 B:「确认这是另一笔交易」（如连续两次同店同金额支付）
  └─ 未命中: 正常生成待确认草稿 (NEEDS_REVIEW)
```

---

### 7. Transaction and Job State Machine

#### 7.1 State Machine Diagram
```text
           ┌──────────────────────────────────────┐
           │                                      │
           ▼                                      │
       [IMPORTED] ──► [RECOGNIZING] ──► [NEEDS_REVIEW] ──► [COMMITTED]
                            │                  │
                            ▼                  ▼
                         [FAILED]         [DISCARDED]
                            │
                            └──► (用户重试 / 启动自愈)
```

#### 7.2 State Transition Matrix
| Source State | Destination State | Trigger / Event | Action & Constraints |
|--------------|-------------------|-----------------|----------------------|
| `None` | `IMPORTED` | New image ingested | Image written to private storage; SHA-256 calculated; job inserted. |
| `IMPORTED` | `RECOGNIZING` | OCR worker started | Platform OCR API invoked via Pigeon `recognizeCapture`. |
| `RECOGNIZING` | `NEEDS_REVIEW` | OCR pipeline finished | Parsing engine extracts fields; inserts into `drafts`. |
| `RECOGNIZING` | `FAILED` | OCR or parser error | Increment `attempt_count`. Record error message. |
| `FAILED` | `RECOGNIZING` | User retry / startup auto-recovery | Retry OCR extraction. |
| `NEEDS_REVIEW` | `COMMITTED` | User confirms draft | Atomic database transaction commits formal transaction. |
| `NEEDS_REVIEW` | `DISCARDED` | User abandons draft | Image cleaned up from private storage; job marked DISCARDED. |
| `RECOGNIZING` | `IMPORTED` | App startup self-healing | On crash recovery, uncompleted jobs reset to allow clean retry. |

#### 7.3 Validation Issues (`drafts.validation_issues`)
- `MISSING_AMOUNT`: No valid amount candidate parsed.
- `MULTIPLE_AMOUNTS`: Ambiguous conflicting amounts (e.g. original vs balance vs discount).
- `MISSING_DATE`: No explicit date recognized (system populates `suggested_today`).
- `MISSING_MERCHANT`: Merchant could not be extracted with high confidence.
- `INVALID_AMOUNT`: Parsed amount is <= 0.
- `STATUS_ABNORMAL`: Bill indicates pending or failed payment (`待付款` / `支付失败`).
- `DUPLICATE_SUSPECTED`: Tier 4 heuristic fuzzy matching found candidate transactions.

---

### 8. Verification Checks in `test_docs_integrity.py`

In `test_docs_integrity.py`, test suite 3 (`test_sqlite_ddl`) enforces the following constraints against SQLite in memory:

1. **Extraction & DDL Execution**: All ````sql ... ```` blocks extracted from `docs/跨平台架构与数据规范.md` must execute with `PRAGMA foreign_keys = ON;` without syntax errors.
2. **12 Tables Presence**:
   - `capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers`.
3. **11 Performance Indices Presence**:
   - `idx_capture_jobs_hash`, `idx_capture_jobs_state`, `idx_drafts_saved_tx`, `idx_tx_occurred_on`, `idx_tx_category`, `idx_tx_deleted_at`, `idx_tx_project`, `idx_tx_account`, `idx_transaction_tags_tag`, `idx_refund_original`, `idx_confirmed_identifiers_tx`.
4. **Amount Constraint**:
   Inserting `amount_minor = 0` must fail with `sqlite3.IntegrityError`.
5. **Idempotence Constraint**:
   Duplicate `origin_draft_id` in `transactions` must fail with `sqlite3.IntegrityError`.
6. **Hard Deduplication Primary Key**:
   Duplicate `(namespace, identifier_type, complete_value, stable_event_kind)` in `confirmed_identifiers` must fail with `sqlite3.IntegrityError`.
7. **Refund Unlinking on Expense Deletion**:
   Deleting original expense in `transactions` must cascade-delete row in `refund_links` while leaving the refund record in `transactions` completely intact.
8. **Project Deletion Nullification**:
   Deleting project must set `classification_rules.project_id` to `NULL`.

---

## Conclusion & Architecture Recommendations

1. **Schema Compliance**: The 12 tables and 11 indices defined in `docs/跨平台架构与数据规范.md` represent the authoritative DDL and must be adopted as the foundational schema.
2. **Zero-Float Policy**: Use `int` minor units (cents) everywhere in Dart and SQLCipher.
3. **Foreign Key Enforcement**: In Flutter / SQLite driver (e.g. `sqflite_sqlcipher` or `sqlite3` via FFI), always execute `PRAGMA foreign_keys = ON;` on every database connection open.
4. **Atomic Operations**: Draft commitment must be wrapped in a single database transaction to guarantee no partial state leaks.
