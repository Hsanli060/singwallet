// test/recognition/channel_status_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/features/recognition/channel_status_parser.dart';
import 'package:singwallet/features/recognition/models/validation_issue.dart';

void main() {
  group('ChannelStatusParser channel and status identification', () {
    test('WeChat bill with WeChat marker and instrument', () {
      final lines = [
        OcrTextLine(
          text: '微信支付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.2, height: 0.03),
        ),
        OcrTextLine(
          text: '支付成功',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.2, height: 0.03),
        ),
        OcrTextLine(
          text: '支付方式：零钱通',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.6, width: 0.4, height: 0.03),
        ),
      ];

      final result = ChannelStatusParser.parse(lines);
      expect(result.paymentChannel, 'wechat');
      expect(result.paymentStatus, 'SUCCESS');
      expect(result.type, 'expense');
      expect(result.paymentMethodLabel, '零钱通');
      expect(result.issues.isEmpty, isTrue);
    });

    test('Alipay bill with Alipay marker', () {
      final lines = [
        OcrTextLine(
          text: '支付宝买单',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.2, height: 0.03),
        ),
        OcrTextLine(
          text: '交易成功',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.2, height: 0.03),
        ),
      ];

      final result = ChannelStatusParser.parse(lines);
      expect(result.paymentChannel, 'alipay');
      expect(result.paymentStatus, 'SUCCESS');
      expect(result.type, 'expense');
    });

    test('UnionPay bill with UnionPay marker', () {
      final lines = [
        OcrTextLine(
          text: '云闪付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.2, height: 0.03),
        ),
        OcrTextLine(
          text: '付款成功',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.2, height: 0.03),
        ),
      ];

      final result = ChannelStatusParser.parse(lines);
      expect(result.paymentChannel, 'unionpay');
      expect(result.paymentStatus, 'SUCCESS');
    });

    test('Pending status raises validation issue and sets status to PENDING', () {
      final lines = [
        OcrTextLine(
          text: '微信支付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.2, height: 0.03),
        ),
        OcrTextLine(
          text: '待支付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.2, height: 0.03),
        ),
      ];

      final result = ChannelStatusParser.parse(lines);
      expect(result.paymentStatus, 'PENDING');
      expect(result.issues.length, 1);
      expect(result.issues.first.code, ValidationIssue.paymentNotSuccess);
    });

    test('Failed status raises validation issue and sets status to FAILED', () {
      final lines = [
        OcrTextLine(
          text: '支付失败',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.2, height: 0.03),
        ),
      ];

      final result = ChannelStatusParser.parse(lines);
      expect(result.paymentStatus, 'FAILED');
      expect(result.issues.length, 1);
    });

    test('Refunded status sets type to refund and paymentStatus to REFUNDED', () {
      final lines = [
        OcrTextLine(
          text: '微信支付',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.2, height: 0.03),
        ),
        OcrTextLine(
          text: '退款成功',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.2, width: 0.2, height: 0.03),
        ),
      ];

      final result = ChannelStatusParser.parse(lines);
      expect(result.paymentStatus, 'REFUNDED');
      expect(result.type, 'refund');
    });
  });
}
