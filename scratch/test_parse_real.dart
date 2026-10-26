import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Run real OCR pipeline against user screenshots', () async {
    final db = await AppDatabase.openInMemory();
    final dedupEngine = DeduplicationEngine(db);
    final classificationEngine = ClassificationRuleEngine(db);
    final pipeline = OcrParsingPipeline(
      dedupEngine: dedupEngine,
      classificationEngine: classificationEngine,
    );

    // Seed 8 standard categories
    final defaultCats = [
      {'id': 'cat_food', 'name': '餐饮美食'},
      {'id': 'cat_transport', 'name': '交通出行'},
      {'id': 'cat_shopping', 'name': '日常购物'},
      {'id': 'cat_entertainment', 'name': '休闲娱乐'},
      {'id': 'cat_housing', 'name': '居家生活'},
      {'id': 'cat_utilities', 'name': '生活缴费'},
      {'id': 'cat_medical', 'name': '医疗健康'},
      {'id': 'cat_other', 'name': '其他支出'},
    ];
    for (final c in defaultCats) {
      await db.insert('categories', {
        'id': c['id'],
        'name': c['name'],
        'applicable_type': 'expense',
        'created_at': '2026-10-22T00:00:00Z',
        'updated_at': '2026-10-22T00:00:00Z',
      });
    }

    final jsonFile = File('scratch/ocr_raw_extracted.json');
    final jsonContent = await jsonFile.readAsString();
    final List<dynamic> data = jsonDecode(jsonContent);

    final resultsList = <Map<String, dynamic>>[];

    for (int i = 0; i < data.length; i++) {
      final img = data[i];
      final linesData = img['Lines'] as List<dynamic>;

      final ocrLines = linesData.map((l) {
        final box = l['Box'];
        return OcrTextLine(
          text: l['Text'] as String,
          boundingBox: OcrBoundingBox(
            left: (box['Left'] as num).toDouble(),
            top: (box['Top'] as num).toDouble(),
            width: (box['Width'] as num).toDouble(),
            height: (box['Height'] as num).toDouble(),
          ),
          confidence: 0.95,
        );
      }).toList();

      final doc = OcrDocument(
        captureId: 'cap_${i + 1}',
        lines: ocrLines,
        engineIdentifier: 'windows_media_ocr_zh_hans',
        processTimeMs: 45,
      );

      final res = await pipeline.process(doc, draftId: 'draft_${i + 1}');

      final imgName = (img['ImagePath'] as String).split(Platform.pathSeparator).last;
      print('\n================ IMAGE ${i + 1}: $imgName ================');
      print('MerchantRaw: ${res.merchantRaw}');
      print('MerchantNormalized: ${res.merchantNormalized}');
      print('AmountMinor: ${res.amountMinor} -> ¥${res.amountMinor != null ? (res.amountMinor! / 100).toStringAsFixed(2) : "NULL"}');
      print('PaymentChannel: ${res.paymentChannel}');
      print('PaymentStatus: ${res.paymentStatus}');
      print('PlatformOrderNo: ${res.platformTransactionNo}');
      print('MerchantOrderNo: ${res.merchantOrderNo}');
      print('OccurredOn: ${res.occurredOn}, OccurredAt: ${res.occurredAt}');
      print('SuggestedCategoryId: ${res.suggestedCategoryId}');
      print('ConfidenceScore: ${res.confidenceScore}');
      print('IsConfident: ${res.isConfident}');
      print('ValidationIssues: ${res.validationIssues.map((e) => e.message).toList()}');

      resultsList.add({
        'index': i + 1,
        'imageName': imgName,
        'imagePath': img['ImagePath'],
        'merchantRaw': res.merchantRaw,
        'merchantNormalized': res.merchantNormalized,
        'amountMinor': res.amountMinor,
        'amountFormatted': res.amountMinor != null ? (res.amountMinor! / 100).toStringAsFixed(2) : null,
        'paymentChannel': res.paymentChannel,
        'paymentStatus': res.paymentStatus,
        'platformTransactionNo': res.platformTransactionNo,
        'merchantOrderNo': res.merchantOrderNo,
        'occurredOn': res.occurredOn,
        'occurredAt': res.occurredAt,
        'suggestedCategoryId': res.suggestedCategoryId,
        'confidenceScore': res.confidenceScore,
        'isConfident': res.isConfident,
        'validationIssues': res.validationIssues.map((e) => e.message).toList(),
      });
    }

    final outJson = File('scratch/pipeline_parsed_results.json');
    await outJson.writeAsString(jsonEncode(resultsList));
    print('\nSuccessfully wrote results to scratch/pipeline_parsed_results.json');
  });
}
