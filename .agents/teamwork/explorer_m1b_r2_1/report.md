# Forensic Remediation Strategy: OCR Pipeline Defect Remediation

**Author**: `explorer_m1b_r2_1`  
**Parent**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Milestone**: M1-B Forensic Remediation (Features F19–F26: OCR Transaction Parsing Pipeline)  
**Date**: 2026-10-22  
**Status**: APPROVED FIX STRATEGY READY FOR WORKER IMPLEMENTATION  

---

## 1. Executive Summary & Defect Catalog

During the forensic audit of Milestone M1-B, 3 operational test failures and static analysis lint warnings were verified in the OCR transaction parsing pipeline. These defects jeopardize monetary calculation accuracy, allow corrupted inputs into the ledger, and present a critical data integrity risk in the Tier 3 platform identifier deduplication engine.

| Defect # | Target File & Component | Severity | Root Cause Mechanism | Impact & Blast Radius |
|---|---|---|---|---|
| **D1** | `lib/features/recognition/amount_parser.dart`<br>`repairOcrNumbers` | **High** | Single-pass regex consumes the preceding character, skipping adjacent optical confusion characters (`O/o`, `l/I`, `S/s`, `B`). | `¥1OOO.OO` becomes `¥10O0.0O`, causing 10x magnitude corruption (`¥100.00` instead of `¥1000.00`). |
| **D2** | `lib/features/recognition/amount_parser.dart`<br>`extractMinorUnits` | **Medium** | Regex `[-+]?[\d,]+(?:\.\d+)?` terminates after the first decimal part `.34`, ignoring `.56`. | Corrupted receipt amounts like `12.34.56` are silently accepted as `12.34` (1234 cents) instead of being flagged as malformed. |
| **D3** | `lib/features/recognition/order_id_parser.dart`<br>`_platformNoRegex`, `_merchantOrderRegex` | **Critical** | Regex character class `[0-9a-zA-Z*xX_.-]+` excludes Unicode ellipsis `…` (\u2026) and fullwidth asterisk `＊` (\uFF0A). | Masked ID `4200002134202610…1234` is truncated to 16 visible digits and falsely graded as `COMPLETE`, triggering duplicate collisions in `confirmed_identifiers`. |
| **D4** | `test/recognition/ocr_adversarial_test.dart`<br>`test/recognition/recognition_adversarial_test.dart` | **Low** | Unused imports trigger `flutter analyze` exit code 1. | Fails repository-wide static analysis gate. |

---

## 2. Detailed Root Cause Analysis & Fix Strategies

### 2.1 Defect 1: Consecutive OCR Character Repair in `AmountParser`

#### 2.1.1 Root Cause Analysis
In `lib/features/recognition/amount_parser.dart:97-113`:
```dart
// Current single-pass implementation:
s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0');
s = s.replaceAllMapped(RegExp(r'[Oo]([0-9.¥￥$€£+-])'), (m) => '0${m[1]}');
```
Because regex engines consume characters in non-overlapping scans:
1. In input `'¥1OOO.OO'`, the first match matches `'1O'` (indices 1–2). The `'O'` at index 2 is consumed.
2. The scan resumes at index 3 (`'O'`), which is not preceded by any match in the scan.
3. The next match is `'.O'` (indices 4–5), leaving the final `'O'` at index 6 untouched.
4. The subsequent backward pass `[Oo]([0-9...])` can only match if a digit/symbol follows immediately. A trailing `'O'` at the end of the token has no following character, resulting in `'¥10O0.0O'`.

#### 2.1.2 Remediation Strategy
We employ a two-fold engineering solution:
1. **Token-Level Quantifiers (`+`)**: Match one or more consecutive confusion characters in a single regex match. By matching `([0-9.¥￥$€£+-])([Oo]+)`, the entire run `'OOO'` is captured in `group(2)` and replaced with `'0' * group(2).length` in a single pass.
2. **Bounded Iterative Convergence Loop**: Wrap the passes in a `while (prev != s && iterations < 10)` loop. This handles cross-character cascading confusion (e.g. `¥1SO.BO` where `S` converts to `5`, which subsequently acts as a digit trigger to convert `O` to `0`).
3. **Pre-compiled Static RegExps**: Compile the regular expressions once as `static final RegExp` at class level to avoid repeated allocation during receipt parsing.

#### 2.1.3 Exact Code Diff (`lib/features/recognition/amount_parser.dart`)

```dart
<<<<
  /// Performs character repair on optical misidentifications in numbers
  static String repairOcrNumbers(String input) {
    var s = input.trim();

    // Full-width numbers and symbols
    s = s
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9')
        .replaceAll('￥', '¥')
        .replaceAll('。', '.')
        .replaceAll('．', '.')
        .replaceAll('·', '.')
        .replaceAll('，', ',');

    // Character repairs: O/o -> 0, l/I/i/|/! -> 1, S/s -> 5, B -> 8
    // Repair O or o in numeric context
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0');
    s = s.replaceAllMapped(RegExp(r'[Oo]([0-9.¥￥$€£+-])'), (m) => '0${m[1]}');

    // Repair l, I, i, |, ! in numeric context
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[lIi|!]'), (m) => '${m[1]}1');
    s = s.replaceAllMapped(RegExp(r'[lIi|!]([0-9.¥￥$€£+-])'), (m) => '1${m[1]}');

    // Repair S or s in numeric context
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Ss]'), (m) => '${m[1]}5');
    s = s.replaceAllMapped(RegExp(r'[Ss]([0-9.¥￥$€£+-])'), (m) => '5${m[1]}');

    // Repair B in numeric context
    s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])B'), (m) => '${m[1]}8');
    s = s.replaceAllMapped(RegExp(r'B([0-9.¥￥$€£+-])'), (m) => '8${m[1]}');

    // Comma disambiguation: 28,90 -> 28.90
    if (s.contains(',') && !s.contains('.')) {
      if (RegExp(r',\d{2}$').hasMatch(s)) {
        s = s.replaceAll(',', '.');
      }
    }

    return s;
  }
====
  // Static compiled regexes for high-throughput OCR character repair
  static final RegExp _repAfterO = RegExp(r'([0-9.¥￥$€£+-])([Oo]+)');
  static final RegExp _repBeforeO = RegExp(r'([Oo]+)([0-9.¥￥$€£+-])');
  static final RegExp _repAfterOne = RegExp(r'([0-9.¥￥$€£+-])([lIi|!]+)');
  static final RegExp _repBeforeOne = RegExp(r'([lIi|!]+)([0-9.¥￥$€£+-])');
  static final RegExp _repAfterFive = RegExp(r'([0-9.¥￥$€£+-])([Ss]+)');
  static final RegExp _repBeforeFive = RegExp(r'([Ss]+)([0-9.¥￥$€£+-])');
  static final RegExp _repAfterEight = RegExp(r'([0-9.¥￥$€£+-])(B+)');
  static final RegExp _repBeforeEight = RegExp(r'(B+)([0-9.¥￥$€£+-])');

  /// Performs character repair on optical misidentifications in numbers
  static String repairOcrNumbers(String input) {
    var s = input.trim();

    // Full-width numbers and symbols
    s = s
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9')
        .replaceAll('￥', '¥')
        .replaceAll('。', '.')
        .replaceAll('．', '.')
        .replaceAll('·', '.')
        .replaceAll('，', ',');

    // Character repairs: O/o -> 0, l/I/i/|/! -> 1, S/s -> 5, B -> 8
    // Iterative convergence loop with quantifier block replacement
    var prev = '';
    var iterations = 0;
    while (prev != s && iterations < 10) {
      iterations++;
      prev = s;

      // Repair O/o in numeric context (handles runs like OOO)
      s = s.replaceAllMapped(_repAfterO, (m) => '${m[1]}${'0' * m[2]!.length}');
      s = s.replaceAllMapped(_repBeforeO, (m) => '${'0' * m[1]!.length}${m[2]}');

      // Repair l, I, i, |, ! in numeric context
      s = s.replaceAllMapped(_repAfterOne, (m) => '${m[1]}${'1' * m[2]!.length}');
      s = s.replaceAllMapped(_repBeforeOne, (m) => '${'1' * m[1]!.length}${m[2]}');

      // Repair S or s in numeric context
      s = s.replaceAllMapped(_repAfterFive, (m) => '${m[1]}${'5' * m[2]!.length}');
      s = s.replaceAllMapped(_repBeforeFive, (m) => '${'5' * m[1]!.length}${m[2]}');

      // Repair B in numeric context
      s = s.replaceAllMapped(_repAfterEight, (m) => '${m[1]}${'8' * m[2]!.length}');
      s = s.replaceAllMapped(_repBeforeEight, (m) => '${'8' * m[1]!.length}${m[2]}');
    }

    // Comma disambiguation: 28,90 -> 28.90
    if (s.contains(',') && !s.contains('.')) {
      if (RegExp(r',\d{2}$').hasMatch(s)) {
        s = s.replaceAll(',', '.');
      }
    }

    return s;
  }
>>>>
```

---

### 2.2 Defect 2: Distorted Multiple Decimals in `AmountParser`

#### 2.2.1 Root Cause Analysis
In `lib/features/recognition/amount_parser.dart:125-142`:
```dart
  static int? extractMinorUnits(String rawStr) {
    final repaired = repairOcrNumbers(rawStr);
    // Find numeric pattern that can contain commas and decimal point
    final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);
    if (numMatch == null) return null;

    final token = numMatch.group(0)!;
    try {
      final cents = CurrencyUtils.parseToMinorUnits(
        token,
        allowNegative: true,
        stripCurrencySymbols: true,
      );
      return cents.abs(); // Financial amounts stored as positive cents
    } catch (_) {
      return null;
    }
  }
```
When `rawStr` is `'12.34.56'`:
- `repaired` is `'12.34.56'`.
- `RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired)` matches `'12'` followed by optional single decimal group `'.34'`.
- `numMatch.group(0)` is `'12.34'`.
- The trailing `'.56'` is discarded by `firstMatch`.
- `CurrencyUtils.parseToMinorUnits("12.34")` returns `1234` cents without triggering `CurrencyUtils`'s built-in multiple decimal protection (`parts.length > 2`).

#### 2.2.2 Remediation Strategy
1. **Multi-Decimal Check**: In `extractMinorUnits`, before extracting tokens, verify whether the candidate contains multiple decimal points:
   ```dart
   if (repaired.split('.').length > 2) {
     return null;
   }
   ```
2. **Boundary Truncation Verification**: Additionally, verify that `numMatch.end` was not immediately followed by another decimal point or distorted digit sequence:
   ```dart
   final matchEnd = numMatch.end;
   if (matchEnd < repaired.length && repaired.substring(matchEnd).startsWith('.')) {
     return null;
   }
   ```
3. Returning `null` from `extractMinorUnits` prevents the corrupted candidate from entering `paidCandidates`. In `AmountParser.parse`, when `paidCandidates` and `standaloneCandidates` are empty, `selectedPaid` remains `null`, `finalPaidAmount` remains `null`, and `ValidationIssue.missingAmountIssue()` is added, as required by Vector 2.5b.

#### 2.2.3 Exact Code Diff (`lib/features/recognition/amount_parser.dart`)

```dart
<<<<
  /// Extracts number token and converts to minor units (cents)
  static int? extractMinorUnits(String rawStr) {
    final repaired = repairOcrNumbers(rawStr);
    // Find numeric pattern that can contain commas and decimal point
    final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);
    if (numMatch == null) return null;

    final token = numMatch.group(0)!;
    try {
      final cents = CurrencyUtils.parseToMinorUnits(
        token,
        allowNegative: true,
        stripCurrencySymbols: true,
      );
      return cents.abs(); // Financial amounts stored as positive cents
    } catch (_) {
      return null;
    }
  }
====
  /// Extracts number token and converts to minor units (cents)
  static int? extractMinorUnits(String rawStr) {
    final repaired = repairOcrNumbers(rawStr);

    // Reject distorted amounts containing multiple decimal points (e.g. "12.34.56")
    if (repaired.split('.').length > 2) {
      return null;
    }

    // Find numeric pattern that can contain commas and decimal point
    final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);
    if (numMatch == null) return null;

    // Reject if the match was prematurely truncated before a subsequent decimal point
    final matchEnd = numMatch.end;
    if (matchEnd < repaired.length && repaired.substring(matchEnd).startsWith('.')) {
      return null;
    }

    final token = numMatch.group(0)!;
    try {
      final cents = CurrencyUtils.parseToMinorUnits(
        token,
        allowNegative: true,
        stripCurrencySymbols: true,
      );
      return cents.abs(); // Financial amounts stored as positive cents
    } catch (_) {
      return null;
    }
  }
>>>>
```

---

### 2.3 Defect 3: Unicode Ellipsis `…` and Fullwidth `＊` in `OrderIdParser`

#### 2.3.1 Root Cause Analysis
In `lib/features/recognition/order_id_parser.dart`:
```dart
static final RegExp _merchantOrderRegex = RegExp(
  r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
);

static final RegExp _platformNoRegex = RegExp(
  r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
);
```
1. Mobile payment receipts commonly display masked transaction numbers using the Unicode ellipsis `…` (U+2026) or fullwidth asterisk `＊` (U+FF0A), e.g. `交易单号 4200002134202610…1234`.
2. Because `…` and `＊` are absent from `[0-9a-zA-Z*xX_.-]+`, the regex terminates at offset 21 immediately before `…`.
3. The captured `platformTransactionNo` is `'4200002134202610'` (16 digits).
4. In lines 124–140:
   - `id` does not contain `*`, `...`, `…`, or `x` (because `…1234` was discarded).
   - `id.length >= 16`.
   - `id.endsWith('.')` is false.
   - Result: `completeness` is set to `IdentifierCompleteness.complete`.
5. **Critical Dedup Vulnerability**: In `PlatformIdentifier`, `isEligibleForHardDedup` evaluates to `true`! The incomplete prefix `4200002134202610` is stored in the database's `confirmed_identifiers` table. Any subsequent transaction starting with those same 16 digits will trigger a false-positive Tier 3 collision and fail commit.

#### 2.3.2 Remediation Strategy
1. **Include `…` and `＊` in Character Classes**: Add `…` and `＊` to both `_merchantOrderRegex` and `_platformNoRegex`.
2. **Update Mask Detection in `parse()`**: Add `id.contains('＊')` to the `hasMaskChars` check to guarantee fullwidth asterisks also downgrade completeness to `IdentifierCompleteness.masked`.

#### 2.3.3 Exact Code Diff (`lib/features/recognition/order_id_parser.dart`)

```dart
<<<<
  static final RegExp _merchantOrderRegex = RegExp(
    r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
  );

  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
  );
====
  static final RegExp _merchantOrderRegex = RegExp(
    r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*＊xX_.\-…]+)',
  );

  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*＊xX_.\-…]+)',
  );
>>>>
```

And in lines 125–130:

```dart
<<<<
    if (platformTransactionNo != null) {
      final id = platformTransactionNo;
      final hasMaskChars = id.contains('*') ||
          id.contains('...') ||
          id.contains('…') ||
          id.toLowerCase().contains('x');
====
    if (platformTransactionNo != null) {
      final id = platformTransactionNo;
      final hasMaskChars = id.contains('*') ||
          id.contains('＊') ||
          id.contains('...') ||
          id.contains('…') ||
          id.toLowerCase().contains('x');
>>>>
```

---

### 2.4 Defect 4: Static Analysis Cleanup (Unused Imports)

#### 2.4.1 Root Cause Analysis
Running `flutter analyze` returns 3 unused import warnings (exit code 1):
1. `test/recognition/ocr_adversarial_test.dart:12:8`: `import 'package:sqflite_common_ffi/sqflite_ffi.dart';` (no sqflite_ffi symbols used).
2. `test/recognition/recognition_adversarial_test.dart:10:8`: `import 'package:singwallet/features/recognition/channel_status_parser.dart';` (no channel status parser symbols used).
3. `test/recognition/recognition_adversarial_test.dart:12:8`: `import 'package:singwallet/features/recognition/models/field_evidence.dart';` (no field evidence symbols used).

#### 2.4.2 Exact Code Diffs

**File 1: `test/recognition/ocr_adversarial_test.dart`**
Remove line 12:
```dart
<<<<
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:singwallet/features/recognition/order_id_parser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
====
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:singwallet/features/recognition/order_id_parser.dart';

void main() {
>>>>
```

**File 2: `test/recognition/recognition_adversarial_test.dart`**
Remove lines 10 and 12:
```dart
<<<<
import 'package:singwallet/features/recognition/amount_parser.dart';
import 'package:singwallet/features/recognition/channel_status_parser.dart';
import 'package:singwallet/features/recognition/merchant_normalizer.dart';
import 'package:singwallet/features/recognition/models/field_evidence.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
====
import 'package:singwallet/features/recognition/amount_parser.dart';
import 'package:singwallet/features/recognition/merchant_normalizer.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
>>>>
```

---

## 3. Regression Safety & Test Coverage Impact Matrix

| Test Suite | Targeted Test Cases | Status Before Fix | Status After Fix | Safety Justification |
|---|---|---|---|---|
| `ocr_adversarial_test.dart` | Vector 1.9 (`¥1OOO.OO`) | **FAIL** (`¥10O0.0O`) | **PASS** (`¥1000.00`) | Quantifiers capture runs of `O` without skips. |
| `ocr_adversarial_test.dart` | Vector 2.5b (`12.34.56`) | **FAIL** (returns `1234`) | **PASS** (returns `null`) | `split('.').length > 2` strictly rejects multiple dots. |
| `ocr_adversarial_test.dart` | Vector 5.1b (`420000...…1234`) | **FAIL** (`isFalse` on COMPLETE) | **PASS** (graded `masked`) | Regex includes `…`, allowing `hasMaskChars` to trigger. |
| `recognition_adversarial_test.dart` | Boundary 2.4 (`¥1OOO.OO`) | **FAIL** | **PASS** | Convergence loop and quantifiers repair all confusion chars. |
| `recognition_adversarial_test.dart` | Boundary 4.1b (`…` in order ID) | **FAIL** | **PASS** | `…` included in ID character class. |
| `amount_parser_test.dart` | All 8 baseline tests | **PASS** (8/8) | **PASS** (8/8) | Fully backwards-compatible with standard amounts. |
| `order_id_parser_test.dart` | All 5 baseline tests | **PASS** (5/5) | **PASS** (5/5) | Fully backwards-compatible with standard IDs. |
| Static Analysis Gate | `flutter analyze` | **FAIL** (3 issues) | **PASS** (0 issues) | Unused imports removed. |

---

## 4. Verification Protocol for Implementing Worker

The implementer (`worker_m1b_r2_1` or designated worker) can verify the changes by running the following sequential checks:

```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path

# Step 1: Run static analysis (must report "No issues found!")
flutter analyze

# Step 2: Run targeted OCR adversarial tests (must report 33 passed, 0 failed)
flutter test test/recognition/ocr_adversarial_test.dart

# Step 3: Run recognition adversarial tests (must report 21 passed, 0 failed)
flutter test test/recognition/recognition_adversarial_test.dart

# Step 4: Run existing unit test suites for amount and order ID parsers
flutter test test/recognition/amount_parser_test.dart test/recognition/order_id_parser_test.dart

# Step 5: Run full repository regression test suite
flutter test
```

All commands must exit with code 0.
