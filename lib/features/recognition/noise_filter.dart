// lib/features/recognition/noise_filter.dart
import '../../core/native/native_bridge.g.dart';

class NoiseFilterConfig {
  static const double defaultStatusBarTop = 0.06;
  static const double dynamicIslandStatusBarTop = 0.075;
  static const double homeIndicatorTop = 0.95;
}

class NoiseFilterResult {
  final List<OcrTextLine> cleanedLines;
  final List<OcrTextLine> filteredNoiseLines;

  const NoiseFilterResult({
    required this.cleanedLines,
    required this.filteredNoiseLines,
  });
}

/// Filters mobile screen chrome, status bar, and home indicators from OCR lines
class NoiseFilter {
  static final List<RegExp> _uiChromePatterns = [
    RegExp(r'^(?:完成|关闭|返回|确定|知道了|返回商家|返回应用)$'),
    RegExp(r'^(?:查看账单详情|查看详情|账单详情|向商家索要发票|开发票|评价|去评价)$'),
    RegExp(r'^(?:设置|更多|分享|保存图片|添加到卡包)$'),
    RegExp(r'^(?:全部账单|账单服务|交易服务|对订单有疑惑|在此商户的交易|发起群收款|申请电子凭证|本服务由财付通提供|条形码|可在支持的商户扫码退款)$'),
    RegExp(r'(?:where.*belong|Oh and I need you|shadow of the sun|噢我需要你啊|我活在.*阴影中|而在这属于我的地方)', caseSensitive: false),
  ];

  static final RegExp _statusBarContentRegex = RegExp(
    r'(?:^\d{1,2}:\d{2}$|5G|4G|LTE|WiFi|中国移动|中国联通|中国电信|电量|\d{1,3}%)',
    caseSensitive: false,
  );

  /// Checks whether a specific line is classified as noise
  static bool isNoise(
    OcrTextLine line, {
    bool hasDynamicIsland = false,
    double topThreshold = NoiseFilterConfig.defaultStatusBarTop,
    double bottomThreshold = NoiseFilterConfig.homeIndicatorTop,
  }) {
    final text = line.text.trim();
    if (text.isEmpty) return true;

    final box = line.boundingBox;
    final clampedTop = box.top.clamp(0.0, 1.0);
    final clampedHeight = box.height.clamp(0.0, 1.0);

    final effectiveTopThreshold =
        hasDynamicIsland ? NoiseFilterConfig.dynamicIslandStatusBarTop : topThreshold;

    final isTopNoise = clampedTop < effectiveTopThreshold;
    final isBottomNoise = clampedTop >= bottomThreshold || (clampedTop + clampedHeight) >= 0.98;
    final isChromeNoise = _uiChromePatterns.any((p) => p.hasMatch(text));

    return isTopNoise || isBottomNoise || isChromeNoise;
  }

  /// Filters status bar and home indicator noise from raw OCR lines
  static NoiseFilterResult filter(
    List<OcrTextLine> rawLines, {
    bool hasDynamicIsland = false,
    double topThreshold = NoiseFilterConfig.defaultStatusBarTop,
    double bottomThreshold = NoiseFilterConfig.homeIndicatorTop,
  }) {
    // Dynamic island auto-detection heuristic: if top region < 0.075 contains status bar cues
    final effectiveDynamicIsland = hasDynamicIsland ||
        rawLines.any((line) {
          final box = line.boundingBox;
          final top = box.top.clamp(0.0, 1.0);
          return top < NoiseFilterConfig.dynamicIslandStatusBarTop &&
              _statusBarContentRegex.hasMatch(line.text.trim());
        });

    final cleaned = <OcrTextLine>[];
    final noise = <OcrTextLine>[];

    for (final line in rawLines) {
      if (isNoise(
        line,
        hasDynamicIsland: effectiveDynamicIsland,
        topThreshold: topThreshold,
        bottomThreshold: bottomThreshold,
      )) {
        noise.add(line);
      } else {
        cleaned.add(line);
      }
    }

    return NoiseFilterResult(cleanedLines: cleaned, filteredNoiseLines: noise);
  }

  /// Convenience method returning just the cleaned lines
  static List<OcrTextLine> filterNoise(
    List<OcrTextLine> lines, {
    bool hasDynamicIsland = false,
  }) {
    return filter(lines, hasDynamicIsland: hasDynamicIsland).cleanedLines;
  }
}
