// lib/features/recognition/merchant_normalizer.dart
import '../../core/native/native_bridge.g.dart';
import 'models/field_evidence.dart';
import 'models/validation_issue.dart';

class MerchantParseResult {
  final String? rawMerchant;
  final String? normalizedMerchant;
  final FieldEvidence? evidence;
  final List<ValidationIssue> issues;

  const MerchantParseResult({
    this.rawMerchant,
    this.normalizedMerchant,
    this.evidence,
    this.issues = const [],
  });
}

/// Extracts raw merchant names from OCR lines and normalizes standard prefixes/suffixes
class MerchantNormalizer {
  static final List<RegExp> _labelPatterns = [
    RegExp(r'(?:收款方|商户全[称你]|商户[简筒]称|商户名称|收款商户|对方名称|交易对方|收款人|商户|商品)[：:\s]+([^\n]+)'),
    RegExp(r'(?:特约商户|扫码付款给|向商户付款|付款给|转账给|向|支付给)[：:\s\-——]*([^\n]+)'),
  ];

  static final List<String> _prefixKeywords = [
    '收款方：', '收款方:', '商户全称：', '商户全称:', '商户名称：', '商户名称:',
    '对方名称：', '对方名称:', '收款商户：', '收款商户:', '商户：', '商户:',
    '特约商户 - ', '特约商户-', '特约商户——', '特约商户 ', '特约商户',
    '扫码付款 - ', '扫码付款-', '扫码付款给 ', '扫码付款给', '扫码付款',
    '向商户付款 - ', '向商户付款-', '向商户付款 ', '向商户付款',
    '扫码消费 - ', '扫码消费',
    '付款给 ', '付款给', '转账给 ', '转账给', '向 ', '向', '支付给 ', '支付给',
    '个人收款码 - ', '赞赏码 - ',
  ];

  static final List<String> _suffixKeywords = [
    '（特约商户）', '(特约商户)',
    '（个体工商户）', '(个体工商户)',
    '（扫码付款）', '(扫码付款)',
    '（二维码收款）', '(二维码收款)',
    ' - 微信支付', '- 微信支付',
    ' - 支付宝', '- 支付宝',
  ];

  static final RegExp _systemKeywords = RegExp(
    r'(?:微信支付|支付宝|云闪付|支付成功|交易成功|付款成功|扣款成功|待支付|处理中|支付失败|退款成功|账单详情|查看详情|当前状态|全部账单|账单服务|交易服务|服务|会员|交易详情|收单[机构枳构]?|完成|关闭|返回|商户单号|交易单号|创建时间|支付时间|支付方[式芤]|实付|原价|优惠|余额)',
  );

  static final List<String> _knownBrands = [
    '海底捞火锅', '星巴克咖啡', '瑞幸咖啡', '奈雪的茶', '蜜雪冰城', '霸王茶姬',
    '麦当劳', '肯德基', '汉堡王', '星巴克', '瑞幸', '喜茶', '奈雪',
    '茶百道', '古茗', '益禾堂', '海底捞', '必胜客', '赛百味', '达美乐',
    '7-Eleven', '便利蜂', '美宜佳', '盒马鲜生', '山姆会员店', '华润万家',
    '永辉超市', '物美超市', '全家', '罗森', '盒马', '山姆', '沃尔玛',
    '大润发', '永辉', '物美', '屈臣氏', '优衣库', '滴滴出行', '滴滴',
  ];

  /// Pure normalization algorithm for a raw merchant string
  static String normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    // 1. Strip known prefixes (longest first)
    bool changed = true;
    while (changed) {
      changed = false;
      for (final prefix in _prefixKeywords) {
        if (s.startsWith(prefix)) {
          s = s.substring(prefix.length).trim();
          changed = true;
          break;
        }
      }
    }

    // 2. Strip known suffix keywords
    for (final suffix in _suffixKeywords) {
      if (s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length).trim();
      }
    }

    // 3. Strip branch/store bracket patterns like （三里屯店）, (国贸店), （王府井餐厅）
    s = s.replaceAll(RegExp(r'[\(（][^()（）]*(?:店|餐厅|分店|支店|分公司|分部)[\)）]'), '').trim();

    // 4. Known brand matching: if s starts with a known brand and remainder is branch info (e.g. 三里屯店)
    for (final brand in _knownBrands) {
      if (s.startsWith(brand) && s.length > brand.length) {
        final remainder = s.substring(brand.length).trim();
        if (remainder.endsWith('店') ||
            remainder.endsWith('餐厅') ||
            remainder.endsWith('分店') ||
            remainder.endsWith('支店') ||
            remainder.isEmpty) {
          s = brand;
          break;
        }
      }
    }

    // 5. Space separated branch suffix (e.g. "某某酒楼 三里屯店")
    s = s.replaceAll(RegExp(r'[\s]+[^()（）\s]*(?:店|餐厅|分店|支店)$'), '').trim();

    // 6. Clean trailing/leading dashes or punctuation
    s = s.replaceAll(RegExp(r'^[\-—\s]+|[\-—\s]+$'), '').trim();

    return s;
  }

  /// Extracts raw merchant and normalizes it from OCR text lines
  static MerchantParseResult extractAndNormalize(List<OcrTextLine> lines) {
    String? rawMerchant;
    FieldEvidence? evidence;
    final issues = <ValidationIssue>[];

    // 1. Look for explicit label pattern
    for (final line in lines) {
      final text = line.text.trim();
      for (final p in _labelPatterns) {
        final m = p.firstMatch(text);
        if (m != null) {
          final candidate = m.group(1)?.trim();
          if (candidate != null && candidate.isNotEmpty && !_systemKeywords.hasMatch(candidate)) {
            rawMerchant = candidate;
            evidence = FieldEvidence(
              rawText: text,
              matchedSubstring: m.group(0) ?? candidate,
              boundingBox: line.boundingBox,
              confidence: line.confidence,
              source: 'ocr_extracted',
            );
            break;
          }
        }
      }
      if (rawMerchant != null) break;
    }

    // 2. If no labeled merchant found, look for prominent header text line
    if (rawMerchant == null) {
      for (final line in lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        if (text.length < 2) continue;
        if (line.boundingBox.top < 0.15) continue; // Skip floating top lyrics or status area

        // Skip system markers, numbers, dates, amounts
        if (_systemKeywords.hasMatch(text)) continue;
        if (RegExp(r'^[0-9.,¥￥$€£+-:\s]+$').hasMatch(text)) continue;
        if (RegExp(r'\d{4}[-/年]\d{1,2}').hasMatch(text)) continue;
        if (RegExp(r'^\d{10,}$').hasMatch(text)) continue; // order ID

        // Accept candidate line as merchant
        rawMerchant = text;
        evidence = FieldEvidence(
          rawText: text,
          matchedSubstring: text,
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        break;
      }
    }

    if (rawMerchant == null || rawMerchant.trim().isEmpty) {
      issues.add(ValidationIssue.missingMerchantIssue());
      return MerchantParseResult(
        rawMerchant: null,
        normalizedMerchant: null,
        evidence: null,
        issues: issues,
      );
    }

    final normalized = normalize(rawMerchant);

    return MerchantParseResult(
      rawMerchant: rawMerchant,
      normalizedMerchant: normalized.isNotEmpty ? normalized : rawMerchant,
      evidence: evidence,
      issues: issues,
    );
  }
}
