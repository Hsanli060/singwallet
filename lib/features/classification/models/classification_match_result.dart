// lib/features/classification/models/classification_match_result.dart

/// 6-Tier classification precedence hierarchy
enum ClassificationTier {
  manual(1, 'User Manual Override', 1.0),
  customRule(2, 'User Custom Rule Matching', 0.95),
  history(3, 'Historical Merchant Mapping', 0.85),
  builtinKeyword(4, 'Built-in Keyword Dictionary', 0.70),
  ai(5, 'AI Recommendation', 0.60),
  fallback(6, 'Default Fallback Category', 0.10);

  final int tierNumber;
  final String label;
  final double defaultConfidence;

  const ClassificationTier(this.tierNumber, this.label, this.defaultConfidence);

  int get rank => tierNumber;
  bool get isHighConfidence => tierNumber <= 2;
}

/// Structured outcome of the classification decision engine
class ClassificationMatchResult {
  final ClassificationTier tier;
  final String categoryId;
  final String? projectId;
  final List<String> tagIds;
  final double confidence;
  final String? matchedRuleId;
  final String? matchedPattern;
  final String? matchedKeyword;
  final String explanation;

  const ClassificationMatchResult({
    required this.tier,
    required this.categoryId,
    this.projectId,
    this.tagIds = const [],
    required this.confidence,
    this.matchedRuleId,
    this.matchedPattern,
    this.matchedKeyword,
    required this.explanation,
  });

  int get confidenceScore => (confidence * 100).round();
  String get matchedBy => explanation;

  /// Factory for manual user explicit selection (Tier 1)
  factory ClassificationMatchResult.manual({
    required String categoryId,
    String? projectId,
    List<String> tagIds = const [],
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.manual,
      categoryId: categoryId,
      projectId: projectId,
      tagIds: tagIds,
      confidence: 1.0,
      explanation: 'User manually specified category: $categoryId',
    );
  }

  /// Factory for custom rule hit (Tier 2)
  factory ClassificationMatchResult.customRule({
    required String categoryId,
    String? projectId,
    required String ruleId,
    required String pattern,
    required int priority,
    List<String> tagIds = const [],
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.customRule,
      categoryId: categoryId,
      projectId: projectId,
      tagIds: tagIds,
      confidence: 0.95,
      matchedRuleId: ruleId,
      matchedPattern: pattern,
      explanation: 'Matched custom rule #$ruleId (priority: $priority, pattern: "$pattern")',
    );
  }

  /// Factory for historical merchant mapping (Tier 3)
  factory ClassificationMatchResult.history({
    required String categoryId,
    String? projectId,
    required int frequency,
    required double confidence,
    List<String> tagIds = const [],
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.history,
      categoryId: categoryId,
      projectId: projectId,
      tagIds: tagIds,
      confidence: confidence,
      explanation: 'Matched historical merchant record ($frequency occurrence(s))',
    );
  }

  /// Factory for built-in dictionary keyword hit (Tier 4)
  factory ClassificationMatchResult.builtinKeyword({
    required String categoryId,
    required String keyword,
    List<String> tagIds = const [],
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.builtinKeyword,
      categoryId: categoryId,
      confidence: 0.70,
      matchedKeyword: keyword,
      tagIds: tagIds,
      explanation: 'Matched built-in keyword "$keyword"',
    );
  }

  /// Factory for AI recommendation (Tier 5)
  factory ClassificationMatchResult.ai({
    required String categoryId,
    double confidence = 0.60,
    String? reason,
    List<String> tagIds = const [],
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.ai,
      categoryId: categoryId,
      confidence: confidence,
      tagIds: tagIds,
      explanation: reason ?? 'Recommended by AI semantic model',
    );
  }

  /// Factory for default fallback (Tier 6)
  factory ClassificationMatchResult.fallback({
    String categoryId = 'cat_other',
    List<String> tagIds = const [],
  }) {
    return ClassificationMatchResult(
      tier: ClassificationTier.fallback,
      categoryId: categoryId,
      confidence: 0.10,
      tagIds: tagIds,
      explanation: 'No rule, history, or keyword match. Assigned to fallback category: $categoryId',
    );
  }

  @override
  String toString() =>
      'ClassificationMatchResult(tier: ${tier.name}, category: $categoryId, conf: $confidence, exp: "$explanation")';
}
