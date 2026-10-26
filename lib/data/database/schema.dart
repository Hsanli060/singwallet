// lib/data/database/schema.dart
/// Authoritative SQLite DDL statements and schema definitions for SingWallet.
/// 
/// Strictly aligns with `docs/跨平台架构与数据规范.md` and `test_docs_integrity.py`.
class AppSchema {
  AppSchema._();

  /// Database schema version.
  static const int version = 1;

  // Table names
  static const String tableCaptureJobs = 'capture_jobs';
  static const String tableDrafts = 'drafts';
  static const String tableAccounts = 'accounts';
  static const String tableCategories = 'categories';
  static const String tableProjects = 'projects';
  static const String tableTags = 'tags';
  static const String tableTransactions = 'transactions';
  static const String tableTransactionMetadata = 'transaction_metadata';
  static const String tableTransactionTags = 'transaction_tags';
  static const String tableRefundLinks = 'refund_links';
  static const String tableClassificationRules = 'classification_rules';
  static const String tableConfirmedIdentifiers = 'confirmed_identifiers';

  /// Ordered table creation DDLs honoring foreign key dependencies.
  static const List<String> createTablesStatements = [
    // 1. Ingestion Task Log (capture_jobs)
    '''
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
    ''',

    // 2. OCR Recognition Drafts (drafts)
    '''
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
    ''',

    // 3. Financial Accounts (accounts)
    '''
    CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        card_last4 TEXT,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 4. Transaction Categories (categories)
    '''
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
    ''',

    // 5. Projects (projects)
    '''
    CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 6. Orthogonal Tags (tags)
    '''
    CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 7. Formal Financial Ledger (transactions)
    '''
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
    ''',

    // 8. Transaction Extended Metadata (transaction_metadata)
    '''
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
    ''',

    // 9. Transaction-Tag Join Table (transaction_tags)
    '''
    CREATE TABLE IF NOT EXISTS transaction_tags (
        transaction_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (transaction_id, tag_id),
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
    );
    ''',

    // 10. Refund Relationship Table (refund_links)
    '''
    CREATE TABLE IF NOT EXISTS refund_links (
        refund_transaction_id TEXT PRIMARY KEY NOT NULL,
        original_expense_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
    );
    ''',

    // 11. Merchant Classification Rules (classification_rules)
    '''
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
    ''',

    // 12. Unique Identifier Hard Deduplication Table (confirmed_identifiers)
    '''
    CREATE TABLE IF NOT EXISTS confirmed_identifiers (
        namespace TEXT NOT NULL,
        identifier_type TEXT NOT NULL,
        complete_value TEXT NOT NULL,
        stable_event_kind TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind),
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
    );
    ''',
  ];

  /// The 11 performance B-tree indices required by the specification.
  static const List<String> createIndicesStatements = [
    // 1. Tier 2 Same-image hash duplicate query
    'CREATE INDEX IF NOT EXISTS idx_capture_jobs_hash ON capture_jobs(content_hash);',

    // 2. Startup recovery for jobs in IMPORTED / RECOGNIZING state
    'CREATE INDEX IF NOT EXISTS idx_capture_jobs_state ON capture_jobs(state);',

    // 3. Check if draft has already been saved to a transaction
    'CREATE INDEX IF NOT EXISTS idx_drafts_saved_tx ON drafts(saved_transaction_id);',

    // 4. Monthly ledger date filtering (occurred_on BETWEEN ? AND ?)
    'CREATE INDEX IF NOT EXISTS idx_tx_occurred_on ON transactions(occurred_on);',

    // 5. Category ledger filtering & monthly breakdown
    'CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);',

    // 6. Filter active transactions (deleted_at IS NULL) & trash bin queries
    'CREATE INDEX IF NOT EXISTS idx_tx_deleted_at ON transactions(deleted_at);',

    // 7. Project ledger grouping and reporting
    'CREATE INDEX IF NOT EXISTS idx_tx_project ON transactions(project_id);',

    // 8. Account balance aggregation & account transaction log
    'CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);',

    // 9. Reverse lookup of transactions associated with a tag
    'CREATE INDEX IF NOT EXISTS idx_transaction_tags_tag ON transaction_tags(tag_id);',

    // 10. Query all refund records linked to an original expense
    'CREATE INDEX IF NOT EXISTS idx_refund_original ON refund_links(original_expense_id);',

    // 11. Query registered platform identifiers by transaction ID
    'CREATE INDEX IF NOT EXISTS idx_confirmed_identifiers_tx ON confirmed_identifiers(transaction_id);',
  ];

  /// List of all 12 expected table names.
  static const List<String> expectedTableNames = [
    tableCaptureJobs,
    tableDrafts,
    tableAccounts,
    tableCategories,
    tableProjects,
    tableTags,
    tableTransactions,
    tableTransactionMetadata,
    tableTransactionTags,
    tableRefundLinks,
    tableClassificationRules,
    tableConfirmedIdentifiers,
  ];

  /// List of all 11 expected index names.
  static const List<String> expectedIndexNames = [
    'idx_capture_jobs_hash',
    'idx_capture_jobs_state',
    'idx_drafts_saved_tx',
    'idx_tx_occurred_on',
    'idx_tx_category',
    'idx_tx_deleted_at',
    'idx_tx_project',
    'idx_tx_account',
    'idx_transaction_tags_tag',
    'idx_refund_original',
    'idx_confirmed_identifiers_tx',
  ];
}
