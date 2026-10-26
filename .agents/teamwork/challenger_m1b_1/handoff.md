# Handoff Report — challenger_m1b_1 (Milestone M1-B OCR Adversarial Challenge)

**Challenger Agent**: `challenger_m1b_1`  
**Parent Orchestrator**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Milestone**: M1-B (Features F19–F30: OCR Transaction Parsing Pipeline)  
**Date**: 2026-10-22  
**Verdict**: **REQUEST_CHANGES**

---

## 1. Observation

1. **Target Files**:
   - `lib/features/recognition/order_id_parser.dart` (154 lines): Extracts platform transaction numbers and merchant order numbers, grading completeness into `COMPLETE`, `MASKED`, `TRUNCATED`, `UNRELIABLE`.
   - `lib/features/recognition/amount_parser.dart` (358 lines): Disambiguates paid vs original vs discount vs fee, filters balance lines, performs OCR character repairs (`O->0`, `l->1`, `S->5`, `B->8`), and parses currency to integer cents.
   - `lib/features/recognition/noise_filter.dart` (100 lines): Geometric filtering of status bar (`< 0.06 / 0.075`), home indicator (`>= 0.95 / top+height >= 0.98`), and UI chrome action buttons.
   - `lib/features/recognition/ocr_pipeline.dart` (246 lines): Coordinates 8-stage OCR parsing, linking draft creation with deduplication and classification.
   - `lib/features/deduplication/deduplication_engine.dart` (470 lines): Hard Tier 3 deduplication engine guarded by `isEligibleForHardDedup => completeness == IdentifierCompleteness.complete`.

2. **Adversarial Test Suite Executed**:
   - `test/recognition/ocr_adversarial_test.dart` (33 unit tests across all 5 requested adversarial vectors).
   - Execution command:
     ```powershell
     $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test test/recognition/ocr_adversarial_test.dart
     ```
   - Execution summary:
     ```text
     00:00 +30 -3: Some tests failed.
     Failing tests:
       - Vector 1.9: Consecutive OCR confused characters (¥1OOO.OO) must be repaired to ¥1000.00
       - Vector 2.5b: Distorted amount with multiple decimals (12.34.56) should not be silently truncated
       - Vector 5.1b: Masked order ID with ellipsis … and 16+ prefix digits must NOT be marked COMPLETE
     ```

3. **Verbatim Failure 1 (CRITICAL — False Hard Dedup on Masked Order ID)**:
   ```text
   Vector 5: Masked & truncated order numbers Vector 5.1b: Masked order ID with ellipsis … and 16+ prefix digits must NOT be marked COMPLETE [E]
     Expected: false
       Actual: <true>
     Masked ID with ellipsis must NOT be graded as complete
     
     test\recognition\ocr_adversarial_test.dart 554:7    main.<fn>.<fn>
   ```
   Code location in `lib/features/recognition/order_id_parser.dart`:
   - Line 32: `_platformNoRegex = RegExp(r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)')`
   - Line 127: `hasMaskChars = id.contains('*') || id.contains('...') || id.contains('…') || id.toLowerCase().contains('x');`
   - Line 140: `completeness = IdentifierCompleteness.complete;`

4. **Verbatim Failure 2 (Consecutive OCR Confusion Unrepaired)**:
   ```text
   Vector 1: Optical character confusion on amounts Vector 1.9: Consecutive OCR confused characters (¥1OOO.OO) must be repaired to ¥1000.00 [E]
     Expected: '¥1000.00'
       Actual: '¥10O0.0O'
        Which: is different.
               Expected: ¥1000.00
                 Actual: ¥10O0.0O
                            ^
                Differ at offset 3
     Consecutive "O"s must be fully repaired without leaving stray "O"s
     
     test\recognition\ocr_adversarial_test.dart 126:7    main.<fn>.<fn>
   ```
   Code location in `lib/features/recognition/amount_parser.dart`:
   - Line 99: `s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0');`
   - Line 100: `s = s.replaceAllMapped(RegExp(r'[Oo]([0-9.¥￥$€£+-])'), (m) => '0${m[1]}');`

5. **Verbatim Failure 3 (Distorted Decimals Silently Sliced)**:
   ```text
   Vector 2: Negative, zero, or distorted amounts Vector 2.5b: Distorted amount with multiple decimals (12.34.56) should not be silently truncated [E]
     Expected: null
       Actual: <1234>
     Distorted amount "12.34.56" must not be silently truncated to 12.34 / 1234 cents
     
     test\recognition\ocr_adversarial_test.dart 200:7    main.<fn>.<fn>
   ```
   Code location in `lib/features/recognition/amount_parser.dart`:
   - Line 128: `final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);`

---

## 2. Logic Chain

1. **Defect 1: Masked Order ID with Unicode Ellipsis Truncation & False COMPLETE Classification (HIGH/CRITICAL RISK)**:
   - *Observation*: `_platformNoRegex` uses regex character class `[0-9a-zA-Z*xX_.-]+`. It does **not** include the Unicode ellipsis `…` (U+2026).
   - *Trace*: When OCR encounters `交易单号 4200002134202610…1234` (a WeChat masked order ID), the regex stops matching right before `…`.
   - *Extraction*: The extracted `rawId` is only `4200002134202610` (the 16 visible digits before the ellipsis).
   - *Grading*: In `OrderIdParser`, line 124, `id = "4200002134202610"`. It contains no `*`, `...`, or `x`. Its length is 16 (`id.length >= 16`). It does not end with `.`.
   - *Result*: `completeness` is set to `IdentifierCompleteness.complete`!
   - *Blast Radius*: In `PlatformIdentifier`, `isEligibleForHardDedup` evaluates to `true`! The masked prefix `4200002134202610` is stored in the `confirmed_identifiers` table as a unique platform key. Any subsequent transaction whose order number begins with those same 16 digits will trigger a false-positive Tier 3 collision and fail commit, corrupting the database idempotence layer.

2. **Defect 2: Non-Overlapping Regex in Consecutive OCR Confusion Repairs (MEDIUM RISK)**:
   - *Observation*: `AmountParser.repairOcrNumbers` uses `s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0')`.
   - *Trace*: In Dart, `replaceAllMapped` advances non-overlapping matches. For input `'¥1OOO.OO'`:
     - Match 1: `'1O'` at index 1–2 is replaced by `'10'`. Index 2 (`'O'`) is consumed.
     - The next character is index 3 (`'O'`), which has no preceding digit or symbol in the regex engine's view.
     - Match 2: `'.O'` at index 4–5 is replaced by `'.0'`.
     - The final character at index 6 (`'O'`) is consumed without replacement.
   - *Result*: `'¥1OOO.OO'` is repaired to `'¥10O0.0O'`. Stray `'O'` characters remain.
   - *Blast Radius*: Large rounded currency amounts (e.g., 1000.00, 2000.00) with multiple zero misrecognitions will fail parsing or truncate incorrectly.

3. **Defect 3: Distorted Decimals Silently Sliced by Greedily Terminated Regex (MEDIUM RISK)**:
   - *Observation*: `extractMinorUnits` attempts to sanitize input using `RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired)`.
   - *Trace*: When a corrupted receipt amount is provided, such as `"12.34.56"`:
     - `[\d,]+` matches `"12"`.
     - `(?:\.\d+)?` matches `".34"` and stops before `".56"`.
     - The token passed to `CurrencyUtils.parseToMinorUnits` is `"12.34"`.
   - *Result*: `CurrencyUtils.parseToMinorUnits("12.34")` returns `1234` cents without error, bypassing the strict multi-decimal validation in `CurrencyUtils`.
   - *Blast Radius*: Scanned receipts with corrupted double-decimal noise (e.g. `12.34.56`) silently record incorrect amounts instead of prompting the user for review via `MISSING_AMOUNT`.

4. **Defect 4: Full-Width Digits in Labeled Amounts Not Captured by Regex (LOW/MEDIUM RISK)**:
   - *Observation*: `_paidLabelRegex` only captures `[0-9.,OlISsBbDd!|]+`.
   - *Trace*: Full-width numbers like `实付 ￥２８．９０` do not match `_paidLabelRegex`.
   - *Result*: `repairOcrNumbers` (which already contains full-width mappings `０->0`, `￥->¥`, etc.) is never executed for labeled amounts.

---

## 3. Caveats

- **Negative Receipts Convention**: WeChat and Alipay expense receipts routinely display expenses with leading minus signs (e.g., `-18.50`). `AmountParser` uses `cents.abs()` to convert this to positive cents (`1850`) so it conforms to the SQLite `CHECK (amount_minor > 0)` constraint. While this handles mobile payment receipts properly, it does not raise a `ValidationIssue` on explicitly negative amounts like `实付 -50.00`.
- **Dynamic Island Threshold Expansion**: In `NoiseFilter`, if any line below `0.075` matches `_statusBarContentRegex` (e.g., time `09:41`), the dynamic island heuristic automatically widens the noise exclusion zone from `0.06` to `0.075`. Main receipt headers must be placed below `0.075` to be preserved when a top clock is present.

---

## 4. Conclusion

While the OCR Transaction Parsing Pipeline successfully passes all 66 worker unit tests and handles standard clean receipts, adversarial stress-testing identified **3 critical and high-priority bugs**:
1. **Critical**: Masked order IDs containing Unicode ellipsis `…` with 16+ visible digits are erroneously graded as `IdentifierCompleteness.complete`, causing false Tier 3 hard deduplication collisions.
2. **Medium**: Consecutive OCR character repairs (`¥1OOO.OO`) leave un-repaired `O`s due to non-overlapping regex replacement.
3. **Medium**: Distorted amounts with multiple decimals (`12.34.56`) are sliced into valid amounts rather than triggering validation issues.

**Verdict**: **REQUEST_CHANGES**.

### Required Action Items for Worker:
1. In `lib/features/recognition/order_id_parser.dart`:
   - Update `_platformNoRegex` and `_merchantOrderRegex` to include `…` (Unicode ellipsis U+2026) in the allowed ID character set:
     ```dart
     static final RegExp _platformNoRegex = RegExp(
       r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.\-…]+)',
     );
     ```
   - Ensure that if `id.contains('…')`, it is graded as `IdentifierCompleteness.masked`.
2. In `lib/features/recognition/amount_parser.dart`:
   - Fix `repairOcrNumbers` to handle consecutive `O`s and full-width numbers by either:
     - Running the replacement in a loop until no more changes occur: `while (prev != s)`, or
     - Normalizing full-width digits before running character confusion regexes.
   - In `extractMinorUnits`, validate that the raw string does not contain multiple decimal points (`repaired.split('.').length > 2`) before extracting tokens.

---

## 5. Verification Method

To reproduce all 3 failing tests and verify the bugs:

```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path

# 1. Run Challenger M1-B adversarial test suite
flutter test test/recognition/ocr_adversarial_test.dart

# 2. Run Peer Challenger M1-B test suite
flutter test test/recognition/recognition_adversarial_test.dart
```

Expected current results:
- `test/recognition/ocr_adversarial_test.dart`: 30 passed, 3 failed (Vector 1.9, Vector 2.5b, Vector 5.1b).
- `test/recognition/recognition_adversarial_test.dart`: 2 failed (Boundary 2.4, Boundary 4.1b).

After worker applies the recommended fixes, all 33 tests in `ocr_adversarial_test.dart` and all tests in `recognition_adversarial_test.dart` must pass with exit code 0.
