// lib/data/database/app_database.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local/database_helper.dart';
import 'schema.dart';

/// Database management helper for SingWallet.
/// 
/// Enforces foreign key constraints (`PRAGMA foreign_keys = ON;`),
/// WAL mode in production, headless desktop testing via FFI,
/// and in-memory test database isolation.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const String dbName = 'singwallet.db';
  static const int dbVersion = AppSchema.version;

  Database? _db;
  DatabaseFactory? _customFactory;
  static bool _ffiInitialized = false;

  /// Visible for testing to inject custom factory or reset singleton
  @visibleForTesting
  void setDatabaseFactory(DatabaseFactory factory) {
    _customFactory = factory;
  }

  /// Ensure desktop FFI is initialized if running on Windows/Linux/macOS
  static void initializeFfi() {
    if (_ffiInitialized) return;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialized = true;
  }

  /// Get active database connection, opening if needed
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await open();
    return _db!;
  }

  /// Opens the database at default persistent path or custom path
  Future<Database> open({String? customPath}) async {
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
        version: dbVersion,
        onConfigure: (db) async {
          // Mandatory: Execute immediately on connection
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final sql in AppSchema.createTablesStatements) {
            batch.execute(sql);
          }
          for (final sql in AppSchema.createIndicesStatements) {
            batch.execute(sql);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await DatabaseHelper.onUpgrade(db, oldVersion, newVersion);
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

  /// Opens an isolated in-memory database for testing
  static Future<Database> openInMemory({DatabaseFactory? factory}) async {
    initializeFfi();
    final f = factory ?? databaseFactoryFfi;
    return await f.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final sql in AppSchema.createTablesStatements) {
            batch.execute(sql);
          }
          for (final sql in AppSchema.createIndicesStatements) {
            batch.execute(sql);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await DatabaseHelper.onUpgrade(db, oldVersion, newVersion);
        },
      ),
    );
  }

  /// Closes database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  /// For testing: close and reset internal reference
  @visibleForTesting
  Future<void> reset() async {
    await close();
  }
}
