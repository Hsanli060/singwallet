// lib/features/recognition/channel_status_parser.dart
import '../../core/native/native_bridge.g.dart';
import 'models/field_evidence.dart';
import 'models/validation_issue.dart';

class ChannelStatusResult {
  final String paymentChannel; // 'wechat', 'alipay', 'unionpay', 'bank_card', 'other'
  final String paymentStatus; // 'SUCCESS', 'PENDING', 'FAILED', 'REFUNDED'
  final String type; // 'expense', 'refund', 'income', 'transfer'
  final String? paymentMethodLabel;
  final FieldEvidence? channelEvidence;
  final FieldEvidence? statusEvidence;
  final List<ValidationIssue> issues;

  const ChannelStatusResult({
    required this.paymentChannel,
    required this.paymentStatus,
    this.type = 'expense',
    this.paymentMethodLabel,
    this.channelEvidence,
    this.statusEvidence,
    this.issues = const [],
  });
}

/// Identifies payment channel, transaction status, and payment method instrument
class ChannelStatusParser {
  static final RegExp _paymentMethodRegex = RegExp(
    r'(?:支付方式|付款方式|支付渠道|付款工具)[：:\s]*([^\n]+)',
  );

  static final List<String> _bankNames = [
    '招商银行', '工商银行', '建设银行', '农业银行', '中国银行', '交通银行', '邮政储蓄',
    '中信银行', '光大银行', '华夏银行', '民生银行', '广发银行', '平安银行', '浦发银行',
    '兴业银行', '北京银行', '上海银行', '微众银行', '网商银行',
  ];

  static ChannelStatusResult parse(List<OcrTextLine> lines) {
    String paymentChannel = 'other';
    String paymentStatus = 'SUCCESS';
    String type = 'expense';
    String? paymentMethodLabel;
    FieldEvidence? channelEvidence;
    FieldEvidence? statusEvidence;
    final issues = <ValidationIssue>[];

    // 1. Scan lines for payment method label (e.g. 支付方式：零钱通)
    for (final line in lines) {
      final text = line.text.trim();
      final methodMatch = _paymentMethodRegex.firstMatch(text);
      if (methodMatch != null) {
        paymentMethodLabel = methodMatch.group(1)?.trim();
        break;
      }
    }

    // 2. Scan lines for channel clues
    for (final line in lines) {
      final text = line.text.trim();

      // WeChat Pay
      if (text.contains('微信支付') ||
          text.contains('微信买单') ||
          text.contains('微信转账') ||
          text.contains('微信红包') ||
          text.contains('微信收款商业版') ||
          text.contains('微信支付凭证') ||
          text.contains('财付通') ||
          text.contains('WeChat Pay')) {
        paymentChannel = 'wechat';
        channelEvidence = FieldEvidence(
          rawText: text,
          matchedSubstring: text.contains('财付通') ? '财付通' : '微信支付',
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        break;
      }

      // Alipay
      if (text.contains('支付宝') ||
          text.contains('支付宝支付') ||
          text.contains('支付宝买单') ||
          text.contains('支付宝交易号') ||
          text.contains('Alipay')) {
        paymentChannel = 'alipay';
        channelEvidence = FieldEvidence(
          rawText: text,
          matchedSubstring: '支付宝',
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        break;
      }

      // UnionPay
      if (text.contains('云闪付') ||
          text.contains('银联') ||
          text.contains('中国银联') ||
          text.contains('银联商务') ||
          text.contains('UnionPay')) {
        paymentChannel = 'unionpay';
        channelEvidence = FieldEvidence(
          rawText: text,
          matchedSubstring: '银联',
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        break;
      }
    }

    // Secondary channel inference from paymentMethodLabel or instrument keywords if channel still 'other'
    if (paymentChannel == 'other') {
      // First pass: check for explicit digital wallet instruments (takes precedence over acquiring banks)
      for (final line in lines) {
        final text = line.text.trim();
        if (text.contains('零钱') || text.contains('零钱通')) {
          paymentChannel = 'wechat';
          paymentMethodLabel ??= text.contains('零钱通') ? '零钱通' : '零钱';
          break;
        }
        if (text.contains('余额宝') || text.contains('花呗')) {
          paymentChannel = 'alipay';
          paymentMethodLabel ??= text.contains('花呗') ? '花呗' : '余额宝';
          break;
        }
      }

      // Second pass: bank cards (ignoring acquirer lines)
      if (paymentChannel == 'other') {
        for (final line in lines) {
          final text = line.text.trim();
          if (text.contains('收单机构') || text.contains('收单')) continue;
          for (final bank in _bankNames) {
            if (text.contains(bank)) {
              paymentChannel = 'bank_card';
              paymentMethodLabel ??= text;
              break;
            }
          }
          if (paymentChannel != 'other') break;
        }
      }
    }

    // 3. Scan lines for status clues
    for (final line in lines) {
      final text = line.text.trim();

      // Refunded
      if (text.contains('退款成功') ||
          text.contains('已退款') ||
          text.contains('退款详情') ||
          text.contains('部分退款')) {
        paymentStatus = 'REFUNDED';
        type = 'refund';
        statusEvidence = FieldEvidence(
          rawText: text,
          matchedSubstring: '退款成功',
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        break;
      }

      // Pending
      if (text.contains('待支付') ||
          text.contains('待付款') ||
          text.contains('处理中') ||
          text.contains('转账处理中')) {
        paymentStatus = 'PENDING';
        statusEvidence = FieldEvidence(
          rawText: text,
          matchedSubstring: text,
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        issues.add(ValidationIssue.nonSuccessStatusIssue('PENDING'));
        break;
      }

      // Failed
      if (text.contains('支付失败') ||
          text.contains('交易失败') ||
          text.contains('扣款失败') ||
          text.contains('交易关闭')) {
        paymentStatus = 'FAILED';
        statusEvidence = FieldEvidence(
          rawText: text,
          matchedSubstring: text,
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        issues.add(ValidationIssue.nonSuccessStatusIssue('FAILED'));
        break;
      }

      // Success
      if (text.contains('支付成功') ||
          text.contains('交易成功') ||
          text.contains('付款成功') ||
          text.contains('扣款成功')) {
        paymentStatus = 'SUCCESS';
        type = 'expense';
        statusEvidence = FieldEvidence(
          rawText: text,
          matchedSubstring: text,
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        break;
      }
    }

    return ChannelStatusResult(
      paymentChannel: paymentChannel,
      paymentStatus: paymentStatus,
      type: type,
      paymentMethodLabel: paymentMethodLabel,
      channelEvidence: channelEvidence,
      statusEvidence: statusEvidence,
      issues: issues,
    );
  }
}
