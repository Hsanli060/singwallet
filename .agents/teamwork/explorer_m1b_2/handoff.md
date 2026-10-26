# Handoff Report: 6-Tier Classification Rule Engine & 3D Orthogonal Grouping (Features F27-F30)

- **Agent**: explorer_m1b_2
- **Milestone**: M1-B (Sub-scope: Classification & 3D Grouping)
- **Recipient**: orchestrator (`a14d1a00-adfd-46db-a470-136d68156a40`)
- **Status**: COMPLETE

---

## 1. Observation

1. **Database Schema & DDL Specifications**:
   - In `docs/跨平台架构与数据规范.md` (lines 195-230, 311-325) and `lib/data/database/schema.dart` (lines 74-108, 183-197), table `categories` defines `parent_id REFERENCES categories(id) ON DELETE SET NULL`; table `projects` defines `id, name, archived_at`; table `tags` defines `id, name, archived_at`; table `transactions` defines `category_id REFERENCES categories(id) ON DELETE RESTRICT` and `project_id REFERENCES projects(id) ON DELETE SET NULL`; table `transaction_tags` defines compound primary key `(transaction_id, tag_id)` with `ON DELETE CASCADE`; table `classification_rules` defines `id, priority INTEGER DEFAULT 100, merchant_pattern TEXT NOT NULL, payment_channel TEXT, category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE, project_id TEXT REFERENCES projects(id) ON DELETE SET NULL, enabled INTEGER DEFAULT 1, version INTEGER DEFAULT 1`.
2. **Existing Models**:
   - `lib/data/models/classification_rule.dart` (lines 1-120), `lib/data/models/category.dart` (lines 1-110), `lib/data/models/project.dart` (lines 1-77), `lib/data/models/tag.dart` (lines 1-77), and `lib/data/models/transaction.dart` (lines 1-110) already define data classes matching the SQLite tables.
3. **Architecture Guidance & Scope in Specifications**:
   - `docs/Android实现方案.md` lines 380-399 states:
     ```text
     「分组」拆成三个彼此独立的维度，避免同一笔钱在汇总时重复计算：
     主分类：一个（餐饮、交通、购物、居家、医疗、娱乐、其他）
     项目：可选一个（国庆旅行、装修、搬家）
     标签：可选多个（工作日、可报销、与朋友聚餐）
     规则优先级：本次用户手动选择 > 用户明确建立的商户规则 > 已确认的历史商户映射 > 内置关键词 > 可选 AI 建议 > 其他 / 待分类。
     修改分类后可选择「以后该商户默认归到餐饮」，不因一次修改就静默改变所有历史记录。
     ```
   - `docs/iOS实现方案.md` lines 473-485 re-affirms the identical 3D orthogonal system, 6-tier hierarchy, and dynamic learning toggle.
4. **Current Implementation Gap**:
   - `lib/features/` currently only contains `deduplication/deduplication_engine.dart`. There is no classification rule engine implemented yet under `lib/features/classification/`.
5. **Peer Subagent Coordination**:
   - `explorer_m1b_1` is analyzing the OCR transaction parsing pipeline (F19-F26).
   - `explorer_m1b_3` is analyzing architecture integration contracts and test suite planning.

---

## 2. Logic Chain

1. **From Observation 1 & 3 to 3D Orthogonal Design**:
   - Because `transactions.category_id` has `RESTRICT` foreign key and is singular, each transaction has exactly one category. Categories form an exhaustive partition of monthly expenditure $\sum \text{Category} = \text{Total Expense}$.
   - Because `transactions.project_id` is nullable and has `SET NULL` cascade, projects represent an independent subset projection $\sum \text{Project} \le \text{Total Expense}$ that does not alter or double-count monthly category budgets.
   - Because `transaction_tags` is a many-to-many junction table, tags provide orthogonal multi-label filtering without modifying category or project balances.
2. **From Observation 3 to 6-Tier Hierarchy**:
   - Information certainty flows from highest (user explicit intent) to lowest (unrecognized fallback).
   - Tier 1 (Manual, confidence 1.0) short-circuits evaluation.
   - Tier 2 (Custom rules in `classification_rules`, confidence 0.95) must be queried with `ORDER BY priority DESC, created_at DESC`.
   - Tier 3 (History, confidence 0.85) queries previous transactions with identical normalized/raw merchant, grouped by category and ordered by frequency and recency.
   - Tier 4 (Built-in dictionary, confidence 0.70) requires a curated Chinese keyword map with longest-match-first sorting to prevent sub-token collisions.
   - Tier 5 (AI recommendation, confidence 0.60) is an optional pluggable provider with strict local schema validation to prevent hallucinated category IDs.
   - Tier 6 (Fallback, confidence 0.10) assigns `cat_other` to prevent misleading automatic guesses.
3. **From Observation 1 to Pattern Matching (F29)**:
   - Rules must support SQL wildcards (`%` -> `.*`, `_` -> `.`) and explicit regexes.
   - Characters other than `%` and `_` must be escaped via `RegExp.escape` to prevent accidental regex injection.
   - Case-insensitivity (`caseSensitive: false`) is mandatory for brand matching (e.g. KFC, 7-Eleven).
   - Redundant wildcards (e.g. `%%%`) must be collapsed to prevent ReDoS.
4. **From Observation 3 to Dynamic Rule Learning (F30)**:
   - When a user confirms a transaction category, `learnRule` creates or updates a rule in `classification_rules`.
   - In accordance with spec, learning applies strictly forward-only: historical transactions in `transactions` are never retroactively altered.

---

## 3. Caveats

1. **Category Seeding**: The initial SQLite DDL creates the `categories` table without default seed rows. Seed scripts or migrations should populate the canonical categories (`cat_food`, `cat_transport`, `cat_shopping`, `cat_entertainment`, `cat_utilities`, `cat_medical`, `cat_income`, `cat_other`) upon database creation.
2. **AI Provider Availability**: Tier 5 is designed as an optional pluggable interface (`AiClassificationProvider`). In Milestone M1-B, local offline rules (Tiers 1-4 and Tier 6) are 100% self-sufficient; Tier 5 will gracefully pass through if no AI provider is configured.
3. **Scope Boundary**: Explorer m1b_2 is read-only investigation. No source code was altered during this task.

---

## 4. Conclusion

The technical blueprint for Features F27-F30 is complete and fully documented in `report.md`.
- Architecture and data flow for the 6-Tier Classification Hierarchy are finalized;
- Wildcard-to-regex compilation algorithm and defensive measures against ReDoS are established;
- Multi-criteria matching logic (merchant, channel, amount range, remarks) is specified;
- Dynamic rule learning semantics and non-retroactivity constraints are clearly scoped;
- Mathematical orthogonality and database relational integrity for the 3D model (Category, Project, Tags) are validated.

---

## 5. Verification Method

To verify the architecture and specifications:
1. **Inspect Blueprint Report**:
   - Read `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1b_2\report.md`
2. **Verify Document Consistency & DDL Integrity**:
   - Run Python verification suite:
     ```powershell
     python test_docs_integrity.py
     ```
   - Verify that all 12 tables and 11 indices pass without errors.
3. **Verify Existing Tests**:
   - Run Flutter test suite:
     ```powershell
     flutter test test/database/database_test.dart
     flutter test test/deduplication/deduplication_test.dart
     ```
