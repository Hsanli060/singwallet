# DISPATCH — challenger_m1a_1

## Task Assignment
Milestone M1-A Adversarial Challenge: Deduplication Stress & Boundary Verification.

## Mandatory Inputs (Read First)
1. `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`
2. `c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md`
3. `c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\report.md`
4. `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`

## Challenge Mission
Adversarially challenge the 4-tier deduplication engine (`lib/features/deduplication/deduplication_engine.dart`):
1. **Tier 1 (Technical Idempotence)**: Verify committing the same `origin_draft_id` twice is blocked by SQLite `UNIQUE` constraint and handled gracefully.
2. **Tier 2 (Image Hash)**: Verify identical SHA-256 content hashes are detected across jobs.
3. **Tier 3 (Hard Platform ID)**:
   - Verify compound PK uniqueness across `(namespace, identifier_type, complete_value, stable_event_kind)`.
   - Verify incomplete / masked identifiers (`*` or partial digits) are strictly excluded from Tier 3 hard uniqueness.
   - Verify refund vs payment distinction: a refund referencing the original transaction order number with `stable_event_kind = 'refund'` must NOT collide with the payment transaction (`stable_event_kind = 'payment'`).
   - Verify soft-deleted item detection: an incoming transaction matching an item in the trash bin (`deleted_at IS NOT NULL`) must prompt for restoration of the original record/ID rather than colliding or creating a duplicate.
4. **Tier 4 (Heuristic Fuzzy Matching)**:
   - Challenge the 24-hour window boundary (23 hours 59 minutes vs 24 hours 01 minutes).
   - Verify same merchant vs different merchant matching behavior.
   - Verify date-only transactions search +/- 1 calendar day safely.
5. Run `flutter test test/deduplication/deduplication_test.dart` and overall `flutter test`.
6. Provide verdict: APPROVE or REQUEST_CHANGES.
7. Write report to `c:\Other\Projects\singwallet\.agents\teamwork\challenger_m1a_1\challenge_report.md` and `handoff.md`.


## 2026-10-22T11:25:38Z
From: orchestrator_1 (0be8f589-cb64-4c3b-aed0-2d1a129de39c)
You are challenger_m1a_1.
Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\challenger_m1a_1
Your parent is orchestrator_1 (conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c).

MANDATORY INPUTS (Read first):
- c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\challenger_m1a_1\DISPATCH.md
- c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\report.md
- c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md

Challenge Mission:
Adversarially challenge the 4-tier deduplication engine (`lib/features/deduplication/deduplication_engine.dart`):
1. Tier 1 (Technical Idempotence): Verify committing the same `origin_draft_id` twice is blocked by SQLite `UNIQUE` constraint and handled gracefully.
2. Tier 2 (Image Hash): Verify identical SHA-256 content hashes are detected across jobs.
3. Tier 3 (Hard Platform ID):
   - Verify compound PK uniqueness across `(namespace, identifier_type, complete_value, stable_event_kind)`.
   - Verify incomplete / masked identifiers (`*` or partial digits) are strictly excluded from Tier 3 hard uniqueness.
   - Verify refund vs payment distinction: a refund referencing the original transaction order number with `stable_event_kind = 'refund'` must NOT collide with the payment transaction (`stable_event_kind = 'payment'`).
   - Verify soft-deleted item detection: an incoming transaction matching an item in the trash bin (`deleted_at IS NOT NULL`) must prompt for restoration of the original record/ID rather than colliding or creating a duplicate.
4. Tier 4 (Heuristic Fuzzy Matching):
   - Challenge the 24-hour window boundary (23 hours 59 minutes vs 24 hours 01 minutes).
   - Verify same merchant vs different merchant matching behavior.
   - Verify date-only transactions search +/- 1 calendar day safely.
5. Run `flutter test test/deduplication/deduplication_test.dart` and overall `flutter test`.
6. Provide verdict: APPROVE or REQUEST_CHANGES.
7. Write report to `c:\Other\Projects\singwallet\.agents\teamwork\challenger_m1a_1\challenge_report.md` and `handoff.md`.
8. Send completion message to orchestrator_1 when finished.
