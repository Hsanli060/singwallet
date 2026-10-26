# Adversarial Challenge Report: Coordinate Normalization, Doc Integrity, and Bridge Fidelity (Milestone M0)

- **Agent**: `challenger_m0_2` (Empirical Challenger: critic, specialist)
- **Target**: Milestone M0 Implementation by `worker_m0_1`
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\challenger_m0_2`
- **Parent**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Date**: 2026-10-22
- **Verdict**: **APPROVE**

---

## 1. Challenge Summary

**Overall risk assessment**: **LOW**

Empirical verification confirms that the Milestone M0 deliverables are production-grade, robust, and mathematically sound:
1. **Coordinate Normalization Math**: Both Android ML Kit (`coerceIn(0.0, 1.0)`) and iOS Apple Vision (`1.0 - visionBox.origin.y - visionBox.size.height` with clamping) yield identical normalized coordinates `[0.0, 1.0]` across all boundary cases (Top-Left, Bottom-Right, Full Screen, Zero-Size degenerate boxes, and 100,000 property-based randomized inputs). The maximum observed difference delta is `1.39e-16`, which is within IEEE 754 double precision machine epsilon (`2.22e-16`).
2. **Doc Integrity Suite**: `python test_docs_integrity.py` executed with exit code 0, verifying all 6 deep verification suites (Markdown link integrity, Pigeon contract consistency, SQLite DDL & foreign key cascades, SWBK v1 AES-256-GCM container crypto roundtrip, CSV formula injection protection, and baseline coordinate math).
3. **Flutter Test Suite**: `flutter test` executed with exit code 0; all 44 unit and widget tests passed cleanly without regressions.

---

## 2. Adversarial Challenges & Findings

### [Low] Challenge 1: IEEE 754 Floating-Point Division Residual at Top-Left Boundary on iOS

- **Assumption Challenged**: Bounding boxes positioned exactly at the top boundary of an image (`rect.top = 0`) will produce exact mathematical `0.0` across all platforms.
- **Attack Scenario**:
  - In Apple Vision, the vertical coordinate space is inverted with the origin at the bottom-left. A box starting at the physical top of the screen (`top = 0`) with height `boxH` on an image of height `H` has Vision coordinates:
    $$\text{origin.y} = \frac{H - \text{boxH}}{H}, \quad \text{size.height} = \frac{\text{boxH}}{H}$$
  - The iOS normalization formula computes:
    $$\text{flutterTop} = \max\left(0.0, \min\left(1.0, 1.0 - \text{origin.y} - \text{size.height}\right)\right)$$
  - For resolutions such as iPhone 12/13/14 (`H = 2532.0`) and `boxH = 100.0`:
    $$\text{origin.y} = \frac{2432.0}{2532.0} \approx 0.9605055292259083728...$$
    $$\text{size.height} = \frac{100.0}{2532.0} \approx 0.0394944707740916271...$$
  - In IEEE 754 double-precision arithmetic, $1.0 - \text{origin.y} - \text{size.height}$ evaluates to $+3.469446951953614 \times 10^{-17}$ rather than exact $0.0$.
  - Because $+3.47 \times 10^{-17} > 0.0$, the outer `max(0.0, ...)` does not clamp it to $0.0$.
- **Blast Radius**: Negligible. When projected onto any physical display ($2532 \times 3.47 \times 10^{-17} \approx 8.78 \times 10^{-14}$ pixels), the sub-atomic difference has zero visual or geometric effect. OCR status bar noise filtering thresholds (`top < 0.06`) correctly classify $3.47 \times 10^{-17}$ as top-of-screen.
- **Mitigation**: Unit tests performing exact `expect(ios.top, 0.0)` must use `closeTo(0.0, 1e-12)` to account for IEEE 754 rounding. In production code, the existing clamp `max(0.0, min(1.0, ...))` prevents any negative values or overflow above 1.0.

### [Low] Challenge 2: Detector Out-of-Bounds Artifacts and Zero-Dimension Images

- **Assumption Challenged**: OCR engines only report bounding boxes strictly within image pixel boundaries, and image dimensions are always positive.
- **Attack Scenario**:
  - Physical text near image edges can cause OCR detectors to emit bounding boxes where `left < 0`, `top < 0`, or `right > imageWidth`.
  - Corrupt or truncated image headers can result in `imageWidth <= 0` or `imageHeight <= 0`, risking divide-by-zero (`NaN` or `Infinity`).
- **Empirical Defense Verification**:
  - Android ML Kit adapter guards against invalid dimensions at lines 102-105:
    ```kotlin
    if (width <= 0 || height <= 0) {
        callback(Result.failure(IllegalStateException("INVALID_IMAGE_DIMENSIONS: Width or height <= 0")))
        return
    }
    ```
    And clamps all four bounding box edges via `(x / dim).coerceIn(0.0, 1.0)`.
  - iOS Apple Vision adapter guards against zero dimensions during `CGImageSourceCopyPropertiesAtIndex` and clamps via `max(0.0, min(1.0, Double(...)))`.
  - Extreme bounding box tests with `left = -50`, `width = 3000` on a $1080 \times 2400$ image confirmed output coordinates are strictly bounded to `[0.0, 1.0]`.

### [Informational] Challenge 3: Analyzer Warnings Introduced by Peer Test File

- **Assumption Challenged**: Running `flutter analyze` across the entire workspace should always yield 0 warnings.
- **Observation**:
  - `worker_m0_1` implementation code in `lib/`, `android/`, and `ios/` passed `flutter analyze` with 0 issues.
  - An independent peer test file `test/core/native/pigeon_stress_challenge_test.dart` (created during parallel testing) triggered 2 informational lint warnings:
    - Line 2: `unnecessary_import` (`dart:typed_data`)
    - Line 182: `prefer_const_declarations`
- **Mitigation**: Peer test file should have `dart:typed_data` import removed and `const` applied to line 182 to maintain zero workspace lint warnings.

---

## 3. Stress Test Results

| # | Test Scenario | Expected Behavior | Actual Behavior | Result |
|---|---------------|-------------------|-----------------|--------|
| 1 | Top-Left Corner Boundary ($0, 0, w, h$) across 5 resolutions | Normalized left=0.0, top $\approx$ 0.0, width/height match | Android: 0.0, iOS: $3.47 \times 10^{-17}$ (delta $< 10^{-12}$) | **PASS** |
| 2 | Bottom-Right Corner Boundary ($W-w, H-h, w, h$) | Touching (1.0, 1.0) boundary, identical coordinates | Max delta $< 10^{-12}$, left+width=1.0, top+height=1.0 | **PASS** |
| 3 | Full Screen Boundary ($0, 0, W, H$) | Identical box $(0.0, 0.0, 1.0, 1.0)$ | Exactly $(0.0, 0.0, 1.0, 1.0)$ on both Android and iOS | **PASS** |
| 4 | Zero-Size Degenerate Boxes at 5 anchor points | Width=0.0, Height=0.0, identical point coordinates | Width=0.0, Height=0.0, point delta $< 10^{-12}$ | **PASS** |
| 5 | 100,000 Randomized Property-Based Boxes | Equivalence between Android ML Kit and iOS Vision within double precision | 100,000 cases passed; max observed delta: $1.39 \times 10^{-16}$ | **PASS** |
| 6 | Out-of-Bounds Detector Artifacts ($<0$, $>W/H$) | Clamped strictly to $[0.0, 1.0]$ without crash | Android `coerceIn` and iOS `max/min` clamped correctly | **PASS** |
| 7 | `python test_docs_integrity.py` | All 6 deep verification suites pass with Exit Code 0 | 6/6 suites passed (Markdown, Pigeon, SQLite, SWBK, CSV, Coords) | **PASS** |
| 8 | `flutter test` Execution | All unit and widget tests pass cleanly | 44/44 tests passed with Exit Code 0 | **PASS** |

---

## 4. Unchallenged Areas

- **Physical ML Kit / Vision OCR Execution on Live Silicon**: Full on-device camera recognition depends on physical Android/iOS hardware (to be validated in device staging / M-Final E2E runs).
- **SQLite Database Native C Library Linking on Non-Windows Hosts**: Verified on Windows with precompiled `sqlite3.dll`; macOS / Linux native linking to be verified in respective CI environments.

---

## 5. Final Recommendation

**Verdict**: **APPROVE**

Milestone M0 satisfies all architectural requirements, demonstrates mathematical fidelity across cross-platform coordinate systems, and passes all automated integrity and unit test suites. Milestone M1 may proceed.
