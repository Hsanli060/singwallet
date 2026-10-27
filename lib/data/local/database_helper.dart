// lib/data/local/database_helper.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/schema.dart';

/// DatabaseHelper manages SQLite database creation, connectivity, and
/// incremental lossless schema migrations across SingWallet releases.
///
/// 【铁律 2】：SQLite 数据库增量无损迁移 (onUpgrade)
/// 1. 采用版本递进式迁移机制（如 `if (oldVersion < 2)`）。
/// 2. 任何添加新字段必须先通过 `PRAGMA table_info(...)` 安全检查是否存在，
///    然后再执行 `ALTER TABLE ... ADD COLUMN`。
/// 3. 新建表使用 `CREATE TABLE IF NOT EXISTS`。
/// 4. 【绝对红线】：严禁执行任何 `DROP TABLE` 或破坏性变更，100% 保证历史账单与数据无损保留。
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  /// Current database schema version.
  static const int _databaseVersion = 2;

  /// Public getter for database version.
  static int get databaseVersion => _databaseVersion;

  static const String dbName = 'singwallet.db';

  Database? _db;
  DatabaseFactory? _customFactory;
  static bool _ffiInitialized = false;

  @visibleForTesting
  void setDatabaseFactory(DatabaseFactory factory) {
    _customFactory = factory;
  }

  /// Ensure desktop FFI is initialized if running on desktop/headless test
  static void initializeFfi() {
    if (_ffiInitialized) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialized = true;
  }

  /// Get active database connection
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await open();
    return _db!;
  }

  /// Opens the database at default persistent path or custom path
  Future<Database> open({String? customPath, int version = _databaseVersion}) async {
    initializeFfi();
    final factory = _customFactory ?? databaseFactory;

    final String path;
    if (customPath != null) {
      path = customPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      path = p.join(docsDir.path, dbName);
    }

    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, v) async {
          await _createBaseTablesAndIndices(db);
          if (v >= 2) {
            await _migrateToV2(db);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await onUpgrade(db, oldVersion, newVersion);
        },
        onOpen: (db) async {
          if (path != inMemoryDatabasePath) {
            await db.execute('PRAGMA journal_mode = WAL;');
            await db.execute('PRAGMA synchronous = NORMAL;');
          }
        },
      ),
    );

    return _db!;
  }

  /// Opens an in-memory database for testing
  static Future<Database> openInMemory({
    DatabaseFactory? factory,
    int version = _databaseVersion,
  }) async {
    initializeFfi();
    final f = factory ?? databaseFactoryFfi;
    return await f.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, v) async {
          await _createBaseTablesAndIndices(db);
          if (v >= 2) {
            await _migrateToV2(db);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await onUpgrade(db, oldVersion, newVersion);
        },
      ),
    );
  }

  /// Creates canonical base tables and indices
  static Future<void> _createBaseTablesAndIndices(Database db) async {
    final batch = db.batch();
    for (final sql in AppSchema.createTablesStatements) {
      batch.execute(sql);
    }
    for (final sql in AppSchema.createIndicesStatements) {
      batch.execute(sql);
    }
    await batch.commit(noResult: true);
  }

  /// 严谨的增量版本升级迁移器
  ///
  /// 逐版本递增执行迁移脚本，从根源上杜绝跨版本升级时数据丢失。
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 铁律 2 核心保证：无损逐级迁移
    if (oldVersion < 2 && newVersion >= 2) {
      await _migrateToV2(db);
    }

    // 后续如有 v3，可按需添加:
    // if (oldVersion < 3 && newVersion >= 3) {
    //   await _migrateToV3(db);
    // }
  }

  /// 迁移到 v2：无损扩展字段与表
  static Future<void> _migrateToV2(Database db) async {
    // 1. 检查并为 transactions 表补充 sync_status 字段（默认 LOCAL，用于同步与备份追踪）
    if (await hasTable(db, 'transactions')) {
      final txCols = await getTableColumns(db, 'transactions');
      if (!txCols.contains('sync_status')) {
        await db.execute("ALTER TABLE transactions ADD COLUMN sync_status TEXT DEFAULT 'LOCAL';");
      }
    }

    // 2. 检查并为 categories 表补充 is_custom 与 color_hex 字段（用于自定义分类支持）
    if (await hasTable(db, 'categories')) {
      final catCols = await getTableColumns(db, 'categories');
      if (!catCols.contains('is_custom')) {
        await db.execute("ALTER TABLE categories ADD COLUMN is_custom INTEGER NOT NULL DEFAULT 0;");
      }
      if (!catCols.contains('color_hex')) {
        await db.execute("ALTER TABLE categories ADD COLUMN color_hex TEXT;");
      }
    }

    // 3. 检查并为 drafts 表补充 vlm_model 字段（用于 VLM 多模态大模型模型名追踪）
    if (await hasTable(db, 'drafts')) {
      final draftCols = await getTableColumns(db, 'drafts');
      if (!draftCols.contains('vlm_model')) {
        await db.execute("ALTER TABLE drafts ADD COLUMN vlm_model TEXT;");
      }
    }

    // 4. 创建 vlm_configurations 表（如果不存在），用于持久化 VLM 大模型服务配置
    await db.execute('''
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

    // 5. 创建 ota_update_logs 表（如果不存在），用于记录 OTA 升级履历
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ota_update_logs (
        id TEXT PRIMARY KEY NOT NULL,
        version TEXT NOT NULL,
        installed_at TEXT NOT NULL,
        source_url TEXT,
        status TEXT NOT NULL
      );
    ''');
  }

  /// Helper to get column names of a table via PRAGMA table_info
  static Future<Set<String>> getTableColumns(Database db, String tableName) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName);');
    final columns = <String>{};
    for (final row in rows) {
      final name = row['name'];
      if (name is String) {
        columns.add(name);
      }
    }
    return columns;
  }

  /// Check whether a column exists in a given table
  static Future<bool> hasColumn(Database db, String tableName, String columnName) async {
    final columns = await getTableColumns(db, tableName);
    return columns.contains(columnName);
  }

  /// Check whether a table exists in SQLite master
  static Future<bool> hasTable(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  /// Closes active database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  @visibleForTesting
  Future<void> reset() async {
    await close();
  }
}
