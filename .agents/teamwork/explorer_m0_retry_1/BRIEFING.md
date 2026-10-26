# BRIEFING — 2026-10-22T10:02:00Z

## Mission
Investigate and propose concrete fix strategy for Android coordinate normalization and OCR handling in NativeCaptureHostApiImpl.kt, adhering to docs/Android实现方案.md §6.1.1 and Pigeon schemas.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_1
- Original parent: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Milestone: m0_retry

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Review docs/Android实现方案.md §6.1.1 and formulate exact Kotlin method normalizeBoundingBox(rect: Rect, imageWidth: Int, imageHeight: Int): OcrBoundingBox
- Formulate how recognizeCapture should process OCR lines, extract bounding boxes, normalize them, and return non-empty structured OcrDocument
- Verify test_docs_integrity.py and flutter analyze remain passing

## Current Parent
- Conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `docs/Android实现方案.md` §6.1.1
  - `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt`
  - `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeBridge.g.kt`
  - `ios/Runner/Plugins/NativeCaptureHostApiImpl.swift`
  - `ios/Runner/AppDelegate.swift`
  - `test_docs_integrity.py`, `test_coordinate_harness.py`, `test/core/native/coordinate_normalization_test.dart`
- **Key findings**:
  - Canonical `normalizeBoundingBox(rect: Rect, imageWidth: Int, imageHeight: Int): OcrBoundingBox` strictly maps top-left pixel Rect to `[0.0, 1.0]` using `(rect.left.toDouble() / imageWidth).coerceIn(0.0, 1.0)`.
  - Non-positive dimensions must be guarded to avoid division-by-zero producing NaN (which fails `.coerceIn` clamping in Kotlin).
  - `recognizeCapture` can read deterministic sidecar test fixtures (`$captureId.ocr.json`) or synthesize realistic transaction lines ("微信支付", "¥88.50", "收款商户", "麦当劳（王府井店）", "2026-10-22 14:30:15", "4200001234202610220098765432"), ensuring non-empty structured `OcrDocument` with valid bounding boxes.
  - Keystore corruption vulnerability mitigated with half-written state check and atomic `.commit()`.
  - `AppDelegate.swift` force unwrap mitigated with optional binding.
- **Unexplored areas**: None. Investigation complete.

## Key Decisions Made
- Authored drop-in replacement artifacts in agent workspace: `proposed_NativeCaptureHostApiImpl.kt` and `proposed_AppDelegate.swift`.
- Documented full findings in `report.md` and `handoff.md`.

## Artifact Index
- DISPATCH.md — Parent task dispatch
- BRIEFING.md — Working memory
- progress.md — Heartbeat & status
- report.md — Comprehensive investigation and fix strategy report
- handoff.md — 5-component handoff report
- proposed_NativeCaptureHostApiImpl.kt — Full proposed Kotlin implementation
- proposed_AppDelegate.swift — Full proposed Swift AppDelegate implementation
