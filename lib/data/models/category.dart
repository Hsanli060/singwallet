// lib/data/models/category.dart

/// Model for the `categories` table.
class Category {
  final String id;
  final String name;
  final String? parentId;
  final String applicableType; // expense, income, both
  final String? iconKey;
  final int sortOrder;
  final String? archivedAt;
  final String createdAt;
  final String updatedAt;

  const Category({
    required this.id,
    required this.name,
    this.parentId,
    required this.applicableType,
    this.iconKey,
    this.sortOrder = 0,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      parentId: map['parent_id'] as String?,
      applicableType: map['applicable_type'] as String,
      iconKey: map['icon_key'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      archivedAt: map['archived_at'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'applicable_type': applicableType,
      'icon_key': iconKey,
      'sort_order': sortOrder,
      'archived_at': archivedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Category copyWith({
    String? id,
    String? name,
    String? parentId,
    String? applicableType,
    String? iconKey,
    int? sortOrder,
    String? archivedAt,
    String? createdAt,
    String? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      applicableType: applicableType ?? this.applicableType,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          parentId == other.parentId &&
          applicableType == other.applicableType &&
          iconKey == other.iconKey &&
          sortOrder == other.sortOrder &&
          archivedAt == other.archivedAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        parentId,
        applicableType,
        iconKey,
        sortOrder,
        archivedAt,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'Category(id: $id, name: $name, parentId: $parentId, type: $applicableType)';
}
