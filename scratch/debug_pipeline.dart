import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/utils/date_utils.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/features/classification/rule_engine.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/features/recognition/ocr_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Debug cleaned lines in pipeline', () async {
    final db = await AppDatabase.openInMemory();
    final pipeline = OcrParsingPipeline(
      dedupEngine: DeduplicationEngine(db),
      classificationEngine: ClassificationRuleEngine(db),
    );

    final jsonFile = File('scratch/ocr_raw_extracted.json');
    final jsonContent = await jsonFile.readAsString();
    final List<dynamic> data = jsonDecode(jsonContent);

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

      for (final l in doc.lines) {
        final r = DateUtils.parseReceiptDateTime(l.text);
        if (r != null || l.text.contains('2026')) {
          print('Line: "${l.text}" -> DateResult: $r');
        }
      }
    }
  });
}
