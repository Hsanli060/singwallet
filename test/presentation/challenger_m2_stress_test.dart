// test/presentation/challenger_m2_stress_test.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/core/utils/currency_utils.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/data/repositories/ledger_repository.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/screens/drafts/widgets/deduplication_dialogs.dart';
import 'package:singwallet/presentation/screens/drafts/widgets/ocr_bounding_box_overlay.dart';
import 'package:singwallet/presentation/screens/transactions/widgets/transaction_group_list.dart';
import 'package:singwallet/presentation/screens/transactions/widgets/transaction_tile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper for async SQLite resolution in widget tests
  Future<void> pumpAsync(WidgetTester tester, [int millis = 80]) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration(milliseconds: millis));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump();
  }

  // =========================================================================
  // 1. Boundary Coordinates Verification: BoundingBoxMapper Stress Harness
  // =========================================================================
  group('1. BoundingBoxMapper Extreme Boundary & Geometry Stress Tests', () {
    test('full unit span [0.0, 1.0] in ultrawide viewport preserves pillarbox letterbox', () {
      const imageSize = Size(1080, 2400); // 9:20 aspect ratio
      const viewportSize = Size(8000, 600); // Extreme ultrawide viewport

      final fullBox = OcrBoundingBox(left: 0.0, top: 0.0, width: 1.0, height: 1.0);
      final rect = BoundingBoxMapper.mapNormalizedToViewport(
        box: fullBox,
        imageSize: imageSize,
        viewportSize: viewportSize,
      );

      // Scale should be constrained by height (600 / 2400 = 0.25)
      expect(rect.height, closeTo(600.0, 0.001));
      expect(rect.width, closeTo(1080 * 0.25, 0.001)); // 270.0
      expect(rect.top, closeTo(0.0, 0.001));
      // Centered horizontally: (8000 - 270) / 2 = 3865.0
      expect(rect.left, closeTo(3865.0, 0.001));
      // Must fit strictly within viewport boundaries
      expect(rect.right, lessThanOrEqualTo(viewportSize.width));
      expect(rect.bottom, lessThanOrEqualTo(viewportSize.height));
      expect(rect.left, greaterThanOrEqualTo(0.0));
      expect(rect.top, greaterThanOrEqualTo(0.0));
    });

    test('full unit span [0.0, 1.0] in ultratall viewport preserves aspect ratio', () {
      const imageSize = Size(3840, 1080); // Wide panorama
      const viewportSize = Size(400, 8000); // Extreme vertical viewport

      final fullBox = OcrBoundingBox(left: 0.0, top: 0.0, width: 1.0, height: 1.0);
      final rect = BoundingBoxMapper.mapNormalizedToViewport(
        box: fullBox,
        imageSize: imageSize,
        viewportSize: viewportSize,
      );

      // Scale constrained by width: 400 / 3840 = 0.1041666...
      const expectedScale = 400.0 / 3840.0;
      const expectedRenderedHeight = 1080.0 * expectedScale; // 112.5
      expect(rect.width, closeTo(400.0, 0.001));
      expect(rect.height, closeTo(expectedRenderedHeight, 0.001));
      expect(rect.left, closeTo(0.0, 0.001));
      // Centered vertically
      const expectedOffsetY = (8000.0 - expectedRenderedHeight) / 2.0;
      expect(rect.top, closeTo(expectedOffsetY, 0.001));
      expect(rect.bottom, lessThanOrEqualTo(viewportSize.height));
    });

    test('sub-pixel microscopic dimensions do not produce NaN or crash', () {
      const imageSize = Size(1000, 1000);
      const viewportSize = Size(500, 500);

      final microBox = OcrBoundingBox(
        left: 0.5,
        top: 0.5,
        width: 1e-9,
        height: 1e-9,
      );

      final rect = BoundingBoxMapper.mapNormalizedToViewport(
        box: microBox,
        imageSize: imageSize,
        viewportSize: viewportSize,
      );

      expect(rect.left.isFinite, isTrue);
      expect(rect.top.isFinite, isTrue);
      expect(rect.width.isFinite, isTrue);
      expect(rect.height.isFinite, isTrue);
      expect(rect.width, greaterThan(0.0));
      expect(rect.height, greaterThan(0.0));
      expect(rect.left, closeTo(250.0, 0.001));
      expect(rect.top, closeTo(250.0, 0.001));
    });

    test('zero and negative viewport or image dimensions safely return Rect.zero', () {
      final box = OcrBoundingBox(left: 0.1, top: 0.1, width: 0.5, height: 0.5);

      expect(
        BoundingBoxMapper.mapNormalizedToViewport(
          box: box,
          imageSize: const Size(0, 1000),
          viewportSize: const Size(500, 500),
        ),
        equals(Rect.zero),
      );

      expect(
        BoundingBoxMapper.mapNormalizedToViewport(
          box: box,
          imageSize: const Size(1000, 0),
          viewportSize: const Size(500, 500),
        ),
        equals(Rect.zero),
      );

      expect(
        BoundingBoxMapper.mapNormalizedToViewport(
          box: box,
          imageSize: const Size(1000, 1000),
          viewportSize: const Size(0, 500),
        ),
        equals(Rect.zero),
      );

      expect(
        BoundingBoxMapper.mapNormalizedToViewport(
          box: box,
          imageSize: const Size(1000, 1000),
          viewportSize: const Size(500, -10),
        ),
        equals(Rect.zero),
      );
    });

    test('1000 random stress coordinates all preserve affine scaling', () {
      final rng = math.Random(42);
      for (var i = 0; i < 1000; i++) {
        final imgW = 100.0 + rng.nextDouble() * 4000.0;
        final imgH = 100.0 + rng.nextDouble() * 4000.0;
        final vpW = 100.0 + rng.nextDouble() * 2000.0;
        final vpH = 100.0 + rng.nextDouble() * 2000.0;

        final l = rng.nextDouble();
        final t = rng.nextDouble();
        final w = rng.nextDouble() * (1.0 - l);
        final h = rng.nextDouble() * (1.0 - t);

        final box = OcrBoundingBox(left: l, top: t, width: w, height: h);
        final rect = BoundingBoxMapper.mapNormalizedToViewport(
          box: box,
          imageSize: Size(imgW, imgH),
          viewportSize: Size(vpW, vpH),
        );

        expect(rect.left.isFinite, isTrue);
        expect(rect.top.isFinite, isTrue);
        expect(rect.width.isFinite, isTrue);
        expect(rect.height.isFinite, isTrue);
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.top, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(vpW + 0.001));
        expect(rect.bottom, lessThanOrEqualTo(vpH + 0.001));
      }
    });
  });

  // =========================================================================
  // 2. Deduplication Alert Dialog Robustness: Tier 3 Block & Tier 4 Explicit Action
  // =========================================================================
  group('2. Deduplication Alert Dialog Robustness Suite', () {
    late Database db;
    late DeduplicationEngine dedupEngine;

    setUp(() async {
      db = await AppDatabase.openInMemory();
      dedupEngine = DeduplicationEngine(db);
      await DatabaseSeeder.seedIfNeeded(db);
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('Tier 3 active duplicate shows Red blocking dialog and blocks barrier dismissal',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('show_tier3_btn'),
                onPressed: () {
                  DeduplicationDialogs.showTier3ActiveDialog(
                    context,
                    transactionId: 'tx_existing_jd',
                    transaction: {
                      'merchant_raw': '京东商城',
                      'amount_minor': 8800,
                      'occurred_on': '2026-10-23',
                    },
                  );
                },
                child: const Text('Show Tier 3'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('show_tier3_btn')));
      await tester.pumpAndSettle();

      // 1. Verify Red alert dialog appears with exact text
      expect(find.text('发现重复交易'), findsOneWidget);
      expect(find.text('发现完全相同订单号的已确认交易，禁止重复入账。'), findsOneWidget);
      expect(find.text('商户: 京东商城'), findsOneWidget);
      expect(find.text('金额: ¥88.00'), findsOneWidget);

      // 2. Barrier dismissibility check: tapping outside dialog (top left 10,10) does NOT dismiss
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('发现重复交易'), findsOneWidget);

      // 3. Tap the only action button '我知道了'
      final okBtn = find.byKey(const ValueKey('tier3_active_dialog_ok'));
      expect(okBtn, findsOneWidget);
      await tester.tap(okBtn);
      await tester.pumpAndSettle();

      // 4. Verify dialog closes
      expect(find.text('发现重复交易'), findsNothing);
    });

    testWidgets('Tier 4 heuristic duplicate dialog requires explicit user confirmation to proceed',
        (tester) async {
      bool? userResult;
      final candidates = [
        {
          'merchant_raw': '瑞幸咖啡 (软件园店)',
          'amount_minor': 3500,
          'occurred_on': '2026-10-23',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('show_tier4_btn'),
                onPressed: () async {
                  userResult = await DeduplicationDialogs.showTier4FuzzyDialog(
                    context,
                    candidates: candidates,
                  );
                },
                child: const Text('Show Tier 4'),
              ),
            ),
          ),
        ),
      );

      // --- Scenario A: User Cancels ---
      await tester.tap(find.byKey(const ValueKey('show_tier4_btn')));
      await tester.pumpAndSettle();

      expect(find.text('疑似重复交易'), findsOneWidget);
      expect(find.text('24小时内发现相同金额的相似交易，是否确认这笔交易不是重复记录？'), findsOneWidget);
      expect(find.text('瑞幸咖啡 (软件园店)'), findsOneWidget);
      expect(find.text('¥35.00'), findsOneWidget);

      // Verify barrier tap does NOT dismiss
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('疑似重复交易'), findsOneWidget);

      // Tap '取消'
      await tester.tap(find.byKey(const ValueKey('tier4_fuzzy_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(find.text('疑似重复交易'), findsNothing);
      expect(userResult, isFalse);

      // --- Scenario B: User Explicitly Confirms ---
      userResult = null;
      await tester.tap(find.byKey(const ValueKey('show_tier4_btn')));
      await tester.pumpAndSettle();

      expect(find.text('疑似重复交易'), findsOneWidget);
      // Tap '继续入账' (explicit user action)
      await tester.tap(find.byKey(const ValueKey('tier4_fuzzy_dialog_proceed')));
      await tester.pumpAndSettle();

      expect(find.text('疑似重复交易'), findsNothing);
      expect(userResult, isTrue);
    });

    test('Tier 3 hard platform duplicate triggers blocking evaluation in engine', () async {
      const existingTx = TransactionEntry(
        id: 'tx_tier3_active',
        type: 'expense',
        amountMinor: 8800,
        merchantRaw: '京东商城',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
      );
      await db.insert('transactions', existingTx.toMap());

      await db.insert('confirmed_identifiers', {
        'namespace': 'alipay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'JD2026102388001122',
        'stable_event_kind': 'payment',
        'transaction_id': existingTx.id,
      });

      final platformId = PlatformIdentifier(
        namespace: 'alipay',
        identifierType: 'platform_transaction_no',
        completeValue: 'JD2026102388001122',
        stableEventKind: 'payment',
        completeness: IdentifierCompleteness.complete,
      );

      final eval = await dedupEngine.evaluate(
        platformIdentifier: platformId,
        merchantRaw: '京东商城新订单',
        amountMinor: 8800,
        occurredOn: '2026-10-23',
      );

      expect(eval.hasHardDuplicate, isTrue);
      expect(eval.tier3.isMatched, isTrue);
      expect(eval.tier3.isInTrash, isFalse);
      expect(eval.tier3.matchedTransactionId, equals('tx_tier3_active'));
    });

    test('Tier 4 24h heuristic duplicate detects same amount candidate and clears beyond 24h', () async {
      const txRecent = TransactionEntry(
        id: 'tx_recent_luckin',
        type: 'expense',
        amountMinor: 3500,
        merchantRaw: '瑞幸咖啡',
        occurredOn: '2026-10-23',
        occurredAt: '2026-10-23T10:00:00Z',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
      );
      await db.insert('transactions', txRecent.toMap());

      // Within 24h (3 hours later): suspected duplicate detected!
      final evalWithin = await dedupEngine.evaluate(
        merchantRaw: '瑞幸咖啡',
        amountMinor: 3500,
        occurredOn: '2026-10-23',
        occurredAt: '2026-10-23T13:00:00Z',
      );
      expect(evalWithin.tier4.hasSuspectedDuplicates, isTrue);
      expect(evalWithin.tier4.candidateTransactions.length, equals(1));
      expect(evalWithin.tier4.candidateTransactions.first['id'], equals('tx_recent_luckin'));

      // Beyond 24h (48 hours later): no false positive!
      final evalBeyond = await dedupEngine.evaluate(
        merchantRaw: '瑞幸咖啡',
        amountMinor: 3500,
        occurredOn: '2026-10-25',
        occurredAt: '2026-10-25T14:00:00Z',
      );
      expect(evalBeyond.tier4.hasSuspectedDuplicates, isFalse);
    });
  });

  // =========================================================================
  // 3. Currency Precision: Decimal Conversion without Floating-Point Drift
  // =========================================================================
  group('3. Currency Precision & Float Drift Immunity Tests', () {
    test('IEEE-754 dangerous floating point values convert with 100% exact minor cents', () {
      // These decimal values notoriously suffer from float drift in double arithmetic:
      // In double: 0.29 * 100 = 28.999999999999996 -> .toInt() produces 28!
      // In double: 0.57 * 100 = 56.99999999999999 -> .toInt() produces 56!
      // In double: 0.58 * 100 = 57.99999999999999 -> .toInt() produces 57!
      // In double: 1.13 * 100 = 112.99999999999999 -> .toInt() produces 112!
      // In double: 1.14 * 100 = 113.99999999999999 -> .toInt() produces 113!
      // In double: 1.15 * 100 = 114.99999999999999 -> .toInt() produces 114!
      // In double: 2.29 * 100 = 228.99999999999997 -> .toInt() produces 228!
      // In double: 29.99 * 100 = 2998.9999999999995 -> .toInt() produces 2998!

      final testCases = <String, int>{
        '0.01': 1,
        '0.07': 7,
        '0.29': 29,
        '0.57': 57,
        '0.58': 58,
        '1.13': 113,
        '1.14': 114,
        '1.15': 115,
        '2.29': 229,
        '29.99': 2999,
        '99.99': 9999,
        '199.90': 19990,
        '1000000.01': 100000001,
        '0.1': 10,
        '0.10': 10,
        '.50': 50,
        '42.': 4200,
        '0': 0,
        '0.00': 0,
      };

      for (final entry in testCases.entries) {
        final parsed = CurrencyUtils.parseToMinorUnits(entry.key);
        expect(
          parsed,
          equals(entry.value),
          reason: 'Input "${entry.key}" must parse strictly to ${entry.value} minor units without float drift',
        );

        // Verify round-trip formatting
        final formatted = CurrencyUtils.centsToYuanString(parsed);
        final roundTripParsed = CurrencyUtils.parseToMinorUnits(formatted);
        expect(roundTripParsed, equals(entry.value));
      }
    });

    test('roundSubUnits parameter handles sub-cent fractional currency accurately', () {
      // Sub-cent truncation vs half-up rounding
      expect(CurrencyUtils.parseToMinorUnits('12.345', roundSubUnits: false), equals(1234));
      expect(CurrencyUtils.parseToMinorUnits('12.345', roundSubUnits: true), equals(1235));
      expect(CurrencyUtils.parseToMinorUnits('12.344', roundSubUnits: true), equals(1234));
      expect(CurrencyUtils.parseToMinorUnits('12.349', roundSubUnits: true), equals(1235));
    });

    test('64-bit integer overflow protection triggers format exception on exceeding boundary', () {
      // Max safe: 92233720368547758 * 100 + 7 = 9223372036854775807
      const maxSafe = '92233720368547758.07';
      final parsed = CurrencyUtils.parseToMinorUnits(maxSafe);
      expect(parsed, equals(9223372036854775807));

      // Overflows signed 64-bit boundary
      const overflowStr = '92233720368547758.08';
      expect(
        () => CurrencyUtils.parseToMinorUnits(overflowStr),
        throwsFormatException,
      );
    });

    test('all 100 combinations from .00 to .99 convert with zero float truncation errors', () {
      for (var cents = 0; cents < 100; cents++) {
        final centStr = cents.toString().padLeft(2, '0');
        final input = '88.$centStr';
        final expected = 8800 + cents;

        final actual = CurrencyUtils.parseToMinorUnits(input);
        expect(actual, equals(expected));
        expect(CurrencyUtils.centsToYuanString(actual), equals(input));
      }
    });
  });

  // =========================================================================
  // 4. Soft Delete & Restore: State Fidelity & Undo Flow without Data Loss
  // =========================================================================
  group('4. Soft Delete & Restore Exact State Integrity Tests', () {
    late Database db;
    late LedgerRepository ledgerRepo;

    setUp(() async {
      db = await AppDatabase.openInMemory();
      ledgerRepo = LedgerRepository(db);
      await DatabaseSeeder.seedIfNeeded(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('soft deleting and restoring transaction preserves 100% of fields and relations', () async {
      // 1. Insert transaction with full rich metadata
      const initialTx = TransactionEntry(
        id: 'tx_rich_fidelity_1',
        originDraftId: null,
        type: 'expense',
        amountMinor: 12850,
        currency: 'CNY',
        merchantRaw: 'Apple Store (静安店)',
        merchantNormalized: '苹果直营店',
        occurredOn: '2026-10-23',
        occurredAt: '2026-10-23T15:30:00Z',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        projectId: 'proj_travel',
        note: '购买 USB-C 数据线',
        createdAt: '2026-10-23T15:35:00Z',
        updatedAt: '2026-10-23T15:35:00Z',
      );
      await db.insert('transactions', initialTx.toMap());

      // Insert confirmed identifier
      await db.insert('confirmed_identifiers', {
        'namespace': 'alipay',
        'identifier_type': 'platform_transaction_no',
        'complete_value': 'AP2026102399990001',
        'stable_event_kind': 'payment',
        'transaction_id': initialTx.id,
      });

      // 2. Initial state verification: appears in active query, summary, and trash is empty
      final initialActive = await ledgerRepo.getTransactions();
      expect(initialActive.any((t) => t.id == initialTx.id), isTrue);

      final summaryBefore = await ledgerRepo.getMonthlySummary('2026-10');
      expect(summaryBefore.totalExpenseMinor, equals(12850));

      final trashBefore = await ledgerRepo.getTrashBinTransactions();
      expect(trashBefore, isEmpty);

      // 3. Perform Soft Delete
      await ledgerRepo.softDeleteTransaction(initialTx.id);

      // 4. Verification post-soft delete:
      // a. Removed from active transactions
      final activePostDelete = await ledgerRepo.getTransactions();
      expect(activePostDelete.any((t) => t.id == initialTx.id), isFalse);

      // b. Monthly summary excludes soft-deleted transaction
      final summaryPostDelete = await ledgerRepo.getMonthlySummary('2026-10');
      expect(summaryPostDelete.totalExpenseMinor, equals(0));

      // c. Appears in trash bin
      final trashPostDelete = await ledgerRepo.getTrashBinTransactions();
      expect(trashPostDelete.length, equals(1));
      expect(trashPostDelete.first.id, equals(initialTx.id));

      // d. Database row inspection: deleted_at is populated, but other fields are UNTOUCHED!
      final rawDeletedRows = await db.query('transactions', where: 'id = ?', whereArgs: [initialTx.id]);
      expect(rawDeletedRows.length, equals(1));
      final rawRow = rawDeletedRows.first;
      expect(rawRow['deleted_at'], isNotNull);
      expect(rawRow['amount_minor'], equals(12850));
      expect(rawRow['merchant_raw'], equals('Apple Store (静安店)'));
      expect(rawRow['merchant_normalized'], equals('苹果直营店'));
      expect(rawRow['note'], equals('购买 USB-C 数据线'));
      expect(rawRow['project_id'], equals('proj_travel'));
      expect(rawRow['account_id'], equals('acc_alipay'));
      expect(rawRow['category_id'], equals('cat_shopping'));

      // e. Relational data in confirmed_identifiers remains intact during soft delete
      final idents = await db.query('confirmed_identifiers', where: 'transaction_id = ?', whereArgs: [initialTx.id]);
      expect(idents.length, equals(1));

      // 5. Perform Restore (Undo)
      await ledgerRepo.restoreTransaction(initialTx.id);

      // 6. Verification post-restore:
      // a. Re-appears in active transactions
      final activePostRestore = await ledgerRepo.getTransactions();
      expect(activePostRestore.length, equals(1));
      final restoredTx = activePostRestore.first;

      // b. Exact state comparison (zero data loss)
      expect(restoredTx.id, equals(initialTx.id));
      expect(restoredTx.originDraftId, equals(initialTx.originDraftId));
      expect(restoredTx.type, equals(initialTx.type));
      expect(restoredTx.amountMinor, equals(initialTx.amountMinor));
      expect(restoredTx.currency, equals(initialTx.currency));
      expect(restoredTx.merchantRaw, equals(initialTx.merchantRaw));
      expect(restoredTx.merchantNormalized, equals(initialTx.merchantNormalized));
      expect(restoredTx.occurredOn, equals(initialTx.occurredOn));
      expect(restoredTx.occurredAt, equals(initialTx.occurredAt));
      expect(restoredTx.eventTimeSource, equals(initialTx.eventTimeSource));
      expect(restoredTx.eventTimePrecision, equals(initialTx.eventTimePrecision));
      expect(restoredTx.paymentChannel, equals(initialTx.paymentChannel));
      expect(restoredTx.accountId, equals(initialTx.accountId));
      expect(restoredTx.categoryId, equals(initialTx.categoryId));
      expect(restoredTx.projectId, equals(initialTx.projectId));
      expect(restoredTx.note, equals(initialTx.note));
      expect(restoredTx.createdAt, equals(initialTx.createdAt));
      expect(restoredTx.deletedAt, isNull);

      // c. Monthly summary is restored
      final summaryPostRestore = await ledgerRepo.getMonthlySummary('2026-10');
      expect(summaryPostRestore.totalExpenseMinor, equals(12850));

      // d. Trash bin is clean again
      final trashPostRestore = await ledgerRepo.getTrashBinTransactions();
      expect(trashPostRestore, isEmpty);
    });

    testWidgets('TransactionGroupList soft delete and undo restores tile and active state',
        (tester) async {
      const tx = TransactionEntry(
        id: 'tx_ui_undo_test',
        type: 'expense',
        amountMinor: 3800,
        merchantRaw: '肯德基',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T12:00:00Z',
        updatedAt: '2026-10-23T12:00:00Z',
      );
      await tester.runAsync(() async {
        await db.insert('transactions', tx.toMap());
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            ledgerRepositoryProvider.overrideWithValue(ledgerRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TransactionGroupList()),
          ),
        ),
      );

      await pumpAsync(tester, 120);

      // 1. Transaction should be visible
      expect(find.text('肯德基'), findsOneWidget);
      expect(find.text('-¥38.00'), findsOneWidget);

      // 2. Trigger soft delete via tile
      final tileFinder = find.byType(TransactionTile);
      expect(tileFinder, findsOneWidget);
      final tile = tester.widget<TransactionTile>(tileFinder);
      tile.onDelete?.call();

      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      // 3. Tile is gone
      expect(find.text('肯德基'), findsNothing);
      expect(find.text('已移入回收站'), findsOneWidget);

      // 4. Tap '撤销'
      final undoBtn = find.text('撤销');
      expect(undoBtn, findsOneWidget);
      await tester.tap(undoBtn);

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      // 5. Transaction is restored
      expect(find.text('肯德基'), findsOneWidget);
      expect(find.text('-¥38.00'), findsOneWidget);

      await tester.runAsync(() async {
        final restoredRows = await db.query('transactions', where: 'id = ?', whereArgs: ['tx_ui_undo_test']);
        expect(restoredRows.first['deleted_at'], isNull);
      });
    });
  });
}
