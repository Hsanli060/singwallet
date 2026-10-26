// lib/features/recognition/ocr_pipeline.dart
import '../../core/native/native_bridge.g.dart';
import '../../core/utils/date_utils.dart';
import '../classification/models/classification_match_result.dart';
import '../classification/rule_engine.dart';
import '../deduplication/deduplication_engine.dart';
import 'amount_parser.dart';
import 'channel_status_parser.dart';
import 'merchant_normalizer.dart';
import 'models/field_evidence.dart';
import 'models/parsed_draft_result.dart';
import 'models/validation_issue.dart';
import 'noise_filter.dart';
import 'order_id_parser.dart';

/// 8-Stage OCR Transaction Parsing & Draft Synthesis Pipeline (Features F19–F26)
class OcrParsingPipeline {
  final DeduplicationEngine? _dedupEngine;
  final ClassificationRuleEngine? _classificationEngine;

  OcrParsingPipeline({
    DeduplicationEngine? dedupEngine,
    ClassificationRuleEngine? classificationEngine,
  })  : _dedupEngine = dedupEngine,
        _classificationEngine = classificationEngine;

  /// Executes full 8-stage parsing on an incoming [OcrDocument]
  Future<ParsedDraftResult> process(
    OcrDocument doc, {
    bool hasDynamicIsland = false,
    String? contentHash,
    String? draftId,
  }) async {
    // Stage 1: Input Normalization & Spatial Bounding Box Clamping
    final normalizedLines = <OcrTextLine>[];
    for (final line in doc.lines) {
      final box = line.boundingBox;
      final cLeft = box.left.clamp(0.0, 1.0);
      final cTop = box.top.clamp(0.0, 1.0);
      final cWidth = box.width.clamp(0.0, 1.0 - cLeft);
      final cHeight = box.height.clamp(0.0, 1.0 - cTop);

      var text = line.text.trim();
      // Collapse spaces between CJK characters introduced by OCR segmentation
      while (text.contains(RegExp(r'([\u4e00-\u9fa5])\s+([\u4e00-\u9fa5])'))) {
        text = text.replaceAllMapped(
          RegExp(r'([\u4e00-\u9fa5])\s+([\u4e00-\u9fa5])'),
          (m) => '${m[1]}${m[2]}',
        );
      }
      // Normalise leading minus / CJK dash before digits
      text = text.replaceAllMapped(
        RegExp(r'^[一—–－]\s*(\d)'),
        (m) => '-${m[1]}',
      );
      // Remove spaces around decimal points or commas in numbers
      text = text.replaceAllMapped(
        RegExp(r'(\d)\s*([.,，．·])\s*(\d)'),
        (m) => '${m[1]}.${m[3]}',
      );

      normalizedLines.add(OcrTextLine(
        text: text,
        boundingBox: OcrBoundingBox(
          left: cLeft,
          top: cTop,
          width: cWidth,
          height: cHeight,
        ),
        confidence: line.confidence,
      ));
    }

    // Stage 1.1: Synthesize horizontal key-value pairs (WeChat / Alipay 2-column layout)
    final candidateLines = <OcrTextLine>[...normalizedLines];
    final leftCols = normalizedLines.where((l) => l.boundingBox.left < 0.25 && l.boundingBox.top > 0.25).toList();
    final rightCols = normalizedLines.where((l) => l.boundingBox.left >= 0.20 && l.boundingBox.top > 0.25).toList();

    for (final left in leftCols) {
      for (final right in rightCols) {
        if (identical(left, right)) continue;
        final dy = (left.boundingBox.top - right.boundingBox.top).abs();
        if (dy < 0.02) {
          final combLeft = left.boundingBox.left;
          final combTop = left.boundingBox.top < right.boundingBox.top ? left.boundingBox.top : right.boundingBox.top;
          final rightEdge = (right.boundingBox.left + right.boundingBox.width);
          final combWidth = (rightEdge - combLeft).clamp(0.0, 1.0);
          final combHeight = left.boundingBox.height > right.boundingBox.height ? left.boundingBox.height : right.boundingBox.height;

          candidateLines.add(OcrTextLine(
            text: '${left.text}：${right.text}',
            boundingBox: OcrBoundingBox(
              left: combLeft,
              top: combTop,
              width: combWidth,
              height: combHeight,
            ),
            confidence: (left.confidence ?? 0.9) * 0.95,
          ));
          break;
        }
      }
    }

    // Stage 2: Noise Filtering (Status bar, Dynamic Island, Home indicator, Action buttons)
    final cleanedLines = NoiseFilter.filterNoise(
      candidateLines,
      hasDynamicIsland: hasDynamicIsland,
    );

    // Stage 3: Payment Channel & Transaction Status Recognition
    final channelResult = ChannelStatusParser.parse(cleanedLines);

    // Stage 4: Amount Extraction & Disambiguation (Paid vs Original vs Discount vs Fee)
    final amountResult = AmountParser.parse(cleanedLines);

    // Stage 5: Merchant Extraction & Normalization
    final merchantResult = MerchantNormalizer.extractAndNormalize(cleanedLines);

    // Stage 6: Transaction Time Extraction
    ParsedDateResult? parsedDate;
    FieldEvidence? dateEvidence;

    for (final line in cleanedLines) {
      final res = DateUtils.parseReceiptDateTime(line.text);
      if (res != null) {
        parsedDate = res;
        dateEvidence = FieldEvidence(
          rawText: line.text,
          matchedSubstring: res.matchedSubstring.isNotEmpty ? res.matchedSubstring : line.text,
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          source: 'ocr_extracted',
        );
        break;
      }
    }

    final dateIssues = <ValidationIssue>[];
    ParsedDateResult dateResult;
    if (parsedDate == null) {
      dateResult = DateUtils.fallbackToday();
      dateIssues.add(ValidationIssue.missingDateIssue());
    } else {
      dateResult = parsedDate;
      if (dateResult.occurredAt == null) {
        // Secondary timestamp recovery: check order/serial/raw lines for embedded timestamps (e.g. MMDDhhmmss)
        final ymd = dateResult.occurredOn.split('-');
        if (ymd.length == 3) {
          final year = int.tryParse(ymd[0]);
          final month = ymd[1];
          final day = ymd[2];
          final mmddPattern = RegExp('$month$day(\\d{2})(\\d{2})(\\d{2})');
          for (final l in cleanedLines) {
            final textNoSpace = l.text.replaceAll(RegExp(r'\s+'), '');
            final m = mmddPattern.firstMatch(textNoSpace);
            if (m != null) {
              final h = int.tryParse(m.group(1)!);
              final min = int.tryParse(m.group(2)!);
              final s = int.tryParse(m.group(3)!);
              if (year != null && DateUtils.isValidDateTime(year, int.parse(month), int.parse(day), h, min, s)) {
                dateResult = ParsedDateResult(
                  occurredOn: dateResult.occurredOn,
                  occurredAt: DateUtils.toUtcIsoStringFromComponents(year, int.parse(month), int.parse(day), h!, min!, s!),
                  precision: 'second',
                  source: 'ocr_extracted',
                  matchedSubstring: m.group(0)!,
                );
                break;
              }
            }
          }
        }
      }
    }

    // Stage 7: Order ID Extraction & Completeness Grading
    final orderResult = OrderIdParser.parse(
      cleanedLines,
      channel: channelResult.paymentChannel,
    );

    // Stage 8: Classification & Deduplication Evaluation
    ClassificationMatchResult? classification;
    final classificationEngine = _classificationEngine;
    final rawMerchant = merchantResult.rawMerchant;
    if (classificationEngine != null && rawMerchant != null) {
      classification = await classificationEngine.classify(
        merchantRaw: rawMerchant,
        merchantNormalized: merchantResult.normalizedMerchant,
        paymentChannel: channelResult.paymentChannel,
        amountMinor: amountResult.paidAmountMinor,
        type: channelResult.type,
      );
    }

    List<String> duplicateCandidates = const [];
    final dedupIssues = <ValidationIssue>[];

    final dedupEngine = _dedupEngine;
    if (dedupEngine != null) {
      PlatformIdentifier? platformId;
      final platformNo = orderResult.platformTransactionNo;
      if (platformNo != null && platformNo.isNotEmpty) {
        String namespace = 'other';
        if (channelResult.paymentChannel == 'wechat') {
          namespace = 'wechat_pay';
        } else if (channelResult.paymentChannel == 'alipay') {
          namespace = 'alipay';
        } else if (channelResult.paymentChannel == 'unionpay') {
          namespace = 'unionpay';
        }

        platformId = PlatformIdentifier(
          namespace: namespace,
          identifierType: 'platform_transaction_no',
          completeValue: platformNo,
          stableEventKind: channelResult.paymentStatus == 'REFUNDED' ? 'refund' : 'payment',
          completeness: orderResult.completeness,
        );
      }

      final dedupEval = await dedupEngine.evaluate(
        originDraftId: draftId,
        imageContentHash: contentHash,
        platformIdentifier: platformId,
        merchantRaw: merchantResult.rawMerchant ?? '',
        merchantNormalized: merchantResult.normalizedMerchant,
        amountMinor: amountResult.paidAmountMinor ?? 0,
        occurredOn: dateResult.occurredOn,
        occurredAt: dateResult.occurredAt,
      );

      if (dedupEval.hasSoftDuplicate) {
        duplicateCandidates = dedupEval.tier4.candidateTransactionIds;
        dedupIssues.add(const ValidationIssue(
          code: ValidationIssue.suspectedDuplicate,
          message: '发现近期存在相同金额与商户的交易，可能为重复录入。',
          field: 'duplicate',
          severity: IssueSeverity.info,
        ));
      }
    }

    // Assemble Field Evidence Map
    final evidenceMap = <String, FieldEvidence>{};
    if (amountResult.paidEvidence != null) {
      evidenceMap['amount'] = amountResult.paidEvidence!;
    }
    if (amountResult.originalEvidence != null) {
      evidenceMap['original_amount'] = amountResult.originalEvidence!;
    }
    if (amountResult.discountEvidence != null) {
      evidenceMap['discount'] = amountResult.discountEvidence!;
    }
    if (amountResult.feeEvidence != null) {
      evidenceMap['fee'] = amountResult.feeEvidence!;
    }
    if (merchantResult.evidence != null) {
      evidenceMap['merchant'] = merchantResult.evidence!;
    }
    if (dateEvidence != null) {
      evidenceMap['occurred_at'] = dateEvidence;
    }
    if (orderResult.platformEvidence != null) {
      evidenceMap['platform_transaction_no'] = orderResult.platformEvidence!;
    }
    if (orderResult.merchantEvidence != null) {
      evidenceMap['merchant_order_no'] = orderResult.merchantEvidence!;
    }
    if (channelResult.channelEvidence != null) {
      evidenceMap['payment_channel'] = channelResult.channelEvidence!;
    }
    if (channelResult.statusEvidence != null) {
      evidenceMap['payment_status'] = channelResult.statusEvidence!;
    }

    // Combine All Validation Issues
    final allIssues = <ValidationIssue>[
      ...channelResult.issues,
      ...amountResult.issues,
      ...merchantResult.issues,
      ...dateIssues,
      ...orderResult.issues,
      ...dedupIssues,
    ];

    // Compute Overall Pipeline Confidence Score
    double score = 1.0;
    if (amountResult.paidAmountMinor == null) score -= 0.3;
    if (merchantResult.rawMerchant == null) score -= 0.2;
    if (dateEvidence == null) score -= 0.2;
    if (channelResult.paymentStatus != 'SUCCESS') score -= 0.1;
    if (orderResult.completeness != IdentifierCompleteness.complete) score -= 0.1;
    if (score < 0.1) score = 0.1;

    return ParsedDraftResult(
      captureId: doc.captureId,
      type: channelResult.type,
      amountMinor: amountResult.paidAmountMinor,
      originalAmountMinor: amountResult.originalAmountMinor,
      discountMinor: amountResult.discountMinor,
      feeMinor: amountResult.feeMinor,
      currency: 'CNY',
      merchantRaw: merchantResult.rawMerchant,
      merchantNormalized: merchantResult.normalizedMerchant,
      occurredOn: dateResult.occurredOn,
      occurredAt: dateResult.occurredAt,
      eventTimezone: dateResult.timezone,
      eventTimeSource: dateResult.source,
      eventTimePrecision: dateResult.precision,
      paymentChannel: channelResult.paymentChannel,
      paymentStatus: channelResult.paymentStatus,
      paymentMethodLabel: channelResult.paymentMethodLabel,
      platformTransactionNo: orderResult.platformTransactionNo,
      merchantOrderNo: orderResult.merchantOrderNo,
      identifierCompleteness: orderResult.completeness,
      suggestedCategoryId: classification?.categoryId,
      suggestedProjectId: classification?.projectId,
      suggestedTagIds: classification?.tagIds ?? const [],
      fieldEvidence: evidenceMap,
      validationIssues: allIssues,
      duplicateCandidates: duplicateCandidates,
      confidenceScore: double.parse(score.toStringAsFixed(2)),
    );
  }
}
