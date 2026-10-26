// lib/data/models/tag.dart

/// Model for the `tags` table.
class Tag {
  final String id;
  final String name;
  final String? archivedAt;
  final String createdAt;
  final String updatedAt;

  const Tag({
    required this.id,
    required this.name,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as String,
      name: map['name'] as String,
      archivedAt: map['archived_at'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'archived_at': archivedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Tag copyWith({
    String? id,
    String? name,
    String? archivedAt,
    String? createdAt,
    String? updatedAt,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          archivedAt == other.archivedAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        archivedAt,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'Tag(id: $id, name: $name)';
}
