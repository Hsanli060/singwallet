# Technical Investigation Report: 64-bit Integer Overflow Prevention in `CurrencyUtils`

- **Agent**: `explorer_m0_r3_1` (Read-only Investigation & Synthesis)
- **Target**: `CurrencyUtils` (`lib/core/utils/currency_utils.dart` and `lib/core/native/currency_utils.dart`)
- **Recipient**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_r3_1`
- **Date**: 2026-10-22

---

## 1. Executive Summary

Empirical challenge results from `challenger_m0_r2_1` demonstrated that `CurrencyUtils.parseToMinorUnits` and `tryParseToMinorUnits` suffer from a critical 64-bit signed integer arithmetic overflow:
- Inputs where `majorUnits > 92233720368547758` (such as `"9223372036854775807"`) silently wrap around 64-bit two's complement integer multiplication (`majorUnits * 100`), resulting in `-100`.
- Because `isNegative` was initially `false`, the `allowNegative: false` check is bypassed, directly delivering a negative integer minor unit to callers. Downstream, this triggers SQLite `CHECK (amount_minor > 0)` constraint failures and risks severe financial ledger corruption.
- Furthermore, a secondary sign parsing flaw allows contradictory sign sequences like `"+-10"` and `"+¥-10"` to parse as `-1000` rather than throwing `FormatException`.

This investigation establishes the exact mathematical boundaries of 64-bit signed integer capacity in minor currency units, validates boundary behavior under integer multiplication and rounding, and provides full drop-in code and test suites.

---

## 2. Mathematical Boundary Calculation

In Dart (native 64-bit VM and AOT runtime), `int` is represented as a signed 64-bit two's complement integer:
$$\text{Max Int64} = 2^{63} - 1 = 9{,}223{,}372{,}036{,}854{,}775{,}807$$
$$\text{Min Int64} = -2^{63} = -9{,}223{,}372{,}036{,}854{,}775{,}808$$

### Derivation of Safe Major and Minor Limits
SingWallet stores monetary amounts in minor units (cents / 分), where $1 \text{ major unit} = 100 \text{ minor units}$.
To determine the maximum major and minor components that can be composed via $\text{majorUnits} \times 100 + \text{minorUnits}$ without exceeding $2^{63} - 1$:

1. **Maximum Safe Major Units (`_maxSafeMajor`)**:
   $$\text{\_maxSafeMajor} = \lfloor (2^{63} - 1) / 100 \rfloor = 92{,}233{,}720{,}368{,}547{,}758$$
2. **Maximum Permissible Minor Units at Boundary (`_maxMinorForBoundary`)**:
   $$\text{\_maxMinorForBoundary} = (2^{63} - 1) \pmod{100} = 7$$
3. **Exact Verification**:
   $$92{,}233{,}720{,}368{,}547{,}758 \times 100 + 7 = 9{,}223{,}372{,}036{,}854{,}775{,}800 + 7 = 9{,}223{,}372{,}036{,}854{,}775{,}807 = 2^{63} - 1$$

### Boundary Transition Table
| Major Units | Minor Units | Total Expression | Value in 64-bit Arithmetic | Status |
|---|---|---|---|---|
| $92233720368547758$ | $7$ | $92233720368547758 \times 100 + 7$ | $+9223372036854775807$ | **SAFE** (Exact $2^{63}-1$) |
| $92233720368547758$ | $8$ | $92233720368547758 \times 100 + 8$ | $-9223372036854775808$ | **OVERFLOW** (Wraps to $-2^{63}$) |
| $92233720368547759$ | $0$ | $92233720368547759 \times 100 + 0$ | $-9223372036854775716$ | **OVERFLOW** (Wraps negative) |
| $9223372036854775807$ | $0$ | $9223372036854775807 \times 100 + 0$ | $-100$ | **OVERFLOW** (Wraps to $-100$) |
| $92233720368547757$ | $100$ | $92233720368547757 \times 100 + 100$ | $+9223372036854775800$ | **SAFE** (Under boundary) |

---

## 3. Root Cause Analysis

### Vulnerability 1: Silent Overflow in `majorUnits * 100`
In `lib/core/utils/currency_utils.dart` (lines 84-88 and 115-116):
```dart
final parsed = int.tryParse(integerStr);
if (parsed == null) {
  throw FormatException('Currency integer part overflow: "$input"');
}
majorUnits = parsed;
...
final total = majorUnits * 100 + minorUnits;
return isNegative ? -total : total;
```
1. `int.tryParse("9223372036854775807")` parses any signed 64-bit integer up to `9223372036854775807`.
2. The multiplication `majorUnits * 100` is performed without checking if `majorUnits` fits within $92233720368547758$.
3. When `majorUnits = 9223372036854775807`:
   $$(2^{63} - 1) \times 100 \equiv (2^{63} \times 100) - 100 \equiv -100 \pmod{2^{64}}$$
4. Because the input string was `"9223372036854775807"`, `isNegative` was `false`.
5. The `if (isNegative && !allowNegative)` check evaluated to `false` and did not throw.
6. The method returned `-100`. A positive input amount was silently returned as a negative minor unit.
7. For negative inputs with `allowNegative: true` (e.g. `"-9223372036854775807"`), `-total` evaluates to `-(-100) = +100`, flipping the sign!

### Vulnerability 2: Decoupled Sign Extraction (`+-10`, `+¥-10`)
In lines 42-59:
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
When input is `"+-10"`:
- `trimmed.startsWith('+')` consumes `+`, leaving `trimmed = "-10"` with `isNegative = false`.
- In `stripCurrencySymbols`, `!isNegative && trimmed.startsWith('-')` is `true`, consuming `-` and setting `isNegative = true`.
- Result: parsed as `-1000` without throwing `FormatException`.

---

## 4. Proposed Solution & Guard Formulation

### Guard Rule
Place the check immediately after `minorUnits` is calculated (which accounts for trailing/leading decimals and sub-cent rounding) and before `total = majorUnits * 100 + minorUnits`:

```dart
// 64-bit integer overflow protection:
// 2^63 - 1 = 9223372036854775807 cents = 92233720368547758 major + 7 minor.
if (majorUnits > _maxSafeMajor ||
    (majorUnits == _maxSafeMajor && minorUnits > _maxMinorForBoundary)) {
  throw FormatException('Currency amount exceeds 64-bit integer limit: "$input"');
}
```

### Sign Guard Rule
Track whether an explicit sign has already been consumed with `hasExplicitSign`:
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
  if (!hasExplicitSign) {
    if (trimmed.startsWith('-')) {
      isNegative = true;
      hasExplicitSign = true;
      trimmed = trimmed.substring(1).trim();
    } else if (trimmed.startsWith('+')) {
      hasExplicitSign = true;
      trimmed = trimmed.substring(1).trim();
    }
  }
}
```

---

## 5. Drop-in Implementation

### Target File: `lib/core/utils/currency_utils.dart`

```dart
/// Monetary calculation utilities using integer minor currency units (cents / 分).
///
/// Ensures 100% precision arithmetic without IEEE 754 floating-point drift.
class CurrencyUtils {
  CurrencyUtils._();

  /// Maximum major currency units that can be safely converted to minor units (cents)
  /// without overflowing a 64-bit signed integer (2^63 - 1 = 9223372036854775807).
  static const int _maxSafeMajor = 92233720368547758; // (2^63 - 1) ~/ 100

  /// Maximum minor units allowed when [majorUnits] equals [_maxSafeMajor].
  static const int _maxMinorForBoundary = 7; // (2^63 - 1) % 100

  /// Public constant for maximum safe major units before 64-bit integer overflow.
  static const int maxSafeMajor = _maxSafeMajor;

  /// Public constant for maximum safe minor units on the 64-bit integer boundary.
  static const int maxMinorForBoundary = _maxMinorForBoundary;

  /// Converts cents (minor currency unit) to display string (e.g. 2890 -> "28.90").
  static String centsToYuanString(int cents) {
    final sign = cents < 0 ? '-' : '';
    final absCents = cents.abs();
    final yuan = absCents ~/ 100;
    final centRemainder = absCents % 100;
    return '$sign$yuan.${centRemainder.toString().padLeft(2, '0')}';
  }

  /// Canonical alias for [centsToYuanString].
  static String formatMinorUnits(int minorUnits) => centsToYuanString(minorUnits);

  /// Parses an amount string to integer minor currency units (cents/分).
  ///
  /// Handles common formats, OCR outputs, and user input edge cases:
  /// - Standard: `"28.90"` -> `2890`, `"28.9"` -> `2890`, `"28"` -> `2800`
  /// - Trailing decimal: `"12."` -> `1200`
  /// - Leading decimal: `".50"` -> `50`, `".5"` -> `50`, `".05"` -> `5`
  /// - Thousands grouping: `"1,234.50"` -> `123450`
  /// - Currency symbols: `"¥28.90"`, `"$28.90"`, `"CNY 28.90"` -> `2890`
  /// - Negative amounts: `"-12.50"`, `"-¥12.50"`, `"-.50"` -> negative cents (when [allowNegative] is true)
  ///
  /// Throws [FormatException] if the input cannot be parsed or represents an
  /// invalid currency amount (e.g., `""`, `"."`, `"12.34.56"`, `"12.ab"`),
  /// or if the parsed amount exceeds 64-bit signed integer limits ($2^{63} - 1$).
  static int parseToMinorUnits(
    String input, {
    bool allowNegative = false,
    bool stripCurrencySymbols = true,
    bool roundSubUnits = false,
  }) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty currency string');
    }

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
      if (!hasExplicitSign) {
        if (trimmed.startsWith('-')) {
          isNegative = true;
          hasExplicitSign = true;
          trimmed = trimmed.substring(1).trim();
        } else if (trimmed.startsWith('+')) {
          hasExplicitSign = true;
          trimmed = trimmed.substring(1).trim();
        }
      }
    }

    trimmed = trimmed.replaceAll(',', '').replaceAll(' ', '');

    if (trimmed.isEmpty || trimmed == '.') {
      throw FormatException('Invalid currency string: "$input"');
    }

    if (isNegative && !allowNegative) {
      throw const FormatException('Negative amount not allowed');
    }

    final parts = trimmed.split('.');
    if (parts.length > 2) {
      throw FormatException('Invalid currency format with multiple decimal points: "$input"');
    }

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

    int minorUnits = 0;
    if (parts.length == 2) {
      final decimalStr = parts[1];
      if (decimalStr.isNotEmpty) {
        if (!RegExp(r'^\d+$').hasMatch(decimalStr)) {
          throw FormatException('Invalid characters in currency decimal part: "$input"');
        }

        if (decimalStr.length == 1) {
          minorUnits = int.parse(decimalStr) * 10;
        } else if (decimalStr.length == 2) {
          minorUnits = int.parse(decimalStr);
        } else {
          final base = int.parse(decimalStr.substring(0, 2));
          if (roundSubUnits) {
            final nextDigit = int.parse(decimalStr[2]);
            minorUnits = nextDigit >= 5 ? base + 1 : base;
          } else {
            minorUnits = base;
          }
        }
      }
    }

    // Explicit 64-bit integer overflow protection:
    // In 64-bit signed two's complement integer arithmetic, max positive value is
    // 2^63 - 1 = 9223372036854775807 cents = 92233720368547758 * 100 + 7.
    // Inputs exceeding this boundary silently wrap around to negative numbers.
    if (majorUnits > _maxSafeMajor ||
        (majorUnits == _maxSafeMajor && minorUnits > _maxMinorForBoundary)) {
      throw FormatException('Currency amount exceeds 64-bit integer limit: "$input"');
    }

    final total = majorUnits * 100 + minorUnits;
    return isNegative ? -total : total;
  }

  /// Attempts to parse [input] to minor currency units, returning `null` on failure.
  static int? tryParseToMinorUnits(
    String? input, {
    bool allowNegative = false,
    bool stripCurrencySymbols = true,
    bool roundSubUnits = false,
  }) {
    if (input == null) return null;
    try {
      return parseToMinorUnits(
        input,
        allowNegative: allowNegative,
        stripCurrencySymbols: stripCurrencySymbols,
        roundSubUnits: roundSubUnits,
      );
    } on FormatException {
      return null;
    }
  }

  /// Backward compatible wrapper around [parseToMinorUnits].
  static int yuanStringToCents(String input, {bool allowNegative = false}) {
    return parseToMinorUnits(input, allowNegative: allowNegative);
  }
}
```

---

## 6. Action Plan for Implementer

1. Replace `lib/core/utils/currency_utils.dart` with the proposed content (available at `.agents/teamwork/explorer_m0_r3_1/proposed_currency_utils.dart`).
2. Verify that `lib/core/native/currency_utils.dart` continues to cleanly re-export `lib/core/utils/currency_utils.dart`.
3. Add the boundary test cases from `.agents/teamwork/explorer_m0_r3_1/proposed_test_cases.dart` to `test/core/utils/currency_utils_test.dart`.
4. Run `flutter test` and `flutter analyze` to verify that all existing 54 tests and new boundary tests pass with 0 warnings.
