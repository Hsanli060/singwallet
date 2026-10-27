// test/ota_and_backup_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/services/backup_restore_service.dart';
import 'package:singwallet/core/services/ota_update_service.dart';
import 'package:singwallet/data/database/schema.dart';
import 'package:singwallet/data/local/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.initializeFfi();

  // ===========================================================================
  // 1. OtaUpdateService Semantic Version Comparison Tests
  // ===========================================================================
  group('1. OtaUpdateService Semantic Version Comparison Tests', () {
    test('compareVersions correctly identifies version precedence', () {
      // Older vs Newer -> negative
      expect(OtaUpdateService.compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(OtaUpdateService.compareVersions('1.0.0', '1.1.0'), lessThan(0));
      expect(OtaUpdateService.compareVersions('1.0.0', '2.0.0'), lessThan(0));
      expect(OtaUpdateService.compareVersions('1.9.99', '2.0.0'), lessThan(0));

      // Newer vs Older -> positive
      expect(OtaUpdateService.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(OtaUpdateService.compareVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(OtaUpdateService.compareVersions('1.2.0', '1.1.9'), greaterThan(0));

      // Identical versions -> 0
      expect(OtaUpdateService.compareVersions('1.0.0', '1.0.0'), equals(0));
      expect(OtaUpdateService.compareVersions('2.5.3', '2.5.3'), equals(0));
    });

    test('compareVersions handles prefix v and V cleanly', () {
      expect(OtaUpdateService.compareVersions('v1.0.0', '1.0.0'), equals(0));
      expect(OtaUpdateService.compareVersions('V2.1.0', 'v2.1.0'), equals(0));
      expect(OtaUpdateService.compareVersions('v1.0.0', 'v1.0.1'), lessThan(0));
      expect(OtaUpdateService.compareVersions('v2.0.0', '1.9.9'), greaterThan(0));
    });

    test('compareVersions handles different component lengths', () {
      expect(OtaUpdateService.compareVersions('1.0', '1.0.0'), equals(0));
      expect(OtaUpdateService.compareVersions('1', '1.0.0'), equals(0));
      expect(OtaUpdateService.compareVersions('1.1', '1.0.9'), greaterThan(0));
      expect(OtaUpdateService.compareVersions('1.0.1', '1.1'), lessThan(0));
    });

    test('compareVersions handles build numbers and prerelease tags', () {
      // Build numbers (+1 vs +2)
      expect(OtaUpdateService.compareVersions('1.0.0+1', '1.0.0+2'), lessThan(0));
      expect(OtaUpdateService.compareVersions('1.0.0+5', '1.0.0+3'), greaterThan(0));
      expect(OtaUpdateService.compareVersions('1.0.0+2', '1.0.0+2'), equals(0));

      // Prerelease tags: prerelease is older than stable release
      expect(OtaUpdateService.compareVersions('1.0.0-beta', '1.0.0'), lessThan(0));
      expect(OtaUpdateService.compareVersions('1.0.0', '1.0.0-rc'), greaterThan(0));
      expect(OtaUpdateService.compareVersions('1.0.0-alpha', '1.0.0-beta'), lessThan(0));
    });
  });

  // ===========================================================================
  // 2. OtaUpdateService Release Manifest Parsing Tests
  // ===========================================================================
  group('2. OtaUpdateService Release Manifest Parsing Tests', () {
    test('parseReleaseManifest parses standard GitHub Releases API JSON', () {
      final githubReleaseJson = {
        'tag_name': 'v1.2.0',
        'name': 'SingWallet v1.2.0 Release',
        'body': '## What is New\n* Added OTA check\n* Backup & restore support',
        'assets': [
          {
            'name': 'singwallet-v1.2.0-release.apk',
            'size': 25165824,
            'browser_download_url':
                'https://github.com/singwallet/singwallet/releases/download/v1.2.0/singwallet-v1.2.0-release.apk',
          },
          {
            'name': 'version.json',
            'size': 512,
            'browser_download_url':
                'https://github.com/singwallet/singwallet/releases/download/v1.2.0/version.json',
          }
        ],
        'preserveDataGuaranteed': true,
      };

      // Current version is 1.0.0 -> hasUpdate: true
      final info = OtaUpdateService.parseReleaseManifest(
        githubReleaseJson,
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, equals('1.2.0'));
      expect(info.currentVersion, equals('1.0.0'));
      expect(info.hasUpdate, isTrue);
      expect(info.apkSize, equals(25165824));
      expect(info.downloadUrl, contains('singwallet-v1.2.0-release.apk'));
      expect(info.changelog, contains('Added OTA check'));
      expect(info.preserveDataGuaranteed, isTrue);
      expect(OtaUpdateService.formatApkSize(info.apkSize), equals('24.0 MB'));

      // If current version is already 1.2.0 -> hasUpdate: false
      final upToDateInfo = OtaUpdateService.parseReleaseManifest(
        githubReleaseJson,
        currentVersion: '1.2.0',
      );
      expect(upToDateInfo.hasUpdate, isFalse);

      // If current version is ahead (e.g. 1.3.0) -> hasUpdate: false
      final aheadInfo = OtaUpdateService.parseReleaseManifest(
        githubReleaseJson,
        currentVersion: '1.3.0',
      );
      expect(aheadInfo.hasUpdate, isFalse);
    });

    test('parseReleaseManifest parses custom version.json', () {
      final customVersionJson = {
        'version': '1.1.5',
        'buildNumber': 42,
        'changelog': 'Bug fixes and performance upgrades',
        'downloadUrl': 'https://download.singwallet.app/singwallet-1.1.5.apk',
        'apkSize': 18874368,
        'preserveDataGuaranteed': true,
        'minCompatibleVersion': '1.0.0',
      };

      final info = OtaUpdateService.parseReleaseManifest(
        customVersionJson,
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, equals('1.1.5'));
      expect(info.hasUpdate, isTrue);
      expect(info.apkSize, equals(18874368));
      expect(info.downloadUrl, equals('https://download.singwallet.app/singwallet-1.1.5.apk'));
      expect(info.changelog, equals('Bug fixes and performance upgrades'));
      expect(info.preserveDataGuaranteed, isTrue);
      expect(OtaUpdateService.formatApkSize(info.apkSize), equals('18.0 MB'));
    });

    test('OtaReleaseInfo serializes and deserializes to JSON cleanly', () {
      const original = OtaReleaseInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        hasUpdate: true,
        changelog: 'Feature improvements',
        downloadUrl: 'https://example.com/app.apk',
        apkSize: 10485760,
        preserveDataGuaranteed: true,
      );

      final json = original.toJson();
      final reconstructed = OtaReleaseInfo.fromJson(json);

      expect(reconstructed, equals(original));
      expect(reconstructed.apkSize, equals(10485760));
    });
  });

  // ===========================================================================
  // 3. DatabaseHelper Incremental Lossless Migration (onUpgrade) Tests
  // ===========================================================================
  group('3. DatabaseHelper Incremental Lossless Migration (onUpgrade) Tests', () {
    late Database db;

    setUp(() async {
      // 1. Open an in-memory database strictly at v1
      final factory = databaseFactoryFfi;
      db = await factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
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
        ),
      );

      // 2. Insert v1 canonical test records
      await db.insert('categories', {
        'id': 'cat_food',
        'name': '餐饮美食',
        'applicable_type': 'expense',
        'icon_key': 'food',
        'sort_order': 1,
        'created_at': '2026-10-27T10:00:00Z',
        'updated_at': '2026-10-27T10:00:00Z',
      });

      await db.insert('accounts', {
        'id': 'acc_wechat',
        'name': '微信钱包',
        'kind': 'wechat',
        'created_at': '2026-10-27T10:00:00Z',
        'updated_at': '2026-10-27T10:00:00Z',
      });

      await db.insert('transactions', {
        'id': 'tx_historical_001',
        'type': 'expense',
        'amount_minor': 3250, // 32.50 CNY
        'currency': 'CNY',
        'merchant_raw': '星巴克咖啡（万象城店）',
        'merchant_normalized': '星巴克',
        'occurred_on': '2026-10-27',
        'occurred_at': '2026-10-27T10:30:00+08:00',
        'event_timezone': 'Asia/Shanghai',
        'event_time_source': 'OCR_EXACT',
        'event_time_precision': 'SECOND',
        'payment_channel': 'wechat',
        'category_id': 'cat_food',
        'account_id': 'acc_wechat',
        'note': '历史重要账单',
        'created_at': '2026-10-27T10:35:00Z',
        'updated_at': '2026-10-27T10:35:00Z',
      });

      await db.insert('transaction_metadata', {
        'transaction_id': 'tx_historical_001',
        'original_amount_minor': 3250,
        'payment_status': 'SUCCESS',
        'platform_transaction_no': '42000021342026102799999',
        'identifier_completeness': 'COMPLETE',
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('onUpgrade migrates v1 to v2 while 100% preserving historical transactions', () async {
      // Prior to upgrade: check v1 columns
      var txColumns = await DatabaseHelper.getTableColumns(db, 'transactions');
      var catColumns = await DatabaseHelper.getTableColumns(db, 'categories');
      expect(txColumns.contains('sync_status'), isFalse);
      expect(catColumns.contains('is_custom'), isFalse);
      expect(await DatabaseHelper.hasTable(db, 'vlm_configurations'), isFalse);

      // Execute onUpgrade from 1 -> 2
      await DatabaseHelper.onUpgrade(db, 1, 2);
      await db.setVersion(2);

      // Verify new columns were safely added
      txColumns = await DatabaseHelper.getTableColumns(db, 'transactions');
      catColumns = await DatabaseHelper.getTableColumns(db, 'categories');
      expect(txColumns.contains('sync_status'), isTrue);
      expect(catColumns.contains('is_custom'), isTrue);
      expect(catColumns.contains('color_hex'), isTrue);

      // Verify new tables were created
      expect(await DatabaseHelper.hasTable(db, 'vlm_configurations'), isTrue);
      expect(await DatabaseHelper.hasTable(db, 'ota_update_logs'), isTrue);

      // 【铁律 2 关键验证】：历史账单必须 100% 完好无损！
      final txRows = await db.query('transactions', where: 'id = ?', whereArgs: ['tx_historical_001']);
      expect(txRows.length, equals(1));
      final tx = txRows.first;
      expect(tx['id'], equals('tx_historical_001'));
      expect(tx['amount_minor'], equals(3250));
      expect(tx['merchant_raw'], equals('星巴克咖啡（万象城店）'));
      expect(tx['note'], equals('历史重要账单'));
      expect(tx['sync_status'], equals('LOCAL')); // Default column populated

      final metaRows = await db.query('transaction_metadata', where: 'transaction_id = ?', whereArgs: ['tx_historical_001']);
      expect(metaRows.length, equals(1));
      expect(metaRows.first['platform_transaction_no'], equals('42000021342026102799999'));
    });

    test('onUpgrade is idempotent and safe against repeated executions', () async {
      // First upgrade
      await DatabaseHelper.onUpgrade(db, 1, 2);
      // Repeated invocation (e.g. re-running migration)
      await DatabaseHelper.onUpgrade(db, 1, 2);
      await DatabaseHelper.onUpgrade(db, 2, 2);

      final txColumns = await DatabaseHelper.getTableColumns(db, 'transactions');
      expect(txColumns.contains('sync_status'), isTrue);

      // Historical transaction remains unharmed
      final txCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM transactions;'));
      expect(txCount, equals(1));
    });
  });

  // ===========================================================================
  // 4. BackupRestoreService Export, v1->v2 Migration & Restore Tests
  // ===========================================================================
  group('4. BackupRestoreService Export, v1->v2 Migration & Restore Tests', () {
    late Database db;

    setUp(() async {
      db = await DatabaseHelper.openInMemory(version: 2);

      // Populate initial sample data
      await db.insert('categories', {
        'id': 'cat_food',
        'name': '餐饮美食',
        'applicable_type': 'expense',
        'icon_key': 'food',
        'sort_order': 1,
        'is_custom': 0,
        'created_at': '2026-10-27T10:00:00Z',
        'updated_at': '2026-10-27T10:00:00Z',
      });

      await db.insert('categories', {
        'id': 'cat_custom_coffee',
        'name': '精选手冲',
        'applicable_type': 'expense',
        'icon_key': 'food',
        'sort_order': 99,
        'is_custom': 1,
        'color_hex': '#D97706',
        'created_at': '2026-10-27T11:00:00Z',
        'updated_at': '2026-10-27T11:00:00Z',
      });

      await db.insert('accounts', {
        'id': 'acc_alipay',
        'name': '支付宝',
        'kind': 'alipay',
        'created_at': '2026-10-27T10:00:00Z',
        'updated_at': '2026-10-27T10:00:00Z',
      });

      await db.insert('projects', {
        'id': 'proj_travel',
        'name': '年度旅行',
        'created_at': '2026-10-27T10:00:00Z',
        'updated_at': '2026-10-27T10:00:00Z',
      });

      await db.insert('transactions', {
        'id': 'tx_test_backup_01',
        'type': 'expense',
        'amount_minor': 12800, // 128.00 CNY
        'currency': 'CNY',
        'merchant_raw': '精品民宿',
        'occurred_on': '2026-10-27',
        'occurred_at': '2026-10-27T12:00:00+08:00',
        'event_timezone': 'Asia/Shanghai',
        'event_time_source': 'MANUAL',
        'event_time_precision': 'MINUTE',
        'payment_channel': 'alipay',
        'category_id': 'cat_custom_coffee',
        'account_id': 'acc_alipay',
        'project_id': 'proj_travel',
        'note': '山顶民宿观星',
        'sync_status': 'LOCAL',
        'created_at': '2026-10-27T12:00:00Z',
        'updated_at': '2026-10-27T12:00:00Z',
      });

      await db.insert('transaction_metadata', {
        'transaction_id': 'tx_test_backup_01',
        'original_amount_minor': 12800,
        'payment_status': 'SUCCESS',
        'identifier_completeness': 'NONE',
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('exportToJson exports valid full snapshot with VLM config', () async {
      final vlmConfig = {
        'protocol': 'ollama',
        'base_url': 'http://localhost:11434',
        'model_name': 'qwen2.5-vl:7b',
      };

      final jsonString = await BackupRestoreService.exportToJson(
        db,
        vlmConfig: vlmConfig,
        appVersion: '1.2.0',
      );

      final Map<String, dynamic> parsed = jsonDecode(jsonString);
      expect(parsed['version'], equals(2));
      expect(parsed['appVersion'], equals('1.2.0'));
      expect(parsed['transactions'], isNotEmpty);
      expect((parsed['transactions'] as List).length, equals(1));
      expect((parsed['categories'] as List).length, equals(2));
      expect((parsed['accounts'] as List).length, equals(1));
      expect((parsed['projects'] as List).length, equals(1));
      expect(parsed['vlmConfig'], isNotNull);
      expect(parsed['vlmConfig']['model_name'], equals('qwen2.5-vl:7b'));
    });

    test('parseAndMigrateSnapshot cleanly migrates legacy v1 backup to v2 format', () {
      final legacyV1Json = {
        'version': 1,
        'appVersion': '1.0.0',
        'exportedAt': '2026-10-25T08:00:00Z',
        'transactions': [
          {
            'id': 'tx_legacy_01',
            'type': 'expense',
            'amount_minor': 500,
            'currency': 'CNY',
            'merchant_raw': '快餐店',
            'occurred_on': '2026-10-25',
            'event_timezone': 'Asia/Shanghai',
            'event_time_source': 'OCR_EXACT',
            'event_time_precision': 'MINUTE',
            'payment_channel': 'wechat',
            'category_id': 'cat_food',
            'created_at': '2026-10-25T08:00:00Z',
            'updated_at': '2026-10-25T08:00:00Z',
            // Note: v1 does NOT have sync_status
          }
        ],
        'transactionMetadata': [],
        'categories': [
          {
            'id': 'cat_food',
            'name': '餐饮美食',
            'applicable_type': 'expense',
            'created_at': '2026-10-25T08:00:00Z',
            'updated_at': '2026-10-25T08:00:00Z',
            // Note: v1 does NOT have is_custom
          },
          {
            'id': 'cat_user_hobby',
            'name': '摄影器材',
            'applicable_type': 'expense',
            'created_at': '2026-10-25T08:00:00Z',
            'updated_at': '2026-10-25T08:00:00Z',
          }
        ],
        'accounts': [],
        'projects': [],
        'tags': [],
        'classificationRules': [],
      };

      final migrated = BackupRestoreService.parseAndMigrateSnapshot(jsonEncode(legacyV1Json));

      // Upgraded to schema version 2
      expect(migrated.version, equals(2));

      // Transactions migrated with default sync_status = 'LOCAL'
      expect(migrated.transactions.first['sync_status'], equals('LOCAL'));

      // Categories migrated: standard cat_food is is_custom=0, user custom is is_custom=1
      final catFood = migrated.categories.firstWhere((c) => c['id'] == 'cat_food');
      final catHobby = migrated.categories.firstWhere((c) => c['id'] == 'cat_user_hobby');
      expect(catFood['is_custom'], equals(0));
      expect(catHobby['is_custom'], equals(1));
    });

    test('importAndMigrateFromJson restores data into clean DB with 100% fidelity', () async {
      // 1. Export current database state
      final exportedJson = await BackupRestoreService.exportToJson(
        db,
        vlmConfig: {'protocol': 'openai', 'model_name': 'gpt-4o'},
      );

      // 2. Open a new clean in-memory database
      final freshDb = await DatabaseHelper.openInMemory(version: 2);
      expect(Sqflite.firstIntValue(await freshDb.rawQuery('SELECT COUNT(*) FROM transactions;')), equals(0));

      // 3. Restore snapshot into fresh DB
      final result = await BackupRestoreService.importAndMigrateFromJson(freshDb, exportedJson);

      expect(result.success, isTrue);
      expect(result.transactionsRestored, equals(1));
      expect(result.categoriesRestored, equals(2));
      expect(result.accountsRestored, equals(1));
      expect(result.projectsRestored, equals(1));
      expect(result.vlmConfigRestored, isTrue);

      // 4. Verify restored record details
      final restoredTx = (await freshDb.query('transactions', where: 'id = ?', whereArgs: ['tx_test_backup_01'])).first;
      expect(restoredTx['amount_minor'], equals(12800));
      expect(restoredTx['merchant_raw'], equals('精品民宿'));
      expect(restoredTx['note'], equals('山顶民宿观星'));

      final restoredVlm = (await freshDb.query('vlm_configurations')).first;
      expect(restoredVlm['model_name'], equals('gpt-4o'));

      await freshDb.close();
    });
  });
}
