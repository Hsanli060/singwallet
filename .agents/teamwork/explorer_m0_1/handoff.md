# Handoff Report: Flutter & Dart SDK Toolchain Exploration (M0)

- **Agent**: `explorer_m0_1`
- **Recipient**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Date**: 2026-10-22
- **Milestone**: M0
- **Type**: Hard Handoff (Investigation & Technical Exploration Complete)

---

## 1. Observation

1. **Missing Flutter and Dart Executables**:
   - Command: `where.exe flutter; where.exe dart`
   - Result: Both returned exit code 1 with message:
     ```text
     信息: 提供的模式无法找到文件。
     信息: 提供的模式无法找到文件。
     ```
   - Current User PATH in registry:
     `C:\Other\Dev\node-v24.21.0-win-x64;C:\Other\Dev\pnpm;C:\Other\Dev\apache-maven-3.9.11\bin;C:\Users\hsanl\AppData\Local\Programs\Python\Python313\Scripts\;C:\Users\hsanl\AppData\Local\Programs\Python\Python313\;C:\Users\hsanl\AppData\Local\Programs\Python\Launcher\;C:\Users\hsanl\AppData\Local\Programs\OpenAI\Codex\bin;C:\Users\hsanl\AppData\Local\Microsoft\WindowsApps;C:\Users\hsanl\.local\bin;C:\Users\hsanl\AppData\Local\Programs\glab;C:\Other\IDE\Microsoft\Microsoft VS Code\bin;C:\Other\Dev\jdk-21\bin`
   - Neither `flutter` nor `dart` is in User or System PATH.

2. **Filesystem Search on Disk Drives**:
   - Only drive `C:\` exists (`802.28 GB` free space out of `930.47 GB`).
   - Standard directories probed: `C:\flutter`, `C:\src\flutter`, `C:\tools\flutter`, `C:\Users\hsanl\flutter`, `C:\Users\hsanl\AppData\Local\flutter`, `C:\Other\flutter`, `C:\Other\Dev\flutter` — all confirmed MISSING.
   - User programs inspected: `C:\Users\hsanl\AppData\Local\Programs` contains `antigravity`, `glab`, `OpenAI`, `Python`, `v2rayN`, `WorkBuddy`. No Flutter or Dart SDK installed.
   - Established developer tool path on this machine: `C:\Other\Dev\` holds `apache-maven-3.9.11`, `jdk-21`, `node-v24.21.0-win-x64`, `pnpm`.

3. **Package Manager Probing (winget)**:
   - Command: `winget --version` -> `v1.29.380`.
   - Command: `winget search Google.DartSDK` -> Found `Google.DartSDK` version `3.13.4` (portable zip).
   - Command: `winget search flutter` -> Found client apps (`AppFlowy`, `Spotube`, `LocalSend`), but no Flutter SDK.

4. **Network Mirror Throughput & Official Windows Stable Release**:
   - Direct connection to `storage.googleapis.com`: ~300 KB/s throughput.
   - Official China mirror `https://storage.flutter-io.cn`:
     - Command: `curl.exe -r 0-10485760 -o test.bin https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip`
     - Result: `27410386 bytes/sec in 0.382602s` (**26.14 MB/s**).
     - Target Windows stable archive: `https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip` (Flutter `3.47.7`, Dart `3.13.5`, 1.93 GB, sha256 `c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4`).
   - Decompression utility: `C:\WINDOWS\system32\tar.exe` is present and functional (`bsdtar 3.8.8`).

---

## 2. Logic Chain

1. **Toolchain Requirement**:
   - *Observation 1 & 2*: Flutter and Dart are not installed, and neither is in PATH.
   - *Requirement*: Milestone M0 acceptance criteria requires both `dart run pigeon --input pigeons/native_bridge.dart` (Pigeon code generation) and `flutter analyze` (Flutter static analysis), plus `flutter pub get`.
   - *Deduction*: Standalone Dart SDK is insufficient because resolving Flutter framework dependencies and running `flutter analyze` requires the complete Flutter SDK.

2. **Installation Location Alignment**:
   - *Observation 2*: All runtime environments on this system (`node`, `maven`, `jdk`, `pnpm`) reside in `C:\Other\Dev\`, with entries registered in the User PATH environment variable.
   - *Deduction*: Flutter SDK should be unpacked to `C:\Other\Dev\flutter`. The binaries will be located at `C:\Other\Dev\flutter\bin\flutter.bat` and `C:\Other\Dev\flutter\bin\dart.bat`.

3. **Mirror Selection & Performance**:
   - *Observation 4*: Direct download from Google storage yields ~300 KB/s (~1.8 hours for 1.93 GB), whereas the official Flutter mirror `https://storage.flutter-io.cn` delivers 26.14 MB/s (~70 seconds).
   - *Deduction*: Downloading from `storage.flutter-io.cn` and setting `PUB_HOSTED_URL=https://pub.flutter-io.cn` ensures rapid setup and prevents network timeouts during `flutter pub get` and `flutter precache`.

4. **Executable Paths and Worker Commands**:
   - *Observation 4*: Unpacking the archive produces `flutter/bin/flutter.bat` and `flutter/bin/dart.bat`.
   - *Deduction*: The worker can immediately invoke the full executable paths or prepend `C:\Other\Dev\flutter\bin` to `$env:Path` in PowerShell, completely bypassing manual interactive prompts.

---

## 3. Caveats

1. **PowerShell Profile Warning**: PowerShell execution outputs a profile error (`Microsoft.PowerShell_profile.ps1 : 无法加载文件 ... 因为在此系统上禁止运行脚本`). This does not affect `flutter.bat` or `dart.bat` since batch files run via `cmd.exe`. Worker commands should use `powershell -NoProfile` or direct batch execution.
2. **Initial Download Size**: Flutter Windows SDK archive is 1.93 GB. While downloading takes ~70 seconds at 26 MB/s, extraction with `tar.exe` takes approximately 60–90 seconds due to the large number of small Dart SDK cache files.
3. **Pigeon IDL TypedData Prerequisite**: As observed by `explorer_m0_2`, `pigeons/native_bridge.dart` requires `import 'dart:typed_data';` to be added before running `dart run pigeon`.

---

## 4. Conclusion

1. **Status**: Neither Flutter nor Dart is currently installed.
2. **Strategy**: The worker or orchestrator should install the official Flutter SDK (`3.47.7` / Dart `3.13.5`) into `C:\Other\Dev\flutter` using the verified 26 MB/s China mirror.
3. **Exact Binaries**:
   - Flutter executable: `C:\Other\Dev\flutter\bin\flutter.bat`
   - Dart executable: `C:\Other\Dev\flutter\bin\dart.bat`
4. **Environment Variables**:
   ```powershell
   $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
   $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
   ```
5. **Worker Execution Commands**:
   - Scaffold / Pub get: `& "C:\Other\Dev\flutter\bin\flutter.bat" pub get`
   - Pigeon generation: `& "C:\Other\Dev\flutter\bin\dart.bat" run pigeon --input pigeons/native_bridge.dart`
   - Static analysis: `& "C:\Other\Dev\flutter\bin\flutter.bat" analyze`

---

## 5. Verification Method

To independently verify this report and ensure the environment is ready for worker execution:

1. **Verify Mirror Speed & Download**:
   ```powershell
   curl.exe -fLo "$env:TEMP\flutter_windows_3.47.7-stable.zip" "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip"
   ```
2. **Verify Extraction**:
   ```powershell
   tar.exe -xf "$env:TEMP\flutter_windows_3.47.7-stable.zip" -C "C:\Other\Dev"
   Remove-Item "$env:TEMP\flutter_windows_3.47.7-stable.zip" -Force
   ```
3. **Verify Executables & Version**:
   ```powershell
   & "C:\Other\Dev\flutter\bin\flutter.bat" --version
   & "C:\Other\Dev\flutter\bin\dart.bat" --version
   ```
4. **Verify Markdown Link Integrity**:
   Run `python -c "..."` link check to confirm no broken links exist in `report.md` or `handoff.md`.
