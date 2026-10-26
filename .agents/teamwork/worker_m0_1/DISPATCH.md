## 2026-10-22T09:27:04Z
You are worker_m0_1.
Your working directory is: c:\Other\Projects\singwallet\.agents\teamwork\worker_m0_1
Your parent is orchestrator_1 (conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

MANDATORY INPUTS (Read these before starting):
- c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_1\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_1\report.md (Toolchain & SDK paths)
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_2\report.md (Scaffold & Pigeon config)
- c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_3\report.md (Native bridge adapters)

Scope & File Ownership:
You own exclusively:
- `pubspec.yaml`
- `analysis_options.yaml`
- `pigeons/native_bridge.dart`
- `lib/` (including `lib/main.dart`, `lib/core/native/native_bridge_service.dart`, etc.)
- `android/` (including `android/app/src/main/kotlin/com/singwallet/app/MainActivity.kt`, `NativeCaptureHostApiImpl.kt`)
- `ios/` (including `ios/Runner/AppDelegate.swift`, `Plugins/NativeCaptureHostApiImpl.swift`)
- `test/core/native/` (including `test/core/native/native_bridge_test.dart`)

Tasks:
1. Environment Toolchain Setup:
   - Check if `C:\Other\Dev\flutter\bin\flutter.bat` exists.
   - If missing, download Flutter 3.47.7 Windows stable zip from `https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip` and extract to `C:\Other\Dev` using `tar.exe`.
   - Set environment variables in your command sessions:
     `$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"`
     `$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"`
     `$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path`
   - Verify `flutter --version` and `dart --version`.
2. Scaffold Setup:
   - Ensure `import 'dart:typed_data';` is added at top of `pigeons/native_bridge.dart` for `Uint8List getOrCreateDatabaseKey()`.
   - Create `pubspec.yaml` with exact configuration specified in `explorer_m0_2/report.md` (pigeon: ^22.7.0, flutter_riverpod, sqflite, sqflite_common_ffi, crypto, intl, path, path_provider, test).
   - Create `analysis_options.yaml` with flutter_lints and exclude `**/*.g.dart`.
   - Run `flutter pub get`.
3. Pigeon Code Generation:
   - Run `dart run pigeon --input pigeons/native_bridge.dart` (or via flutter).
   - Verify all 4 generated files exist:
     - `lib/core/native/native_bridge.g.dart`
     - `test/core/native/native_bridge_test.g.dart`
     - `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeBridge.g.kt`
     - `ios/Runner/Plugins/NativeBridge.g.swift`
4. Native Adapters & App Setup:
   - Implement Android host adapter `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt` and register in `MainActivity.kt`.
   - Implement iOS host adapter `ios/Runner/Plugins/NativeCaptureHostApiImpl.swift` and register in `AppDelegate.swift`.
   - Implement `lib/main.dart` and `lib/core/native/native_bridge_service.dart`.
   - Implement unit test `test/core/native/native_bridge_test.dart` using mock host API from `native_bridge_test.g.dart` to verify serialization and Host/Flutter API channels.
5. Verification:
   - Run `flutter analyze` — ensure zero fatal errors.
   - Run `flutter test test/core/native/native_bridge_test.dart` — ensure exit code 0.
   - Run `python test_docs_integrity.py` — ensure exit code 0.
   - Record all command outputs and results in your `handoff.md` and `report.md`.

Send completion message to orchestrator_1 (0be8f589-cb64-4c3b-aed0-2d1a129de39c) when finished.
