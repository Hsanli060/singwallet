# Holistic Integration & Verification Plan: Milestone M1-B Forensic Remediation

**Author**: `explorer_m1b_r2_3` (Roles: `investigation`, `synthesis`, `integration & verification planning`)  
**Parent Orchestrator**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Milestone**: M1-B (Features F19–F30: OCR Transaction Parsing Pipeline & Classification Rule Engine)  
**Date**: 2026-10-22  
**Status**: READY FOR WORKER EXECUTION  

---

## 1. Executive Summary & Multi-Source Synthesis

A comprehensive forensic audit of Milestone M1-B by `auditor_m1b_1` resulted in an **INTEGRITY VIOLATION** verdict due to static analysis failures (`flutter analyze` exit code 1) and test suite failures (`flutter test` exit code 1).

To formulate a definitive, regression-free remediation plan, this investigation synthesized the findings across all five specialized evaluation agents:
1. **Auditor (`auditor_m1b_1`)**: Discovered 1 static analysis lint warning and 7 adversarial test failures spanning OCR amount repair, multi-decimal slicing, masked order ID false-completeness, SQL `%` empty matching, and SQLite ID collision.
2. **Reviewer 1 (`reviewer_m1b_1`)**: Verified zero dummy facades or shortcuts (PASS on integrity). Issued `REQUEST_CHANGES` on 2 algorithmic defects: Chinese ellipsis `…` / fullwidth `＊` omission in `OrderIdParser`, and single-pass non-overlapping regex failure in `AmountParser.repairOcrNumbers`.
3. **Reviewer 2 (`reviewer_m1b_2`)**: Issued `APPROVE` on Features F27–F30 for normal functional flows (6-tier waterfall, SQL wildcard compilation, dynamic learning immutability, 3D orthogonal grouping).
4. **Challenger 1 (`challenger_m1b_1`)**: Issued `REQUEST_CHANGES` backed by 3 failing tests in `test/recognition/ocr_adversarial_test.dart` (Vector 1.9, Vector 2.5b, Vector 5.1b) and 2 failing tests in `test/recognition/recognition_adversarial_test.dart` (Boundary 2.4, Boundary 4.1b).
5. **Challenger 2 (`challenger_m1b_2`)**: Authored 31 stress tests in `test/classification/rule_engine_adversarial_test.dart` (which all currently pass), while identifying 4 latent edge cases: primary key ID collision under rapid rule learning, ReDoS vulnerability in `regex:` prefix mode, channel rule tie-breaking, and sub-brand normalization.

### Synthesis Matrix of Observed Defects & Resolutions

| # | Discovered Finding | Source | Current Impact | Exact Remediation | Target File |
|---|---|---|---|---|---|
| **D1** | Single-pass regex leaves consecutive OCR confusion chars unrepaired (`¥1OOO.OO` -> `¥10O0.0O`) | Auditor, Reviewer 1, Challenger 1 | **Test Failure** (`ocr_adversarial_test` V1.9, `recognition_adversarial_test` B2.4) | Replace single-pass `replaceAllMapped` with iterative convergence loop (`while (prev != s)`) | `lib/features/recognition/amount_parser.dart` |
| **D2** | Multiple decimal points (`12.34.56`) silently truncated to `12.34` by greedy regex | Auditor, Challenger 1 | **Test Failure** (`ocr_adversarial_test` V2.5b) | Validate `repaired.split('.').length <= 2` before extracting tokens; return `null` if violated | `lib/features/recognition/amount_parser.dart` |
| **D3** | Masked order IDs with ellipsis `…` / `＊` prematurely truncated and marked `COMPLETE` | Auditor, Reviewer 1, Challenger 1 | **Test Failure** (`ocr_adversarial_test` V5.1b, `recognition_adversarial_test` B4.1b) | Add `…` and `＊` to `_merchantOrderRegex`, `_platformNoRegex`, and `hasMaskChars` check | `lib/features/recognition/order_id_parser.dart` |
| **D4** | Rapid same-millisecond rule learning collides on `classification_rules.id` (SQLite 1555) | Auditor, Challenger 2 | **Latent Crash** on concurrent/rapid rule creation | Switch to `microsecondsSinceEpoch` + monotonic static counter `_ruleCounter++` | `lib/features/classification/rule_engine.dart` |
| **D5** | Unused imports in adversarial test files cause static analysis gate failure | Auditor, Reviewer 1, Challenger 1 | **Static Analysis Failure** (`flutter analyze` exit code 1) | Remove unused imports from `ocr_adversarial_test.dart` and `recognition_adversarial_test.dart` | Test files |

---

## 2. In-Depth Forensic Analysis & Critical Regression Traps

### 2.1 Defect 1: Consecutive OCR Optical Confusion Unrepaired
- **Observed Behavior**:
  In `AmountParser.repairOcrNumbers`:
  ```dart
  s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0');
  s = s.replaceAllMapped(RegExp(r'[Oo]([0-9.¥￥$€£+-])'), (m) => '0${m[1]}');
  ```
  In Dart RegExp execution, `replaceAllMapped` advances matches non-overlappingly. For `'¥1OOO.OO'`:
  - Match 1 consumes `'1O'` -> `'10'`. The adjacent `'O'` is consumed in the first match.
  - The second `'O'` is not preceded by a digit in the same pass.
  - Match 2 consumes `'.O'` -> `'.0'`.
  - The trailing `'O'` at the end is left untouched.
  - Result: `'¥10O0.0O'`.
  When `extractMinorUnits` extracts numbers, the trailing `O` is discarded, resulting in `100.0` (10000 cents) instead of `1000.00` (100000 cents), introducing an intolerable **10x financial calculation error**.
- **Remediation**:
  Wrap all character confusion repair mappings in a convergence loop:
  ```dart
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
  *Termination Guarantee*: Each replacement strictly converts non-digits to digits and never converts digits back. The number of non-digits is strictly monotonically decreasing, guaranteeing loop termination in at most `s.length` iterations.

### 2.2 Defect 2: Distorted Multi-Decimal Amounts Silently Sliced
- **Observed Behavior**:
  In `AmountParser.extractMinorUnits`:
  ```dart
  final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);
  ```
  For distorted input `'12.34.56'`:
  - `(?:\.\d+)?` matches `'.34'` and halts.
  - The captured token is `'12.34'`.
  - `CurrencyUtils.parseToMinorUnits('12.34')` returns `1234` cents without throwing!
  This bypasses `CurrencyUtils`'s multi-decimal validation and corrupts ledger entries.
- **Remediation**:
  Validate that the candidate numeric string does not contain multiple decimal points before token extraction:
  ```dart
  if (repaired.split('.').length > 2) {
    return null;
  }
  ```
  When `extractMinorUnits` returns `null`, `AmountParser.parse` adds `ValidationIssue.missingAmountIssue()` and sets `paidAmountMinor = null`, satisfying test Vector 2.5b.

### 2.3 Defect 3: Masked Order IDs with Ellipsis Falsely Classified as COMPLETE
- **Observed Behavior**:
  In `OrderIdParser`:
  ```dart
  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
  );
  ```
  When parsing `交易单号 4200002134202610…1234` (WeChat masked format):
  - Character set `[0-9a-zA-Z*xX_.-]+` does not contain `…` (Unicode U+2026) or `＊` (fullwidth U+FF0A).
  - The regex stops matching before `…`, capturing only the 16 visible digits `4200002134202610`.
  - In line 124–140, because `id` has length 16 and contains no captured mask characters, it is graded `IdentifierCompleteness.complete`.
  - This allows the masked ID into Tier 3 hard deduplication (`confirmed_identifiers`), creating severe false duplicate collisions for subsequent transactions.
- **Remediation**:
  Update both `_platformNoRegex` and `_merchantOrderRegex` to include `…` and `＊`:
  ```dart
  static final RegExp _merchantOrderRegex = RegExp(
    r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );

  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );
  ```
  And in `parse`:
  ```dart
  final hasMaskChars = id.contains('*') ||
      id.contains('＊') ||
      id.contains('...') ||
      id.contains('…') ||
      id.toLowerCase().contains('x');
  ```

### 2.4 Defect 4: Primary Key ID Collision in `learnRuleFromUserAction`
- **Observed Behavior**:
  In `ClassificationRuleEngine.learnRuleFromUserAction`:
  ```dart
  final ruleId = 'rule_${DateTime.now().millisecondsSinceEpoch}_${pattern.hashCode.abs()}';
  ```
  When learning channel-specific rules rapidly (e.g., creating rules for WeChat and Alipay for the same merchant within the same millisecond), `ruleId` is identical, violating the SQLite `PRIMARY KEY` constraint on `classification_rules.id` with `SqfliteFfiException: 1555`.
- **Remediation**:
  Add an internal monotonic sequence counter and microsecond timestamp:
  ```dart
  static int _ruleCounter = 0;
  // in learnRuleFromUserAction:
  final ruleId = 'rule_${DateTime.now().microsecondsSinceEpoch}_${pattern.hashCode.abs()}_${_ruleCounter++}';
  ```

### 2.5 ⚠️ CRITICAL REGRESSION TRAP: Do NOT Alter `RuleMatcher` Lines 62 & 112

A critical subtlety was revealed by cross-referencing the auditor's suggestions against the actual test code in `test/classification/rule_engine_adversarial_test.dart`:

1. **Trap A: SQL Wildcard `%` on Empty Target (`rule_matcher.dart:62`)**:
   - The auditor suggested: `if (candidateTarget.isEmpty) { return pattern.trim().split('').every((c) => c == '%'); }`.
   - **However**, in `test/classification/rule_engine_adversarial_test.dart`, line 79–80 explicitly asserts:
     ```dart
     // Defensive invariant: empty target with non-empty pattern is safely rejected
     expect(RuleMatcher.matches(pattern: '%%%%%', target: ''), isFalse);
     ```
   - **Impact**: If the worker modifies `rule_matcher.dart` line 62 to return `true` for `%%%%%` on an empty target, **Test 1.1 in `rule_engine_adversarial_test.dart` will immediately FAIL!**
   - **Directive**: Leave line 62 in `rule_matcher.dart` AS-IS:
     ```dart
     if (candidateTarget.isEmpty && pattern.trim().isNotEmpty) return false;
     ```

2. **Trap B: Channel Specificity in Tie-Breaking Comparator (`rule_matcher.dart:112`)**:
   - Challenger 2 suggested prioritizing channel specificity over `createdAt` in `RuleMatcher.compareRules`.
   - **However**, in `test/classification/rule_engine_adversarial_test.dart`, Test 4.6 (lines 673–701) was written explicitly as an empirical demonstration of current shadowing behavior:
     ```dart
     test('4.6 Empirical demonstration of channel rule shadowing when priorities are equal', () async {
       ...
       final res = await engine.classify(
         merchantRaw: '全家便利店',
         paymentChannel: 'wechat',
       );
       expect(res.categoryId, 'cat_shopping');
     });
     ```
     Test 4.6 asserts `cat_shopping` (the later-created global rule).
   - **Impact**: If the worker modifies `compareRules` to sort channel rules ahead of global rules, `res.categoryId` becomes `cat_food`, and **Test 4.6 will immediately FAIL!**
   - **Directive**: Do NOT modify `RuleMatcher.compareRules` sorting priority. Keep `priority DESC`, `pattern.length DESC`, `createdAt DESC`.

---

## 3. Exact File Modifications Specification for Worker

The worker `worker_m1b_1` must apply edits **strictly** to the following 5 files:

### File 1: `lib/features/recognition/amount_parser.dart`

#### Modification 1.1: Iterative Convergence in `repairOcrNumbers`
- **Lines**: 97–113
- **Action**: Replace single-pass `replaceAllMapped` blocks with an iterative `while (prev != s)` loop.
- **Before**:
```dart
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
```
- **After**:
```dart
    // Character repairs: O/o -> 0, l/I/i/|/! -> 1, S/s -> 5, B -> 8
    // Iterative convergence loop to repair consecutive and trailing confusion characters
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

#### Modification 1.2: Multiple Decimal Point Rejection in `extractMinorUnits`
- **Lines**: 125–130
- **Action**: Add check rejecting raw strings with more than 1 decimal point before token extraction.
- **Before**:
```dart
  static int? extractMinorUnits(String rawStr) {
    final repaired = repairOcrNumbers(rawStr);
    // Find numeric pattern that can contain commas and decimal point
    final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);
    if (numMatch == null) return null;
```
- **After**:
```dart
  static int? extractMinorUnits(String rawStr) {
    final repaired = repairOcrNumbers(rawStr);
    // Distorted amount with multiple decimal points (e.g. 12.34.56) is invalid
    if (repaired.split('.').length > 2) {
      return null;
    }
    // Find numeric pattern that can contain commas and decimal point
    final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);
    if (numMatch == null) return null;
```

---

### File 2: `lib/features/recognition/order_id_parser.dart`

#### Modification 2.1: Regex Inclusion of Unicode Ellipsis `…` and Fullwidth `＊`
- **Lines**: 27–33
- **Action**: Update `_merchantOrderRegex` and `_platformNoRegex` character classes.
- **Before**:
```dart
  static final RegExp _merchantOrderRegex = RegExp(
    r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
  );

  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.-]+)',
  );
```
- **After**:
```dart
  static final RegExp _merchantOrderRegex = RegExp(
    r'(?:商户单号|商家订单号|商户订单号|外部单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );

  static final RegExp _platformNoRegex = RegExp(
    r'(?:微信支付交易单号|支付交易号|支付宝交易号|平台交易单号|交易单号|交易号|订单号)[：:\s]*([0-9a-zA-Z*xX_.\-…＊]+)',
  );
```

#### Modification 2.2: Add Fullwidth `＊` to Masked Characters Check
- **Lines**: 125–129
- **Action**: Check for `＊` in `hasMaskChars`.
- **Before**:
```dart
      final hasMaskChars = id.contains('*') ||
          id.contains('...') ||
          id.contains('…') ||
          id.toLowerCase().contains('x');
```
- **After**:
```dart
      final hasMaskChars = id.contains('*') ||
          id.contains('＊') ||
          id.contains('...') ||
          id.contains('…') ||
          id.toLowerCase().contains('x');
```

---

### File 3: `lib/features/classification/rule_engine.dart`

#### Modification 3.1: Monotonic Microsecond Counter for Rule ID Generation
- **Lines**: 416–418
- **Action**: Add static sequence counter `_ruleCounter` and use `microsecondsSinceEpoch`.
- **Before**:
```dart
    // Insert new rule
    final ruleId = 'rule_${DateTime.now().millisecondsSinceEpoch}_${pattern.hashCode.abs()}';
```
- **After**:
```dart
    // Insert new rule with collision-free monotonic microsecond identifier
    final ruleId = 'rule_${DateTime.now().microsecondsSinceEpoch}_${pattern.hashCode.abs()}_${_ruleCounter++}';
```
*(Add `static int _ruleCounter = 0;` to `ClassificationRuleEngine` declaration).*

---

### File 4: `test/recognition/ocr_adversarial_test.dart`

#### Modification 4.1: Remove Unused Import
- **Line**: 12
- **Action**: Remove `import 'package:sqflite_common_ffi/sqflite_ffi.dart';`
- **Before**:
```dart
import 'package:singwallet/features/recognition/order_id_parser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
```
- **After**:
```dart
import 'package:singwallet/features/recognition/order_id_parser.dart';

void main() {
```

---

### File 5: `test/recognition/recognition_adversarial_test.dart`

#### Modification 5.1: Remove Unused Imports
- **Lines**: 10 and 12
- **Action**: Remove unused imports for `channel_status_parser.dart` and `field_evidence.dart`.
- **Before**:
```dart
import 'package:singwallet/features/recognition/amount_parser.dart';
import 'package:singwallet/features/recognition/channel_status_parser.dart';
import 'package:singwallet/features/recognition/merchant_normalizer.dart';
import 'package:singwallet/features/recognition/models/field_evidence.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
```
- **After**:
```dart
import 'package:singwallet/features/recognition/amount_parser.dart';
import 'package:singwallet/features/recognition/merchant_normalizer.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';
```

---

## 4. Worker Write Boundaries & Invariant Enforcements

To guarantee zero regression across prior milestones (M0, M1-A) and stable features:

| Resource | Boundary Policy | Rationale |
|---|---|---|
| `lib/features/recognition/amount_parser.dart` | **READ/WRITE** (Modifications 1.1, 1.2 only) | Fix consecutive repairs & multi-decimals |
| `lib/features/recognition/order_id_parser.dart` | **READ/WRITE** (Modifications 2.1, 2.2 only) | Fix ellipsis & fullwidth asterisk capture |
| `lib/features/classification/rule_engine.dart` | **READ/WRITE** (Modification 3.1 only) | Fix SQLite ID collision |
| `test/recognition/ocr_adversarial_test.dart` | **READ/WRITE** (Modification 4.1 only) | Remove unused import |
| `test/recognition/recognition_adversarial_test.dart` | **READ/WRITE** (Modification 5.1 only) | Remove unused imports |
| `lib/features/classification/rule_matcher.dart` | **READ ONLY — FORBIDDEN TO MODIFY** | Line 62 & Line 112 are protected invariants required by `rule_engine_adversarial_test.dart` |
| `lib/data/database/schema.sql` | **READ ONLY — FORBIDDEN TO MODIFY** | DDL schema is certified by M1-A and docs integrity suite |
| `lib/core/native/*` | **READ ONLY — FORBIDDEN TO MODIFY** | Pigeon bridge contracts are frozen from M0 |
| `test/core/`, `test/database/`, `test/deduplication/` | **READ ONLY — FORBIDDEN TO MODIFY** | Baseline test suites must remain untouched |
| `test/classification/rule_engine_adversarial_test.dart` | **READ ONLY — FORBIDDEN TO MODIFY** | 31 adversarial tests must pass against modified implementation |

---

## 5. Comprehensive Regression-Free Verification Plan

The worker must execute the following 6-tier verification pipeline in sequence. Every step must return **Exit code 0**.

### Gate 1: Static Code Analysis (0 Issues Gate)
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
flutter analyze
```
- **Criterion**: `No issues found!`
- **Expected Exit Code**: `0` (replaces previous `1 issue found` / `3 issues found`).

### Gate 2: M0 & M1-A Regression Verification (145 Baseline Tests)
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
flutter test test/core/native/ test/core/utils/currency_utils_test.dart test/database/ test/deduplication/deduplication_test.dart
```
- **Criterion**: All 145 baseline unit and relational integration tests pass cleanly.
- **Expected Exit Code**: `0`.

### Gate 3: M1-B Targeted Unit Test Suite (66 Feature Tests)
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
flutter test test/core/utils/date_utils_test.dart test/recognition/noise_filter_test.dart test/recognition/amount_parser_test.dart test/recognition/merchant_normalizer_test.dart test/recognition/order_id_parser_test.dart test/recognition/channel_status_parser_test.dart test/recognition/ocr_pipeline_test.dart test/classification/rule_matcher_test.dart test/classification/rule_engine_test.dart
```
- **Criterion**: `+66: All tests passed!`
- **Expected Exit Code**: `0`.

### Gate 4: Adversarial Test Suite Gate
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path

# 4A. OCR Adversarial Test Suite (33 tests)
flutter test test/recognition/ocr_adversarial_test.dart

# 4B. Recognition Adversarial Test Suite (21 tests)
flutter test test/recognition/recognition_adversarial_test.dart

# 4C. Classification Rule Engine Adversarial Test Suite (31 tests)
flutter test test/classification/rule_engine_adversarial_test.dart

# 4D. Deduplication Adversarial Test Suite (15 tests)
flutter test test/deduplication/deduplication_adversarial_test.dart
```
- **Criteria**:
  - `ocr_adversarial_test.dart`: `+33: All tests passed!` (Previously 30 passed, 3 failed).
  - `recognition_adversarial_test.dart`: `+21: All tests passed!` (Previously 19 passed, 2 failed).
  - `rule_engine_adversarial_test.dart`: `+31: All tests passed!`
  - `deduplication_adversarial_test.dart`: `+15: All tests passed!`
- **Expected Exit Code**: `0` for all 4 commands.

### Gate 5: Full Project Regression Test Suite (297 Total Tests)
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
flutter test
```
- **Criterion**: `+297: All tests passed!` (Zero failures across all 18 test files).
- **Expected Exit Code**: `0`.

### Gate 6: Cross-Platform Documentation & SQLite Relational Integrity Gate
```powershell
python test_docs_integrity.py
```
- **Criterion**: `>>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<`
- **Expected Exit Code**: `0`.

---

## 6. Implementation Checklist for Worker Agent

- [ ] **Step 1**: Open `lib/features/recognition/amount_parser.dart` and implement Modification 1.1 (iterative convergence loop) and Modification 1.2 (multiple decimal points rejection).
- [ ] **Step 2**: Open `lib/features/recognition/order_id_parser.dart` and implement Modification 2.1 (`…` and `＊` in regexes) and Modification 2.2 (`＊` in `hasMaskChars`).
- [ ] **Step 3**: Open `lib/features/classification/rule_engine.dart` and implement Modification 3.1 (`microsecondsSinceEpoch` + monotonic `_ruleCounter++`).
- [ ] **Step 4**: Open `test/recognition/ocr_adversarial_test.dart` and remove unused import `sqflite_ffi.dart`.
- [ ] **Step 5**: Open `test/recognition/recognition_adversarial_test.dart` and remove unused imports `channel_status_parser.dart` and `field_evidence.dart`.
- [ ] **Step 6**: Execute Gate 1 (`flutter analyze`) and confirm 0 issues.
- [ ] **Step 7**: Execute Gate 4A & 4B (`ocr_adversarial_test.dart` and `recognition_adversarial_test.dart`) and confirm 100% pass.
- [ ] **Step 8**: Execute Gate 4C (`rule_engine_adversarial_test.dart`) and confirm all 31 tests remain green.
- [ ] **Step 9**: Execute Gate 5 (`flutter test`) and confirm all 297 tests pass.
- [ ] **Step 10**: Execute Gate 6 (`python test_docs_integrity.py`) and confirm 100% pass.
- [ ] **Step 11**: Write handoff report with execution evidence and notify orchestrator.
