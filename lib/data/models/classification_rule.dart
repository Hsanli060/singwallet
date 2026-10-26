// lib/data/models/classification_rule.dart

/// Model for the `classification_rules` table.
class ClassificationRule {
  final String id;
  final int priority;
  final String merchantPattern;
  final String? paymentChannel;
  final String categoryId;
  final String? projectId;
  final int enabled; // 1 or 0
  final int version;
  final String createdAt;
  final String updatedAt;

  const ClassificationRule({
    required this.id,
    this.priority = 100,
    required this.merchantPattern,
    this.paymentChannel,
    required this.categoryId,
    this.projectId,
    this.enabled = 1,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isEnabled => enabled == 1;

  factory ClassificationRule.fromMap(Map<String, dynamic> map) {
    return ClassificationRule(
      id: map['id'] as String,
      priority: (map['priority'] as int?) ?? 100,
      merchantPattern: map['merchant_pattern'] as String,
      paymentChannel: map['payment_channel'] as String?,
      categoryId: map['category_id'] as String,
      projectId: map['project_id'] as String?,
      enabled: (map['enabled'] as int?) ?? 1,
      version: (map['version'] as int?) ?? 1,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'priority': priority,
      'merchant_pattern': merchantPattern,
      'payment_channel': paymentChannel,
      'category_id': categoryId,
      'project_id': projectId,
      'enabled': enabled,
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  ClassificationRule copyWith({
    String? id,
    int? priority,
    String? merchantPattern,
    String? paymentChannel,
    String? categoryId,
    String? projectId,
    int? enabled,
    int? version,
    String? createdAt,
    String? updatedAt,
  }) {
    return ClassificationRule(
      id: id ?? this.id,
      priority: priority ?? this.priority,
      merchantPattern: merchantPattern ?? this.merchantPattern,
      paymentChannel: paymentChannel ?? this.paymentChannel,
      categoryId: categoryId ?? this.categoryId,
      projectId: projectId ?? this.projectId,
      enabled: enabled ?? this.enabled,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassificationRule &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          priority == other.priority &&
          merchantPattern == other.merchantPattern &&
          paymentChannel == other.paymentChannel &&
          categoryId == other.categoryId &&
          projectId == other.projectId &&
          enabled == other.enabled &&
          version == other.version &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        priority,
        merchantPattern,
        paymentChannel,
        categoryId,
        projectId,
        enabled,
        version,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'ClassificationRule(id: $id, pattern: $merchantPattern, catId: $categoryId, priority: $priority)';
}
