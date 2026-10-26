# Technical Exploration Report: Flutter & Dart SDK Environment and Toolchain (M0)

- **Agent**: `explorer_m0_1`
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_1`
- **Recipient**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Date**: 2026-10-22
- **Milestone**: M0 (Flutter Project Scaffold & Native Pigeon Bridge)

---

## 1. Executive Summary

This report delivers a comprehensive technical investigation of the Windows environment, Flutter/Dart SDK installation status, network performance, and execution strategies required for Milestone M0.

### Key Discoveries
1. **Flutter / Dart SDK Status**: Neither Flutter nor Dart SDK is currently installed on this Windows machine. Exhaustive probes across PATH, standard paths (`C:\flutter`, `C:\src\flutter`, `C:\tools\flutter`), user home directories, AppData, and Program Files confirmed absence of any existing Flutter/Dart development toolchain.
2. **System Toolchain Convention**: Development runtimes on this machine are uniformly organized under `C:\Other\Dev\` (e.g., `apache-maven-3.9.11`, `jdk-21`, `node-v24.21.0-win-x64`, `pnpm`), with over 802 GB of free disk space on drive `C:\`.
3. **Network & Mirror Benchmarks**:
   - Direct connection to `storage.googleapis.com` is throttled (~300 KB/s), requiring ~1.8 hours for a 1.9 GB download.
   - The official Flutter China mirror (`https://storage.flutter-io.cn`) was verified active and achieved a sustained throughput of **26.14 MB/s**, enabling the complete 1.93 GB Flutter SDK Windows stable release (`3.47.7`) to download in ~70 seconds.
4. **Extraction & Execution Tools**: Native Windows utility `tar.exe` (bsdtar 3.8.8) is available in `C:\WINDOWS\system32\tar.exe` to decompress the zip archive directly without third-party extraction tools.
5. **Concrete Execution Paths**: Flutter and Dart executables should be installed into `C:\Other\Dev\flutter\bin`, providing `flutter.bat` and `dart.bat` for seamless execution of `flutter pub get`, `dart run pigeon --input pigeons/native_bridge.dart`, and `flutter analyze`.

---

## 2. Environment Probe Findings

### 2.1 PATH and Executable Verification
- Executed `where.exe flutter` and `where.exe dart`: Both returned exit code 1 ("Could not find files for the given pattern").
- Current User PATH in Windows Registry:
  - `C:\Other\Dev\node-v24.21.0-win-x64`
  - `C:\Other\Dev\pnpm`
  - `C:\Other\Dev\apache-maven-3.9.11\bin`
  - `C:\Users\hsanl\AppData\Local\Programs\Python\Python313\Scripts\`
  - `C:\Users\hsanl\AppData\Local\Programs\Python\Python313\`
  - `C:\Users\hsanl\AppData\Local\Programs\Python\Launcher\`
  - `C:\Users\hsanl\AppData\Local\Programs\OpenAI\Codex\bin`
  - `C:\Users\hsanl\AppData\Local\Microsoft\WindowsApps`
  - `C:\Users\hsanl\.local\bin`
  - `C:\Users\hsanl\AppData\Local\Programs\glab`
  - `C:\Other\IDE\Microsoft\Microsoft VS Code\bin`
  - `C:\Other\Dev\jdk-21\bin`
- Current System PATH in Windows Registry:
  - `C:\WINDOWS\system32`
  - `C:\WINDOWS`
  - `C:\WINDOWS\System32\Wbem`
  - `C:\WINDOWS\System32\WindowsPowerShell\v1.0\`
  - `C:\WINDOWS\System32\OpenSSH\`
  - `C:\Program Files\Git\cmd`

### 2.2 Filesystem Inspection Across Common Paths
Checked target paths:
- `C:\flutter` — MISSING
- `C:\src\flutter` — MISSING
- `C:\tools\flutter` — MISSING
- `C:\Users\hsanl\flutter` — MISSING
- `C:\Users\hsanl\AppData\Local\flutter` — MISSING
- `C:\Other\flutter` — MISSING
- `C:\Other\Dev\flutter` — MISSING
- `C:\Program Files` & `C:\Program Files (x86)` — No Flutter or Dart SDK installed (only embedded runtime UI assets inside DingTalk desktop app).

### 2.3 Package Manager Availability (winget)
- `winget --version`: `v1.29.380` (Operational).
- `winget search Google.DartSDK`: Found package `Google.DartSDK` version `3.13.4` (portable zip distribution, 219 MB).
- `winget search Flutter`: Returned zero official Flutter SDK packages (Flutter is not hosted as an official winget package in Microsoft Community Repo).

### 2.4 Network Connectivity & Throughput Benchmarks
- Tested `https://pub.dev` and `https://github.com`: Fully reachable (HTTP 200).
- Direct Google Cloud Storage (`storage.googleapis.com`): Verified reachable but limited to ~280–320 KB/s.
- Official Flutter China Mirror (`https://storage.flutter-io.cn` and `https://pub.flutter-io.cn`):
  - HTTP 200 verified with Byte-nginx / Aliyun CDN edge nodes.
  - Measured 10 MB chunk download: Completed in 0.38 seconds at **26.14 MB/s** (27,410,386 bytes/s).
  - Target Windows Stable Flutter release:
    - Version: `3.47.7`
    - Dart SDK Version: `3.13.5`
    - Archive URL: `https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip`
    - Package Size: 1,934,624,561 bytes (~1.80 GiB)
    - SHA256: `c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4`

---

## 3. Concrete Fix Strategy & Installation Procedure

To fulfill all Acceptance Criteria of M0 (both `dart run pigeon` and `flutter analyze`), a complete Flutter SDK installation is required.

### 3.1 Recommended Primary Strategy: Full Flutter SDK in `C:\Other\Dev\flutter`

This strategy strictly complies with the machine's established environment convention (`C:\Other\Dev\`).

#### Step 1: Download Archive via China Mirror
Download the pre-packaged Windows stable zip archive using `curl.exe`:
```powershell
$tempZip = "$env:TEMP\flutter_windows_3.47.7-stable.zip"
curl.exe -fL -o $tempZip "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip"
```

#### Step 2: Extract Directly to `C:\Other\Dev`
The archive contains a root folder named `flutter`. Extracting into `C:\Other\Dev` will create `C:\Other\Dev\flutter`:
```powershell
tar.exe -xf $tempZip -C "C:\Other\Dev"
Remove-Item $tempZip -Force
```

#### Step 3: Configure User Environment Variables & PATH
Persist the configuration in the Windows User Registry and update the running session environment:
```powershell
# Persist environment variables in User Registry
[Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", "https://pub.flutter-io.cn", "User")
[Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "https://storage.flutter-io.cn", "User")

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*C:\Other\Dev\flutter\bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;C:\Other\Dev\flutter\bin", "User")
}

# Update current session environment
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
```

#### Step 4: Warm Up Flutter Cache
Initialize the SDK cache and disable telemetric analytics:
```powershell
& "C:\Other\Dev\flutter\bin\flutter.bat" config --no-analytics
& "C:\Other\Dev\flutter\bin\flutter.bat" precache
```

### 3.2 Alternative Fallback Strategy: Standalone Dart SDK via winget
If downloading Flutter SDK is deferred or blocked:
1. Install standalone Dart SDK via winget:
   ```powershell
   winget install Google.DartSDK --silent --accept-source-agreements --accept-package-agreements
   ```
2. **Capabilities & Limitations**:
   - Capable of: `dart pub get` (pure Dart packages), `dart run pigeon --input pigeons/native_bridge.dart`, `dart analyze`.
   - Incapable of: Resolving Flutter framework dependencies (e.g. `sdk: flutter` in `pubspec.yaml`), running `flutter analyze`, or building native assets.
   - **Conclusion**: Fallback strategy does NOT satisfy the acceptance criterion "flutter analyze 无致命错误". Primary Strategy 3.1 is mandatory.

---

## 4. Exact Paths & Commands for Worker M0

When the worker agent starts Milestone M0 tasks, use the following exact paths and command patterns.

### 4.1 Canonical Executable Paths
- **Flutter CLI**: `C:\Other\Dev\flutter\bin\flutter.bat`
- **Dart CLI**: `C:\Other\Dev\flutter\bin\dart.bat`
- **Underlying Dart Executable**: `C:\Other\Dev\flutter\bin\cache\dart-sdk\bin\dart.exe`

### 4.2 In-Session Environment Setup
At the beginning of each PowerShell execution script, ensure the environment variables are active:
```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path
```

### 4.3 Task Commands for Worker M0

#### 1. Flutter Dependency Resolution (`flutter pub get`)
Working directory: `c:\Other\Projects\singwallet`
```powershell
& "C:\Other\Dev\flutter\bin\flutter.bat" pub get
```

#### 2. Pigeon Bridge Code Generation
Working directory: `c:\Other\Projects\singwallet`
> Note: As identified by peer explorer `explorer_m0_2`, `pigeons/native_bridge.dart` requires `import 'dart:typed_data';` at line 2 before code generation, and the output directories (`lib/core/native/`, `test/core/native/`, `android/app/src/main/kotlin/com/singwallet/app/bridge/`, `ios/Runner/Plugins/`) must exist.

Command:
```powershell
& "C:\Other\Dev\flutter\bin\dart.bat" run pigeon --input pigeons/native_bridge.dart
```

#### 3. Static Code Analysis (`flutter analyze`)
Working directory: `c:\Other\Projects\singwallet`
```powershell
& "C:\Other\Dev\flutter\bin\flutter.bat" analyze
```

---

## 5. Risk Assessment & Operational Guidelines

1. **PowerShell Script Execution Policy**:
   The machine has a restrictive execution policy for user profiles (`Microsoft.PowerShell_profile.ps1`). `flutter.bat` and `dart.bat` are Windows command script files invoked via `cmd.exe`, which bypass PowerShell script execution restrictions. For PowerShell inline commands, always execute with `-NoProfile` or invoke the `.bat` wrapper directly with `& "..."`.
2. **Preservation of Existing Project Files**:
   Do NOT execute `flutter create .` directly over the repository root without preserving `README.md` and `test_docs_integrity.py`. `flutter create` will overwrite existing files. Scaffold creation should either be done by writing `pubspec.yaml`, `analysis_options.yaml`, and directory skeletons manually, or by backing up existing files prior to generation.
3. **Repository Link Integrity Compatibility**:
   `test_docs_integrity.py` validates all markdown files in the repository. Avoid bracket-parenthesis combinations such as `[Type]` followed directly by `(arg)` in markdown text, as they are matched by the regex link validator and will fail if the target does not exist as a file.
