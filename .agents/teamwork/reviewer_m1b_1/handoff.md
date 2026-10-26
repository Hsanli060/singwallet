# Milestone M1-B Review & Adversarial Challenge Report

**Reviewer Agent**: `reviewer_m1b_1`  
**Parent Orchestrator**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Review Target**: Milestone M1-B (Features F19–F26: OCR Transaction Parsing Pipeline)  
**Worker Under Review**: `worker_m1b_1`  
**Date**: 2026-10-22  

---

## Review Summary

**Verdict**: **`REQUEST_CHANGES`**  
**Integrity Audit**: **PASS** (Zero hardcoding, zero dummy facades, zero shortcuts detected; real domain logic implemented).  
**Algorithmic / Defect Assessment**: **2 MAJOR FINDINGS** discovered via adversarial stress-testing in `OrderIdParser` and `AmountParser`.

---

## 1. Observation

1. **Static Analysis & Baseline Automated Tests**:
   - Running `$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter analyze` returned:
     ```text
     Analyzing singwallet...
     No issues found! (ran in 6.8s)
     ```
   - Running `$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test` verified that all 211 baseline tests passed with exit code 0 across 16 test files.
   - Running `python test_docs_integrity.py` returned:
     ```text
     ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%!
     ```
2. **Implementation Quality & Architectural Compliance**:
   - `lib/core/utils/date_utils.dart`: Implemented calendar validation via `DateTime.utc` rejecting invalid days (e.g. Feb 30th) and strictly enforcing zero hallucination (`occurredAt: null`, `precision: 'day'`) when only date is present.
   - `lib/features/recognition/noise_filter.dart`: Correctly implemented `NoiseFilterConfig.defaultStatusBarTop = 0.06`, `dynamicIslandStatusBarTop = 0.075`, and `homeIndicatorTop = 0.95`, conforming strictly to `docs/iOS实现方案.md` lines 451–457.
   - `lib/features/recognition/channel_status_parser.dart`: Accurately mapped payment channels (`wechat`, `alipay`, `unionpay`, `bank_card`, `other`) and detected non-success states (`PENDING`, `FAILED`, `REFUNDED`).
   - `lib/features/recognition/merchant_normalizer.dart`: Correctly stripped prefixes (`特约商户-`, `扫码付款给 `, `向商户付款-`), store branches, and suffixes (`（特约商户）`).
   - `lib/features/recognition/ocr_pipeline.dart`: Assembled all 8 stages, clamped incoming coordinates to `[0.0, 1.0]`, and serialized candidates into `Draft` entities with full JSON provenance.
3. **Adversarial Stress Test Suite (`test/recognition/recognition_adversarial_test.dart`)**:
   - 21 adversarial stress tests were implemented. 19 passed, but 2 tests revealed critical edge-case bugs:
   - **Observation 3A**: In `lib/features/recognition/order_id_parser.dart`, lines 28 & 32:
     ```dart
     static final RegExp _merchantOrderRegex = RegExp(
       r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
     );

     static final RegExp _platformNoRegex = RegExp(
       r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
     );
     ```
     When parsing `交易单号 4200002134202610…1234` (order ID masked with Chinese ellipsis `…` U+2026):
     The regex character class `[0-9a-zA-Z*xX_.-]+` does not match `…`. The regex stops matching before `…`, capturing only the 16-character prefix `4200002134202610`. In line 125–140, because the captured `id` does not contain `…` and its length is >= 16, `OrderIdParser` assigns:
     ```text
     Extracted platformTransactionNo: 4200002134202610
     completeness: IdentifierCompleteness.complete
     ```
     The masked ID is falsely classified as `COMPLETE` instead of `MASKED`.
   - **Observation 3B**: In `lib/features/recognition/amount_parser.dart`, lines 99–104:
     ```dart
     s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0');
     s = s.replaceAllMapped(RegExp(r'[Oo]([0-9.¥￥$€£+-])'), (m) => '0${m[1]}');
     ```
     When input has repeated confusion characters, such as `¥1OOO.OO` or `¥10OO`:
     In a single non-overlapping regex pass, `([0-9...])[Oo]` only matches the first `O` adjacent to a digit in the original string. The intermediate `O` characters are not converted. For `¥1OOO.OO`, the string becomes `¥10O0.0O`. The trailing `O` is not matched by `[Oo]([0-9...])` because it is at the end of the string. Consequently:
     `extractMinorUnits` extracts `100.0` (minor units: 10000 cents / 100.00 RMB instead of 1000.00 RMB), causing a **10x financial calculation error**.

---

## 2. Logic Chain

1. From **Observation 1**, the codebase has high static quality, zero linter warnings, and all baseline unit tests pass. There is zero evidence of facade implementations or hardcoded outputs (Integrity Audit: PASS).
2. From **Observation 2**, Features F19 (Noise Filtering), F20 (Channel & Status), F22 (Merchant Normalization), F23 (Time Extraction), and F26 (Pipeline Assembly) fully satisfy architectural criteria in `docs/Android实现方案.md` and `docs/iOS实现方案.md`.
3. From **Observation 3A**, Feature F24 (Order ID Extraction & Completeness Grading) requires classifying platform transaction numbers into `COMPLETE`, `MASKED`, or `TRUNCATED`. The architectural document (`docs/Android实现方案.md` line 465) explicitly mandates: *"截断、打码、OCR 不确定的编号不能作为强唯一键。"* Because `_platformNoRegex` omits `…` and `＊` in its character set, masked IDs with 16+ unmasked prefix digits are extracted as truncated substrings and graded as `IdentifierCompleteness.complete`. This allows masked IDs to enter Tier 3 hard deduplication (`confirmed_identifiers`), creating severe false duplicate collision risks for subsequent user transactions.
4. From **Observation 3B**, Feature F21 (Amount Disambiguation & OCR Character Repair) requires optical character repairs (`O->0`, `l->1`). The single-pass regex replacement fails when consecutive `O` characters occur, leaving trailing `O` characters untouched. When converted to numeric tokens, the trailing `O` is dropped by regex `\d+`, altering the parsed magnitude by an order of magnitude.
5. Therefore, while the architecture and design are sound, these two bugs pose material financial and data-integrity risks in production, warranting a verdict of **`REQUEST_CHANGES`**.

---

## 3. Findings & Required Fixes

### [Major] Finding 1: Chinese Ellipsis `…` and Fullwidth Asterisk `＊` Omitted in `OrderIdParser` Character Class
- **Location**: `lib/features/recognition/order_id_parser.dart`, lines 28 and 32.
- **Problem**: `_platformNoRegex` and `_merchantOrderRegex` use `[0-9a-zA-Z*xX_.-]+`, which excludes `…` (U+2026) and `＊` (U+FF0A). Masked order numbers like `4200002134202610…1234` are cut off at `…`, causing `4200002134202610` to be extracted and falsely marked as `IdentifierCompleteness.complete`.
- **Required Fix**:
  Update `_platformNoRegex` and `_merchantOrderRegex` to include `…` and `＊`:
  ```dart
  static final RegExp _merchantOrderRegex = RegExp(
    r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );

  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );
  ```
  And in `parse(...)`:
  ```dart
  final hasMaskChars = id.contains('*') ||
      id.contains('＊') ||
      id.contains('...') ||
      id.contains('…') ||
      id.toLowerCase().contains('x');
  ```

### [Major] Finding 2: `repairOcrNumbers` Fails on Consecutive Confusion Characters
- **Location**: `lib/features/recognition/amount_parser.dart`, lines 97–113.
- **Problem**: Single non-overlapping pass of `replaceAllMapped` leaves consecutive or trailing confusion characters unconverted (e.g. `¥1OOO.OO` -> `¥10O0.0O`), resulting in a 10x calculation error when parsed into cents.
- **Required Fix**:
  Execute the replacement in a loop until convergence, or match one or more occurrences `[Oo]+` / handle end-of-token context:
  ```dart
  // Iterative convergence loop for OCR confusion characters
  var prev = '';
  while (prev != s) {
    prev = s;
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0');
    s = s.replaceAllMapped(RegExp(r'[Oo]([0-9.¥￥$€£+-])'), (m) => '0${m[1]}');
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[lIi|!]'), (m) => '${m[1]}1');
    s = s.replaceAllMapped(RegExp(r'[lIi|!]([0-9.¥￥$€£+-])'), (m) => '1${m[1]}');
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Ss]'), (m) => '${m[1]}5');
    s = s.replaceAllMapped(RegExp(r'[Ss]([0-9.¥￥$€£+-])'), (m) => '5${m[1]}');
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])B'), (m) => '${m[1]}8');
    s = s.replaceAllMapped(RegExp(r'B([0-9.¥￥$€£+-])'), (m) => '8${m[1]}');
  }
  ```

---

## 4. Caveats

- **No caveats**: All 10 implementation files and 9 test suites were thoroughly reviewed. The adversarial stress suite `test/recognition/recognition_adversarial_test.dart` was executed to verify every edge case.

---

## 5. Conclusion

**Verdict**: **`REQUEST_CHANGES`**

Milestone M1-B has strong engineering fundamentals and conforms to the high-level architecture. However, Worker `worker_m1b_1` must address the 2 major findings above (updating `OrderIdParser` to capture and grade `…`/`＊` masked IDs, and updating `AmountParser.repairOcrNumbers` to iteratively resolve consecutive confusion characters) to make the test suite in `test/recognition/recognition_adversarial_test.dart` 100% green before Milestone M1-B can be approved for merge.

---

## 6. Verification Method

To verify the fixes independently:

1. **Static Analysis**:
   ```powershell
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   flutter analyze
   ```
   *Expected outcome*: 0 issues found.

2. **Adversarial Stress Test Suite**:
   ```powershell
   flutter test test/recognition/recognition_adversarial_test.dart
   ```
   *Expected outcome*: All 21 tests pass without failure (Boundary 2.4 and Boundary 4.1b must pass).

3. **Full Regression Test Suite**:
   ```powershell
   flutter test
   ```
   *Expected outcome*: All 232+ tests pass with exit code 0.
