## 2026-10-22T10:49:47Z
You are explorer_m1a_1.
Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_1
Your parent is orchestrator_1 (conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c).

MANDATORY INPUTS (Read first):
- c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_2\report.md
- c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md
- c:\Other\Projects\singwallet\test_docs_integrity.py

Investigation Scope:
Milestone M1-A: Unified SQLite Data Layer & Core Ledger Transactions.
1. Formulate the exact SQL DDL for all 12 tables and 11 indices in Dart/SQLite:
   - Tables: `capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers`.
   - Ensure `CHECK (amount_minor > 0)` and `origin_draft_id UNIQUE` on `transactions`.
   - Ensure `FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE` on `refund_links`.
   - Ensure 11 indices with exact matching names and column lists.
2. Formulate database helper (`lib/data/database/app_database.dart`):
   - Opens database, executes `PRAGMA foreign_keys = ON;` immediately.
   - Supports desktop headless execution with `sqflite_common_ffi` (via `sqfliteFfiInit()` and `databaseFactoryFfi`).
3. Formulate how the worker should structure the database files and models.

Write report to `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_1\report.md` and `handoff.md`.
Notify orchestrator_1 when done.
