# DISPATCH — reviewer_m1a_2

## Task Assignment
Milestone M1-A Code Review: 4-Tier Deduplication Engine, State Machine & Crash Recovery.

## Mandatory Inputs (Read First)
1. `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`
2. `c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md`
3. `c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\report.md`
4. `c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\handoff.md`
5. `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`
6. `c:\Other\Projects\singwallet\test_docs_integrity.py`

## Review Scope
1. Examine `lib/features/deduplication/deduplication_engine.dart`:
   - Verify Tier 1: Technical idempotence (`origin_draft_id UNIQUE`).
   - Verify Tier 2: Same-image hash SHA-256 against `capture_jobs(content_hash)`.
   - Verify Tier 3: Hard platform transaction ID (`confirmed_identifiers` compound PK: `namespace`, `identifier_type`, `complete_value`, `stable_event_kind`). Verify incomplete/masked IDs are excluded.
   - Verify Tier 4: Heuristic fuzzy matching (same merchant + identical `amount_minor` + within 24 hours).
2. Examine `lib/data/database/state_machine.dart`:
   - Verify transition rules matrix (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED`).
   - Verify startup recovery `recoverLingeringJobs` safely resets stuck `RECOGNIZING` jobs to `IMPORTED` or `FAILED`.
3. Run verification commands:
   ```powershell
   $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
   $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   flutter analyze
   flutter test
   python test_docs_integrity.py
   ```
4. Provide verdict: APPROVE or REQUEST_CHANGES.
5. Write report to `c:\Other\Projects\singwallet\.agents\teamwork\reviewer_m1a_2\report.md` and `handoff.md`.


## 2026-10-22T11:25:38Z
You are reviewer_m1a_2.
Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\reviewer_m1a_2
Your parent is orchestrator_1 (conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c).

MANDATORY INPUTS (Read first):
- c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\reviewer_m1a_2\DISPATCH.md
- c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\report.md
- c:\Other\Projects\singwallet\.agents\teamwork\worker_m1a_1\handoff.md
- c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md
- c:\Other\Projects\singwallet\test_docs_integrity.py

Review Scope:
Milestone M1-A Code Review: 4-Tier Deduplication Engine, State Machine & Crash Recovery:
1. Examine `lib/features/deduplication/deduplication_engine.dart`:
   - Verify Tier 1: Technical idempotence (`origin_draft_id UNIQUE`).
   - Verify Tier 2: Same-image hash SHA-256 against `capture_jobs(content_hash)`.
   - Verify Tier 3: Hard platform transaction ID (`confirmed_identifiers` compound PK: `namespace`, `identifier_type`, `complete_value`, `stable_event_kind`). Verify incomplete/masked IDs are excluded.
   - Verify Tier 4: Heuristic fuzzy matching (same merchant + identical `amount_minor` + within 24 hours).
2. Examine `lib/data/database/state_machine.dart`:
   - Verify transition rules matrix (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED`).
   - Verify startup recovery `recoverLingeringJobs` safely resets stuck `RECOGNIZING` jobs to `IMPORTED` or `FAILED`.
3. Run verification commands:
   ```powershell
   $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
   $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   flutter analyze
   flutter test
   python test_docs_integrity.py
   ```
4. Provide verdict: APPROVE or REQUEST_CHANGES.
5. Write report to `c:\Other\Projects\singwallet\.agents\teamwork\reviewer_m1a_2\report.md` and `handoff.md`.
6. Send completion message to orchestrator_1 when finished.
