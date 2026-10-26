import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';

/// Android ML Kit normalization logic (docs/Android实现方案.md line 310)
OcrBoundingBox normalizeAndroidMlKit({
  required double rectLeft,
  required double rectTop,
  required double rectWidth,
  required double rectHeight,
  required double imageWidth,
  required double imageHeight,
}) {
  return OcrBoundingBox(
    left: (rectLeft / imageWidth).clamp(0.0, 1.0),
    top: (rectTop / imageHeight).clamp(0.0, 1.0),
    width: (rectWidth / imageWidth).clamp(0.0, 1.0),
    height: (rectHeight / imageHeight).clamp(0.0, 1.0),
  );
}

/// iOS Apple Vision normalization logic (ios/Runner/Plugins/NativeCaptureHostApiImpl.swift line 131)
OcrBoundingBox normalizeIosVision({
  required double visionOriginX,
  required double visionOriginY,
  required double visionWidth,
  required double visionHeight,
}) {
  return OcrBoundingBox(
    left: visionOriginX.clamp(0.0, 1.0),
    top: (1.0 - visionOriginY - visionHeight).clamp(0.0, 1.0),
    width: visionWidth.clamp(0.0, 1.0),
    height: visionHeight.clamp(0.0, 1.0),
  );
}

void main() {
  group('Coordinate Normalization Cross-Platform Empirical Verification', () {
    const resolutions = [
      (1080.0, 1920.0),
      (1080.0, 2400.0),
      (1170.0, 2532.0),
      (1290.0, 2796.0),
    ];

    test('Boundary 1: Top-Left corner yields identical (0.0, 0.0) normalized coordinates', () {
      for (final (w, h) in resolutions) {
        const boxW = 200.0;
        const boxH = 100.0;

        final android = normalizeAndroidMlKit(
          rectLeft: 0.0,
          rectTop: 0.0,
          rectWidth: boxW,
          rectHeight: boxH,
          imageWidth: w,
          imageHeight: h,
        );

        // Apple Vision: origin at bottom-left
        // bottom = boxH, so distance from bottom is (h - boxH)
        final ios = normalizeIosVision(
          visionOriginX: 0.0,
          visionOriginY: (h - boxH) / h,
          visionWidth: boxW / w,
          visionHeight: boxH / h,
        );

        expect(android.left, 0.0);
        expect(android.top, 0.0);
        expect(ios.left, closeTo(0.0, 1e-12));
        expect(ios.top, closeTo(0.0, 1e-12));
        expect(android.left, closeTo(ios.left, 1e-12));
        expect(android.top, closeTo(ios.top, 1e-12));
        expect(android.width, closeTo(ios.width, 1e-12));
        expect(android.height, closeTo(ios.height, 1e-12));
      }
    });

    test('Boundary 2: Bottom-Right corner yields identical coordinates touching (1.0, 1.0)', () {
      for (final (w, h) in resolutions) {
        const boxW = 200.0;
        const boxH = 100.0;

        final android = normalizeAndroidMlKit(
          rectLeft: w - boxW,
          rectTop: h - boxH,
          rectWidth: boxW,
          rectHeight: boxH,
          imageWidth: w,
          imageHeight: h,
        );

        // Apple Vision: origin at bottom-left
        // bottom = h, so distance from bottom is 0.0
        final ios = normalizeIosVision(
          visionOriginX: (w - boxW) / w,
          visionOriginY: 0.0,
          visionWidth: boxW / w,
          visionHeight: boxH / h,
        );

        expect(android.left + android.width, closeTo(1.0, 1e-12));
        expect(android.top + android.height, closeTo(1.0, 1e-12));
        expect(ios.left + ios.width, closeTo(1.0, 1e-12));
        expect(ios.top + ios.height, closeTo(1.0, 1e-12));
        expect(android.left, closeTo(ios.left, 1e-12));
        expect(android.top, closeTo(ios.top, 1e-12));
      }
    });

    test('Boundary 3: Full screen covers entire [0.0, 0.0, 1.0, 1.0] box', () {
      for (final (w, h) in resolutions) {
        final android = normalizeAndroidMlKit(
          rectLeft: 0.0,
          rectTop: 0.0,
          rectWidth: w,
          rectHeight: h,
          imageWidth: w,
          imageHeight: h,
        );

        final ios = normalizeIosVision(
          visionOriginX: 0.0,
          visionOriginY: 0.0,
          visionWidth: 1.0,
          visionHeight: 1.0,
        );

        expect(android.left, 0.0);
        expect(android.top, 0.0);
        expect(android.width, 1.0);
        expect(android.height, 1.0);

        expect(ios.left, 0.0);
        expect(ios.top, 0.0);
        expect(ios.width, 1.0);
        expect(ios.height, 1.0);
      }
    });

    test('Boundary 4: Zero size degenerate box produces identical point coordinates', () {
      for (final (w, h) in resolutions) {
        final testPoints = [
          (0.0, 0.0),
          (w, h),
          (w / 2, h / 2),
          (0.0, h),
          (w, 0.0),
        ];

        for (final (px, py) in testPoints) {
          final android = normalizeAndroidMlKit(
            rectLeft: px,
            rectTop: py,
            rectWidth: 0.0,
            rectHeight: 0.0,
            imageWidth: w,
            imageHeight: h,
          );

          final ios = normalizeIosVision(
            visionOriginX: px / w,
            visionOriginY: (h - py) / h,
            visionWidth: 0.0,
            visionHeight: 0.0,
          );

          expect(android.width, 0.0);
          expect(android.height, 0.0);
          expect(ios.width, 0.0);
          expect(ios.height, 0.0);
          expect(android.left, closeTo(ios.left, 1e-12));
          expect(android.top, closeTo(ios.top, 1e-12));
        }
      }
    });

    test('Property-based randomized stress test across 5000 random boxes', () {
      final rand = Random(42);
      const w = 1170.0;
      const h = 2532.0;

      for (var i = 0; i < 5000; i++) {
        final x1 = rand.nextDouble() * w;
        final x2 = rand.nextDouble() * w;
        final y1 = rand.nextDouble() * h;
        final y2 = rand.nextDouble() * h;

        final left = min(x1, x2);
        final top = min(y1, y2);
        final width = max(x1, x2) - left;
        final height = max(y1, y2) - top;

        final android = normalizeAndroidMlKit(
          rectLeft: left,
          rectTop: top,
          rectWidth: width,
          rectHeight: height,
          imageWidth: w,
          imageHeight: h,
        );

        final ios = normalizeIosVision(
          visionOriginX: left / w,
          visionOriginY: (h - (top + height)) / h,
          visionWidth: width / w,
          visionHeight: height / h,
        );

        expect(android.left, inInclusiveRange(0.0, 1.0));
        expect(android.top, inInclusiveRange(0.0, 1.0));
        expect(android.width, inInclusiveRange(0.0, 1.0));
        expect(android.height, inInclusiveRange(0.0, 1.0));

        expect(android.left, closeTo(ios.left, 1e-12));
        expect(android.top, closeTo(ios.top, 1e-12));
        expect(android.width, closeTo(ios.width, 1e-12));
        expect(android.height, closeTo(ios.height, 1e-12));
      }
    });
  });
}
