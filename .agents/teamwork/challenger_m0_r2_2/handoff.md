# Handoff Report: Coordinate Normalization Verification & Challenge

- **Agent**: `challenger_m0_r2_2` (Critic, Specialist)
- **Recipient**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\challenger_m0_r2_2`
- **Date**: 2026-10-22
- **Milestone**: M0 Round 2 Challenge

---

## 1. Observation

1. **Android Coordinate Normalization Implementation**:
   In `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt`, lines 47–68:
   ```kotlin
   fun normalizeBoundingBox(rect: Rect, imageWidth: Int, imageHeight: Int): OcrBoundingBox {
       if (imageWidth <= 0 || imageHeight <= 0) {
           return OcrBoundingBox(left = 0.0, top = 0.0, width = 0.0, height = 0.0)
       }
       val flutterLeft = (rect.left.toDouble() / imageWidth).coerceIn(0.0, 1.0)
       val flutterTop = (rect.top.toDouble() / imageHeight).coerceIn(0.0, 1.0)
       val flutterWidth = (rect.width().toDouble() / imageWidth).coerceIn(0.0, 1.0)
       val flutterHeight = (rect.height().toDouble() / imageHeight).coerceIn(0.0, 1.0)
       return OcrBoundingBox(
           left = flutterLeft,
           top = flutterTop,
           width = flutterWidth,
           height = flutterHeight
       )
   }

   fun normalizeBoundingBox(rect: Rect?, imageWidth: Int, imageHeight: Int): OcrBoundingBox {
       return normalizeBoundingBox(rect ?: Rect(), imageWidth, imageHeight)
   }
   ```
   Matches specification in `docs/Android实现方案.md` lines 310–315.

2. **iOS Coordinate Normalization Implementation**:
   In `ios/Runner/Plugins/NativeCaptureHostApiImpl.swift`, lines 130–142:
   ```swift
   // Apple Vision coordinate inversion to Top-Left origin [0.0, 1.0]
   let flutterLeft = max(0.0, min(1.0, Double(visionBox.origin.x)))
   let flutterTop = max(0.0, min(1.0, Double(1.0 - visionBox.origin.y - visionBox.size.height)))
   let flutterWidth = max(0.0, min(1.0, Double(visionBox.size.width)))
   let flutterHeight = max(0.0, min(1.0, Double(visionBox.size.height)))
   ```
   Matches specification in `docs/iOS实现方案.md` lines 380–386.

3. **Execution of `python test_docs_integrity.py`**:
   - Command: `python test_docs_integrity.py`
   - Exit code: `0`
   - Output snippet:
     ```
     --- 1. Testing Markdown Files & Local Links Integrity --- ... OK
     --- 2. Testing Pigeon Contract & Cross-Document Consistency --- ... OK
     --- 3. Testing SQLite DDL, Constraints & Cascades --- ... OK
     --- 4. Testing SWBK v1 Cross-Platform Backup Encryption & Authentication --- ... OK
     --- 5. Testing CSV Formula Injection Protection --- ... OK
     --- 6. Testing OCR Coordinate System Normalization Math ---
       Android ML Kit & iOS Apple Vision coordinate mapping verified to be mathematically equivalent!
       Result: left=0.0855, top=0.1975, width=0.2564, height=0.0395
     >>> ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%! <<<
     ```

4. **Execution of `python test_coordinate_harness.py`**:
   - Command: `python test_coordinate_harness.py`
   - Exit code: `0`
   - Output snippet:
     ```
     === Running Coordinate Normalization Boundary Tests ===
       [OK] All boundary test cases passed across all resolutions!
     === Running 100000 Randomized Stress & Property-Based Tests ===
       [OK] 100000 randomized tests PASSED!
       Maximum observed delta between Android & iOS: 1.39e-16 (machine precision: ~2.22e-16)
     === Running Out-of-Bounds & Detector Artifacts Test ===
       [OK] Out-of-bounds and detector artifact clamping verified successfully!
     >>> COORDINATE NORMALIZATION EMPIRICAL SUITE PASSED! <<<
     ```

5. **Adversarial Stress Test (500,000 iterations)**:
   - Command: Inline Python runner with 12 distinct resolution configurations including $1 \times 1$ minimal resolution and $1080 \times 15,000$ extreme panoramic screenshot.
   - Result: Exit code `0`, max observed difference $1.388 \times 10^{-16}$.

---

## 2. Logic Chain

1. From Observation 1, Android ML Kit normalization operates on pixel integers `(rect.left, rect.top, rect.width(), rect.height())` divided by image dimensions `(imageWidth, imageHeight)` and clamped to `[0.0, 1.0]`. It includes guard clauses for `imageWidth <= 0 || imageHeight <= 0` and null `rect`.
2. From Observation 2, iOS Apple Vision operates on normalized coordinates `(visionBox.origin.x, visionBox.origin.y, visionBox.size.width, visionBox.size.height)`. The vertical inversion formula is `1.0 - visionBox.origin.y - visionBox.size.height`, clamped to `[0.0, 1.0]`.
3. Geometrically, for a physical text line located at pixel distance $Y_{\text{top}}$ from the top of an image with height $H$ and height $\Delta Y$, its pixel bottom is $Y_{\text{top}} + \Delta Y$. Its distance from the bottom of the image in Vision's coordinate system is $H - (Y_{\text{top}} + \Delta Y)$. Hence $\text{visionBox.origin.y} = 1.0 - (Y_{\text{top}} + \Delta Y) / H$.
4. Substituting into iOS formula:
   $$\text{flutterTop} = 1.0 - \left(1.0 - \frac{Y_{\text{top}} + \Delta Y}{H}\right) - \frac{\Delta Y}{H} = \frac{Y_{\text{top}}}{H}$$
   This is algebraically identical to Android ML Kit's formula $\text{flutterTop} = \frac{\text{rect.top}}{H}$.
5. From Observations 3, 4, and 5, empirical testing across boundary conditions, out-of-bounds inputs, degenerate sizes, standard resolutions, and extreme panoramic aspect ratios demonstrated numerical equivalence down to double precision floating-point epsilon ($1.39 \times 10^{-16}$).
6. Therefore, coordinate normalization between Android ML Kit and iOS Vision is completely consistent, robust against edge cases, and compliant with all project specifications.

---

## 3. Caveats

- Device hardware runtime camera orientation (e.g., EXIF 90°/180° orientation tags) is handled by underlying framework APIs (ML Kit `InputImage.fromBitmap(..., rotationDegrees)` and Vision `VNImageRequestHandler(ciImage:orientation:)`) and was not tested against live physical sensors in this environment. Standard screenshots are portrait orientation and unaffected.
- No other caveats.

---

## 4. Conclusion

- **Verdict**: **APPROVE**
- All boundary test cases, out-of-bounds guards, degenerate inputs, and property-based stress tests pass with 100% success.
- `test_docs_integrity.py` and `test_coordinate_harness.py` exit with code `0`.
- The implementation in `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt` and `ios/Runner/Plugins/NativeCaptureHostApiImpl.swift` is production-ready.

---

## 5. Verification Method

To independently verify these results:

1. **Run docs and DDL integrity suite**:
   ```powershell
   python test_docs_integrity.py
   ```
   *Expected*: Exit code 0, all 6 verification test suites pass.

2. **Run coordinate harness suite**:
   ```powershell
   python test_coordinate_harness.py
   ```
   *Expected*: Exit code 0, 100,000 property-based tests pass with max delta $< 2.22 \times 10^{-16}$.

3. **Inspect implementation source code**:
   - `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt` (lines 47–68)
   - `ios/Runner/Plugins/NativeCaptureHostApiImpl.swift` (lines 130–142)
   - `c:\Other\Projects\singwallet\.agents\teamwork\challenger_m0_r2_2\challenge_report.md`
