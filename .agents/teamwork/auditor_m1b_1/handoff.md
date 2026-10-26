# Milestone M1-B Forensic Audit Report

**Auditor Agent**: `auditor_m1b_1`  
**Parent Orchestrator**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Milestone**: M1-B (Features F19–F30: OCR Pipeline & Classification Rule Engine)  
**Integrity Mode**: Development (from `ORIGINAL_REQUEST.md`)  
**Verdict**: **INTEGRITY VIOLATION** (REJECTED)

---

## Forensic Audit Summary

| Check # | Forensic Check Name | Status | Details |
|---|---|---|---|
| 1 | Static Analysis & Pattern Verification | **FAIL** | `flutter analyze` returned 1 issue (exit code 1). Unused import in `test/recognition/ocr_adversarial_test.dart:8:8`. No hardcoding in source code. |
| 2 | Logic Genuineness | **PASS** | Genuine implementations in date parsing, noise filtering, amount parsing, merchant normalization, order ID completeness, rule matching, and 6-tier classification. No dummy facades or empty mocks. |
| 3 | Database & Schema Compliance | **PASS** | Integer minor units (cents) strictly used for currency; foreign key relationships respected; zero amount flagged and prevented from draft commit. |
| 4 | Independent Execution | **FAIL** | `flutter analyze` failed (exit code 1); `flutter test` failed (exit code 1, 7 failing adversarial test cases); `python test_docs_integrity.py` passed (exit code 0). |

---

## 1. Observation

### 1.1 Source Code & Implementation Inspection
- `lib/core/utils/date_utils.dart` (227 lines): Authentic date/time parsing with second, minute, and day precision, timezone UTC conversion, and zero-hallucination policy (`occurredAt == null` for day precision). Zero hardcoded test values.
- `lib/features/recognition/models/` (`field_evidence.dart`, `validation_issue.dart`, `parsed_draft_result.dart`): Robust data models supporting SQLite candidate fields serialization and draft entity synthesis.
- `lib/features/recognition/` (`noise_filter.dart`, `amount_parser.dart`, `merchant_normalizer.dart`, `order_id_parser.dart`, `channel_status_parser.dart`, `ocr_pipeline.dart`): Genuine parsers using geometry heuristics, optical character substitution, platform ID pattern recognition, and status detection.
- `lib/features/classification/` (`models/classification_match_result.dart`, `rule_matcher.dart`, `rule_engine.dart`): Genuine 6-tier hierarchy cascade with ReDoS protection, wildcard compilation, historical transaction query, and dynamic rule learning.

### 1.2 Targeted Worker Test Suites
The 9 unit test suites authored by `worker_m1b_1` execute and pass cleanly:
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test test/core/utils/date_utils_test.dart test/recognition/noise_filter_test.dart test/recognition/amount_parser_test.dart test/recognition/merchant_normalizer_test.dart test/recognition/order_id_parser_test.dart test/recognition/channel_status_parser_test.dart test/recognition/ocr_pipeline_test.dart test/classification/rule_matcher_test.dart test/classification/rule_engine_test.dart
```
Output:
```text
00:01 +66: All tests passed!
Exit code: 0
```

### 1.3 Static Analysis Gate Failure
Executing static analysis across the repository fails:
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter analyze
```
Verbatim Tool Output:
```text
Analyzing singwallet...                                         

warning - Unused import: 'package:singwallet/features/recognition/ocr_pipeline.dart'. Try removing the import directive - test\recognition\ocr_adversarial_test.dart:8:8 - unused_import

1 issue found. (ran in 6.8s)
Exit code: 1
```

### 1.4 Full Automated Test Suite Gate Failure
Executing the full project test suite (`flutter test`) fails with exit code 1. 7 test cases failed across two test suites:
```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test
```

#### Failure Group A: `test/recognition/ocr_adversarial_test.dart` (3 failures)
1. **Consecutive OCR confused characters repair incomplete**:
   - Location: `test/recognition/ocr_adversarial_test.dart:126`
   - Test: `Vector 1.9: Consecutive OCR confused characters (¥1OOO.OO) must be repaired to ¥1000.00`
   - Error:
     ```text
     Expected: '¥1000.00'
       Actual: '¥10O0.0O'
     ```
   - Root Cause: In `lib/features/recognition/amount_parser.dart`, the single-pass regex `s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), ...)` only repairs alternating characters. When multiple `O`s occur consecutively, subsequent `O`s are skipped because the preceding character was consumed in the first match.
2. **Multiple decimals in amount silently truncated**:
   - Location: `test/recognition/ocr_adversarial_test.dart:200`
   - Test: `Vector 2.5b: Distorted amount with multiple decimals (12.34.56) should not be silently truncated`
   - Error:
     ```text
     Expected: null
       Actual: <1234>
     ```
   - Root Cause: In `lib/features/recognition/amount_parser.dart`, `extractMinorUnits` runs `RegExp(r'[-+]?[\d,]+(?:\.\d+)?')`, matching the leading `12.34` and discarding `.56`, thus returning 1234 cents rather than flagging a malformed amount.
3. **Masked order ID with Unicode ellipsis incorrectly classified as complete**:
   - Location: `test/recognition/ocr_adversarial_test.dart:554`
   - Test: `Vector 5.1b: Masked order ID with ellipsis … and 16+ prefix digits must NOT be marked COMPLETE`
   - Error:
     ```text
     Expected: false
       Actual: <true>
     ```
   - Root Cause: In `lib/features/recognition/order_id_parser.dart`, `_platformNoRegex` uses `[0-9a-zA-Z*xX_.-]+` which does not include the Unicode ellipsis character `…` (\u2026). The regex parser truncates the token before `…`, resulting in a 16-character clean prefix that gets graded as `IdentifierCompleteness.complete`.

#### Failure Group B: `test/classification/rule_engine_adversarial_test.dart` (4 failures)
4. **Wildcard `%` matching empty string**:
   - Location: `test/classification/rule_engine_adversarial_test.dart:79`
   - Test: `Vector 1.1: Collapsing of excessive consecutive % wildcards (%%%%%)`
   - Error:
     ```text
     Expected: true
       Actual: <false>
     ```
   - Root Cause: In `lib/features/classification/rule_matcher.dart:62`:
     ```dart
     final candidateTarget = target.trim();
     if (candidateTarget.isEmpty && pattern.trim().isNotEmpty) return false;
     ```
     This early return unconditionally rejects empty target strings, even when the pattern consists entirely of `%` wildcards (which matches empty strings in SQL semantics).
5. **ReDoS lockup on nested quantifiers**:
   - Location: `test/classification/rule_engine_adversarial_test.dart:147`
   - Test: `Vector 1.5: Complex backtracking regexes with regex: prefix fail safely without ReDoS lockup`
   - Error:
     ```text
     TimeoutException after 0:00:30.000000: Test timed out after 30 seconds.
     Expected: a value less than <2000>
       Actual: <42759>
     ```
   - Root Cause: `RuleMatcher.patternToRegExp` allows arbitrary expressions with the `regex:` prefix without enforcing a maximum repetition depth or pattern safety checks, causing Dart's RegExp engine to backtrack catastrophically on `regex:^(a+)+$`.
6. **Rule learning match vs history precedence on non-canonicalized merchant**:
   - Location: `test/classification/rule_engine_adversarial_test.dart:544`
   - Test: `Vector 4.2: Historical transactions are strictly immutable and never altered by rule learning`
   - Error:
     ```text
     Expected: ClassificationTier:<ClassificationTier.customRule>
       Actual: ClassificationTier:<ClassificationTier.history>
     ```
7. **Primary key ID collision under rapid rule learning**:
   - Location: `test/classification/rule_engine_adversarial_test.dart:586`
   - Test: `Vector 4.4: Channel-specific vs global rule learning separation`
   - Error:
     ```text
     SqfliteFfiException(sqlite_error: 1555): UNIQUE constraint failed: classification_rules.id
     Causing statement: INSERT INTO classification_rules (id, ...) VALUES ('rule_1792677121978_32449559', ...)
     ```
   - Root Cause: In `lib/features/classification/rule_engine.dart:417`:
     ```dart
     final ruleId = 'rule_${DateTime.now().millisecondsSinceEpoch}_${pattern.hashCode.abs()}';
     ```
     When multiple rules for different channels are learned in the same millisecond for the same pattern, `ruleId` is identical, violating the primary key constraint on `classification_rules.id`.

### 1.5 Documentation & SQLite DDL Verification
```powershell
python test_docs_integrity.py
```
Output:
```text
>>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<
Exit code: 0
```

---

## 2. Logic Chain

1. Step 1: The worker `worker_m1b_1` provided genuine, non-facade implementations of the assigned 12 features across `lib/features/recognition/` and `lib/features/classification/`. No hardcoded strings or dummy mock implementations were detected.
2. Step 2: Under development integrity mode, code reuse and real logic are verified. All 66 tests across the worker's 9 targeted test suites passed.
3. Step 3: Per the Integrity Forensics protocol, the auditor must independently execute the quality gates:
   - `flutter analyze`
   - `flutter test`
   - `python test_docs_integrity.py`
4. Step 4: `flutter analyze` returned exit code 1 due to an unused import in `test/recognition/ocr_adversarial_test.dart`.
5. Step 5: `flutter test` returned exit code 1 due to 7 failing tests in adversarial test suites, exposing real edge cases (ReDoS hang, ID collision under concurrent learning, incomplete consecutive character repair, and tokenization boundary issues).
6. Step 6: The Integrity Forensics mandate states: "If ANY check fails, your verdict is INTEGRITY VIOLATION and you MUST reject the work product." Both the build/test execution check and static analysis check failed.
7. Step 7: Therefore, the official verdict is **INTEGRITY VIOLATION**.

---

## 3. Caveats

- The core functional implementations (F19–F30) in `lib/` are authentic and performant under all standard use cases.
- The failures occur under adversarial stress conditions (pathological ReDoS inputs, sub-millisecond rapid rule generation, and malformed OCR inputs) and 1 static analysis lint in an adversarial test file.
- The auditor does not fix code directly, as auditors are strictly restricted to observation and verification.

---

## 4. Conclusion

**Verdict: INTEGRITY VIOLATION**  
The work product for Milestone M1-B cannot be certified clean because:
1. `flutter analyze` fails with exit code 1.
2. `flutter test` fails with exit code 1 (7 adversarial test failures).

### Required Remediation for Worker
1. In `test/recognition/ocr_adversarial_test.dart:8:8`, remove unused import `import 'package:singwallet/features/recognition/ocr_pipeline.dart';`.
2. In `lib/features/classification/rule_engine.dart:417`, add a nanosecond/microsecond counter or random UUID component to `ruleId` generation to prevent primary key collisions:
   ```dart
   final ruleId = 'rule_${DateTime.now().microsecondsSinceEpoch}_${pattern.hashCode.abs()}_${_ruleCounter++}';
   ```
3. In `lib/features/classification/rule_matcher.dart:62`, allow pure `%` patterns to match empty target strings:
   ```dart
   if (candidateTarget.isEmpty) {
     return pattern.trim().split('').every((c) => c == '%');
   }
   ```
4. In `lib/features/recognition/amount_parser.dart`:
   - Replace single-pass character repair with a loop or global character replacement so consecutive OCR characters like `OOO` are completely repaired.
   - Reject tokens containing multiple decimal points (e.g. `12.34.56`).
5. In `lib/features/recognition/order_id_parser.dart`:
   - Include Unicode ellipsis `…` in the pattern `_platformNoRegex` so masked tokens are not prematurely truncated before the mask marker.

---

## 5. Verification Method

To verify the reported findings independently:

1. **Static Analysis Failure**:
   ```powershell
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter analyze
   ```
   *Result*: Exits with code 1.

2. **Adversarial Test Suite Failures**:
   ```powershell
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test test/recognition/ocr_adversarial_test.dart
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test test/classification/rule_engine_adversarial_test.dart
   ```
   *Result*: Exits with code 1.
