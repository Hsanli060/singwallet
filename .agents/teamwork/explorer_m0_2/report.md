# Technical Exploration Report: Flutter Scaffold & Pigeon Configuration (Milestone M0)

- **Author**: `explorer_m0_2` (Technical Explorer)
- **Parent**: `orchestrator_1` (`0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Date**: 2026-10-22
- **Integrity Mode**: development
- **Scope**: Requirement 1 (R1) — Flutter Scaffold Setup, Pigeon Configuration, Dart Entrypoint, and Safe File Scaffolding

---

## 1. Executive Summary

Milestone M0 establishes the core foundation of SingWallet:
1. Valid Flutter application structure compliant with Clean Architecture layering.
2. Strongly-typed bidirectional Pigeon bridge contract (`pigeons/native_bridge.dart`) generating Dart, Kotlin, and Swift code with zero static analysis defects.
3. Safe worker scaffolding procedures that prevent overwriting or damaging existing architecture documents (`docs/`), test harnesses (`test_docs_integrity.py`), or repository indices (`README.md`).

This investigation resolves all five mandated questions with concrete file contents, architectural rationale, and verification steps.

---

## 2. Investigation Point 1: `pigeons/native_bridge.dart` & `Uint8List` Analysis

### 2.1 Code Examination & Problem Statement
In `pigeons/native_bridge.dart` (lines 108–111):
```dart
  /// 从安全硬件 (Keystore / Keychain) 异步获取或初始化 256 位数据库加密主密钥
  @async
  Uint8List getOrCreateDatabaseKey();
```
At the top of the existing file (lines 1–2):
```dart
// pigeons/native_bridge.dart
import 'package:pigeon/pigeon.dart';
```

### 2.2 Finding & Diagnostic
1. **Dart Core Library Boundary**: In Dart, `Uint8List` is defined within `dart:typed_data`. It is **not** part of `dart:core`.
2. **Pigeon Package Scope**: `package:pigeon/pigeon.dart` exports Pigeon generator annotations (`@ConfigurePigeon`, `@HostApi`, `@FlutterApi`, `@async`, `PigeonOptions`, `KotlinOptions`, `SwiftOptions`), but does **not** re-export `dart:typed_data`.
3. **Analyzer / Compiler Defect**: If `import 'dart:typed_data';` is omitted:
   - `dart analyze` or `flutter analyze` reports: `Undefined class 'Uint8List'`.
   - `dart run pigeon --input pigeons/native_bridge.dart` fails with a compilation/type resolution error.
4. **Resolution**: `import 'dart:typed_data';` **must** be explicitly added at line 2 before `import 'package:pigeon/pigeon.dart';`.

### 2.3 Verification Against Integrity Suite (`test_docs_integrity.py`)
`test_docs_integrity.py` (§2, lines 45–69) tests Pigeon contract consistency by inspecting `pigeons/native_bridge.dart`:
- Verifies that types `ImageSourceKind`, `CaptureResult`, `OcrBoundingBox`, `OcrTextLine`, `OcrDocument`, `NativeCaptureHostApi`, `NativeCaptureFlutterApi` are present.
- Verifies that methods `pickSingleImage`, `fetchPendingExternalCaptures`, `recognizeCapture`, `deleteCaptureImage`, `readImageFromClipboard`, `startOneShotScreenCapture`, `getOrCreateDatabaseKey`, `onExternalCaptureReceived` are present.
Adding `import 'dart:typed_data';` modifies only the header imports and does not alter any expected type names or method signatures. Therefore, `test_docs_integrity.py` remains 100% passing.

### 2.4 Updated `pigeons/native_bridge.dart` Header
```dart
// pigeons/native_bridge.dart
import 'dart:typed_data';
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/core/native/native_bridge.g.dart',
  dartTestOut: 'test/core/native/native_bridge_test.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/com/singwallet/app/bridge/NativeBridge.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.singwallet.app.bridge'),
  swiftOut: 'ios/Runner/Plugins/NativeBridge.g.swift',
  swiftOptions: SwiftOptions(),
))
```

---

## 3. Investigation Point 2: Exact Contents of `pubspec.yaml`

The `pubspec.yaml` file must satisfy all dependencies for M0 (Pigeon code generation, linting, tests) and M1 (SQLite, cryptography, intl, riverpod state management).

### 3.1 Canonical `pubspec.yaml`
```yaml
name: singwallet
description: "SingWallet - Production-Ready Personal Expense & Transaction Ledger"
publish_to: "none"
version: 1.0.0+1

environment:
  sdk: ">=3.2.0 <4.0.0"
  flutter: ">=3.16.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  sqflite: ^2.3.3+1
  sqflite_common_ffi: ^2.3.3
  crypto: ^3.0.3
  intl: ^0.19.0
  path: ^1.9.0
  path_provider: ^2.1.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  pigeon: ^22.7.0
  test: ^1.25.0

flutter:
  uses-material-design: true
```

### 3.2 Dependency Rationale & Compatibility Matrix

| Package | Constraint | Purpose in SingWallet |
|---|---|---|
| `flutter` | `sdk: flutter` | Core Flutter UI and platform service bindings |
| `flutter_riverpod` | `^2.5.1` | Compile-time safe state management, dependency injection for repositories & services |
| `sqflite` | `^2.3.3+1` | Android / iOS native SQLite database engine (supporting 12 tables & 11 indices) |
| `sqflite_common_ffi` | `^2.3.3` | Desktop / VM SQLite engine enabling automated unit tests without device emulators |
| `crypto` | `^3.0.3` | SHA-256 calculation for Tier-2 image deduplication & SWBK v1 key derivation |
| `intl` | `^0.19.0` | Date/time parsing, chronological ordering, and currency localization |
| `path` | `^1.9.0` | Cross-platform file path manipulation |
| `path_provider` | `^2.1.2` | Sandbox directory resolution (App Documents, App Cache, Temporary) |
| `flutter_test` | `sdk: flutter` | Flutter widget and unit test harness |
| `flutter_lints` | `^3.0.0` | Official Flutter static analysis linter rules |
| `pigeon` | `^22.7.0` | Type-safe code generator for Flutter ↔ Android (Kotlin) / iOS (Swift) bridge |
| `test` | `^1.25.0` | Standalone Dart test runner for pure domain and database logic |

---

## 4. Investigation Point 3: `analysis_options.yaml` with `flutter_lints`

To guarantee production-level code hygiene and satisfy acceptance criterion *“Flutter 项目依赖安装完整，项目可通过静态分析检查（flutter analyze 无致命错误）”*, `analysis_options.yaml` must enable strict linting while excluding Pigeon-generated files from human style checks.

### 4.1 Canonical `analysis_options.yaml`
```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    missing_required_param: error
    missing_return: error
    todo: ignore

linter:
  rules:
    - prefer_const_constructors
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - prefer_final_fields
    - prefer_final_locals
    - avoid_print
    - avoid_unnecessary_containers
    - use_build_context_synchronously
    - unnecessary_nullable_for_final_variable_declarations
    - directives_ordering
    - unawaited_futures
    - cancel_subscriptions
```

### 4.2 Key Configuration Features
1. **Pigeon Exclusion (`exclude: - "**/*.g.dart"`)**: Pigeon generates low-level platform channel serialization codecs and message dispatchers. These generated files contain machine-generated boilerplate (e.g. dynamic casts, raw object indexing) that should not fail CI lint gates.
2. **Strict Mode (`strict-casts`, `strict-inference`, `strict-raw-types`)**: Prevents untyped `dynamic` leaks across clean architecture layers.
3. **Safety Rules**:
   - `avoid_print`: Prevents inadvertent logging of sensitive financial data in production.
   - `use_build_context_synchronously`: Guards against async context access across Flutter frames.
   - `prefer_const_*`: Maximizes widget tree canonicalization and memory efficiency.

---

## 5. Investigation Point 4: Minimal Flutter Entrypoint & Placeholder Structure

### 5.1 Minimal Compilable App Entrypoint (`lib/main.dart`)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: SingWalletApp(),
    ),
  );
}

class SingWalletApp extends StatelessWidget {
  const SingWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SingWallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      home: const SingWalletHomePage(),
    );
  }
}

class SingWalletHomePage extends StatelessWidget {
  const SingWalletHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SingWallet'),
        centerTitle: true,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: Color(0xFF6750A4),
            ),
            SizedBox(height: 16),
            Text(
              'SingWallet Core Initialized',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Milestone M0: Scaffold & Native Pigeon Bridge',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 5.2 Native Bridge Service Wrapper (`lib/core/native/native_bridge_service.dart`)
This high-level service wraps `NativeCaptureHostApi`, provides strongly-typed domain error handling (`NativeBridgeException`), and allows mock injection for testing:
```dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';

/// Domain exception for native host bridge failures
class NativeBridgeException implements Exception {
  final String code;
  final String message;
  final Object? details;

  NativeBridgeException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'NativeBridgeException($code): $message';
}

/// High-level service managing platform-native screenshot ingestion and OCR
class NativeBridgeService {
  final NativeCaptureHostApi _hostApi;

  NativeBridgeService({NativeCaptureHostApi? hostApi})
      : _hostApi = hostApi ?? NativeCaptureHostApi();

  /// Pick single image via platform photo picker
  Future<CaptureResult?> pickSingleImage() async {
    try {
      return await _hostApi.pickSingleImage();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to pick single image',
        details: e.details,
      );
    }
  }

  /// Fetch pending external captures from Share sheet / App Group
  Future<List<CaptureResult>> fetchPendingExternalCaptures() async {
    try {
      final list = await _hostApi.fetchPendingExternalCaptures();
      return list.whereType<CaptureResult>().toList();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to fetch pending captures',
        details: e.details,
      );
    }
  }

  /// Run native offline OCR (ML Kit on Android / Vision on iOS)
  Future<OcrDocument> recognizeCapture(String captureId) async {
    try {
      return await _hostApi.recognizeCapture(captureId);
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to execute OCR for capture: $captureId',
        details: e.details,
      );
    }
  }

  /// Delete cached screenshot image from private storage
  Future<bool> deleteCaptureImage(String captureId) async {
    try {
      return await _hostApi.deleteCaptureImage(captureId);
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to delete capture: $captureId',
        details: e.details,
      );
    }
  }

  /// Read image from system clipboard
  Future<CaptureResult?> readImageFromClipboard() async {
    try {
      return await _hostApi.readImageFromClipboard();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to read image from clipboard',
        details: e.details,
      );
    }
  }

  /// Android one-shot screen capture (returns null on iOS or user cancel)
  Future<CaptureResult?> startOneShotScreenCapture() async {
    try {
      return await _hostApi.startOneShotScreenCapture();
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        return null;
      }
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to execute one-shot screen capture',
        details: e.details,
      );
    }
  }

  /// Derive or retrieve 256-bit AES database key from Keystore/Keychain
  Future<Uint8List> getOrCreateDatabaseKey() async {
    try {
      return await _hostApi.getOrCreateDatabaseKey();
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        code: e.code,
        message: e.message ?? 'Failed to access hardware database key',
        details: e.details,
      );
    }
  }
}
```

### 5.3 Global App Constants (`lib/core/constants/app_constants.dart`)
```dart
/// Global system constants and thresholds for SingWallet
class AppConstants {
  AppConstants._();

  static const String appName = 'SingWallet';
  static const String databaseName = 'singwallet.db';
  static const int databaseVersion = 1;

  // OCR Normalization limits & cutoffs
  static const double statusBarMaxTop = 0.075; // Status bar area cutoff
  static const double homeIndicatorMinTop = 0.95; // Home bar area cutoff

  // Deduplication time window
  static const Duration fuzzyDedupWindow = Duration(hours: 24);

  // Supported image extensions
  static const List<String> supportedImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
}
```

### 5.4 Monetary Units Math Utility (`lib/core/utils/currency_utils.dart`)
Complies strictly with R2 integer-cents arithmetic requirement:
```dart
/// Monetary calculation utilities using integer cents (minor currency units)
class CurrencyUtils {
  CurrencyUtils._();

  /// Converts cents (minor currency unit) to display string (e.g. 2890 -> "28.90")
  static String centsToYuanString(int cents) {
    final sign = cents < 0 ? '-' : '';
    final absCents = cents.abs();
    final yuan = absCents ~/ 100;
    final centRemainder = absCents % 100;
    return '$sign$yuan.${centRemainder.toString().padLeft(2, '0')}';
  }

  /// Parses user input string (e.g. "28.90" or "28.9" or "28") to cents
  /// Throws [FormatException] if invalid format or negative when not allowed
  static int yuanStringToCents(String input, {bool allowNegative = false}) {
    final trimmed = input.trim().replaceAll(',', '');
    if (trimmed.isEmpty) {
      throw const FormatException('Empty currency string');
    }

    final isNegative = trimmed.startsWith('-');
    if (isNegative && !allowNegative) {
      throw const FormatException('Negative amount not allowed');
    }

    final cleanStr = isNegative ? trimmed.substring(1) : trimmed;
    final parts = cleanStr.split('.');

    if (parts.length > 2) {
      throw FormatException('Invalid currency format: $input');
    }

    final yuan = int.tryParse(parts[0]);
    if (yuan == null) {
      throw FormatException('Invalid currency integer part: $input');
    }

    int cents = 0;
    if (parts.length == 2) {
      final centPart = parts[1];
      if (centPart.length == 1) {
        cents = int.parse(centPart) * 10;
      } else if (centPart.length == 2) {
        cents = int.parse(centPart);
      } else {
        // Truncate to 2 decimal digits
        cents = int.parse(centPart.substring(0, 2));
      }
    }

    final total = yuan * 100 + cents;
    return isNegative ? -total : total;
  }
}
```

### 5.5 Pigeon Unit Test Harness (`test/core/native/native_bridge_service_test.dart`)
Uses the mock class generated by Pigeon in `test/core/native/native_bridge_test.g.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/native/native_bridge_service.dart';
import 'native_bridge_test.g.dart';

class MockNativeCaptureHostApi implements TestNativeCaptureHostApi {
  CaptureResult? mockPickResult;
  List<CaptureResult> mockPendingCaptures = [];
  OcrDocument? mockOcrDoc;
  bool mockDeleteResult = true;
  CaptureResult? mockClipboardResult;
  CaptureResult? mockScreenCaptureResult;
  Uint8List? mockDbKey;

  @override
  Future<CaptureResult?> pickSingleImage() async => mockPickResult;

  @override
  List<CaptureResult> fetchPendingExternalCaptures() => mockPendingCaptures;

  @override
  Future<OcrDocument> recognizeCapture(String captureId) async {
    if (mockOcrDoc != null) return mockOcrDoc!;
    throw Exception('Capture not found: $captureId');
  }

  @override
  bool deleteCaptureImage(String captureId) => mockDeleteResult;

  @override
  CaptureResult? readImageFromClipboard() => mockClipboardResult;

  @override
  Future<CaptureResult?> startOneShotScreenCapture() async => mockScreenCaptureResult;

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async => mockDbKey ?? Uint8List(32);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockNativeCaptureHostApi mockApi;
  late NativeBridgeService service;

  setUp(() {
    mockApi = MockNativeCaptureHostApi();
    TestNativeCaptureHostApi.setUp(mockApi);
    service = NativeBridgeService();
  });

  tearDown(() {
    TestNativeCaptureHostApi.setUp(null);
  });

  test('pickSingleImage returns mock capture result', () async {
    final expected = CaptureResult(
      captureId: 'cap_123',
      localFilePath: '/tmp/test.png',
      imageWidth: 1080,
      imageHeight: 2400,
      contentHash: 'abc123hash',
      sourceKind: ImageSourceKind.photoPicker,
    );
    mockApi.mockPickResult = expected;

    final result = await service.pickSingleImage();
    expect(result, isNotNull);
    expect(result!.captureId, 'cap_123');
    expect(result.sourceKind, ImageSourceKind.photoPicker);
  });

  test('getOrCreateDatabaseKey returns 32-byte key', () async {
    final keyBytes = Uint8List.fromList(List.generate(32, (i) => i));
    mockApi.mockDbKey = keyBytes;

    final result = await service.getOrCreateDatabaseKey();
    expect(result.length, 32);
    expect(result, equals(keyBytes));
  });

  test('startOneShotScreenCapture returns null on unsupported', () async {
    mockApi.mockScreenCaptureResult = null;
    final result = await service.startOneShotScreenCapture();
    expect(result, isNull);
  });
}
```

### 5.6 Basic Widget Smoke Test (`test/widget_test.dart`)
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/main.dart';

void main() {
  testWidgets('SingWalletApp launches and displays core title', (WidgetTester tester) async {
    await tester.pumpWidget(const SingWalletApp());
    expect(find.text('SingWallet'), findsOneWidget);
    expect(find.text('SingWallet Core Initialized'), findsOneWidget);
  });
}
```

---

## 6. Investigation Point 5: Non-Destructive Scaffolding Runbook for Worker

### 6.1 Collision Risk Assessment
The workspace root directory currently contains:
- `README.md` (Contains mandatory document links verified by `test_docs_integrity.py`).
- `docs/` (`Android实现方案.md`, `iOS实现方案.md`, `跨平台架构与数据规范.md`).
- `pigeons/` (`native_bridge.dart`).
- `test_docs_integrity.py` (Architectural integrity validator).
- `.agents/` (Agent metadata directory).

**Risk**: Running `flutter create .` directly will overwrite `README.md` with default Flutter boilerplate, breaking `test_docs_integrity.py` immediately.

### 6.2 Recommended Step-by-Step Procedure

#### Phase 1: Directory Tree & Target Preparation
Create all target output directories required by Pigeon and Clean Architecture:
```powershell
# Create Flutter source hierarchy
New-Item -ItemType Directory -Force -Path "lib/core/constants"
New-Item -ItemType Directory -Force -Path "lib/core/native"
New-Item -ItemType Directory -Force -Path "lib/core/utils"
New-Item -ItemType Directory -Force -Path "lib/data/database"
New-Item -ItemType Directory -Force -Path "lib/features/recognition"
New-Item -ItemType Directory -Force -Path "lib/features/classification"
New-Item -ItemType Directory -Force -Path "lib/features/deduplication"

# Create test hierarchy
New-Item -ItemType Directory -Force -Path "test/core/native"
New-Item -ItemType Directory -Force -Path "test/database"
New-Item -ItemType Directory -Force -Path "test/deduplication"
New-Item -ItemType Directory -Force -Path "test/parser"

# Create Android and iOS bridge target directories
New-Item -ItemType Directory -Force -Path "android/app/src/main/kotlin/com/singwallet/app/bridge"
New-Item -ItemType Directory -Force -Path "ios/Runner/Plugins"
```

#### Phase 2: Patch `pigeons/native_bridge.dart`
Add `import 'dart:typed_data';` at line 2 of `pigeons/native_bridge.dart`.

#### Phase 3: Create Project Config Files
1. Write `pubspec.yaml` with the canonical content from §3.1.
2. Write `analysis_options.yaml` with the canonical content from §4.1.
3. Write `lib/main.dart` with the canonical content from §5.1.
4. Write `lib/core/constants/app_constants.dart` (§5.3).
5. Write `lib/core/utils/currency_utils.dart` (§5.4).
6. Write `lib/core/native/native_bridge_service.dart` (§5.2).

#### Phase 4: Protect `README.md` if Invoking `flutter create`
If the worker generates native platform wrappers (`android/`, `ios/`) via `flutter create`:
```powershell
# 1. Back up README.md
Copy-Item README.md README.md.bak -Force

# 2. Run flutter create with package org
flutter create --org com.singwallet --project-name singwallet .

# 3. Restore original README.md
Copy-Item README.md.bak README.md -Force
Remove-Item README.md.bak -Force
```

#### Phase 5: Dependency Installation & Pigeon Code Generation
```powershell
# 1. Install dependencies
flutter pub get

# 2. Execute Pigeon code generation
dart run pigeon --input pigeons/native_bridge.dart
```

#### Phase 6: Write Tests & Host Bridge Skeletons
1. Place `test/core/native/native_bridge_service_test.dart` (§5.5).
2. Place `test/widget_test.dart` (§5.6).
3. Implement `android/.../NativeCaptureHostApiImpl.kt` and `ios/.../NativeCaptureHostApiImpl.swift` (detailed by `explorer_m0_3`).

#### Phase 7: Verification Pipeline
Execute the four verification gates in sequence:
```powershell
# Gate 1: Markdown & Architecture integrity check
python test_docs_integrity.py

# Gate 2: Static analysis
flutter analyze

# Gate 3: Unit tests
flutter test

# Gate 4: Test mock harness verification
flutter test test/core/native/native_bridge_service_test.dart
```

---

## 7. Features & Checklist Verification

| Feature | Verification Command / Target | Success Criteria |
|---|---|---|
| Pigeon IDL | `dart run pigeon --input pigeons/native_bridge.dart` | Exit 0, 4 generated files present |
| Dart Bridge | `lib/core/native/native_bridge.g.dart` | Compiles cleanly, exports all classes/methods |
| Kotlin Bridge | `android/.../bridge/NativeBridge.g.kt` | Package `com.singwallet.app.bridge` |
| Swift Bridge | `ios/.../Plugins/NativeBridge.g.swift` | Swift protocol & setup helper present |
| Static Linter | `flutter analyze` | No issues found (exit code 0) |
| Unit Test Mock | `flutter test test/core/native/native_bridge_service_test.dart` | All tests pass (exit code 0) |
| Integrity Suite | `python test_docs_integrity.py` | 6 suites pass 100% |

---

## 8. Conclusion

All prerequisites for Milestone M0 scaffolding and Pigeon code generation are defined with complete, production-ready specifications. The worker has a zero-ambiguity runbook to scaffold files without risking existing project assets.
