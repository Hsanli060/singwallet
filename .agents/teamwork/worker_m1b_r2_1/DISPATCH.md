## 2026-10-22T14:08:30Z
Read ORIGINAL_REQUEST.md at c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md first! Subagents MUST read it before starting work.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\worker_m1b_r2_1
Your parent conversation ID is: a14d1a00-adfd-46db-a470-136d68156a40
Scope document: c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_2\PROJECT.md

Task: Execute Milestone M1-B Forensic Remediation per the blueprint at:
c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1b_r2_3\report.md

You have STRICT WRITE OWNERSHIP restricted to exactly 5 files:
1. `lib/features/recognition/amount_parser.dart`
   - Modification 1.1: In `repairOcrNumbers`, replace single-pass replaceAllMapped with iterative convergence loop (`while (prev != s)`) to repair consecutive OCR confusion characters (`¥1OOO.OO` -> `¥1000.00`).
   - Modification 1.2: In `extractMinorUnits`, reject distorted amounts with multiple decimal points (e.g. `repaired.split('.').length > 2 -> return null;`) before token extraction so `12.34.56` is not silently sliced.
2. `lib/features/recognition/order_id_parser.dart`
   - Modification 2.1: Add Unicode ellipsis `…` (\u2026) and fullwidth asterisk `＊` (\uFF0A) to `_merchantOrderRegex` and `_platformNoRegex`.
   - Modification 2.2: Add `＊` to `hasMaskChars` check in `parse()`.
3. `lib/features/classification/rule_engine.dart`
   - Modification 3.1: In `learnRuleFromUserAction`, add `static int _ruleCounter = 0;` and use `microsecondsSinceEpoch` + `_ruleCounter++` to prevent SQLite 1555 PRIMARY KEY collisions on same-millisecond rule learning.
4. `test/recognition/ocr_adversarial_test.dart`
   - Remove unused import `import 'package:sqflite_common_ffi/sqflite_ffi.dart';` (or any other unused import).
5. `test/recognition/recognition_adversarial_test.dart`
   - Remove unused imports `channel_status_parser.dart` and `field_evidence.dart`.

CRITICAL INVARIANT WARNING:
DO NOT modify `lib/features/classification/rule_matcher.dart`! Line 62 and line 112 are required invariants tested by `test/classification/rule_engine_adversarial_test.dart`.
DO NOT modify any other files in `lib/data/` or `lib/core/native/`.

Verification requirements:
Environment: `$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path`
1. `flutter analyze` -> MUST BE 0 issues found!
2. `flutter test` -> MUST execute all unit, integration, and adversarial tests (all 297+ tests) with 100% pass and exit code 0!
3. `python test_docs_integrity.py` -> MUST pass 100%!

Write your complete handoff report to `c:\Other\Projects\singwallet\.agents\teamwork\worker_m1b_r2_1\handoff.md` and send message to parent a14d1a00-adfd-46db-a470-136d68156a40 when finished.
