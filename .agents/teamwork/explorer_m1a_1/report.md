# Milestone M1-A Investigation Report: Unified SQLite Data Layer & Core Ledger Transactions

**Date**: 2026-10-22  
**Milestone**: M1-A  
**Author**: `explorer_m1a_1` (Data Architecture Explorer)  
**Target Recipient**: `orchestrator_1` (Orchestrator) & `worker_m1a_1` (Implementer)  
**Authoritative References**:
- `docs/跨平台架构与数据规范.md` (Sections 3 & 4)
- `test_docs_integrity.py` (Test Suite 3: `test_sqlite_ddl`)
- `pigeons/native_bridge.dart` (`getOrCreateDatabaseKey()`)
- `pubspec.yaml` (`sqflite: ^2.3.3+1`, `sqflite_common_ffi: ^2.3.3`)

---

## 1. Executive Summary

This report establishes the technical blueprint for **Milestone M1-A: Unified SQLite Data Layer & Core Ledger Transactions**.

The design guarantees 100% cross-platform parity across Android and iOS by anchoring the complete relational schema, foreign key cascade actions, 11 performance indices, monetary integrity constraints, and four-tier deduplication state transitions in Flutter's SQLite layer via `sqflite` and `sqflite_common_ffi`.

### Key Architectural Invariants
1. **12 Tables & 11 Indices**: Exactly identical schema matching `docs/跨平台架构与数据规范.md` and verified in `test_docs_integrity.py`.
2. **Zero-Float Accounting**: Mandatory integer cent storage (`amount_minor INTEGER NOT NULL CHECK (amount_minor > 0)`). Floating-point numbers are completely prohibited in persistence and business logic.
3. **Strict Foreign Key Enforcement**: `PRAGMA foreign_keys = ON;` is executed on every database connection during `onConfigure`.
4. **Desktop & Headless Test Support**: Headless execution in `flutter test` on Windows/Linux/macOS is enabled via `sqfliteFfiInit()` and `databaseFactory = databaseFactoryFfi`.
5. **Cascade & Unlinking Semantics**:
   - `refund_links.original_expense_id REFERENCES transactions(id) ON DELETE CASCADE` automatically unlinks refunds when original expenses are purged, without deleting the refund transaction itself.
   - `transactions.category_id REFERENCES categories(id) ON DELETE RESTRICT` prevents orphan ledger entries.
   - `transactions.origin_draft_id TEXT UNIQUE` ensures strict Tier 1 idempotence.
   - `confirmed_identifiers` compound primary key guarantees Tier 3 hard deduplication.

---

## 2. Complete SQL DDL for All 12 Tables

The 12 tables must be created in order of their foreign key dependency tree:
`capture_jobs` -> `drafts` -> `accounts` -> `categories` -> `projects` -> `tags` -> `transactions` -> `transaction_metadata` -> `transaction_tags` -> `refund_links` -> `classification_rules` -> `confirmed_identifiers`.

```sql
-- ============================================================================
-- 1. Ingestion Task Log (capture_jobs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS capture_jobs (
    id TEXT PRIMARY KEY NOT NULL,
    content_hash TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    imported_at TEXT NOT NULL,
    private_image_ref TEXT NOT NULL,
    state TEXT NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    parser_version INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- ============================================================================
-- 2. OCR Recognition Drafts (drafts)
-- ============================================================================
CREATE TABLE IF NOT EXISTS drafts (
    id TEXT PRIMARY KEY NOT NULL,
    capture_id TEXT NOT NULL UNIQUE,
    candidate_fields TEXT NOT NULL,
    field_evidence TEXT NOT NULL,
    validation_issues TEXT NOT NULL,
    duplicate_candidates TEXT NOT NULL,
    saved_transaction_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(capture_id) REFERENCES capture_jobs(id) ON DELETE CASCADE
);

-- ============================================================================
-- 3. Financial Accounts (accounts)
-- ============================================================================
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    card_last4 TEXT,
    archived_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- ============================================================================
-- 4. Transaction Categories (categories)
-- ============================================================================
CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    parent_id TEXT,
    applicable_type TEXT NOT NULL,
    icon_key TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    archived_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(parent_id) REFERENCES categories(id) ON DELETE SET NULL
);

-- ============================================================================
-- 5. Projects (projects)
-- ============================================================================
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    archived_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- ============================================================================
-- 6. Orthogonal Tags (tags)
-- ============================================================================
CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    archived_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- ============================================================================
-- 7. Formal Financial Ledger (transactions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY NOT NULL,
    origin_draft_id TEXT UNIQUE,
    type TEXT NOT NULL,
    amount_minor INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'CNY',
    merchant_raw TEXT NOT NULL,
    merchant_normalized TEXT,
    occurred_on TEXT NOT NULL,
    occurred_at TEXT,
    event_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
    event_time_source TEXT NOT NULL,
    event_time_precision TEXT NOT NULL,
    payment_channel TEXT NOT NULL,
    account_id TEXT,
    transfer_to_account_id TEXT,
    category_id TEXT,
    project_id TEXT,
    note TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    CHECK (amount_minor > 0),
    FOREIGN KEY(origin_draft_id) REFERENCES drafts(id) ON DELETE SET NULL,
    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE SET NULL,
    FOREIGN KEY(transfer_to_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
    FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT,
    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
);

-- ============================================================================
-- 8. Transaction Extended Metadata (transaction_metadata)
-- ============================================================================
CREATE TABLE IF NOT EXISTS transaction_metadata (
    transaction_id TEXT PRIMARY KEY NOT NULL,
    original_amount_minor INTEGER,
    discount_minor INTEGER,
    fee_minor INTEGER,
    payment_status TEXT NOT NULL DEFAULT 'SUCCESS',
    platform_transaction_no TEXT,
    merchant_order_no TEXT,
    identifier_completeness TEXT NOT NULL DEFAULT 'NONE',
    payment_method_label TEXT,
    FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
);

-- ============================================================================
-- 9. Transaction-Tag Join Table (transaction_tags)
-- ============================================================================
CREATE TABLE IF NOT EXISTS transaction_tags (
    transaction_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (transaction_id, tag_id),
    FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
    FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- ============================================================================
-- 10. Refund Relationship Table (refund_links)
-- ============================================================================
CREATE TABLE IF NOT EXISTS refund_links (
    refund_transaction_id TEXT PRIMARY KEY NOT NULL,
    original_expense_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
    FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
);

-- ============================================================================
-- 11. Merchant Classification Rules (classification_rules)
-- ============================================================================
CREATE TABLE IF NOT EXISTS classification_rules (
    id TEXT PRIMARY KEY NOT NULL,
    priority INTEGER NOT NULL DEFAULT 100,
    merchant_pattern TEXT NOT NULL,
    payment_channel TEXT,
    category_id TEXT NOT NULL,
    project_id TEXT,
    enabled INTEGER NOT NULL DEFAULT 1,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
);

-- ============================================================================
-- 12. Unique Identifier Hard Deduplication Table (confirmed_identifiers)
-- ============================================================================
CREATE TABLE IF NOT EXISTS confirmed_identifiers (
    namespace TEXT NOT NULL,
    identifier_type TEXT NOT NULL,
    complete_value TEXT NOT NULL,
    stable_event_kind TEXT NOT NULL,
    transaction_id TEXT NOT NULL,
    PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind),
    FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
);
```

---

## 3. The 11 Performance Indices

The following 11 indices match `docs/跨平台架构与数据规范.md` lines 159-338 and are strictly verified in `test_docs_integrity.py:115-120`:

```sql
-- 1. Tier 2 Same-image hash duplicate query
CREATE INDEX IF NOT EXISTS idx_capture_jobs_hash ON capture_jobs(content_hash);

-- 2. Startup recovery for jobs in IMPORTED / RECOGNIZING state
CREATE INDEX IF NOT EXISTS idx_capture_jobs_state ON capture_jobs(state);

-- 3. Check if draft has already been saved to a transaction
CREATE INDEX IF NOT EXISTS idx_drafts_saved_tx ON drafts(saved_transaction_id);

-- 4. Monthly ledger date filtering (occurred_on BETWEEN ? AND ?)
CREATE INDEX IF NOT EXISTS idx_tx_occurred_on ON transactions(occurred_on);

-- 5. Category ledger filtering & monthly breakdown
CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);

-- 6. Filter active transactions (deleted_at IS NULL) & trash bin queries
CREATE INDEX IF NOT EXISTS idx_tx_deleted_at ON transactions(deleted_at);

-- 7. Project ledger grouping and reporting
CREATE INDEX IF NOT EXISTS idx_tx_project ON transactions(project_id);

-- 8. Account balance aggregation & account transaction log
CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);

-- 9. Reverse lookup of transactions associated with a tag
CREATE INDEX IF NOT EXISTS idx_transaction_tags_tag ON transaction_tags(tag_id);

-- 10. Query all refund records linked to an original expense
CREATE INDEX IF NOT EXISTS idx_refund_original ON refund_links(original_expense_id);

-- 11. Query registered platform identifiers by transaction ID
CREATE INDEX IF NOT EXISTS idx_confirmed_identifiers_tx ON confirmed_identifiers(transaction_id);
```

---

## 4. Foreign Key Constraints & Cascade Semantics Matrix

| Foreign Key | Referenced Target | Cascade Action | Purpose & Operational Semantics |
|-------------|-------------------|----------------|---------------------------------|
| `drafts.capture_id` | `capture_jobs.id` | `ON DELETE CASCADE` | Purging an ingestion job removes its OCR draft candidate cache. |
| `categories.parent_id` | `categories.id` | `ON DELETE SET NULL` | Deleting a parent category unlinks subcategories, promoting them to top-level. |
| `transactions.origin_draft_id` | `drafts.id` | `ON DELETE SET NULL` | Purging temporary drafts does not damage permanent ledger records. |
| `transactions.account_id` | `accounts.id` | `ON DELETE SET NULL` | Deleting an account preserves ledger history while unlinking account. |
| `transactions.transfer_to_account_id` | `accounts.id` | `ON DELETE SET NULL` | Deleting transfer destination account preserves the transfer record. |
| `transactions.category_id` | `categories.id` | `ON DELETE RESTRICT` | **Critical Safety**: Prevents deletion of categories in active use. Raises `FOREIGN KEY constraint failed`. |
| `transactions.project_id` | `projects.id` | `ON DELETE SET NULL` | Deleting a project retains member transactions with `project_id = NULL`. |
| `transaction_metadata.transaction_id` | `transactions.id` | `ON DELETE CASCADE` | Extended metadata strictly tracks transaction lifecycle. |
| `transaction_tags.transaction_id` | `transactions.id` | `ON DELETE CASCADE` | Deleting transaction purges its tag join associations. |
| `transaction_tags.tag_id` | `tags.id` | `ON DELETE CASCADE` | Deleting tag removes join associations without deleting transactions. |
| `refund_links.refund_transaction_id` | `transactions.id` | `ON DELETE CASCADE` | Deleting a refund transaction purges the refund link. |
| `refund_links.original_expense_id` | `transactions.id` | `ON DELETE CASCADE` | **Crucial Behavior**: Permanently deleting an original expense cascade-deletes the `refund_links` row. The refund transaction itself (`transactions` row) remains completely intact as an unlinked refund. |
| `classification_rules.category_id` | `categories.id` | `ON DELETE CASCADE` | Deleting a category purges all automated classification rules mapping into it. |
| `classification_rules.project_id` | `projects.id` | `ON DELETE SET NULL` | Deleting a project nullifies rule project assignment without deleting rule. |
| `confirmed_identifiers.transaction_id` | `transactions.id` | `ON DELETE CASCADE` | Permanently deleting a transaction releases its platform ID for re-import. |

---

## 5. Database Helper Architecture (`lib/data/database/app_database.dart`)

### 5.1 FFI & Connection Mechanics
1. **Desktop / Headless Environment Initialization**:
   `sqflite` on Windows, Linux, and macOS requires `sqflite_common_ffi`.
   ```dart
   if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
     sqfliteFfiInit();
     databaseFactory = databaseFactoryFfi;
   }
   ```
2. **`PRAGMA foreign_keys = ON;` in `onConfigure`**:
   SQLite disables foreign keys by default for backwards compatibility. Setting it in `onConfigure` ensures that every connection opened executes `PRAGMA foreign_keys = ON;` prior to running `onCreate`, migrations, or user queries.
3. **In-Memory Testing Support**:
   For headless unit tests, `openDatabase(inMemoryDatabasePath, ...)` provides sub-millisecond setup and complete isolation without touching disk.

### 5.2 Implementation Blueprint for `AppDatabase`

```dart
// lib/data/database/app_database.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'schema.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const String dbName = 'singwallet.db';
  static const int dbVersion = 1;

  Database? _db;
  DatabaseFactory? _customFactory;

  /// Visible for testing to inject custom factory or reset singleton
  @visibleForTesting
  void setDatabaseFactory(DatabaseFactory factory) {
    _customFactory = factory;
  }

  /// Ensure desktop FFI is initialized if running on Windows/Linux/macOS
  static void initializeFfi() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  /// Get active database connection, opening if needed
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await open();
    return _db!;
  }

  /// Opens the database at default persistent path or custom path
  Future<Database> open({String? customPath, String? password}) async {
    initializeFfi();
    final factory = _customFactory ?? databaseFactory;

    final String path;
    if (customPath != null) {
      path = customPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      path = p.join(docsDir.path, dbName);
    }

    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) async {
          // Mandatory: Execute immediately on connection
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final sql in AppSchema.createTablesStatements) {
            batch.execute(sql);
          }
          for (final sql in AppSchema.createIndicesStatements) {
            batch.execute(sql);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Schema migrations framework
        },
        onOpen: (db) async {
          if (path != inMemoryDatabasePath) {
            await db.execute('PRAGMA journal_mode = WAL;');
            await db.execute('PRAGMA synchronous = NORMAL;');
          }
        },
      ),
    );

    return _db!;
  }

  /// Opens an isolated in-memory database for testing
  static Future<Database> openInMemory({DatabaseFactory? factory}) async {
    initializeFfi();
    final f = factory ?? databaseFactoryFfi;
    return await f.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final sql in AppSchema.createTablesStatements) {
            batch.execute(sql);
          }
          for (final sql in AppSchema.createIndicesStatements) {
            batch.execute(sql);
          }
          await batch.commit(noResult: true);
        },
      ),
    );
  }

  /// Closes database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  /// For testing: close and reset internal reference
  @visibleForTesting
  Future<void> reset() async {
    await close();
  }
}
```

---

## 6. Directory Structure & File Manifest for M1-A Worker

The implementer (`worker_m1a_1`) should create the following files:

```text
lib/
├── data/
│   ├── database/
│   │   ├── app_database.dart          # Database open, configure, PRAGMA, FFI helper
│   │   ├── schema.dart                # Table creation and index SQL statements
│   │   ├── transaction_manager.dart   # Atomic multi-table commits, soft-delete, reports
│   │   └── state_machine.dart         # Task state lifecycle transitions & self-healing
│   └── models/
│       ├── models.dart                # Barrel export for all 12 models
│       ├── capture_job.dart           # Model for capture_jobs table
│       ├── draft.dart                 # Model for drafts table
│       ├── account.dart               # Model for accounts table
│       ├── category.dart              # Model for categories table
│       ├── project.dart               # Model for projects table
│       ├── tag.dart                   # Model for tags table
│       ├── transaction_entry.dart     # Model for transactions table
│       ├── transaction_metadata.dart  # Model for transaction_metadata table
│       ├── transaction_tag.dart       # Model for transaction_tags table
│       ├── refund_link.dart           # Model for refund_links table
│       ├── classification_rule.dart   # Model for classification_rules table
│       └── confirmed_identifier.dart  # Model for confirmed_identifiers table
└── features/
    └── deduplication/
        └── deduplication_engine.dart  # 4-tier anti-duplicate evaluation engine
```

### Corresponding Test Manifest
```text
test/
├── database/
│   ├── app_database_test.dart         # PRAGMA foreign_keys, FFI desktop, in-memory open
│   ├── ddl_integrity_test.dart        # 12 tables, 11 indices, amount > 0 CHECK, UNIQUE
│   ├── cascade_rules_test.dart        # refund_links CASCADE, RESTRICT, SET NULL tests
│   ├── transaction_manager_test.dart  # Atomic commit, soft-delete, trash recovery, monthly stats
│   └── state_machine_test.dart        # State transitions, error retry, startup recovery
└── deduplication/
    └── four_tier_dedup_test.dart      # Tier 1, 2, 3 (hard intercept), 4 (fuzzy candidate)
```

---

## 7. Model Layer Design (`lib/data/models/`)

All models must adhere to:
1. **Immutable fields** (`final`).
2. **Type-safe Enums** with serialization to uppercase or lowercase strings matching SQLite schema.
3. **`fromMap(Map<String, dynamic> map)`** and **`toMap()`** methods.
4. **`copyWith(...)`** for immutable modifications.
5. **No `double` for currency**: `int amountMinor` in cents everywhere.

### Key Model Enums
```dart
enum JobState {
  imported,
  recognizing,
  needsReview,
  committed,
  failed,
  discarded;

  String toDbString() => name.toUpperCase();
  static JobState fromDbString(String val) =>
      JobState.values.firstWhere((e) => e.name.toUpperCase() == val.toUpperCase());
}

enum TransactionType {
  expense,
  income,
  refund,
  transfer;

  String toDbString() => name;
  static TransactionType fromDbString(String val) =>
      TransactionType.values.firstWhere((e) => e.name == val);
}

enum EventTimePrecision { second, minute, day }
enum EventTimeSource { ocrExtracted, suggestedToday, userSelected }
enum PaymentChannel { wechat, alipay, unionpay, cash, other }
enum IdentifierCompleteness { none, complete, masked, truncated, unreliable }
enum PaymentStatus { success, refunded, partialRefunded }
```

---

## 8. Core Transaction Engine & Deduplication Logic

### 8.1 Atomic Draft Commitment (`TransactionManager`)
Committing a draft requires an atomic SQLite transaction:
```dart
Future<void> commitDraft({
  required TransactionEntry transaction,
  TransactionMetadata? metadata,
  List<String>? tagIds,
  ConfirmedIdentifier? identifier,
  String? originalExpenseId,
}) async {
  final db = await _db.database;
  await db.transaction((txn) async {
    // 1. Insert transaction row
    await txn.insert('transactions', transaction.toMap());

    // 2. Insert metadata if provided
    if (metadata != null) {
      await txn.insert('transaction_metadata', metadata.toMap());
    }

    // 3. Insert tags if provided
    if (tagIds != null && tagIds.isNotEmpty) {
      for (final tagId in tagIds) {
        await txn.insert('transaction_tags', {
          'transaction_id': transaction.id,
          'tag_id': tagId,
        });
      }
    }

    // 4. Insert confirmed identifier if complete
    if (identifier != null) {
      await txn.insert('confirmed_identifiers', identifier.toMap());
    }

    // 5. Insert refund link if refund
    if (transaction.type == TransactionType.refund && originalExpenseId != null) {
      await txn.insert('refund_links', {
        'refund_transaction_id': transaction.id,
        'original_expense_id': originalExpenseId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    // 6. Update draft record
    if (transaction.originDraftId != null) {
      await txn.update(
        'drafts',
        {
          'saved_transaction_id': transaction.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [transaction.originDraftId],
      );
    }

    // 7. Transition capture job to COMMITTED
    final draftRows = await txn.query('drafts',
        columns: ['capture_id'],
        where: 'id = ?',
        whereArgs: [transaction.originDraftId]);
    if (draftRows.isNotEmpty) {
      final captureId = draftRows.first['capture_id'] as String;
      await txn.update(
        'capture_jobs',
        {
          'state': 'COMMITTED',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [captureId],
      );
    }
  });
}
```

### 8.2 Monthly Aggregations
```dart
Future<MonthlyFinancialSummary> getMonthlySummary(String yearMonth) async {
  // yearMonth format: "YYYY-MM"
  final startDate = '$yearMonth-01';
  final endDate = '$yearMonth-31';
  final db = await _db.database;

  final expenseRes = await db.rawQuery('''
    SELECT COALESCE(SUM(amount_minor), 0) AS total
    FROM transactions
    WHERE type = 'expense' AND deleted_at IS NULL AND occurred_on BETWEEN ? AND ?
  ''', [startDate, endDate]);
  final totalExpense = (expenseRes.first['total'] as int?) ?? 0;

  final refundRes = await db.rawQuery('''
    SELECT COALESCE(SUM(amount_minor), 0) AS total
    FROM transactions
    WHERE type = 'refund' AND deleted_at IS NULL AND occurred_on BETWEEN ? AND ?
  ''', [startDate, endDate]);
  final totalRefund = (refundRes.first['total'] as int?) ?? 0;

  return MonthlyFinancialSummary(
    totalExpenseMinor: totalExpense,
    totalRefundMinor: totalRefund,
    netExpenseMinor: totalExpense - totalRefund,
  );
}
```

---

## 9. Verification & Quality Gates

The worker's implementation can be verified using the following concrete commands:
1. Run `python test_docs_integrity.py` to ensure schema consistency with specs.
2. Run `C:\Other\Dev\flutter\bin\flutter.bat analyze` to ensure zero static analysis errors.
3. Run `C:\Other\Dev\flutter\bin\flutter.bat test` to execute all unit tests.
