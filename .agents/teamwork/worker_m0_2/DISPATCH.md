## 2026-10-22T10:02:53Z

You are worker_m0_2.
Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\worker_m0_2
Your parent is orchestrator_1 (conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

MANDATORY INPUTS (Read these before starting):
- c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\reviewer_m0_2\handoff.md (Failure reasons)
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_1\report.md and handoff.md (Android OCR & coordinate normalization implementation)
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\report.md and master_key_guard.patch (Android Keystore state guarding)
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_3\report.md and handoff.md (iOS AppDelegate & CurrencyUtils)

Scope & File Ownership:
You own exclusively:
- `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt`
- `ios/Runner/AppDelegate.swift`
- `lib/core/native/currency_utils.dart`
- `test/core/utils/currency_utils_test.dart`
- `test/` (any updated tests)

Tasks:
1. Apply the Android OCR coordinate normalization logic and realistic receipt parsing to `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt` per `explorer_m0_retry_1`. Implement `normalizeBoundingBox(rect: Rect, imageWidth: Int, imageHeight: Int): OcrBoundingBox` and realistic structured lines.
2. Apply the Keystore persistence state safety checks from `explorer_m0_retry_2` to `NativeCaptureHostApiImpl.kt` (`hasEncrypted != hasIv` corruption check, synchronous `.commit()`, alias verification).
3. Safely update `ios/Runner/AppDelegate.swift` per `explorer_m0_retry_3` to eliminate force unwrapping and safely bind `FlutterViewController`.
4. Update `lib/core/native/currency_utils.dart` to robustly handle edge cases (trailing period, leading period, currency symbols) and add `test/core/utils/currency_utils_test.dart`.
5. Run full verification suite:
   ```powershell
   $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
   $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   flutter analyze
   flutter test
   python test_docs_integrity.py
   ```
   Ensure ALL verification commands exit with code 0.
6. Write your report to `report.md` and `handoff.md`.
7. Send message to orchestrator_1 when completed.
