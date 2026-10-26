// lib/features/recognition/models/field_evidence.dart
import '../../../core/native/native_bridge.g.dart';

/// Spatial, confidence, and textual provenance for an extracted draft field
class FieldEvidence {
  final String rawText;
  final String matchedSubstring;
  final OcrBoundingBox boundingBox;
  final double? confidence;
  final String source; // e.g. 'ocr_extracted', 'rule_inferred', 'geometry_heuristic'

  const FieldEvidence({
    required this.rawText,
    required this.matchedSubstring,
    required this.boundingBox,
    this.confidence,
    this.source = 'ocr_extracted',
  });

  Map<String, dynamic> toMap() => {
    'raw_text': rawText,
    'rawText': rawText,
    'matched_substring': matchedSubstring,
    'matchedSubstring': matchedSubstring,
    'bounding_box': {
      'left': boundingBox.left,
      'top': boundingBox.top,
      'width': boundingBox.width,
      'height': boundingBox.height,
    },
    'boundingBox': {
      'left': boundingBox.left,
      'top': boundingBox.top,
      'width': boundingBox.width,
      'height': boundingBox.height,
    },
    'confidence': confidence,
    'source': source,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FieldEvidence.fromMap(Map<String, dynamic> map) {
    final rawBox = map['bounding_box'] ?? map['boundingBox'];
    final boxMap = (rawBox is Map) ? rawBox : <String, dynamic>{};
    return FieldEvidence(
      rawText: (map['raw_text'] ?? map['rawText'] ?? '') as String,
      matchedSubstring: (map['matched_substring'] ?? map['matchedSubstring'] ?? '') as String,
      boundingBox: OcrBoundingBox(
        left: (boxMap['left'] as num?)?.toDouble() ?? 0.0,
        top: (boxMap['top'] as num?)?.toDouble() ?? 0.0,
        width: (boxMap['width'] as num?)?.toDouble() ?? 0.0,
        height: (boxMap['height'] as num?)?.toDouble() ?? 0.0,
      ),
      confidence: (map['confidence'] as num?)?.toDouble(),
      source: (map['source'] as String?) ?? 'ocr_extracted',
    );
  }

  factory FieldEvidence.fromJson(Map<String, dynamic> json) => FieldEvidence.fromMap(json);

  @override
  String toString() =>
      'FieldEvidence(matched: "$matchedSubstring", source: $source, confidence: $confidence)';
}
