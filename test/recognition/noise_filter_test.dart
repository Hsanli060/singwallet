// test/recognition/noise_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/features/recognition/noise_filter.dart';

void main() {
  group('NoiseFilter geometric and semantic filtering', () {
    test('Standard status bar line at top 0.03 is filtered out', () {
      final line = OcrTextLine(
        text: '09:41',
        boundingBox: OcrBoundingBox(left: 0.05, top: 0.03, width: 0.1, height: 0.02),
      );
      expect(NoiseFilter.isNoise(line), isTrue);
    });

    test('Dynamic island line at top 0.065 is filtered when hasDynamicIsland is true', () {
      final line = OcrTextLine(
        text: '中国移动 5G',
        boundingBox: OcrBoundingBox(left: 0.75, top: 0.065, width: 0.2, height: 0.02),
      );
      expect(NoiseFilter.isNoise(line, hasDynamicIsland: false), isFalse);
      expect(NoiseFilter.isNoise(line, hasDynamicIsland: true), isTrue);
    });

    test('Dynamic island heuristic auto-detects status content near top', () {
      final statusLine = OcrTextLine(
        text: '5G 100%',
        boundingBox: OcrBoundingBox(left: 0.8, top: 0.065, width: 0.15, height: 0.015),
      );
      final normalLine = OcrTextLine(
        text: '微信支付',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.15, width: 0.3, height: 0.03),
      );

      final result = NoiseFilter.filter([statusLine, normalLine]);
      expect(result.filteredNoiseLines.length, 1);
      expect(result.filteredNoiseLines.first.text, '5G 100%');
      expect(result.cleanedLines.length, 1);
      expect(result.cleanedLines.first.text, '微信支付');
    });

    test('Home indicator at top 0.96 is filtered out', () {
      final line = OcrTextLine(
        text: '一',
        boundingBox: OcrBoundingBox(left: 0.4, top: 0.96, width: 0.2, height: 0.01),
      );
      expect(NoiseFilter.isNoise(line), isTrue);
    });

    test('Common UI chrome buttons (查看账单详情, 完成) are filtered as noise', () {
      final chromeLine1 = OcrTextLine(
        text: '查看账单详情',
        boundingBox: OcrBoundingBox(left: 0.3, top: 0.85, width: 0.4, height: 0.04),
      );
      final chromeLine2 = OcrTextLine(
        text: '完成',
        boundingBox: OcrBoundingBox(left: 0.4, top: 0.90, width: 0.2, height: 0.04),
      );
      expect(NoiseFilter.isNoise(chromeLine1), isTrue);
      expect(NoiseFilter.isNoise(chromeLine2), isTrue);
    });

    test('Normal receipt content in the main viewport is strictly retained', () {
      final headerLine = OcrTextLine(
        text: '海底捞火锅',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.12, width: 0.5, height: 0.04),
      );
      final amountLine = OcrTextLine(
        text: '¥ 328.00',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.25, width: 0.4, height: 0.06),
      );
      final bottomDetailLine = OcrTextLine(
        text: '交易时间: 2026-10-22 19:30:15',
        boundingBox: OcrBoundingBox(left: 0.1, top: 0.91, width: 0.7, height: 0.03),
      );

      final result = NoiseFilter.filter([headerLine, amountLine, bottomDetailLine]);
      expect(result.cleanedLines.length, 3);
      expect(result.filteredNoiseLines.isEmpty, isTrue);
    });
  });
}
