// test/recognition/merchant_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/features/recognition/merchant_normalizer.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';

void main() {
  group('MerchantNormalizer extraction and normalization', () {
    test('Prefix stripping: 特约商户-瑞幸咖啡（国贸店） -> 瑞幸咖啡', () {
      final norm = MerchantNormalizer.normalize('特约商户-瑞幸咖啡（国贸店）');
      expect(norm, '瑞幸咖啡');
    });

    test('Prefix stripping: 扫码付款给 麦当劳三里屯店 -> 麦当劳', () {
      final norm = MerchantNormalizer.normalize('扫码付款给 麦当劳三里屯店');
      expect(norm, '麦当劳');
    });

    test('Prefix stripping: 向商户付款-肯德基 -> 肯德基', () {
      final norm = MerchantNormalizer.normalize('向商户付款-肯德基');
      expect(norm, '肯德基');
    });

    test('Prefix stripping: 付款给 滴滴出行 -> 滴滴出行', () {
      final norm = MerchantNormalizer.normalize('付款给 滴滴出行');
      expect(norm, '滴滴出行');
    });

    test('Suffix stripping: 星巴克咖啡（特约商户） -> 星巴克咖啡', () {
      final norm = MerchantNormalizer.normalize('星巴克咖啡（特约商户）');
      expect(norm, '星巴克咖啡');
    });

    test('Label extraction from lines: 收款方：麦当劳（王府井餐厅）', () {
      final lines = [
        OcrTextLine(
          text: '微信支付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.3, height: 0.03),
        ),
        OcrTextLine(
          text: '收款方：麦当劳（王府井餐厅）',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.6, height: 0.04),
        ),
      ];

      final res = MerchantNormalizer.extractAndNormalize(lines);
      expect(res.rawMerchant, '麦当劳（王府井餐厅）');
      expect(res.normalizedMerchant, '麦当劳');
      expect(res.evidence, isNotNull);
      expect(res.issues.isEmpty, isTrue);
    });

    test('Prominent header fallback when no label is present', () {
      final lines = [
        OcrTextLine(
          text: '微信支付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.3, height: 0.03),
        ),
        OcrTextLine(
          text: '支付成功',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.15, width: 0.3, height: 0.03),
        ),
        OcrTextLine(
          text: '海底捞火锅',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.25, width: 0.5, height: 0.04),
        ),
        OcrTextLine(
          text: '¥328.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.35, width: 0.3, height: 0.05),
        ),
      ];

      final res = MerchantNormalizer.extractAndNormalize(lines);
      expect(res.rawMerchant, '海底捞火锅');
      expect(res.normalizedMerchant, '海底捞火锅');
      expect(res.issues.isEmpty, isTrue);
    });

    test('Missing merchant flags MISSING_MERCHANT issue', () {
      final lines = [
        OcrTextLine(
          text: '支付成功',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.3, height: 0.03),
        ),
        OcrTextLine(
          text: '¥100.00',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.03),
        ),
      ];

      final res = MerchantNormalizer.extractAndNormalize(lines);
      expect(res.rawMerchant, isNull);
      expect(res.issues.any((i) => i.code == ValidationIssue.missingMerchant), isTrue);
    });
  });
}
