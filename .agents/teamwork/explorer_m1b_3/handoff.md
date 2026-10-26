# Handoff Report — Milestone M1-B: Systems Architecture, Integration Contracts & Test Suite Specification

**Date**: 2026-10-22  
**Sender**: `explorer_m1b_3` (Explorer Archetype)  
**Recipient**: `orchestrator_2` (`a14d1a00-adfd-46db-a470-136d68156a40`)  
**Type**: Hard Handoff (Investigation & Specification Complete)  
**Report Artifact**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1b_3\report.md`

---

## 1. Observation

1. **Codebase Architecture & Existing Data Layer (M1-A)**:
   - `lib/data/database/schema.dart:26-211` defines 12 core tables: `capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers`.
   - `lib/data/database/transaction_manager.dart:107-272` implements atomic multi-table commitment:
     - Line 144 enforces `jobState == CaptureJobState.needsReview.value`.
     - Lines 157-165 enforce `origin_draft_id UNIQUE` idempotence.
     - Lines 169-204 enforce Tier 3 platform identifier uniqueness against `confirmed_identifiers` (rejecting active collisions and flagging 30-day trash collisions).
     - Lines 246-267 atomically update `drafts.saved_transaction_id` and `capture_jobs.state = COMMITTED`.
   - `lib/data/database/state_machine.dart:73-97` specifies valid transitions: `IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` (terminal).
   - `lib/features/deduplication/deduplication_engine.dart:48-65` defines `PlatformIdentifier` with `IdentifierCompleteness.complete` eligibility check. Lines 336-419 implement Tier 4 heuristic fuzzy matching using raw/normalized merchant, exact `amountMinor`, and a 24-hour time window.
   - `lib/core/utils/currency_utils.dart:45-149` converts major currency strings to integer cents without floating-point error, handling currency symbols, commas, and negative signs.
   - **Missing File Discovery**: `orchestrator_2/PROJECT.md` line 159 listed `lib/core/utils/date_utils.dart` as `# Done (M1-A)`. Direct file inspection showed that `date_utils.dart` does not exist in `lib/core/utils/` (only `currency_utils.dart` exists).

2. **Native Bridge Interface (M0)**:
   - `pigeons/native_bridge.dart:42-82` and `lib/core/native/native_bridge.g.dart:85-188` establish:
     - `OcrBoundingBox(left, top, width, height)` in normalized `[0.0, 1.0]` coordinates with top-left origin.
     - `OcrTextLine(text, boundingBox, confidence)`.
     - `OcrDocument(captureId, lines, engineIdentifier, processTimeMs)`.
   - `lib/core/native/native_bridge_service.dart:54-64` wraps `NativeCaptureHostApi.recognizeCapture(captureId)`.

3. **Current Automated Test Suite**:
   - Running `cmd /c "set PATH=C:\Other\Dev\flutter\bin;%PATH% && flutter test"` executed 145 unit/integration tests with 100% pass rate:
     `00:02 +145: All tests passed!` (Exit code 0).
   - Running `python test_docs_integrity.py` passed all 6 verification test suites:
     `>>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<` (Exit code 0).

---

## 2. Logic Chain

1. From **Observation 1**, `TransactionManager.commitDraft` requires drafts to be in the `NEEDS_REVIEW` state before commitment and verifies relational constraints against `transactions`, `transaction_metadata`, and `confirmed_identifiers`. Therefore, the M1-B OCR pipeline must produce a draft entity that populates `candidate_fields`, `field_evidence`, `validation_issues`, and `duplicate_candidates`, and transitions the associated `capture_job` from `RECOGNIZING` to `NEEDS_REVIEW`.
2. From **Observation 1 (Missing File Discovery)**, because `lib/core/utils/date_utils.dart` is missing, transaction timestamp extraction, precision classification (`second`, `minute`, `day`), and UTC ISO-8601 conversions required by `transactions.occurred_at` and `transactions.occurred_on` cannot function without it. `DateUtils` must therefore be specified and implemented as part of M1-B.
3. From **Observation 2**, `OcrDocument` emits `OcrTextLine` items with normalized bounding boxes `[0.0, 1.0]`. This allows `NoiseFilter` to filter status bar text (`top < 0.06` or `0.075`) and home indicator text (`top > 0.95`) deterministically before parsing begins.
4. Parsing must be broken into specialized, independently testable sub-parsers:
   - `ChannelStatusParser`: maps "微信支付" / "支付宝" to channels, and "支付成功" vs "处理中" / "待付款" to transaction status.
   - `AmountParser`: disambiguates labeled text ("实付" vs "原价" / "优惠" / "余额"), repairs OCR misrecognitions (`O`->`0`, `l`->`1`, `S`->`5`), and enforces `CHECK (amount_minor > 0)` by invalidating 0 or negative values.
   - `MerchantNormalizer`: strips common merchant prefixes ("特约商户-", "扫码付款给", "向商户付款") to produce clean `merchant_normalized` values for classification and deduplication.
   - `OrderIdParser`: identifies WeChat (420000...) and Alipay (20...) order formats and tags completeness (`COMPLETE`, `MASKED`, `TRUNCATED`).
5. From **Observation 1**, `ClassificationRuleEngine` must evaluate a 6-tier hierarchy (Manual Override > Custom Rules > Historical Transactions > Built-in Keywords > AI Recommendation > Default Fallback). `RuleMatcher` must convert SQL `%` and `_` wildcards to regular expressions while escaping regex meta-characters (`(`, `)`, `+`, `*`, `?`) to prevent crashes on merchant names with branch parentheticals (e.g., `麦当劳（三里屯店）`).
6. When a user manually corrects a category in draft review, dynamic rule learning (`learnRuleFromUserAction`) persists a new or updated rule in `classification_rules`, ensuring that future imports from that merchant are classified automatically at Tier 2.

---

## 3. Caveats

1. **AI Recommendation (Tier 5)**: In accordance with offline-first local operation and M1 project requirements, Tier 5 (AI recommendation) is specified as an extensible stub returning `null`. It does not make network calls.
2. **Flutter Path Dependency**: The Flutter binary is located at `C:\Other\Dev\flutter\bin`. Terminal commands must prepend this directory to `PATH` (e.g. `set PATH=C:\Other\Dev\flutter\bin;%PATH%`).
3. **No Code Implementation in Investigation Phase**: In strict accordance with the explorer archetype rules, no source code files or tests were created in `lib/` or `test/`. All concrete class designs, method signatures, data structures, and test suites are specified in `report.md`.

---

## 4. Conclusion

The architectural investigation, relational contracts, data flow from Pigeon bridge to SQLite storage, and comprehensive test suite specification for Milestone M1-B are complete:
1. Complete class definitions, method signatures, and data contracts have been specified for:
   - Missing utility: `DateUtils` in `lib/core/utils/date_utils.dart`
   - Recognition feature: `FieldEvidence`, `ValidationIssue`, `ParsedDraftResult`, `NoiseFilter`, `AmountParser`, `MerchantNormalizer`, `OrderIdParser`, `ChannelStatusParser`, and `OcrParsingPipeline` in `lib/features/recognition/`
   - Classification feature: `ClassificationMatchResult`, `RuleMatcher`, and `ClassificationRuleEngine` in `lib/features/classification/`
2. The end-to-end data lifecycle from Pigeon bridge ingestion to atomic ledger commitment was traced with explicit state transitions, error recovery mechanisms, and deduplication integration.
3. A 10-suite test plan was formulated, comprising unit tests for every sub-parser and rule engine tier, integration scenarios with realistic WeChat/Alipay receipts, and adversarial edge case protections.
4. All findings and specifications are compiled into `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1b_3\report.md`.

---

## 5. Verification Method

### 5.1 Verification Commands
To independently verify the existing codebase and the documentation integrity:

```powershell
# Set environment
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path

# 1. Run all 145 automated tests
flutter test

# 2. Run documentation and SQLite schema integrity suite
python test_docs_integrity.py
```

### 5.2 Artifact Verification
Inspect the comprehensive specification report:
- `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1b_3\report.md`

### 5.3 Invalidation Conditions
- Any of the 145 existing tests failing in `flutter test`.
- Any failure in `test_docs_integrity.py`.
- Any divergence between the M1-B models and the SQLite table schemas defined in `lib/data/database/schema.dart`.
