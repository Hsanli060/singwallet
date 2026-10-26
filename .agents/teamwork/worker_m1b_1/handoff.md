# Milestone M1-B Handoff Report: OCR Transaction Parsing Pipeline & 6-Tier Classification Rule Engine

**Worker Agent**: `worker_m1b_1`  
**Parent Orchestrator**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Milestone**: M1-B (Features F19 through F30)  
**Date**: 2026-10-22  

---

## 1. Observation

1. **Missing Prerequisite**: Prior to M1-B, `lib/core/utils/date_utils.dart` was missing despite being referenced in the project plan. The OCR pipeline strictly required receipt date-time parsing, precision classification (`second`, `minute`, `day`), zero-hallucination handling (`occurred_at == null` when only date is present), and UTC conversion.
2. **Recognition Pipeline Components**:
   - `lib/features/recognition/models/field_evidence.dart`: Modeled spatial bounding boxes (`OcrBoundingBox`), confidence score, raw text, and source tracking.
   - `lib/features/recognition/models/validation_issue.dart`: Implemented standardized issue codes (`MISSING_AMOUNT`, `ZERO_AMOUNT_NOT_PERMITTED`, `MULTIPLE_AMOUNTS`, `MISSING_DATE`, `MISSING_MERCHANT`, `PAYMENT_NOT_SUCCESS`, `MASKED_ORDER_ID`, `TRUNCATED_ORDER_ID`, `SUSPECTED_DUPLICATE`).
   - `lib/features/recognition/models/parsed_draft_result.dart`: Synthesized parsed draft output, candidate fields JSON serialization, field evidence JSON mapping, validation issues, and direct conversion to SQLite `Draft` entities (`toDraftEntity(...)`).
   - `lib/features/recognition/noise_filter.dart`: Geometry-based noise filtering for status bars (`top < 0.06` or `0.075` for Dynamic Island), home indicators (`top > 0.95` or `(top + height) >= 0.98`), and UI chrome buttons (`查看账单详情`, `完成`).
   - `lib/features/recognition/amount_parser.dart`: Labeled amount disambiguation (实付 vs 原价 vs 优惠 vs 手续费), account balance exclusion (零钱余额, 可用余额), OCR character repair (`O->0`, `l->1`, `S->5`, `B->8`), comma decimal handling (`28,90 -> 28.90`), thousands separator stripping (`1,234.50 -> 123450`), and `CHECK (amount_minor > 0)` boundary compliance.
   - `lib/features/recognition/merchant_normalizer.dart`: Explicit label and header extraction, prefix stripping (`特约商户-`, `扫码付款给 `, `向商户付款-`), suffix stripping (`（特约商户）`), store branch normalization, and brand canonicalization.
   - `lib/features/recognition/order_id_parser.dart`: Platform transaction numbers (WeChat 28-digit `420000...`, Alipay 28-digit `20...`) vs merchant order numbers (`商户单号`), with completeness grading (`complete`, `masked`, `truncated`, `none`).
   - `lib/features/recognition/channel_status_parser.dart`: Payment channel detection (`wechat`, `alipay`, `unionpay`, `bank_card`, `other`), payment status (`SUCCESS`, `PENDING`, `FAILED`, `REFUNDED`), and payment instrument label extraction.
   - `lib/features/recognition/ocr_pipeline.dart`: Full 8-stage coordinator executing input normalization, noise filtering, channel/status parsing, amount parsing, merchant normalization, date extraction, order ID extraction, and classification/deduplication integration.
3. **Classification Rule Engine**:
   - `lib/features/classification/models/classification_match_result.dart`: 6-tier classification result model (`ClassificationTier` 1..6, confidence scores, explanations).
   - `lib/features/classification/rule_matcher.dart`: SQL wildcard (`%`, `_`) safe compilation to RegExp, ReDoS protection via `%` collapsing and 200-char length limits, explicit `regex:` patterns, literal special character escaping, case-insensitivity, channel filtering, and deterministic tie-breaking comparator.
   - `lib/features/classification/rule_engine.dart`: 6-tier resolution cascade (Tier 1: Manual Override > Tier 2: Custom Active Rules > Tier 3: Historical Identical Merchant > Tier 4: Built-in Chinese Keyword Dictionary > Tier 5: Local Schema-Validated AI > Tier 6: Fallback `cat_other`). Dynamic rule learning (`learnRuleFromUserAction`) with strict non-retroactivity.
4. **Verification Outputs**:
   - `flutter analyze` executed with: `No issues found! (ran in 6.6s)` (Exit code 0).
   - `flutter test` executed with: `All 211 tests passed!` (145 existing M0/M1-A tests + 66 new M1-B tests, 0 failures, Exit code 0).
   - `python test_docs_integrity.py` executed with: `ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%!` (Exit code 0).

---

## 2. Logic Chain

1. Step 1: `DateUtils` was implemented to parse Chinese financial receipt timestamps across seconds, minutes, and days. By refusing to hallucinate hours/minutes when only a date is present, `occurred_at` remains `null`, preventing false temporal drift.
2. Step 2: The sub-parsers (`NoiseFilter`, `ChannelStatusParser`, `AmountParser`, `MerchantNormalizer`, `OrderIdParser`) were implemented with real deterministic algorithms. `AmountParser` uses integer cents math and corrects optical OCR confusion without floating-point arithmetic. `OrderIdParser` grades completeness, directly protecting Tier 3 hard deduplication from false collisions caused by masked or truncated IDs.
3. Step 3: `RuleMatcher` converts `%` and `_` to regular expressions while escaping all literal regex metacharacters, eliminating ReDoS vulnerabilities and crashes from parentheses or plus signs.
4. Step 4: `ClassificationRuleEngine` evaluates rules in descending order of certainty. Dynamic rule learning writes new rules for future drafts without altering existing transactions, respecting accounting immutability.
5. Step 5: `OcrParsingPipeline` unifies all 8 stages, linking OCR text to deduplication and classification, and generating production-ready `Draft` entities for SQLite persistence.
6. Step 6: 9 targeted automated test suites (66 tests) were implemented and executed, confirming that all sub-parsers, integration flows, and adversarial scenarios pass without error or regression.

---

## 3. Caveats

- Tier 5 AI classification is designed as a pluggable interface (`AiClassificationProvider`) with local SQLite schema validation. In offline operation without an external AI service, the engine cleanly cascades from Tier 4 to Tier 6 fallback as designed.
- Image files are assumed to be loaded and OCR-processed by the platform native bridges (ML Kit / Vision) into `OcrDocument` before entering the Dart pipeline.

---

## 4. Conclusion

Milestone M1-B is fully implemented, verified, and production-ready:
- All 12 assigned features (F19 through F30) are genuinely implemented with real domain logic and zero dummy facades.
- All 13 core files and 9 comprehensive test suites conform strictly to the architectural specifications and write ownership boundaries.
- All quality gates (`flutter analyze`, `flutter test`, `python test_docs_integrity.py`) pass 100% with exit code 0.

---

## 5. Verification Method

To independently verify this milestone:

1. **Environment Setup**:
   ```powershell
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   ```

2. **Static Analysis**:
   ```powershell
   flutter analyze
   ```
   *Expected outcome*: 0 issues found.

3. **Automated Test Suites Execution**:
   ```powershell
   flutter test
   ```
   *Expected outcome*: All 211 tests pass with exit code 0.

4. **Targeted M1-B Suites**:
   ```powershell
   flutter test test/core/utils/date_utils_test.dart
   flutter test test/recognition/noise_filter_test.dart
   flutter test test/recognition/amount_parser_test.dart
   flutter test test/recognition/merchant_normalizer_test.dart
   flutter test test/recognition/order_id_parser_test.dart
   flutter test test/recognition/channel_status_parser_test.dart
   flutter test test/recognition/ocr_pipeline_test.dart
   flutter test test/classification/rule_matcher_test.dart
   flutter test test/classification/rule_engine_test.dart
   ```
   *Expected outcome*: 9/9 test suites pass with 66/66 test cases green.

5. **Cross-Platform Schema & Backup Integrity Check**:
   ```powershell
   python test_docs_integrity.py
   ```
   *Expected outcome*: 100% pass across all 6 deep verification suites.
