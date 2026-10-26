# BRIEFING — 2026-10-22T10:54:00Z

## Mission
Investigate and formulate the detailed architecture, SQL queries, Dart classes, algorithms, error handling, and testable interfaces for Milestone M1-A: 4-Tier Deduplication & Atomic Commitment.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1a_2
- Original parent: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Milestone: M1-A

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Design 4-tier deduplication engine (`lib/features/deduplication/deduplication_engine.dart`)
- Design atomic draft commitment transaction manager (`lib/data/database/transaction_manager.dart`)
- Align with `ORIGINAL_REQUEST.md`, `PROJECT.md`, `spec_miner_survey_2/report.md`, and `docs/跨平台架构与数据规范.md`

## Current Parent
- Conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md`, `orchestrator_1/PROJECT.md`
  - `spec_miner_survey_2/report.md`
  - `docs/跨平台架构与数据规范.md`, `docs/Android实现方案.md`, `docs/iOS实现方案.md`
  - `pubspec.yaml`, `lib/core/constants/app_constants.dart`, `lib/core/utils/currency_utils.dart`
  - `test_docs_integrity.py`
  - Peer explorer scopes (`explorer_m1a_1`, `explorer_m1a_3`)
- **Key findings**:
  - Tier 1: Enforces technical idempotence via `origin_draft_id UNIQUE` on `transactions`, preventing duplicate re-saving of the same draft.
  - Tier 2: Enforces same-image deduplication using SHA-256 hash against `capture_jobs(content_hash)`, backed by `idx_capture_jobs_hash`.
  - Tier 3: Enforces hard platform order ID deduplication on `confirmed_identifiers` table using compound PK `(namespace, identifier_type, complete_value, stable_event_kind)`. Only unmasked `COMPLETE` IDs participate. Distinguishes active vs trash-bin items.
  - Tier 4: Heuristic fuzzy matching: same merchant (raw/normalized) + identical `amount_minor` + within 24 hours of occurrence. Generates soft warning in `drafts.duplicate_candidates` with `DUPLICATE_SUSPECTED`, permitting user override for consecutive identical purchases.
  - Transaction Manager: Executes draft commitment in a single SQLite transaction (`txn`), verifying draft in `NEEDS_REVIEW`, inserting into `transactions`, `transaction_metadata`, `transaction_tags`, `confirmed_identifiers`, (and `refund_links` if refund), updating `drafts.saved_transaction_id` and setting `capture_jobs.state = 'COMMITTED'`. Automatic rollback on constraint/runtime failure.
- **Unexplored areas**: None. Ready for complete specification formulation.

## Key Decisions Made
- Formulate complete, production-grade Dart interface and implementation architecture for `DeduplicationEngine` and `TransactionManager`.
- Provide exact SQL statements, parameters, error types, and concrete data models.
- Provide edge-case handling guidelines (trash-bin matches, multiple purchases at same merchant, date-only vs timestamp comparisons, rollback verification).

## Artifact Index
- DISPATCH.md — incoming instructions
- progress.md — liveness heartbeat
- BRIEFING.md — persistent situational awareness
- report.md — comprehensive technical report
- handoff.md — self-contained handoff report
