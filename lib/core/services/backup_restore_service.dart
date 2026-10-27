// lib/core/services/backup_restore_service.dart
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../data/local/database_helper.dart';

/// Structured snapshot container representing a full export of SingWallet user data.
class BackupSnapshot {
  final int version;
  final String exportedAt;
  final String appVersion;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> transactionMetadata;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> tags;
  final List<Map<String, dynamic>> classificationRules;
  final Map<String, dynamic>? vlmConfig;

  const BackupSnapshot({
    required this.version,
    required this.exportedAt,
    required this.appVersion,
    required this.transactions,
    required this.transactionMetadata,
    required this.categories,
    required this.accounts,
    required this.projects,
    required this.tags,
    required this.classificationRules,
    this.vlmConfig,
  });

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) {
    return BackupSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 1,
      exportedAt: json['exportedAt'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      appVersion: json['appVersion'] as String? ?? '1.0.0',
      transactions: (json['transactions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      transactionMetadata: (json['transactionMetadata'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      categories: (json['categories'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      accounts: (json['accounts'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      projects: (json['projects'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      tags: (json['tags'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      classificationRules: (json['classificationRules'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      vlmConfig: json['vlmConfig'] != null ? Map<String, dynamic>.from(json['vlmConfig'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'exportedAt': exportedAt,
      'appVersion': appVersion,
      'transactions': transactions,
      'transactionMetadata': transactionMetadata,
      'categories': categories,
      'accounts': accounts,
      'projects': projects,
      'tags': tags,
      'classificationRules': classificationRules,
      'vlmConfig': vlmConfig,
    };
  }

  String toJsonString({bool pretty = false}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }
}

/// Result report returned after restoring a backup snapshot.
class BackupRestoreResult {
  final bool success;
  final int migratedFromVersion;
  final int targetVersion;
  final int transactionsRestored;
  final int categoriesRestored;
  final int accountsRestored;
  final int projectsRestored;
  final int tagsRestored;
  final int rulesRestored;
  final bool vlmConfigRestored;
  final String? errorMessage;

  const BackupRestoreResult({
    required this.success,
    required this.migratedFromVersion,
    required this.targetVersion,
    this.transactionsRestored = 0,
    this.categoriesRestored = 0,
    this.accountsRestored = 0,
    this.projectsRestored = 0,
    this.tagsRestored = 0,
    this.rulesRestored = 0,
    this.vlmConfigRestored = false,
    this.errorMessage,
  });

  @override
  String toString() =>
      'BackupRestoreResult(success: $success, migrated: v$migratedFromVersion -> v$targetVersion, txs: $transactionsRestored, cats: $categoriesRestored, accounts: $accountsRestored, error: $errorMessage)';
}

/// Service handling full data export and lossless schema-migrated restore.
///
/// 【铁律 3 + 方式 2】：全量备份导出与无损恢复
/// 1. 结构化全量导出：包含账单、扩展元数据、内置/自定义分类、账户、项目、标签、分类规则以及 VLM 配置。
/// 2. 无损 Schema 迁移：导入 v1 备份时，自动进行 Schema 迁移补齐（如 is_custom、sync_status 等），
///    将数据安全升级到 v2 标准，保证数据永不损坏。
class BackupRestoreService {
  BackupRestoreService._();

  static const int currentSchemaVersion = DatabaseHelper.databaseVersion;

  /// Default category IDs known in standard seed
  static const Set<String> _defaultCategoryIds = {
    'cat_food',
    'cat_transport',
    'cat_shopping',
    'cat_entertainment',
    'cat_utilities',
    'cat_medical',
    'cat_other',
    'cat_salary',
  };

  /// Exports full database state to a JSON formatted string.
  static Future<String> exportToJson(
    Database db, {
    Map<String, dynamic>? vlmConfig,
    String appVersion = '1.0.0',
    bool pretty = true,
  }) async {
    // 1. Transactions and metadata
    final transactions = await db.query('transactions');
    final metadata = await db.query('transaction_metadata');

    // 2. Auxiliary classifications and dimensions
    final categories = await db.query('categories');
    final accounts = await db.query('accounts');
    final projects = await db.query('projects');
    final tags = await db.query('tags');
    final rules = await db.query('classification_rules');

    // 3. Resolve VLM Configuration (from parameter or DB table)
    Map<String, dynamic>? resolvedVlmConfig = vlmConfig;
    if (resolvedVlmConfig == null && await DatabaseHelper.hasTable(db, 'vlm_configurations')) {
      final vlmRows = await db.query('vlm_configurations', limit: 1);
      if (vlmRows.isNotEmpty) {
        resolvedVlmConfig = Map<String, dynamic>.from(vlmRows.first);
      }
    }

    final snapshot = BackupSnapshot(
      version: currentSchemaVersion,
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      appVersion: appVersion,
      transactions: transactions.map((r) => Map<String, dynamic>.from(r)).toList(),
      transactionMetadata: metadata.map((r) => Map<String, dynamic>.from(r)).toList(),
      categories: categories.map((r) => Map<String, dynamic>.from(r)).toList(),
      accounts: accounts.map((r) => Map<String, dynamic>.from(r)).toList(),
      projects: projects.map((r) => Map<String, dynamic>.from(r)).toList(),
      tags: tags.map((r) => Map<String, dynamic>.from(r)).toList(),
      classificationRules: rules.map((r) => Map<String, dynamic>.from(r)).toList(),
      vlmConfig: resolvedVlmConfig,
    );

    return snapshot.toJsonString(pretty: pretty);
  }

  /// Parses JSON string and performs lossless v1 -> v2 schema migration if necessary.
  static BackupSnapshot parseAndMigrateSnapshot(String jsonString) {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup file: Root JSON must be an object.');
    }

    final rawSnapshot = BackupSnapshot.fromJson(decoded);
    final originalVersion = rawSnapshot.version;

    // Lossless schema migration v1 -> v2
    if (originalVersion < 2) {
      final migratedCategories = <Map<String, dynamic>>[];
      for (final cat in rawSnapshot.categories) {
        final migratedCat = Map<String, dynamic>.from(cat);
        // v2 adds is_custom column: determine custom status from defaults
        if (!migratedCat.containsKey('is_custom')) {
          final id = migratedCat['id'] as String? ?? '';
          migratedCat['is_custom'] = _defaultCategoryIds.contains(id) ? 0 : 1;
        }
        if (!migratedCat.containsKey('color_hex')) {
          migratedCat['color_hex'] = null;
        }
        migratedCategories.add(migratedCat);
      }

      final migratedTransactions = <Map<String, dynamic>>[];
      for (final tx in rawSnapshot.transactions) {
        final migratedTx = Map<String, dynamic>.from(tx);
        // v2 adds sync_status column: defaults to LOCAL
        if (!migratedTx.containsKey('sync_status')) {
          migratedTx['sync_status'] = 'LOCAL';
        }
        migratedTransactions.add(migratedTx);
      }

      return BackupSnapshot(
        version: 2,
        exportedAt: rawSnapshot.exportedAt,
        appVersion: rawSnapshot.appVersion,
        transactions: migratedTransactions,
        transactionMetadata: rawSnapshot.transactionMetadata,
        categories: migratedCategories,
        accounts: rawSnapshot.accounts,
        projects: rawSnapshot.projects,
        tags: rawSnapshot.tags,
        classificationRules: rawSnapshot.classificationRules,
        vlmConfig: rawSnapshot.vlmConfig,
      );
    }

    return rawSnapshot;
  }

  /// Restores SingWallet data from a JSON backup string with lossless schema upgrade.
  ///
  /// Guarantees database integrity using an atomic SQLite transaction.
  /// Strictly avoids any `DROP TABLE` operations.
  static Future<BackupRestoreResult> importAndMigrateFromJson(
    Database db,
    String jsonString, {
    bool clearExisting = false,
  }) async {
    try {
      // 1. Ensure DB schema is at current version
      final currentDbVersion = await db.getVersion();
      if (currentDbVersion < currentSchemaVersion) {
        await DatabaseHelper.onUpgrade(db, currentDbVersion, currentSchemaVersion);
        await db.setVersion(currentSchemaVersion);
      }

      // 2. Parse and migrate snapshot
      final dynamic rawJson = jsonDecode(jsonString);
      final rawVersion = (rawJson is Map && rawJson.containsKey('version'))
          ? (rawJson['version'] as num?)?.toInt() ?? 1
          : 1;

      final snapshot = parseAndMigrateSnapshot(jsonString);

      var txCount = 0;
      var catCount = 0;
      var accCount = 0;
      var projCount = 0;
      var tagCount = 0;
      var ruleCount = 0;
      var vlmRestored = false;

      await db.transaction((txn) async {
        if (clearExisting) {
          // Clear tables in reverse dependency order (NEVER DROP TABLE)
          await txn.delete('confirmed_identifiers');
          await txn.delete('refund_links');
          await txn.delete('transaction_tags');
          await txn.delete('transaction_metadata');
          await txn.delete('transactions');
          await txn.delete('classification_rules');
          await txn.delete('tags');
          await txn.delete('projects');
          await txn.delete('categories');
          await txn.delete('accounts');
        }

        // 1. Restore Accounts
        for (final row in snapshot.accounts) {
          await txn.insert('accounts', row, conflictAlgorithm: ConflictAlgorithm.replace);
          accCount++;
        }

        // 2. Restore Categories (Preserve defaults and custom categories)
        for (final row in snapshot.categories) {
          await txn.insert('categories', row, conflictAlgorithm: ConflictAlgorithm.replace);
          catCount++;
        }

        // 3. Restore Projects
        for (final row in snapshot.projects) {
          await txn.insert('projects', row, conflictAlgorithm: ConflictAlgorithm.replace);
          projCount++;
        }

        // 4. Restore Tags
        for (final row in snapshot.tags) {
          await txn.insert('tags', row, conflictAlgorithm: ConflictAlgorithm.replace);
          tagCount++;
        }

        // 5. Restore Transactions
        for (final row in snapshot.transactions) {
          await txn.insert('transactions', row, conflictAlgorithm: ConflictAlgorithm.replace);
          txCount++;
        }

        // 6. Restore Transaction Metadata
        for (final row in snapshot.transactionMetadata) {
          await txn.insert('transaction_metadata', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 7. Restore Classification Rules
        for (final row in snapshot.classificationRules) {
          await txn.insert('classification_rules', row, conflictAlgorithm: ConflictAlgorithm.replace);
          ruleCount++;
        }

        // 8. Restore VLM Configurations if present
        if (snapshot.vlmConfig != null) {
          await txn.execute('''
            CREATE TABLE IF NOT EXISTS vlm_configurations (
              id TEXT PRIMARY KEY NOT NULL,
              protocol TEXT NOT NULL,
              base_url TEXT NOT NULL,
              model_name TEXT NOT NULL,
              api_key TEXT,
              custom_prompt TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
          ''');

          final cfg = Map<String, dynamic>.from(snapshot.vlmConfig!);
          cfg['id'] ??= 'vlm_config';
          cfg['protocol'] ??= '';
          cfg['base_url'] ??= '';
          cfg['model_name'] ??= '';
          cfg['api_key'] ??= '';
          cfg['custom_prompt'] ??= '';
          cfg['created_at'] ??= DateTime.now().toUtc().toIso8601String();
          cfg['updated_at'] ??= DateTime.now().toUtc().toIso8601String();

          await txn.insert(
            'vlm_configurations',
            cfg,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          vlmRestored = true;
        }
      });

      return BackupRestoreResult(
        success: true,
        migratedFromVersion: rawVersion,
        targetVersion: currentSchemaVersion,
        transactionsRestored: txCount,
        categoriesRestored: catCount,
        accountsRestored: accCount,
        projectsRestored: projCount,
        tagsRestored: tagCount,
        rulesRestored: ruleCount,
        vlmConfigRestored: vlmRestored,
      );
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        migratedFromVersion: 1,
        targetVersion: currentSchemaVersion,
        errorMessage: e.toString(),
      );
    }
  }
}
