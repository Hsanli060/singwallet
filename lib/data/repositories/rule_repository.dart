// lib/data/repositories/rule_repository.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/models.dart';

/// Abstract contract for Classification Rules repository.
abstract class IRuleRepository {
  Future<List<ClassificationRule>> getAllRules();
  Future<void> setRuleEnabled(String ruleId, bool enabled);
  Future<void> updateRulePriority(String ruleId, int newPriority);
  Future<void> saveRule(ClassificationRule rule);
  Future<void> deleteRule(String ruleId);
  Future<void> reorderRules(List<ClassificationRule> reordered);
}

/// Production implementation of [IRuleRepository] powered by SQLite.
class RuleRepository implements IRuleRepository {
  final DatabaseExecutor _db;

  RuleRepository(DatabaseExecutor db) : _db = db;

  @override
  Future<List<ClassificationRule>> getAllRules() async {
    final rows = await _db.query(
      'classification_rules',
      orderBy: 'priority DESC, created_at DESC',
    );
    return rows.map(ClassificationRule.fromMap).toList();
  }

  @override
  Future<void> setRuleEnabled(String ruleId, bool enabled) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _db.update(
      'classification_rules',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  @override
  Future<void> updateRulePriority(String ruleId, int newPriority) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _db.update(
      'classification_rules',
      {
        'priority': newPriority,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  @override
  Future<void> saveRule(ClassificationRule rule) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final existing = await _db.query(
      'classification_rules',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [rule.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final updated = rule.copyWith(updatedAt: nowIso);
      await _db.update(
        'classification_rules',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [rule.id],
      );
    } else {
      await _db.insert(
        'classification_rules',
        rule.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<void> deleteRule(String ruleId) async {
    await _db.delete(
      'classification_rules',
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  @override
  Future<void> reorderRules(List<ClassificationRule> reordered) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final total = reordered.length;

    for (var i = 0; i < total; i++) {
      final rule = reordered[i];
      // Assign strictly descending priorities in steps of 10
      final calculatedPriority = (total - i) * 10;
      await _db.update(
        'classification_rules',
        {
          'priority': calculatedPriority,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [rule.id],
      );
    }
  }
}
