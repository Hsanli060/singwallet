// lib/features/recognition/amount_parser.dart
import '../../core/native/native_bridge.g.dart';
import '../../core/utils/currency_utils.dart';
import 'models/field_evidence.dart';
import 'models/validation_issue.dart';

class ParsedAmountResult {
  final int? paidAmountMinor;
  final int? originalAmountMinor;
  final int? discountMinor;
  final int? feeMinor;
  final FieldEvidence? paidEvidence;
  final FieldEvidence? originalEvidence;
  final FieldEvidence? discountEvidence;
  final FieldEvidence? feeEvidence;
  final List<ValidationIssue> issues;

  const ParsedAmountResult({
    this.paidAmountMinor,
    this.originalAmountMinor,
    this.discountMinor,
    this.feeMinor,
    this.paidEvidence,
    this.originalEvidence,
    this.discountEvidence,
    this.feeEvidence,
    this.issues = const [],
  });
}

class _AmountCandidate {
  final int amountMinor;
  final String rawText;
  final String matchedSubstring;
  final OcrBoundingBox boundingBox;
  final double? confidence;
  final String labelKind; // 'paid', 'original', 'discount', 'fee', 'standalone'

  const _AmountCandidate({
    required this.amountMinor,
    required this.rawText,
    required this.matchedSubstring,
    required this.boundingBox,
    this.confidence,
    required this.labelKind,
  });
}

/// Disambiguates, cleans, and converts amounts from OCR text lines
class AmountParser {
  static final RegExp _excludedKeywordsRegex = RegExp(
    r'(?:零钱余额|账户余额|可用余额|账户可用余额|月累计|累计支出|当前余额|余额)',
  );

  static final RegExp _paidLabelRegex = RegExp(
    r'(?:实付金额|实付款|实付|支付金额|付款金额|扣款金额|扣款|支出金额|金额)[：:\s]*[-+]?[¥￥$€£]?\s*([0-9.,OlISsBbDd!|]+)',
  );

  static final RegExp _originalLabelRegex = RegExp(
    r'(?:商品原价|原价|订单金额|商品金额|应付金额|票价)[：:\s]*[-+]?[¥￥$€£]?\s*([0-9.,OlISsBbDd!|]+)',
  );

  static final RegExp _discountLabelRegex = RegExp(
    r'(?:优惠减免|店铺优惠|优惠|折扣|立减|红包抵扣|满减|代金券)[：:\s]*[-+]?[¥￥$€£]?\s*([0-9.,OlISsBbDd!|]+)',
  );

  static final RegExp _feeLabelRegex = RegExp(
    r'(?:含手续费|手续费|服务费)[：:\s]*[-+]?[¥￥$€£]?\s*([0-9.,OlISsBbDd!|]+)',
  );

  static final RegExp _standaloneRegex = RegExp(
    r'(?:^|[\s¥￥$€£+-])([+-]?[¥￥$€£]?\s*[0-9.,OlISsBbDd!|]+)(?:$|[\s元])',
  );

  /// Performs character repair on optical misidentifications in numbers
  static String repairOcrNumbers(String input) {
    var s = input.trim();

    // Full-width numbers and symbols
    s = s
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9')
        .replaceAll('￥', '¥')
        .replaceAll('。', '.')
        .replaceAll('．', '.')
        .replaceAll('·', '.')
        .replaceAll('，', ',');

    // Character repairs: O/o -> 0, l/I/i/|/! -> 1, S/s -> 5, B -> 8
    // Iterative convergence loop to repair consecutive and trailing confusion characters
    var prev = '';
    while (prev != s) {
      prev = s;
      s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Oo]'), (m) => '${m[1]}0');
      s = s.replaceAllMapped(RegExp(r'[Oo]([0-9.¥￥$€£+-])'), (m) => '0${m[1]}');
      s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[lIi|!]'), (m) => '${m[1]}1');
      s = s.replaceAllMapped(RegExp(r'[lIi|!]([0-9.¥￥$€£+-])'), (m) => '1${m[1]}');
      s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])[Ss]'), (m) => '${m[1]}5');
      s = s.replaceAllMapped(RegExp(r'[Ss]([0-9.¥￥$€£+-])'), (m) => '5${m[1]}');
      s = s.replaceAllMapped(RegExp(r'([0-9.¥￥$€£+-])B'), (m) => '${m[1]}8');
      s = s.replaceAllMapped(RegExp(r'B([0-9.¥￥$€£+-])'), (m) => '8${m[1]}');
    }

    // Comma disambiguation: 28,90 -> 28.90
    if (s.contains(',') && !s.contains('.')) {
      if (RegExp(r',\d{2}$').hasMatch(s)) {
        s = s.replaceAll(',', '.');
      }
    }

    return s;
  }

  /// Extracts number token and converts to minor units (cents)
  static int? extractMinorUnits(String rawStr) {
    final repaired = repairOcrNumbers(rawStr);
    // Distorted amount with multiple decimal points (e.g. 12.34.56) is invalid
    if (repaired.split('.').length > 2) {
      return null;
    }
    // Find numeric pattern that can contain commas and decimal point
    final numMatch = RegExp(r'[-+]?[\d,]+(?:\.\d+)?').firstMatch(repaired);
    if (numMatch == null) return null;

    final token = numMatch.group(0)!;
    try {
      final cents = CurrencyUtils.parseToMinorUnits(
        token,
        allowNegative: true,
        stripCurrencySymbols: true,
      );
      return cents.abs(); // Financial amounts stored as positive cents
    } catch (_) {
      return null;
    }
  }

  /// Parses all amount types from OCR text lines
  static ParsedAmountResult parse(List<OcrTextLine> lines) {
    final paidCandidates = <_AmountCandidate>[];
    final originalCandidates = <_AmountCandidate>[];
    final discountCandidates = <_AmountCandidate>[];
    final feeCandidates = <_AmountCandidate>[];
    final standaloneCandidates = <_AmountCandidate>[];
    final issues = <ValidationIssue>[];

    for (final line in lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;

      // Check if line is strictly an excluded balance line without "实付"
      final isExcludedBalance = _excludedKeywordsRegex.hasMatch(text) &&
          !text.contains('实付') &&
          !text.contains('实付款');
      if (isExcludedBalance) {
        continue;
      }

      // 1. Check Paid Label
      final paidMatch = _paidLabelRegex.firstMatch(text);
      if (paidMatch != null) {
        final rawNum = paidMatch.group(1);
        if (rawNum != null) {
          final cents = extractMinorUnits(rawNum);
          if (cents != null) {
            paidCandidates.add(_AmountCandidate(
              amountMinor: cents,
              rawText: text,
              matchedSubstring: paidMatch.group(0) ?? rawNum,
              boundingBox: line.boundingBox,
              confidence: line.confidence,
              labelKind: 'paid',
            ));
            continue;
          }
        }
      }

      // 2. Check Original Label
      final origMatch = _originalLabelRegex.firstMatch(text);
      if (origMatch != null) {
        final rawNum = origMatch.group(1);
        if (rawNum != null) {
          final cents = extractMinorUnits(rawNum);
          if (cents != null) {
            originalCandidates.add(_AmountCandidate(
              amountMinor: cents,
              rawText: text,
              matchedSubstring: origMatch.group(0) ?? rawNum,
              boundingBox: line.boundingBox,
              confidence: line.confidence,
              labelKind: 'original',
            ));
            continue;
          }
        }
      }

      // 3. Check Discount Label
      final discMatch = _discountLabelRegex.firstMatch(text);
      if (discMatch != null) {
        final rawNum = discMatch.group(1);
        if (rawNum != null) {
          final cents = extractMinorUnits(rawNum);
          if (cents != null) {
            discountCandidates.add(_AmountCandidate(
              amountMinor: cents,
              rawText: text,
              matchedSubstring: discMatch.group(0) ?? rawNum,
              boundingBox: line.boundingBox,
              confidence: line.confidence,
              labelKind: 'discount',
            ));
            continue;
          }
        }
      }

      // 4. Check Fee Label
      final feeMatch = _feeLabelRegex.firstMatch(text);
      if (feeMatch != null) {
        final rawNum = feeMatch.group(1);
        if (rawNum != null) {
          final cents = extractMinorUnits(rawNum);
          if (cents != null) {
            feeCandidates.add(_AmountCandidate(
              amountMinor: cents,
              rawText: text,
              matchedSubstring: feeMatch.group(0) ?? rawNum,
              boundingBox: line.boundingBox,
              confidence: line.confidence,
              labelKind: 'fee',
            ));
            continue;
          }
        }
      }

      // 5. Standalone amount candidate (e.g. "¥328.00" or "-18.50")
      // Only consider if line is not an order ID or date
      final isDateOrId = text.contains(':') ||
          text.contains('-') && text.length > 10 ||
          RegExp(r'\d{6,}').hasMatch(text); // potential order ID
      if (!isDateOrId) {
        final standaloneMatch = _standaloneRegex.firstMatch(text);
        if (standaloneMatch != null) {
          final rawNum = standaloneMatch.group(1);
          if (rawNum != null) {
            final cents = extractMinorUnits(rawNum);
            if (cents != null) {
              standaloneCandidates.add(_AmountCandidate(
                amountMinor: cents,
                rawText: text,
                matchedSubstring: standaloneMatch.group(0) ?? rawNum,
                boundingBox: line.boundingBox,
                confidence: line.confidence,
                labelKind: 'standalone',
              ));
            }
          }
        }
      }
    }

    _AmountCandidate? selectedPaid;
    FieldEvidence? paidEvidence;
    FieldEvidence? originalEvidence;
    FieldEvidence? discountEvidence;
    FieldEvidence? feeEvidence;

    // Disambiguate paid amount
    if (paidCandidates.isNotEmpty) {
      // Check if multiple conflicting values in paidCandidates
      final distinctValues = paidCandidates.map((c) => c.amountMinor).toSet();
      if (distinctValues.length > 1) {
        issues.add(ValidationIssue.multipleAmountsIssue());
      }
      selectedPaid = paidCandidates.first;
    } else if (standaloneCandidates.isNotEmpty) {
      final distinctValues = standaloneCandidates.map((c) => c.amountMinor).toSet();
      if (distinctValues.length > 1) {
        issues.add(ValidationIssue.multipleAmountsIssue());
      }
      selectedPaid = standaloneCandidates.first;
    }

    int? finalPaidAmount;
    if (selectedPaid != null) {
      if (selectedPaid.amountMinor <= 0) {
        issues.add(ValidationIssue.zeroAmountIssue());
        finalPaidAmount = null; // Zero amount cannot be committed
      } else {
        finalPaidAmount = selectedPaid.amountMinor;
      }
      paidEvidence = FieldEvidence(
        rawText: selectedPaid.rawText,
        matchedSubstring: selectedPaid.matchedSubstring,
        boundingBox: selectedPaid.boundingBox,
        confidence: selectedPaid.confidence,
        source: 'ocr_extracted',
      );
    } else {
      issues.add(ValidationIssue.missingAmountIssue());
    }

    if (originalCandidates.isNotEmpty) {
      final orig = originalCandidates.first;
      originalEvidence = FieldEvidence(
        rawText: orig.rawText,
        matchedSubstring: orig.matchedSubstring,
        boundingBox: orig.boundingBox,
        confidence: orig.confidence,
        source: 'ocr_extracted',
      );
    }

    if (discountCandidates.isNotEmpty) {
      final disc = discountCandidates.first;
      discountEvidence = FieldEvidence(
        rawText: disc.rawText,
        matchedSubstring: disc.matchedSubstring,
        boundingBox: disc.boundingBox,
        confidence: disc.confidence,
        source: 'ocr_extracted',
      );
    }

    if (feeCandidates.isNotEmpty) {
      final fee = feeCandidates.first;
      feeEvidence = FieldEvidence(
        rawText: fee.rawText,
        matchedSubstring: fee.matchedSubstring,
        boundingBox: fee.boundingBox,
        confidence: fee.confidence,
        source: 'ocr_extracted',
      );
    }

    return ParsedAmountResult(
      paidAmountMinor: finalPaidAmount,
      originalAmountMinor: originalCandidates.isNotEmpty ? originalCandidates.first.amountMinor : null,
      discountMinor: discountCandidates.isNotEmpty ? discountCandidates.first.amountMinor : null,
      feeMinor: feeCandidates.isNotEmpty ? feeCandidates.first.amountMinor : null,
      paidEvidence: paidEvidence,
      originalEvidence: originalEvidence,
      discountEvidence: discountEvidence,
      feeEvidence: feeEvidence,
      issues: issues,
    );
  }
}
