# Technical Investigation Report: Strict Sign Parsing in CurrencyUtils

- **Agent**: `explorer_m0_r3_2` (Specialist Explorer: investigation, synthesis)
- **Target**: Milestone M0 / Currency Parsing Engine (`lib/core/utils/currency_utils.dart`)
- **Parent**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_r3_2`
- **Date**: 2026-10-22
- **Status**: Complete & Empirically Verified

---

## 1. Executive Summary & Root Cause Analysis

### 1.1 Problem Statement
In `lib/core/utils/currency_utils.dart`, adversarial inputs containing conflicting sign sequences such as `"+-10"` and `"+¥-10"` silently parsed as `-1000` (valid negative 10.00 Yuan) rather than being rejected with `FormatException`. In addition, `tryParseToMinorUnits("+-10")` returned `-1000` instead of `null`.

### 1.2 Root Cause Analysis
In `CurrencyUtils.parseToMinorUnits` (lines 42–60 of `lib/core/utils/currency_utils.dart`):

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

The defect arises from the interaction between two decoupled sign-stripping steps without persistent state tracking:
1. **Initial Sign Stripping (Lines 43–48)**:
   When input begins with `'+'`, the `+` character is stripped, but `isNegative` remains `false`. The parser does not record that an explicit sign has already been consumed.
2. **Post-Symbol Sign Stripping (Lines 55–58)**:
   After currency symbol stripping, the parser checks `if (!isNegative && trimmed.startsWith('-'))`.
   Because `isNegative` was left `false` by the preceding `+`, the guard mistakenly assumes *no sign has been processed yet*.
   Consequently, it encounters the second sign (`'-'`), strips it, and sets `isNegative = true`.
3. **Silent Conversion**:
   - For `"+-10"`: `+` is stripped $\to$ `"-10"`. Currency regex does not match. `!isNegative` is true $\to$ `-` is stripped, `isNegative = true` $\to$ remaining `"10"` is parsed as 1000 minor units $\to$ returns `-1000`.
   - For `"+¥-10"`: `+` is stripped $\to$ `"¥-10"`. `¥` is stripped $\to$ `"-10"`. `!isNegative` is true $\to$ `-` is stripped, `isNegative = true` $\to$ returns `-1000`.

In contrast, combinations like `"--10"`, `"-+10"`, and `"++10"` failed because either `isNegative` was already `true` (preventing the second minus from being stripped, leaving it to fail the `^\d+$` integer regex) or `+` was not checked in the second sign pass.

---

## 2. Formulation of Strict Sign Parsing Logic

### 2.1 Core Invariant
In standard monetary syntax:
$$\text{Amount} = [\text{Sign}_1]\;[\text{CurrencySymbol}]\;[\text{Sign}_2]\;\text{Digits}$$

To ensure mathematical and financial integrity, **at most one explicit sign** may appear across both sign positions ($\text{Sign}_1$ and $\text{Sign}_2$). Specifically:
1. If $\text{Sign}_1$ is present, $\text{Sign}_2$ is strictly forbidden.
2. If $\text{Sign}_1$ is absent, $\text{Sign}_2$ is permitted (supporting formats like `"¥-10"` or `"¥+10"`).
3. Any sequence of multiple consecutive signs (e.g. `"+-10"`, `"-+10"`, `"++10"`, `"--10"`, `"¥--10"`, `"¥+-10"`) must be rejected.

### 2.2 Proposed Solution: State Tracking (`hasLeadingSign` / `hasExplicitSign`)

We define a boolean flag:
```dart
bool hasLeadingSign = false; // or hasExplicitSign
```

When checking the leading character:
- If `trimmed.startsWith('-')`: set `isNegative = true; hasLeadingSign = true;`.
- If `trimmed.startsWith('+')`: set `hasLeadingSign = true;`.

Then, after stripping currency symbols, inspect the remaining prefix:
- Only allow sign extraction if `!hasLeadingSign`.
- If `hasLeadingSign` is already `true`, any subsequent sign is NOT stripped, causing downstream numeric validation to reject the input, OR it can be fast-failed immediately.

---

## 3. Design Options & Comparison

### Option 1: Clean State Tracking (Recommended & Canonical)
This option tracks `hasLeadingSign` and ensures a second sign is never consumed. Any unconsumed sign character remains in `trimmed` and is rejected by the existing integer regex validation `RegExp(r'^\d+$')`.

```dart
    bool isNegative = false;
    bool hasLeadingSign = false;

    if (trimmed.startsWith('-')) {
      isNegative = true;
      hasLeadingSign = true;
      trimmed = trimmed.substring(1).trim();
    } else if (trimmed.startsWith('+')) {
      hasLeadingSign = true;
      trimmed = trimmed.substring(1).trim();
    }

    if (stripCurrencySymbols) {
      trimmed = trimmed.replaceFirst(
        RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
        '',
      );
      if (!hasLeadingSign) {
        if (trimmed.startsWith('-')) {
          isNegative = true;
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
        } else if (trimmed.startsWith('+')) {
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
        }
      }
    }
```

#### Why Option 1 is Recommended:
1. **Minimal, surgical diff**: Only 7 lines added/modified. Zero redundant checks.
2. **Harmonious with peer agents**: Exactly matches the sign tracking adopted in `explorer_m0_r3_1/proposed_currency_utils.dart`.
3. **100% test pass**: Tested against all 48 adversarial assertions from `explorer_m0_r3_3` with zero failures.
4. **Natural integration with existing regex**: Any non-digit (including `-` or `+`) left in the integer part triggers `FormatException('Invalid characters in currency integer part: "$input"')`.

---

### Option 2: Explicit Fast-Fail Sign Validation (Alternative Defense-in-Depth)
This option adds explicit guard clauses that throw a dedicated `FormatException` immediately if a second sign character is detected:

```dart
    bool isNegative = false;
    bool hasLeadingSign = false;

    if (trimmed.startsWith('-')) {
      isNegative = true;
      hasLeadingSign = true;
      trimmed = trimmed.substring(1).trim();
    } else if (trimmed.startsWith('+')) {
      hasLeadingSign = true;
      trimmed = trimmed.substring(1).trim();
    }

    // Fast-fail: consecutive signs before currency symbol
    if (hasLeadingSign && (trimmed.startsWith('-') || trimmed.startsWith('+'))) {
      throw FormatException('Invalid currency string with multiple signs: "$input"');
    }

    if (stripCurrencySymbols) {
      trimmed = trimmed.replaceFirst(
        RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
        '',
      );
      if (hasLeadingSign) {
        if (trimmed.startsWith('-') || trimmed.startsWith('+')) {
          throw FormatException('Invalid currency string with multiple signs: "$input"');
        }
      } else {
        if (trimmed.startsWith('-')) {
          isNegative = true;
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
        } else if (trimmed.startsWith('+')) {
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
        }
        if (hasLeadingSign && (trimmed.startsWith('-') || trimmed.startsWith('+'))) {
          throw FormatException('Invalid currency string with multiple signs: "$input"');
        }
      }
    }
```

#### Option 2 Trade-offs:
- **Pros**: Throws early with a specialized message (`Invalid currency string with multiple signs`).
- **Cons**: Adds ~18 lines of boilerplate code. Both options throw `FormatException`, and `tryParseToMinorUnits` catches `FormatException` equally.

---

### Comparison Matrix

| Property | Original Code | Option 1 (Recommended) | Option 2 (Fast-Fail) |
|---|---|---|---|
| `"+-10"` | Parses to `-1000` ❌ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"+¥-10"` | Parses to `-1000` ❌ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"-+10"` | Throws `FormatException` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"++10"` | Throws `FormatException` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"--10"` | Throws `FormatException` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"-¥+10"` | Throws `FormatException` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"-¥-10"` | Throws `FormatException` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"+¥+10"` | Throws `FormatException` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| `"¥-10"` | Parses to `-1000` ✅ | Parses to `-1000` ✅ | Parses to `-1000` ✅ |
| `"¥+10"` | Throws `FormatException` ❌ | Parses to `1000` ✅ | Parses to `1000` ✅ |
| `"¥+-10"` | Throws `FormatException` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ | Throws `FormatException`, `tryParse` returns `null` ✅ |
| Line footprint | Base | +7 lines | +18 lines |

---

## 4. Empirical Test Verification

We executed two dedicated empirical verification suites (`verify_sign_parsing.dart` and `test_options.dart`) in Dart VM:

### Suite 1: Full Boundary Matrix (`verify_sign_parsing.dart`)
- **Total Test Cases**: 61
- **Passed**: 61
- **Failed**: 0
- **Verbatim Output**:
```text
=== Running Malformed Conflicting Sign Test Cases ===
=== Running Valid Sign & Currency Combinations ===
=== Results: Passed: 61, Failed: 0 ===
```

### Suite 2: Comparative Verification (`test_options.dart`)
Running all 12 adversarial test cases from `explorer_m0_r3_3` across both `parseToMinorUnits` and `tryParseToMinorUnits`, with both `allowNegative: true` and `allowNegative: false` (48 assertions per implementation):
```text
--- Testing Option 1 (State tracking & downstream validation) ---
  [OK] All 12 conflicting sign test cases passed in Option 1 (State tracking & downstream validation) (48 assertions)!
--- Testing Option 2 (Explicit fast-fail multiple signs validation) ---
  [OK] All 12 conflicting sign test cases passed in Option 2 (Explicit fast-fail multiple signs validation) (48 assertions)!
ALL COMPARISONS SUCCESSFUL!
```

---

## 5. Exact Drop-in Code Patch

Target File: `lib/core/utils/currency_utils.dart`

```diff
--- a/lib/core/utils/currency_utils.dart
+++ b/lib/core/utils/currency_utils.dart
@@ -42,19 +42,27 @@ class CurrencyUtils {
     bool isNegative = false;
+    bool hasLeadingSign = false;
     if (trimmed.startsWith('-')) {
       isNegative = true;
+      hasLeadingSign = true;
       trimmed = trimmed.substring(1).trim();
     } else if (trimmed.startsWith('+')) {
+      hasLeadingSign = true;
       trimmed = trimmed.substring(1).trim();
     }

     if (stripCurrencySymbols) {
       trimmed = trimmed.replaceFirst(
         RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
         '',
       );
-      if (!isNegative && trimmed.startsWith('-')) {
-        isNegative = true;
-        trimmed = trimmed.substring(1).trim();
+      if (!hasLeadingSign) {
+        if (trimmed.startsWith('-')) {
+          isNegative = true;
+          hasLeadingSign = true;
+          trimmed = trimmed.substring(1).trim();
+        } else if (trimmed.startsWith('+')) {
+          hasLeadingSign = true;
+          trimmed = trimmed.substring(1).trim();
+        }
       }
     }
```

---

## 6. Integration With Peer Explorers

1. **Alignment with `explorer_m0_r3_1` (Integer Overflow)**:
   In `explorer_m0_r3_1/proposed_currency_utils.dart`, `hasExplicitSign` is integrated seamlessly with `_maxSafeMajor = 92233720368547758` and `_maxMinorForBoundary = 7`. Both fixes operate orthogonally without any conflict.
2. **Alignment with `explorer_m0_r3_3` (Unit Test Suite)**:
   All test cases in `explorer_m0_r3_3/currency_utils_test.patch` (specifically lines 115–153 covering `conflictingSignCases`) pass 100% against this logic.
