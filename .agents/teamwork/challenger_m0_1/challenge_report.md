# Milestone M0 Adversarial Challenge Report: Pigeon Serialization, Codecs, & Error Paths

- **Agent**: `challenger_m0_1` (Critic / Specialist)
- **Target**: Milestone M0 (Pigeon Native Bridge & Scaffold)
- **Date**: 2026-10-22
- **Verdict**: **APPROVE**

---

## 1. Challenge Summary

**Overall risk assessment**: **LOW**

Adversarial stress-testing of the Pigeon serialization layer, data transfer models, HostApi error translation, and FlutterApi reverse event dispatch demonstrated high robustness, type fidelity, and secure error isolation across all verified dimensions.

A dedicated 24-case test suite was authored and executed at:
`test/core/native/pigeon_stress_challenge_test.dart`

All 44 tests in the project (`flutter test`) and all 6 document/architecture integrity suites (`python test_docs_integrity.py`) pass 100% with zero static analysis issues (`flutter analyze` clean).

---

## 2. Challenges & Empirical Stress Tests

### Challenge 1 (Low Risk): Codec Precision Drift & Extreme Float Boundary Behavior
- **Assumption challenged**: Pigeon's StandardMessageCodec might truncate 64-bit float precision or mishandle out-of-range coordinates, infinities, or NaN in `OcrBoundingBox`.
- **Attack scenario**:
  - Encoded bounding box with 17-digit IEEE-754 precision (`0.12345678901234567`, `0.9876543210987654`).
  - Encoded coordinates outside unit interval `[0.0, 1.0]` (`-100.5`, `5000.25`).
  - Injected extreme doubles (`double.maxFinite`, `double.minPositive`, `-double.maxFinite`).
  - Injected `double.infinity`, `-double.infinity`, and `double.nan`.
- **Empirical result**: **PASS**. StandardMessageCodec preserves full 64-bit IEEE-754 float precision. Out-of-bounds numbers and infinities roundtrip faithfully without clipping or distortion; `double.nan` roundtrips with `.isNaN == true`.
- **Mitigation / Note**: Raw Pigeon DTOs transmit values verbatim without silent clipping. Downstream OCR post-processing layers are responsible for business validation clamping.

### Challenge 2 (Low Risk): Integer Overflow, Unicode Emojis, and Giant Payload Handling
- **Assumption challenged**: StandardMessageCodec might corrupt 64-bit integers on 32-bit platforms, mangle multibyte unicode/emojis, or crash under large OCR documents.
- **Attack scenario**:
  - Transmitted 64KB string payload, UTF-8 emoji sequences (`💸`, `💳`), embedded null bytes (`\u0000`), control characters (`\t\r\n`), and path traversal strings (`../../etc/passwd`).
  - Injected 64-bit integer limits: min int64 (`-9223372036854775808`) and max int64 (`9223372036854775807`).
  - Transmitted database key `Uint8List` varying from 0 bytes, 32 bytes (standard AES-256), 64 bytes, to 1MB binary buffers.
  - Serialized a massive 1,000-line OCR document with full text, nested boxes, and confidence scores.
- **Empirical result**: **PASS**. Zero data corruption detected. All 1,000 nested lines and multi-byte UTF-8 sequences were deserialized identically.

### Challenge 3 (Medium Risk): Native HostApi Exception Leakage and UNSUPPORTED Fallback
- **Assumption challenged**: Platform-native exceptions (e.g. storage denied, Keystore locked, missing file) might bypass high-level domain handling or cause uncaught exceptions in UI code.
- **Attack scenario**:
  - Simulated `PlatformException(code: 'PERMISSION_DENIED')` on `pickSingleImage`.
  - Simulated `PlatformException(code: 'APP_GROUP_UNAVAILABLE')` on `fetchPendingExternalCaptures`.
  - Simulated `PlatformException(code: 'FILE_NOT_FOUND')` on `recognizeCapture`.
  - Simulated `PlatformException(code: 'UNSUPPORTED')` vs `MEDIA_PROJECTION_DENIED` on `startOneShotScreenCapture`.
  - Simulated `PlatformException(code: 'KEYSTORE_FAILED')` on `getOrCreateDatabaseKey`.
  - Disconnected channel: Simulated unregistered HostApi resulting in `channel-error`.
- **Empirical result**: **PASS**.
  - `NativeBridgeService` wraps all incoming `PlatformException` instances into typed `NativeBridgeException`, preserving error `code`, `message`, and `details`.
  - On `startOneShotScreenCapture`, `UNSUPPORTED` exception correctly yields `null` without throwing, satisfying the cross-platform specification (iOS prohibition against screen capture).
  - Unregistered or disconnected channel throws `PlatformException(code: 'channel-error')`, which is cleanly captured as `NativeBridgeException`.

### Challenge 4 (Medium Risk): Native-to-Flutter FlutterApi Exception Resilience
- **Assumption challenged**: If the Flutter application handler for `onExternalCaptureReceived` throws an uncaught exception (e.g., SQLite constraint violation or out of memory during ingestion), it might crash the native BinaryMessenger loop or cause a native host hang.
- **Attack scenario**:
  - Registered a FlutterApi receiver whose callback throws `FormatException`.
  - Registered a FlutterApi receiver whose callback throws `PlatformException`.
  - Sent native event through binary messenger via `handlePlatformMessage`.
- **Empirical result**: **PASS**.
  - Pigeon's autogenerated wrapper intercepts synchronous Dart exceptions and returns `['error', message, details]` back to the native caller.
  - When `PlatformException` is thrown, Pigeon wraps it into the exact code and message requested.
  - The native platform message channel receives a valid error response without hanging or unhandled crash.

### Challenge 5 (Low Risk): Data Payload Corruption Fast-Fail Behavior
- **Assumption challenged**: Corrupted or incomplete binary packets might deserialize into invalid models with corrupted state.
- **Attack scenario**:
  - Decoded truncated lists missing required fields in `CaptureResult`.
  - Injected `null` into required non-nullable fields.
  - Injected `int` into `OcrBoundingBox` fields where `double` is expected.
  - Injected non-`OcrTextLine` objects into `OcrDocument.lines`.
- **Empirical result**: **PASS**.
  - Truncated lists throw `RangeError` immediately.
  - Nulls and invalid types throw `TypeError` immediately via Dart strong-mode type checks.
  - *Architectural Note*: `OcrDocument.decode` uses `(result[1] as List<Object?>?)!.cast<OcrTextLine>()`. Because Dart's `.cast<T>()` returns a lazy `CastList`, invalid items inside `lines` trigger `TypeError` upon element access rather than at decode constructor time. This behavior is safe and standard in Dart collection casting.

### Challenge 6 (Security): Native Path Traversal on `captureId`
- **Assumption challenged**: Malicious captureId inputs (e.g. `../../etc/passwd` or `..\\windows\\system32`) could result in arbitrary file deletion or access in `NativeCaptureHostApiImpl.kt` or `NativeCaptureHostApiImpl.swift`.
- **Attack scenario**: Inspected Android and iOS native source code for directory traversal defenses.
- **Empirical result**: **PASS**.
  - Android (`NativeCaptureHostApiImpl.kt` lines 34, 83, 118): Validates `captureId` against `Regex("^[a-zA-Z0-9_-]+$")` in both `recognizeCapture` and `deleteCaptureImage`.
  - iOS (`NativeCaptureHostApiImpl.swift` lines 14, 84, 176): Validates `captureId` against `safeIdRegex` (`^[a-zA-Z0-9_-]+$`) in both `recognizeCapture` and `deleteCaptureImage`.
  - Path traversal characters (`/`, `\`, `.`) are strictly rejected with error code or boolean false.

---

## 3. Stress Test Results Summary

| Scenario / Target | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|
| `ImageSourceKind` (all 5 values) | Exact index preservation | Exact match | PASS |
| `OcrBoundingBox` float precision | 1e-12 precision preserved | Exact match | PASS |
| `OcrBoundingBox` extreme IEEE values | NaN, Inf, maxFinite preserved | Exact match | PASS |
| `CaptureResult` empty strings & limits | Empty strings, int64 max/min | Exact match | PASS |
| `CaptureResult` UTF-8 emojis & null byte | Multi-byte string fidelity | Exact match | PASS |
| `OcrTextLine` nullable confidence | `null` preserved, non-null preserved | Exact match | PASS |
| `OcrDocument` 1,000 lines stress test | High-throughput list roundtrip | Exact match | PASS |
| `Uint8List` 0, 32, 64, 1MB buffers | Byte-for-byte binary match | Exact match | PASS |
| `pickSingleImage` PlatformException | Mapped to `NativeBridgeException` | Mapped correctly | PASS |
| `fetchPendingExternalCaptures` error | Mapped to `NativeBridgeException` | Mapped correctly | PASS |
| `recognizeCapture` FILE_NOT_FOUND | Mapped to `NativeBridgeException` | Mapped correctly | PASS |
| `deleteCaptureImage` FILE_LOCKED | Mapped to `NativeBridgeException` | Mapped correctly | PASS |
| `readImageFromClipboard` CLIPBOARD_EMPTY | Mapped to `NativeBridgeException` | Mapped correctly | PASS |
| `startOneShotScreenCapture` UNSUPPORTED | Gracefully returns null | Returns null | PASS |
| `startOneShotScreenCapture` DENIED | Mapped to `NativeBridgeException` | Mapped correctly | PASS |
| `getOrCreateDatabaseKey` KEYSTORE_FAILED | Mapped to `NativeBridgeException` | Mapped correctly | PASS |
| `NativeCaptureFlutterApi` event dispatch | Calls receiver, returns empty | Returns empty reply | PASS |
| `NativeCaptureFlutterApi` callback crash | Intercepts, returns error reply | Returns error reply | PASS |
| `NativeCaptureFlutterApi` PlatformEx | Returns error code and message | Returns error code | PASS |
| `CaptureResult.decode` corrupt payload | Fast-fail with RangeError/TypeError | Throws RangeError/TypeError | PASS |
| `OcrBoundingBox.decode` int vs double | Fast-fail via strong type check | Throws TypeError | PASS |
| `OcrDocument.decode` malformed lines | Lazy CastList checks on access | Throws TypeError on access | PASS |
| HostApi disconnected channel | Throws PlatformException(channel-error) | Throws channel-error | PASS |
| Path traversal attack on `captureId` | Regex rejects path traversal | Rejects input | PASS |

Total tests in suite: 24/24 passed.

---

## 4. Unchallenged Areas

- **Physical Hardware Keystore**: Execution on physical Android / iOS devices with hardware-backed Secure Enclave / Titan M chips was validated through architectural code review and unit mock harnesses rather than physical hardware (acceptable for CI/desktop development environment).
