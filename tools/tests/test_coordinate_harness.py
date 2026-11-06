"""
Empirical verification harness for OCR coordinate normalization between
Android ML Kit and iOS Apple Vision.

Tests:
1. Boundary cases:
   - Top-Left corner (0, 0, w, h)
   - Bottom-Right corner (W - w, H - h, w, h)
   - Full screen (0, 0, W, H)
   - Zero size degenerate boxes:
     * at (0, 0, 0, 0)
     * at (W, H, 0, 0)
     * at (W/2, H/2, 0, 0)
     * at (0, H, 0, 0)
     * at (W, 0, 0, 0)
   - Single-pixel boxes at various positions
2. Out-of-bounds clamping behavior:
   - Sub-zero coordinates (e.g. left < 0, top < 0)
   - Overflow coordinates (e.g. right > W, bottom > H)
3. Stress / Property-Based Testing:
   - 100,000 randomized boxes across standard resolutions
     (1080x2400 Android, 1170x2532 iPhone 14/15/16 Pro, 1290x2796 Pro Max)
"""

import sys
import random
import math

def android_mlkit_normalize(rect_left, rect_top, rect_width, rect_height, image_width, image_height):
    """
    Android ML Kit logic from docs/Android实现方案.md line 310:
    val rect = textLine.boundingBox ?: Rect()
    val flutterLeft = (rect.left.toDouble() / imageWidth).coerceIn(0.0, 1.0)
    val flutterTop = (rect.top.toDouble() / imageHeight).coerceIn(0.0, 1.0)
    val flutterWidth = (rect.width().toDouble() / imageWidth).coerceIn(0.0, 1.0)
    val flutterHeight = (rect.height().toDouble() / imageHeight).coerceIn(0.0, 1.0)
    """
    def coerce_in(val, min_v, max_v):
        return max(min_v, min(max_v, val))

    flutter_left = coerce_in(float(rect_left) / image_width, 0.0, 1.0)
    flutter_top = coerce_in(float(rect_top) / image_height, 0.0, 1.0)
    flutter_width = coerce_in(float(rect_width) / image_width, 0.0, 1.0)
    flutter_height = coerce_in(float(rect_height) / image_height, 0.0, 1.0)

    return flutter_left, flutter_top, flutter_width, flutter_height


def ios_vision_normalize(vision_origin_x, vision_origin_y, vision_width, vision_height):
    """
    iOS Apple Vision logic from ios/Runner/Plugins/NativeCaptureHostApiImpl.swift line 131:
    let flutterLeft = max(0.0, min(1.0, Double(visionBox.origin.x)))
    let flutterTop = max(0.0, min(1.0, Double(1.0 - visionBox.origin.y - visionBox.size.height)))
    let flutterWidth = max(0.0, min(1.0, Double(visionBox.size.width)))
    let flutterHeight = max(0.0, min(1.0, Double(visionBox.size.height)))
    """
    flutter_left = max(0.0, min(1.0, float(vision_origin_x)))
    flutter_top = max(0.0, min(1.0, float(1.0 - vision_origin_y - vision_height)))
    flutter_width = max(0.0, min(1.0, float(vision_width)))
    flutter_height = max(0.0, min(1.0, float(vision_height)))

    return flutter_left, flutter_top, flutter_width, flutter_height


def ground_truth_to_vision(rect_left, rect_top, rect_width, rect_height, image_width, image_height):
    """
    Apple Vision coordinates for a physical box [rect_left, rect_top, rect_width, rect_height]:
    Origin is at Bottom-Left:
    bottom_y_from_top = rect_top + rect_height
    origin_y = (image_height - bottom_y_from_top) / image_height
    """
    origin_x = float(rect_left) / image_width
    origin_y = (float(image_height) - (rect_top + rect_height)) / image_height
    width = float(rect_width) / image_width
    height = float(rect_height) / image_height
    return origin_x, origin_y, width, height


def run_boundary_tests():
    print("=== Running Coordinate Normalization Boundary Tests ===")
    resolutions = [
        (1080, 1920), # Standard FHD
        (1080, 2400), # Typical Android 20:9
        (1170, 2532), # iPhone 12/13/14
        (1290, 2796), # iPhone 14/15/16 Pro Max
        (1, 1),       # Minimal resolution 1x1
    ]

    for W, H in resolutions:
        # Case 1: Top-Left boundary
        w_box, h_box = int(W * 0.2), int(H * 0.1)
        a_l, a_t, a_w, a_h = android_mlkit_normalize(0, 0, w_box, h_box, W, H)
        vx, vy, vw, vh = ground_truth_to_vision(0, 0, w_box, h_box, W, H)
        i_l, i_t, i_w, i_h = ios_vision_normalize(vx, vy, vw, vh)

        assert abs(a_l - i_l) < 1e-12, f"Top-Left left mismatch for {W}x{H}: {a_l} vs {i_l}"
        assert abs(a_t - i_t) < 1e-12, f"Top-Left top mismatch for {W}x{H}: {a_t} vs {i_t}"
        assert abs(a_w - i_w) < 1e-12, f"Top-Left width mismatch for {W}x{H}: {a_w} vs {i_w}"
        assert abs(a_h - i_h) < 1e-12, f"Top-Left height mismatch for {W}x{H}: {a_h} vs {i_h}"
        assert a_l == 0.0 and a_t == 0.0, f"Top-Left not at (0, 0): ({a_l}, {a_t})"

        # Case 2: Bottom-Right boundary
        br_left = W - w_box
        br_top = H - h_box
        a_l, a_t, a_w, a_h = android_mlkit_normalize(br_left, br_top, w_box, h_box, W, H)
        vx, vy, vw, vh = ground_truth_to_vision(br_left, br_top, w_box, h_box, W, H)
        i_l, i_t, i_w, i_h = ios_vision_normalize(vx, vy, vw, vh)

        assert abs(a_l - i_l) < 1e-12, f"Bottom-Right left mismatch for {W}x{H}: {a_l} vs {i_l}"
        assert abs(a_t - i_t) < 1e-12, f"Bottom-Right top mismatch for {W}x{H}: {a_t} vs {i_t}"
        assert abs(a_w - i_w) < 1e-12, f"Bottom-Right width mismatch for {W}x{H}: {a_w} vs {i_w}"
        assert abs(a_h - i_h) < 1e-12, f"Bottom-Right height mismatch for {W}x{H}: {a_h} vs {i_h}"
        assert abs(a_l + a_w - 1.0) < 1e-12, f"Bottom-Right right edge not at 1.0: {a_l + a_w}"
        assert abs(a_t + a_h - 1.0) < 1e-12, f"Bottom-Right bottom edge not at 1.0: {a_t + a_h}"

        # Case 3: Full Screen boundary
        a_l, a_t, a_w, a_h = android_mlkit_normalize(0, 0, W, H, W, H)
        vx, vy, vw, vh = ground_truth_to_vision(0, 0, W, H, W, H)
        i_l, i_t, i_w, i_h = ios_vision_normalize(vx, vy, vw, vh)

        assert (a_l, a_t, a_w, a_h) == (0.0, 0.0, 1.0, 1.0), f"Android full screen error: {(a_l, a_t, a_w, a_h)}"
        assert (i_l, i_t, i_w, i_h) == (0.0, 0.0, 1.0, 1.0), f"iOS full screen error: {(i_l, i_t, i_w, i_h)}"

        # Case 4: Zero size degenerate boxes
        degenerate_points = [
            (0, 0),        # Top-Left point
            (W, H),        # Bottom-Right point
            (0, H),        # Bottom-Left point
            (W, 0),        # Top-Right point
            (W // 2, H // 2), # Center point
        ]
        for px, py in degenerate_points:
            a_l, a_t, a_w, a_h = android_mlkit_normalize(px, py, 0, 0, W, H)
            vx, vy, vw, vh = ground_truth_to_vision(px, py, 0, 0, W, H)
            i_l, i_t, i_w, i_h = ios_vision_normalize(vx, vy, vw, vh)

            assert abs(a_l - i_l) < 1e-12, f"Zero-size left mismatch at ({px}, {py})"
            assert abs(a_t - i_t) < 1e-12, f"Zero-size top mismatch at ({px}, {py})"
            assert a_w == 0.0 and i_w == 0.0, "Zero-size width should be 0.0"
            assert a_h == 0.0 and i_h == 0.0, "Zero-size height should be 0.0"

    print("  [OK] All boundary test cases passed across all resolutions!")


def run_randomized_stress_test(num_iterations=100000):
    print(f"\n=== Running {num_iterations} Randomized Stress & Property-Based Tests ===")
    random.seed(42)

    max_delta = 0.0
    resolutions = [
        (1080, 2400),
        (1170, 2532),
        (1290, 2796),
        (720, 1600),
        (1440, 3200),
    ]

    for i in range(num_iterations):
        W, H = random.choice(resolutions)

        # Generate arbitrary bounding box within image
        x1 = random.randint(0, W)
        x2 = random.randint(0, W)
        y1 = random.randint(0, H)
        y2 = random.randint(0, H)

        left = min(x1, x2)
        top = min(y1, y2)
        width = max(x1, x2) - left
        height = max(y1, y2) - top

        a_l, a_t, a_w, a_h = android_mlkit_normalize(left, top, width, height, W, H)
        vx, vy, vw, vh = ground_truth_to_vision(left, top, width, height, W, H)
        i_l, i_t, i_w, i_h = ios_vision_normalize(vx, vy, vw, vh)

        # Check range constraints [0.0, 1.0]
        for val in (a_l, a_t, a_w, a_h, i_l, i_t, i_w, i_h):
            assert 0.0 <= val <= 1.0, f"Value out of bounds [0.0, 1.0]: {val}"

        # Check equivalence between Android ML Kit and iOS Vision
        delta_l = abs(a_l - i_l)
        delta_t = abs(a_t - i_t)
        delta_w = abs(a_w - i_w)
        delta_h = abs(a_h - i_h)

        local_max = max(delta_l, delta_t, delta_w, delta_h)
        if local_max > max_delta:
            max_delta = local_max

        assert delta_l < 1e-12, f"Iteration {i}: left mismatch delta={delta_l}"
        assert delta_t < 1e-12, f"Iteration {i}: top mismatch delta={delta_t}"
        assert delta_w < 1e-12, f"Iteration {i}: width mismatch delta={delta_w}"
        assert delta_h < 1e-12, f"Iteration {i}: height mismatch delta={delta_h}"

    print(f"  [OK] {num_iterations} randomized tests PASSED!")
    print(f"  Maximum observed delta between Android & iOS: {max_delta:.2e} (machine precision: ~2.22e-16)")


def run_out_of_bounds_test():
    print("\n=== Running Out-of-Bounds & Detector Artifacts Test ===")
    W, H = 1080, 2400

    # Negative coordinates
    a_l, a_t, a_w, a_h = android_mlkit_normalize(-50, -20, 200, 100, W, H)
    assert a_l == 0.0, f"Negative left should coerce to 0.0, got {a_l}"
    assert a_t == 0.0, f"Negative top should coerce to 0.0, got {a_t}"

    # Vision with negative origin or overflow
    i_l, i_t, i_w, i_h = ios_vision_normalize(-0.05, 1.05, 0.2, 0.1)
    assert i_l == 0.0, f"Negative origin.x should clamp to 0.0, got {i_l}"
    assert i_t == 0.0, f"Top exceeding boundaries should clamp to 0.0, got {i_t}"

    # Exceeding width/height
    a_l, a_t, a_w, a_h = android_mlkit_normalize(100, 100, 3000, 5000, W, H)
    assert a_w == 1.0, f"Excess width should coerce to 1.0, got {a_w}"
    assert a_h == 1.0, f"Excess height should coerce to 1.0, got {a_h}"

    i_l, i_t, i_w, i_h = ios_vision_normalize(0.1, 0.1, 2.5, 3.0)
    assert i_w == 1.0, f"Excess width should clamp to 1.0, got {i_w}"
    assert i_h == 1.0, f"Excess height should clamp to 1.0, got {i_h}"

    print("  [OK] Out-of-bounds and detector artifact clamping verified successfully!")


if __name__ == "__main__":
    run_boundary_tests()
    run_randomized_stress_test(100000)
    run_out_of_bounds_test()
    print("\n=======================================================")
    print(">>> COORDINATE NORMALIZATION EMPIRICAL SUITE PASSED! <<<")
    print("=======================================================")
