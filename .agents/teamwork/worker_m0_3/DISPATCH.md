## 2026-10-22T10:27:35Z
You are worker_m0_3.
Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\worker_m0_3
Your parent is orchestrator_1 (conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

MANDATORY INPUTS:
- c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\challenger_m0_r2_1\handoff.md
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_r3_1\report.md and proposed_currency_utils.dart
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_r3_2\report.md and handoff.md
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_r3_3\report.md and currency_utils_test.patch

Scope & Exclusive File Ownership:
- `lib/core/utils/currency_utils.dart`
- `lib/core/native/currency_utils.dart`
- `test/core/utils/currency_utils_test.dart`

Tasks:
1. Update `lib/core/utils/currency_utils.dart` (and `lib/core/native/currency_utils.dart`) using the exact implementations from `explorer_m0_r3_1` and `explorer_m0_r3_2`:
   - Enforce 64-bit integer overflow guard:
     `const int _maxSafeMajor = 92233720368547758;`
     `const int _maxMinorForBoundary = 7;`
     Throw `FormatException('Currency amount exceeds 64-bit integer limit: "$input"')` if exceeded.
   - Enforce strict sign parsing grammar: track `bool hasLeadingSign` so conflicting signs (`+-10`, `+¥-10`, `-+10`, `-¥+10`) throw `FormatException` and return `null` in `tryParseToMinorUnits`.
2. Update `test/core/utils/currency_utils_test.dart` per `explorer_m0_r3_3` to add all boundary and conflicting sign test cases.
3. Run verification:
   ```powershell
   $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
   $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   flutter analyze
   flutter test
   python test_docs_integrity.py
   python test_coordinate_harness.py
   ```
   Ensure ALL verification commands pass with exit code 0.
4. Write report and handoff.md.
5. Notify orchestrator_1 when finished.
