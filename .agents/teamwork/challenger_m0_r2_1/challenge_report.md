# Empirical Challenge Report: Currency Parsing Logic & Pigeon Communication

- **Agent**: `challenger_m0_r2_1` (Empirical Challenger: critic, specialist)
- **Parent**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Target**: Milestone M0 (Flutter Scaffold, Pigeon Native Bridge & Currency Parsing Engine)
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\challenger_m0_r2_1`
- **Date**: 2026-10-22
- **Verdict**: **REQUEST_CHANGES**

---

## Challenge Summary

**Overall risk assessment**: **HIGH**

While the Pigeon native communication layer, Android ML Kit / iOS Vision coordinate normalization, and the existing 54-test suite pass completely, empirical stress testing of `CurrencyUtils.parseToMinorUnits` and `tryParseToMinorUnits` under extreme boundary inputs revealed two concrete defects:
1. **Critical 64-bit Integer Overflow**: Inputs approaching or reaching maximum signed 64-bit integer values (e.g. `9223372036854775807` or values with major units $> 92,233,720,368,547,758$) silently wrap around 64-bit two's complement integer arithmetic during `majorUnits * 100`, returning negative amounts (e.g. `-100`) even when `allowNegative: false` is enforced. This violates the core domain guarantee that positive inputs cannot produce negative results and violates the downstream SQLite `CHECK (amount_minor > 0)` constraint.
2. **Malformed Mixed Sign Bypass**: Mixed conflicting signs such as `"+-10"` and `"+¥-10"` bypass validation due to decoupled sign extraction (first stripping `+`, then subsequently stripping `-` after currency symbol stripping), silently parsing as valid negative amounts (`-1000`) instead of throwing `FormatException`.

---

## Challenges

### [Critical] Challenge 1: Silent 64-bit Integer Overflow Bypasses `allowNegative: false`

- **Assumption challenged**: `CurrencyUtils.parseToMinorUnits` assumes that `int.tryParse(integerStr) == null` is sufficient to prevent integer overflow.
- **Attack scenario**:
  An external transaction input, OCR scan artifact, or adversarial receipt supplies an amount string with `majorUnits > 92233720368547758` (up to `int.maxFinite` = `9223372036854775807`).
  For example:
  ```dart
  CurrencyUtils.parseToMinorUnits('9223372036854775807', allowNegative: false);
  ```
- **Observed Behavior (Empirical)**:
  1. `integerStr` (`"9223372036854775807"`) is parsed by `int.tryParse`, succeeding with `majorUnits = 9223372036854775807`.
  2. Line 115 computes: `final total = majorUnits * 100 + minorUnits;`
  3. In 64-bit Dart VM / Flutter runtime:
     $9,223,372,036,854,775,807 \times 100 \pmod{2^{64}} = -100$.
  4. Line 67's negative check (`if (isNegative && !allowNegative)`) evaluated earlier when `isNegative` was `false` (no leading minus sign in input).
  5. The method returns `-100`!
  6. `tryParseToMinorUnits('9223372036854775807')` also returns `-100`.
- **Blast radius**:
  - Positive input produces negative minor unit integer, directly violating the `allowNegative: false` interface contract.
  - When written to SQLite tables (`transactions`, `drafts`, `capture_jobs`), this triggers immediate `CHECK (amount_minor > 0)` constraint failures, or corrupts ledger balance calculations by crediting instead of debiting.
  - Inverted sign on negative overflow: `parseToMinorUnits('-9223372036854775807', allowNegative: true)` returns `+100`.
- **Mitigation**:
  Before computing `total`, guard against integer overflow beyond max signed 64-bit integer minor capacity:
  ```dart
  const maxSafeMajor = 92233720368547758; // 9223372036854775807 ~/ 100
  if (majorUnits > maxSafeMajor || (majorUnits == maxSafeMajor && minorUnits > 7)) {
    throw FormatException('Currency amount exceeds 64-bit integer capacity: "$input"');
  }
  ```

---

### [Medium] Challenge 2: Decoupled Sign Extraction Accepts Malformed Mixed Signs (`"+-10"`, `"+¥-10"`)

- **Assumption challenged**: Sign parsing only accepts a single well-formed prefix (`+` or `-`).
- **Attack scenario**:
  Input string contains conflicting signs, e.g. `"+-10"` or `"+¥-10"`.
- **Observed Behavior (Empirical)**:
  In `lib/core/utils/currency_utils.dart` lines 42-59:
  ```dart
  bool isNegative = false;
  if (trimmed.startsWith('-')) {
    isNegative = true;
    trimmed = trimmed.substring(1).trim();
  } else if (trimmed.startsWith('+')) {
    trimmed = trimmed.substring(1).trim();
  }

  if (stripCurrencySymbols) {
    trimmed = trimmed.replaceFirst(
      RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
      '',
    );
    if (!isNegative && trimmed.startsWith('-')) {
      isNegative = true;
      trimmed = trimmed.substring(1).trim();
    }
  }
  ```
  1. For `"+-10"`, `trimmed.startsWith('+')` matches. `+` is stripped. `trimmed` becomes `"-10"`.
  2. `stripCurrencySymbols` runs. `RegExp` does not match, leaves `trimmed = "-10"`.
  3. `if (!isNegative && trimmed.startsWith('-'))`: since `isNegative` was `false`, this condition passes!
  4. `-` is stripped and `isNegative` is set to `true`!
  5. `total` computes to `1000`. The function returns `-1000`.
  6. In contrast, `"--10"`, `"-+10"`, and `"++10"` are properly rejected with `FormatException`.
- **Blast radius**:
  - Malformed sign sequences (`+-` or `+¥-`) are parsed as valid numbers rather than rejected, leading to unexpected negative values when OCR generates noisy prefix tokens.
- **Mitigation**:
  Track whether an explicit sign was already consumed, and disallow a second sign:
  ```dart
  bool isNegative = false;
  bool hasExplicitSign = false;
  if (trimmed.startsWith('-')) {
    isNegative = true;
    hasExplicitSign = true;
    trimmed = trimmed.substring(1).trim();
  } else if (trimmed.startsWith('+')) {
    hasExplicitSign = true;
    trimmed = trimmed.substring(1).trim();
  }

  if (stripCurrencySymbols) {
    trimmed = trimmed.replaceFirst(
      RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
      '',
    );
    if (!hasExplicitSign && trimmed.startsWith('-')) {
      isNegative = true;
      hasExplicitSign = true;
      trimmed = trimmed.substring(1).trim();
    }
  }
  ```

---

## Stress Test Results

| Scenario | Input | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|---|
| Multiple dots (mid) | `"1.2.3"` | FormatException / null | Throws FormatException / returns null | **PASS** |
| Multiple dots (consecutive) | `"1..2"`, `".."` | FormatException / null | Throws FormatException / returns null | **PASS** |
| Multiple dots (spaces) | `". ."`, `"1. 2. 3"` | FormatException / null | Throws FormatException / returns null | **PASS** |
| Single dot only | `"."`, `"-."`, `"+."` | FormatException / null | Throws FormatException / returns null | **PASS** |
| Negative amount (disallowed) | `"-12.50"` | FormatException | Throws FormatException | **PASS** |
| Negative amount (allowed) | `"-12.50"`, `allowNegative: true` | `-1250` | Returns `-1250` | **PASS** |
| Negative with currency symbol | `"-¥12.50"`, `"¥-12.50"` | `-1250` | Returns `-1250` | **PASS** |
| Explicit positive sign | `"+12.50"`, `"+.50"` | `1250`, `50` | Returns `1250`, `50` | **PASS** |
| Malformed double minus | `"--10"` | FormatException | Throws FormatException | **PASS** |
| Malformed minus-plus | `"-+10"` | FormatException | Throws FormatException | **PASS** |
| Malformed double plus | `"++10"` | FormatException | Throws FormatException | **PASS** |
| Malformed plus-minus | `"+-10"` | FormatException | Returns `-1000` (silently parses) | **FAIL** |
| Malformed plus-symbol-minus | `"+¥-10"` | FormatException | Returns `-1000` (silently parses) | **FAIL** |
| Fullwidth currency symbol | `"￥ 100.00"` | `10000` | Returns `10000` | **PASS** |
| Major currency symbols | `"¥"`, `"$`, `"€"`, `"£"`, `"CNY"`, `"RMB"`, `"USD"` | Stripped correctly | Returns correct minor units | **PASS** |
| Case-insensitive currency | `"cny 10.50"`, `"rmb 20"` | `1050`, `2000` | Returns `1050`, `2000` | **PASS** |
| Unsupported currencies / suffixes | `"₩100"`, `"100元"`, `"100 CNY"` | FormatException / null | Throws FormatException / returns null | **PASS** |
| Subcent truncation (default) | `"10.999"`, `"12.344"` | `1099`, `1234` | Returns `1099`, `1234` | **PASS** |
| Subcent half-up rounding carry | `"10.995"`, `"0.999"`, `roundSubUnits: true` | `1100`, `100` | Returns `1100`, `100` | **PASS** |
| Long decimal fractions | `"12.34567890123456789"` | `1234` (trunc), `1235` (round) | Returns `1234`, `1235` | **PASS** |
| Max safe int64 input | `"92233720368547758.07"` | `9223372036854775807` | Returns `9223372036854775807` | **PASS** |
| Max int64 string (overflow) | `"9223372036854775807"` | FormatException / null | Returns `-100` (wraps to negative!) | **FAIL** |
| Int64 overflow major unit | `"92233720368547759.00"` | FormatException / null | Returns `-9223372036854775716` | **FAIL** |
| Beyond int64 string | `"99999999999999999999"` | FormatException / null | Throws FormatException / returns null | **PASS** |
| Pigeon Codec Fidelity | Enums, boxes, 64KB strings, 1000 lines | 100% roundtrip | 100% roundtrip verified | **PASS** |
| Pigeon HostApi Error Paths | PlatformException -> NativeBridgeException | Wrapped properly | Wrapped properly | **PASS** |
| Flutter Test Suite | `flutter test` (54 tests) | 54/54 pass (exit 0) | 54/54 passed in 00:00 (exit 0) | **PASS** |
| Flutter Static Analysis | `flutter analyze` | 0 issues (exit 0) | 0 issues found in 10.0s (exit 0) | **PASS** |

---

## Unchallenged Areas

- **Full Native OCR ML Kit & Vision Execution on Physical Devices**: Mock and synthesized data verification used as M0 is an offline/headless scaffolding milestone. Hardware execution will occur in M1-B integration testing.
- **SQLCipher SQLite Key Loading**: Native Keystore key generation and envelope state guards are verified via Android unit harness and mock bridge, but full SQLite encryption initialization occurs in M1-A.

---

## Actionable Recommendations for Remediation Worker

1. In `lib/core/utils/currency_utils.dart`:
   - Introduce `hasExplicitSign` flag to prevent consuming multiple signs (`+-10` and `+¥-10`).
   - Add maximum safe integer check before multiplying `majorUnits * 100`:
     ```dart
     const maxSafeMajor = 92233720368547758; // 9223372036854775807 ~/ 100
     if (majorUnits > maxSafeMajor || (majorUnits == maxSafeMajor && minorUnits > 7)) {
       throw FormatException('Currency amount exceeds 64-bit integer capacity: "$input"');
     }
     ```
2. In `test/core/utils/currency_utils_test.dart`:
   - Add test cases asserting that `"+-10"` and `"+¥-10"` throw `FormatException`.
   - Add test cases asserting that `"9223372036854775807"` and `"92233720368547759.00"` throw `FormatException` and return `null` in `tryParseToMinorUnits`.
   - Re-run `flutter test` to ensure all tests pass.
