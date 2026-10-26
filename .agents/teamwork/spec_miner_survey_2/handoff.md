# Handoff Report: R2 统一 SQLite 数据层与事务管理规范挖掘

**Agent**: `spec_miner_survey_2`  
**Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_2`  
**Date**: 2026-10-22  
**Type**: Hard Handoff (Task Complete)

---

## 1. Observation

1. **`ORIGINAL_REQUEST.md:22-24` & `38-39`**:
   > "### R2. 统一 SQLite 数据层与事务管理（M1）  
   > 依据 docs/跨平台架构与数据规范.md 建立完整的 12 张核心数据表、外键级联与 11 项性能索引。实现安全的数据库初始化、事务管理、数据迁移机制以及四层防重与状态机流转逻辑。所有货币金额字段以最小货币单位整数存储。"  
   > "12 张数据表、外键级联（如 refund_links ON DELETE CASCADE 原消费彻底删除解绑）与 11 项索引在 SQLite 引擎中验证通过"  
   > "金额以最小货币单位整数（cents/分）存储，无浮点数精度截断问题"

2. **`docs/跨平台架构与数据规范.md:144-339`**:
   Defines the complete SQL DDL for 12 tables and 11 indices:
   - 12 tables: `capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers`.
   - 11 indices: `idx_capture_jobs_hash`, `idx_capture_jobs_state`, `idx_drafts_saved_tx`, `idx_tx_occurred_on`, `idx_tx_category`, `idx_tx_deleted_at`, `idx_tx_project`, `idx_tx_account`, `idx_transaction_tags_tag`, `idx_refund_original`, `idx_confirmed_identifiers_tx`.

3. **`docs/跨平台架构与数据规范.md:255`**:
   > `CHECK (amount_minor > 0)` in `transactions` table.

4. **`docs/跨平台架构与数据规范.md:304-305`**:
   > `FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE -- 原消费彻底删除时自动解除关联，退款账目本身保留`

5. **`docs/跨平台架构与数据规范.md:360-375` & `docs/Android实现方案.md:456-470`**:
   Defines the four-tier deduplication flow:
   - Layer 1: Technical idempotence (`captureId`, `saved_transaction_id`, `origin_draft_id UNIQUE`).
   - Layer 2: Same-image hash (`content_hash` SHA-256 lookup in `capture_jobs`).
   - Layer 3: Hard platform transaction identifier check (`confirmed_identifiers` table, compound PK `(namespace, identifier_type, complete_value, stable_event_kind)`).
   - Layer 4: Heuristic fuzzy matching (same merchant + same `amount_minor` + within 24 hours `occurred_on`/`at` -> populates `duplicate_candidates`).

6. **`docs/跨平台架构与数据规范.md:153`, `docs/Android实现方案.md:486`, `docs/iOS实现方案.md:520`**:
   Defines the task state machine:
   `[IMPORTED] -> [RECOGNIZING] -> [NEEDS_REVIEW] -> [COMMITTED]` (or `FAILED` / `DISCARDED`).

7. **`test_docs_integrity.py:83-230`**:
   `test_sqlite_ddl()` extracts the SQL blocks from `docs/跨平台架构与数据规范.md`, executes them against SQLite with `PRAGMA foreign_keys = ON;`, and rigorously tests:
   - Creation of 12 tables.
   - Creation of 11 indices.
   - `amount_minor > 0` CHECK violation rejection.
   - `origin_draft_id` UNIQUE violation rejection.
   - `confirmed_identifiers` compound PK violation rejection.
   - Refund unlinking on deletion of original expense without deleting the refund record.
   - `classification_rules` foreign key `ON DELETE SET NULL` on project deletion.

8. **Test Execution Result**:
   Running `python test_docs_integrity.py` succeeded with exit code 0 (`>>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<`).

---

## 2. Logic Chain

1. From Observation 1, R2 requires exact compliance with the schemas, constraints, indexing, integer currency handling, transaction state machines, and deduplication specifications laid out in `docs/跨平台架构与数据规范.md`.
2. From Observation 2, 3, and 7, the schema contains exactly 12 core tables and 11 named performance indices. The SQLite DDL has been verified directly in Python's `sqlite3` driver under `PRAGMA foreign_keys = ON;`.
3. From Observation 4 and 7, when an original expense transaction is deleted from `transactions`, the row in `refund_links` is cascade-deleted, but SQLite does not touch the refund transaction itself (`transactions` row with `type = 'refund'`). This fulfills the unbinding requirement without data corruption.
4. From Observation 3 and 7, storing all currencies as integer cents (`amount_minor`) accompanied by `CHECK (amount_minor > 0)` prevents float precision loss while guaranteeing non-negative, non-zero financial transactions.
5. From Observation 5, deduplication is layered into four distinct stages: technical idempotence, SHA-256 image hash match, complete platform identifier uniqueness (hard intercept), and heuristic fuzzy matching (soft warning).
6. From Observation 6, capture jobs undergo a deterministic state progression (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED`), where drafts with parsing uncertainties remain in `NEEDS_REVIEW` with `validation_issues` rather than failing technically.
7. Combining all the above, a comprehensive specification mining report `report.md` was drafted and confirmed to maintain markdown structural integrity and satisfy repository testing constraints.

---

## 3. Caveats

- **SQLCipher vs Vanilla SQLite in Test Suite**: `test_docs_integrity.py` executes against Python's built-in `sqlite3` without encryption. In the actual Flutter mobile app, SQLCipher FFI is used with a 256-bit key from native Keystore / Keychain. The DDL, indices, and constraints are identical in SQLCipher.
- **SQLite Foreign Keys Default**: SQLite disables foreign keys by default. Every connection in the Flutter implementation must run `PRAGMA foreign_keys = ON;` immediately upon opening.
- No other caveats.

---

## 4. Conclusion

The specification mining for **R2. 统一 SQLite 数据层与事务管理（M1）** is complete. All 12 tables, 11 performance indices, foreign key cascades, integer currency rules, 4-tier deduplication mechanisms, and state transitions have been extracted, cross-verified with `test_docs_integrity.py`, and documented in `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_2\report.md`.

---

## 5. Verification Method

To independently verify this specification report:
1. Run the test suite:
   ```powershell
   python test_docs_integrity.py
   ```
   Expected result: Exit code 0, all 6 test suites passing (including Markdown integrity and SQLite DDL suite).
2. Inspect `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_2\report.md` for full DDL, index definitions, cascade rules, and edge case mappings.
