# Handoff Report: 4-Tier Deduplication & Atomic Commitment (M1-A)

**Sender**: `explorer_m1a_2`  
**Recipient**: `orchestrator_1`  
**Milestone**: M1-A (Unified SQLite Data Layer & Core Ledger Transactions)  
**Deliverable Document**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_2\report.md`  

---

## 1. Observation

1. **Mandatory Documentation and DDL Constraints**:
   - In `docs/跨平台架构与数据规范.md:233-264`, the `transactions` table defines `origin_draft_id TEXT UNIQUE` and `CHECK (amount_minor > 0)`.
   - `docs/跨平台架构与数据规范.md:329-338` defines the dedicated index table `confirmed_identifiers` with compound primary key:
     `PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind)`.
   - `docs/跨平台架构与数据规范.md:361-378` defines the 4-tier deduplication flowchart:
     - Level 1: Technical Idempotence (`captureId` / `origin_draft_id`).
     - Level 2: Same-Image Hash Check (`content_hash == image SHA-256`).
     - Level 3: Complete Platform Transaction Number Unique Check (`confirmed_identifiers`).
     - Level 4: Heuristic Fuzzy Matching (Same merchant + identical amount + within 24 hours).
2. **Platform and Domain Edge Cases**:
   - In `docs/Android实现方案.md:465-470`:
     - *"平台交易号的命名空间包含支付平台与编号类型；商户订单号还必须包含稳定商户标识，缺少该作用域时只做疑似重复。截断、打码、OCR 不确定的编号不能作为强唯一键。`stable_event_kind` 区分原支付与退款事件，不因用户修改收支类型或分类而改变；退款使用自己的退款事件标识，不能因为引用原支付订单就被误认为重复消费。"*
     - *"确认入账时在同一数据库事务里再次检查草稿状态、完整标识和重复情况。必须保留「同店同金额连续买两次」这种合法场景；只有日期、没有时分秒时不能按分钟级时间窗口判断。"*
     - *"删除采用 30 天回收站：`deleted_at` 标记后从正常统计排除，完整编号索引暂时保留。再次识别到该交易时提示恢复原记录，保留原 ID，并在草稿的 `saved_transaction_id` 记录结果，不另造一笔。"*
3. **Draft Commitment Transaction Boundaries**:
   - In `docs/Android实现方案.md:493` and `spec_miner_survey_2/report.md:389-401`:
     - Saving draft and transitioning `capture_jobs.state` to `COMMITTED` must occur in the exact same SQLite database transaction.
     - Single transaction writes to `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, (and `refund_links`), updating `drafts.saved_transaction_id` and setting `capture_jobs.state = 'COMMITTED'`.
     - On any constraint violation, immediate rollback occurs, leaving draft in `NEEDS_REVIEW`.
4. **Existing Codebase Foundations**:
   - `lib/core/constants/app_constants.dart:14` already defines:
     `static const Duration fuzzyDedupWindow = Duration(hours: 24);`
   - `pubspec.yaml:14-16` provides `sqflite: ^2.3.3+1`, `sqflite_common_ffi: ^2.3.3`, and `crypto: ^3.0.3`.
   - `test_docs_integrity.py:144-189` already contains reference Python unit tests validating `origin_draft_id UNIQUE`, `amount_minor > 0`, and `confirmed_identifiers` compound PK uniqueness.

---

## 2. Logic Chain

1. **Tier 1 (Technical Idempotence)**:
   - Supported by Observation 1 and Observation 4 (`origin_draft_id UNIQUE`).
   - Querying `transactions WHERE origin_draft_id = ?` allows instant bypass and location of the existing transaction if a draft has already been committed.
   - Enforcing `origin_draft_id UNIQUE` at SQLite level prevents double-commitment even if multiple requests arrive simultaneously.
2. **Tier 2 (Same-Image Hash Check)**:
   - Supported by Observation 1 (`capture_jobs.content_hash` with `idx_capture_jobs_hash`).
   - When an image is ingested, its SHA-256 hash is checked against `capture_jobs`.
   - If matched, the system skips duplicate OCR pipelines and directs the user to the existing draft, existing ledger transaction, or trash bin item.
3. **Tier 3 (Hard Platform Identifier Check)**:
   - Supported by Observation 1 and Observation 2 (`confirmed_identifiers`).
   - Strict filter: only identifiers with `completeness == COMPLETE` participate; masked/truncated numbers are strictly excluded to avoid false positives.
   - Differentiating active transactions (`deleted_at IS NULL`) from soft-deleted transactions (`deleted_at IS NOT NULL`) ensures:
     - Active duplicates are hard-intercepted (`HardDuplicateException`).
     - Trash bin items prompt 1-click restoration keeping original ID.
   - Including `stable_event_kind` (`payment` vs `refund`) in the primary key ensures refunds referencing the same order number do not collide with the payment.
4. **Tier 4 (Heuristic Fuzzy Matching)**:
   - Supported by Observation 1, Observation 2, and Observation 4.
   - Matches merchant (raw or normalized) + identical `amount_minor` + 24-hour window (`AppConstants.fuzzyDedupWindow`).
   - Handles date-only precision by searching $\pm 1$ calendar day, and precise timestamps by checking $\le 24$ hours.
   - Acts as a **soft warning** (populating `drafts.duplicate_candidates` and `DUPLICATE_SUSPECTED`), allowing legitimate double-purchases to be explicitly confirmed by the user.
5. **Atomic Transaction Commitment**:
   - Supported by Observation 3.
   - Using `_database.transaction((txn) async { ... })` ensures ACID atomicity across all 7 affected tables.
   - Verifying `NEEDS_REVIEW` state and checking Tier 1/Tier 3 inside `txn` eliminates race conditions.
   - Any failure (CHECK violation, duplicate ID, FK error) automatically triggers SQLite rollback, preserving pristine database state.

---

## 3. Caveats

- **Network-Free Offline Execution**: Deduplication relies purely on local SQLite storage; external cloud synchronization deduplication is not in scope for M1-A.
- **Merchant Order Number Scoping**: Platform order numbers (WeChat/Alipay) are globally unique within their namespace. Merchant-internal order numbers must include merchant identity to guarantee uniqueness; if merchant scope is absent, they degrade to Tier 4 fuzzy matching.
- **Image Deletion Timing**: Deleting temporary image files is explicitly performed outside the database transaction to prevent filesystem errors from rolling back valid ledger commits.

---

## 4. Conclusion

The architecture, class designs, SQL queries, exception hierarchies, and test specifications for:
1. `lib/features/deduplication/deduplication_engine.dart` (4-tier deduplication engine)
2. `lib/data/database/transaction_manager.dart` (atomic draft commitment transaction manager)
are completely formulated, strictly aligned with `docs/跨平台架构与数据规范.md`, and ready for immediate implementation by Worker M1-A. Full code formulations and test cases are documented in `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_2\report.md`.

---

## 5. Verification Method

1. **Document Inspection**:
   Inspect `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_2\report.md` Sections 5.1 and 5.2 for complete Dart implementations.
2. **Schema & Constraint Alignment**:
   Cross-verify column names and constraints against `docs/跨平台架构与数据规范.md` (Lines 147-338) and `test_docs_integrity.py` (Lines 125-189).
3. **Automated Unit Tests**:
   Once implemented by Worker M1-A, run:
   ```powershell
   flutter test test/deduplication/deduplication_test.dart
   flutter test test/database/transaction_manager_test.dart
   ```
   All test cases specified in Section 6 of `report.md` must pass with exit code 0.
