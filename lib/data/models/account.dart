// lib/data/models/account.dart

/// Model for the `accounts` table.
class Account {
  final String id;
  final String name;
  final String kind; // cash, debit_card, credit_card, e_wallet, other
  final String? cardLast4;
  final String? archivedAt;
  final String createdAt;
  final String updatedAt;

  const Account({
    required this.id,
    required this.name,
    required this.kind,
    this.cardLast4,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as String,
      name: map['name'] as String,
      kind: map['kind'] as String,
      cardLast4: map['card_last4'] as String?,
      archivedAt: map['archived_at'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'kind': kind,
      'card_last4': cardLast4,
      'archived_at': archivedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Account copyWith({
    String? id,
    String? name,
    String? kind,
    String? cardLast4,
    String? archivedAt,
    String? createdAt,
    String? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      cardLast4: cardLast4 ?? this.cardLast4,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Account &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          kind == other.kind &&
          cardLast4 == other.cardLast4 &&
          archivedAt == other.archivedAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        kind,
        cardLast4,
        archivedAt,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'Account(id: $id, name: $name, kind: $kind)';
}
