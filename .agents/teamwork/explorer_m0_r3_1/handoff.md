# Handoff Report: CurrencyUtils 64-bit Overflow Prevention Investigation

- **Agent**: `explorer_m0_r3_1` (Read-only Investigation & Synthesis)
- **Target**: Milestone M0 (Currency Parsing Engine Overflow Prevention)
- **Sender Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_r3_1`
- **Recipient**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Date**: 2026-10-22
- **Handoff Type**: Hard (Task Complete)

---

## 1. Observation

### Observation 1: Existing File Structure & Implementation
- `lib/core/utils/currency_utils.dart` contains the monetary parser implementation.
  - Lines 77-89:
    ```dart
    final integerStr = parts[0];
    final int majorUnits;
    if (integerStr.isEmpty) {
      majorUnits = 0;
    } else {
      if (!RegExp(r'^\d+$').hasMatch(integerStr)) {
        throw FormatException('Invalid characters in currency integer part: "$input"');
      }
      final parsed = int.tryParse(integerStr);
      if (parsed == null) {
        throw FormatException('Currency integer part overflow: "$input"');
      }
      majorUnits = parsed;
    }
    ```
  - Lines 115-116:
    ```dart
    final total = majorUnits * 100 + minorUnits;
    return isNegative ? -total : total;
    ```
- `lib/core/native/currency_utils.dart` contains a single export:
  ```dart
  export '../utils/currency_utils.dart';
  ```
- `test/core/utils/currency_utils_test.dart` currently contains 130 lines covering basic positive amounts, trailing/leading decimals, thousands grouping, currency symbols, negative amounts, sub-cent rounding, and malformed characters.

### Observation 2: Empirical Arithmetic Wrap-around
In 64-bit Dart VM / two's complement signed integer representation:
- $2^{63} - 1 = 9223372036854775807$.
- `int.tryParse("9223372036854775807")` succeeds and assigns `majorUnits = 9223372036854775807`.
- Evaluating `majorUnits * 100`:
  $$9223372036854775807 \times 100 \pmod{2^{64}} = -100$$
- `parseToMinorUnits("9223372036854775807")` returns `-100` instead of throwing `FormatException`.
- Evaluating `92233720368547758 * 100 + 7` yields `9223372036854775807` ($2^{63}-1$, safe).
- Evaluating `92233720368547758 * 100 + 8` wraps to `-9223372036854775808` (overflow).

### Observation 3: Mixed Sign Sequence Bypass
In `lib/core/utils/currency_utils.dart`:
- Lines 42-59 decouple prefix sign stripping from currency symbol stripping:
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
- When input is `"+-10"`, `+` is stripped first (`isNegative` remains `false`), then `!isNegative && trimmed.startsWith('-')` is true, stripping `-` and setting `isNegative = true`.
- `parseToMinorUnits("+-10", allowNegative: true)` returns `-1000` rather than throwing `FormatException`.
- `parseToMinorUnits("+¥-10", allowNegative: true)` returns `-1000` rather than throwing `FormatException`.

---

## 2. Logic Chain

1. **Premise 1 (64-bit Integer Limit)**:
   Per Dart language specification and 64-bit hardware, signed integers are represented in two's complement with range $[-2^{63}, 2^{63}-1]$ ($[-9223372036854775808, 9223372036854775807]$).
2. **Premise 2 (Minor Unit Representation)**:
   Every major currency unit equals 100 minor units (cents). Thus, `total = majorUnits * 100 + minorUnits`.
3. **Step 3 (Boundary Division)**:
   Dividing $(2^{63} - 1)$ by 100:
   - Quotient: $9223372036854775807 \div 100 = 92233720368547758$ (`_maxSafeMajor`).
   - Remainder: $9223372036854775807 \pmod{100} = 7$ (`_maxMinorForBoundary`).
4. **Step 4 (Overflow Condition)**:
   From Observation 2, if `majorUnits > _maxSafeMajor`, then `majorUnits * 100` exceeds $2^{63}-1$ and wraps around to negative values. If `majorUnits == _maxSafeMajor`, then `minorUnits` must not exceed 7; if `minorUnits > 7`, `majorUnits * 100 + minorUnits` wraps around to negative values.
   Therefore, the condition:
   `majorUnits > _maxSafeMajor || (majorUnits == _maxSafeMajor && minorUnits > _maxMinorForBoundary)`
   is both necessary and sufficient to prevent any 64-bit integer overflow.
5. **Step 5 (Sign Integrity)**:
   From Observation 3, tracking `hasExplicitSign` ensures that after consuming an initial sign (`+` or `-`), no secondary sign is consumed after symbol stripping, causing conflicting inputs (`+-10`, `+¥-10`) to retain invalid characters and fail `RegExp(r'^\d+$')`.
6. **Conclusion**:
   Applying the boundary constants, the overflow check, and `hasExplicitSign` makes `CurrencyUtils` provably immune to integer overflow and malformed mixed signs.

---

## 3. Caveats

- **No Caveats** regarding arithmetic boundary precision: The calculation is exact for 64-bit two's complement signed integers.
- **Web Platform (JavaScript / WebAssembly)**: In Dart compiled to JavaScript (dart2js), integers are represented as 54-bit floats unless using `dart:typed_data` or BigInt, where safe integer boundary is $2^{53}-1$ ($9007199254740991$). However, SingWallet targets Flutter Mobile (Android/iOS 64-bit ARM/x86_64 native VM), where 64-bit integers are standard.
- **Read-Only Scope**: This agent is read-only and has not modified `lib/core/utils/currency_utils.dart` directly. Drop-in files and tests are prepared in `.agents/teamwork/explorer_m0_r3_1/`.

---

## 4. Conclusion

The exact 64-bit boundary and overflow prevention logic is established:
1. **Boundary Constants**:
   ```dart
   static const int _maxSafeMajor = 92233720368547758;
   static const int _maxMinorForBoundary = 7;
   static const int maxSafeMajor = _maxSafeMajor;
   static const int maxMinorForBoundary = _maxMinorForBoundary;
   ```
2. **Explicit Overflow Guard**:
   ```dart
   if (majorUnits > _maxSafeMajor ||
       (majorUnits == _maxSafeMajor && minorUnits > _maxMinorForBoundary)) {
     throw FormatException('Currency amount exceeds 64-bit integer limit: "$input"');
   }
   ```
3. **Prepared Artifacts**:
   - Technical Report: `.agents/teamwork/explorer_m0_r3_1/report.md`
   - Complete drop-in source: `.agents/teamwork/explorer_m0_r3_1/proposed_currency_utils.dart`
   - Comprehensive test suite: `.agents/teamwork/explorer_m0_r3_1/proposed_test_cases.dart`

---

## 5. Verification Method

To verify the proposed implementation:

1. **Inspect Drop-in Code**:
   View `.agents/teamwork/explorer_m0_r3_1/proposed_currency_utils.dart` and `.agents/teamwork/explorer_m0_r3_1/proposed_test_cases.dart`.
2. **Apply to Codebase**:
   Copy `proposed_currency_utils.dart` into `lib/core/utils/currency_utils.dart`.
   Append `proposed_test_cases.dart` tests into `test/core/utils/currency_utils_test.dart`.
3. **Run Test Suites**:
   ```powershell
   & "C:\Other\Dev\flutter\bin\flutter.bat" test test/core/utils/currency_utils_test.dart
   & "C:\Other\Dev\flutter\bin\flutter.bat" test
   & "C:\Other\Dev\flutter\bin\flutter.bat" analyze
   ```
4. **Invalidation Conditions**:
   - `CurrencyUtils.parseToMinorUnits("9223372036854775807")` fails to throw `FormatException` or returns negative value.
   - `CurrencyUtils.parseToMinorUnits("92233720368547758.07")` does not return `9223372036854775807`.
   - `CurrencyUtils.parseToMinorUnits("+-10", allowNegative: true)` does not throw `FormatException`.
