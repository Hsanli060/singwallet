// test/presentation/transactions_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/data/repositories/ledger_repository.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/providers/transaction_providers.dart';
import 'package:singwallet/presentation/screens/transactions/transactions_screen.dart';
import 'package:singwallet/presentation/screens/transactions/widgets/monthly_summary_card.dart';
import 'package:singwallet/presentation/screens/transactions/widgets/transaction_group_list.dart';
import 'package:singwallet/presentation/screens/transactions/widgets/transaction_tile.dart';
import 'package:singwallet/presentation/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
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

  Widget buildTestApp({
    Widget? home,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        ledgerRepositoryProvider.overrideWithValue(ledgerRepo),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: home ?? const TransactionsScreen(),
      ),
    );
  }

  /// Helper to allow SQLite FFI background isolate to resolve before pumping frames
  Future<void> pumpAsync(WidgetTester tester, [int millis = 100]) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration(milliseconds: millis));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  group('MonthlySummaryCard Widget Tests', () {
    testWidgets('renders month selector and updates month on chevron clicks', (tester) async {
      await tester.pumpWidget(buildTestApp(
        home: const Scaffold(body: MonthlySummaryCard()),
        overrides: [
          selectedMonthProvider.overrideWith(() => _FixedMonthNotifier('2026-10')),
        ],
      ));
      await pumpAsync(tester);

      expect(find.text('2026年10月'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Verify 4 key financial metrics labels
      expect(find.text('本月支出'), findsOneWidget);
      expect(find.text('退款总计'), findsOneWidget);
      expect(find.text('净支出'), findsOneWidget);
      expect(find.text('总收入'), findsOneWidget);
    });

    testWidgets('displays correct aggregated currency amounts', (tester) async {
      // Insert sample transactions into SQLite
      const tx1 = TransactionEntry(
        id: 'tx_sum_1',
        type: 'expense',
        amountMinor: 5800, // 58.00
        merchantRaw: '喜茶',
        occurredOn: '2026-10-15',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-15T12:00:00Z',
        updatedAt: '2026-10-15T12:00:00Z',
      );
      const tx2 = TransactionEntry(
        id: 'tx_sum_2',
        type: 'refund',
        amountMinor: 800, // 8.00
        merchantRaw: '喜茶退款',
        occurredOn: '2026-10-16',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-16T12:00:00Z',
        updatedAt: '2026-10-16T12:00:00Z',
      );
      const tx3 = TransactionEntry(
        id: 'tx_sum_3',
        type: 'income',
        amountMinor: 100000, // 1000.00
        merchantRaw: '发工资',
        occurredOn: '2026-10-20',
        eventTimeSource: 'user_selected',
        eventTimePrecision: 'day',
        paymentChannel: 'bank',
        accountId: 'acc_bank',
        categoryId: 'cat_income',
        createdAt: '2026-10-20T09:00:00Z',
        updatedAt: '2026-10-20T09:00:00Z',
      );

      await tester.runAsync(() async {
        await db.insert('transactions', tx1.toMap());
        await db.insert('transactions', tx2.toMap());
        await db.insert('transactions', tx3.toMap());
      });

      await tester.pumpWidget(buildTestApp(
        home: const Scaffold(body: MonthlySummaryCard()),
        overrides: [
          selectedMonthProvider.overrideWith(() => _FixedMonthNotifier('2026-10')),
        ],
      ));
      await pumpAsync(tester);

      // Expense: 58.00, Refund: 8.00, Net Expense: 50.00, Income: 1000.00
      expect(find.text('¥58.00'), findsOneWidget);
      expect(find.text('¥8.00'), findsOneWidget);
      expect(find.text('¥50.00'), findsOneWidget);
      expect(find.text('¥1000.00'), findsOneWidget);
      expect(find.text('共 2 笔'), findsOneWidget); // 1 expense + 1 refund
    });
  });

  group('TransactionGroupList & TransactionTile Tests', () {
    testWidgets('renders single TransactionTile directly', (tester) async {
      const tx = TransactionEntry(
        id: 'tx_single_tile',
        type: 'expense',
        amountMinor: 2500,
        merchantRaw: '星巴克',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        projectId: 'proj_travel',
        createdAt: '2026-10-23T14:30:00Z',
        updatedAt: '2026-10-23T14:30:00Z',
      );
      await tester.pumpWidget(buildTestApp(
        home: const Scaffold(body: TransactionTile(transaction: tx)),
      ));
      await pumpAsync(tester);
      expect(find.text('星巴克'), findsOneWidget);
      expect(find.text('微信支付'), findsOneWidget);
      expect(find.text('餐饮美食'), findsOneWidget);
      expect(find.text('#旅行出游'), findsOneWidget);
    });

    testWidgets('renders daily grouped header with subtotal and rich tile elements', (tester) async {
      const tx = TransactionEntry(
        id: 'tx_rich_tile',
        type: 'refund',
        amountMinor: 2500, // 25.00
        merchantRaw: '星巴克甄选店',
        merchantNormalized: '星巴克',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        projectId: 'proj_travel',
        note: '咖啡退差价',
        createdAt: '2026-10-23T14:30:00Z',
        updatedAt: '2026-10-23T14:30:00Z',
      );
      await tester.runAsync(() async {
        await db.insert('transactions', tx.toMap());
      });

      await tester.pumpWidget(buildTestApp(
        home: const Scaffold(body: TransactionGroupList()),
      ));
      await pumpAsync(tester);

      // Daily header
      expect(find.textContaining('2026-10-23'), findsWidgets);
      expect(find.textContaining('退款 ¥25.00'), findsOneWidget);

      // Merchant
      expect(find.text('星巴克'), findsOneWidget);

      // Capsules & Badges
      expect(find.text('微信支付'), findsOneWidget); // Account name
      expect(find.text('餐饮美食'), findsOneWidget); // Category name
      expect(find.text('退款'), findsOneWidget); // Refund badge
      expect(find.text('#旅行出游'), findsOneWidget); // Project badge
      expect(find.text('咖啡退差价'), findsOneWidget); // Note
      expect(find.text('+¥25.00'), findsOneWidget); // Amount with sign
    });

    testWidgets('empty state displays friendly placeholder', (tester) async {
      await tester.pumpWidget(buildTestApp(
        home: const Scaffold(body: TransactionGroupList()),
      ));
      await pumpAsync(tester);

      expect(find.text('暂无流水记录'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    });
  });

  group('Soft Delete & Undo SnackBar Tests', () {
    testWidgets('dismissing transaction tile triggers softDelete and Undo restores it', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const tx = TransactionEntry(
        id: 'tx_soft_delete_1',
        type: 'expense',
        amountMinor: 3000,
        merchantRaw: '全家便利店',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-23T08:00:00Z',
        updatedAt: '2026-10-23T08:00:00Z',
      );
      await tester.runAsync(() async {
        await db.insert('transactions', tx.toMap());
      });

      await tester.pumpWidget(buildTestApp(
        home: const Scaffold(body: TransactionGroupList()),
      ));
      await pumpAsync(tester);

      expect(find.text('全家便利店'), findsOneWidget);

      // Drag to dismiss
      await tester.drag(find.byKey(const Key('tx_tile_tx_soft_delete_1')), const Offset(-600, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // finish slide off screen
      await tester.pump(const Duration(milliseconds: 300)); // finish resize and trigger onDismissed

      // Let SQLite background isolate process softDelete and refresh completely
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      // Should be removed from list
      expect(find.text('全家便利店'), findsNothing);
      expect(find.text('已移入回收站'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);

      // Tap Undo ("撤销")
      await tester.tap(find.text('撤销'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      // Transaction is restored
      expect(find.text('全家便利店'), findsOneWidget);
    });
  });

  group('TransactionFilterSheet Tests', () {
    testWidgets('opens filter sheet, selects filters, applies them and displays active chips', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const tx1 = TransactionEntry(
        id: 'tx_f_1',
        type: 'expense',
        amountMinor: 4000,
        merchantRaw: '肯德基',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
      );
      const tx2 = TransactionEntry(
        id: 'tx_f_2',
        type: 'income',
        amountMinor: 80000,
        merchantRaw: '兼职报酬',
        occurredOn: '2026-10-23',
        eventTimeSource: 'user_selected',
        eventTimePrecision: 'day',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_income',
        createdAt: '2026-10-23T11:00:00Z',
        updatedAt: '2026-10-23T11:00:00Z',
      );

      await tester.runAsync(() async {
        await db.insert('transactions', tx1.toMap());
        await db.insert('transactions', tx2.toMap());
      });

      await tester.pumpWidget(buildTestApp(
        home: const TransactionsScreen(),
      ));
      await pumpAsync(tester);

      expect(find.text('肯德基'), findsOneWidget);
      expect(find.text('兼职报酬'), findsOneWidget);

      // Tap Filter button in AppBar
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      expect(find.text('筛选流水'), findsOneWidget);
      expect(find.text('交易类型'), findsOneWidget);

      // Select '收入' type ChoiceChip
      await tester.tap(find.widgetWithText(ChoiceChip, '收入'));
      await tester.pump();

      // Tap '应用筛选'
      await tester.tap(find.text('应用筛选'));
      await pumpAsync(tester, 300);
      await tester.pumpAndSettle();

      // Sheet is closed, active filter chips bar visible
      expect(find.text('类型: 收入'), findsOneWidget);
      expect(find.text('肯德基'), findsNothing);
      expect(find.text('兼职报酬'), findsOneWidget);

      // Dismiss chip
      await tester.tap(find.text('重置全部')); // Reset all
      await pumpAsync(tester, 300);
      await tester.pumpAndSettle();

      expect(find.text('肯德基'), findsOneWidget);
      expect(find.text('兼职报酬'), findsOneWidget);
    });
  });

  group('TrashBinDialog Tests', () {
    testWidgets('shows soft-deleted transactions and supports restore, permanent delete, and purge all', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const tx1 = TransactionEntry(
        id: 'tx_trash_1',
        type: 'expense',
        amountMinor: 6600,
        merchantRaw: '耐克专柜',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-22T10:00:00Z',
        updatedAt: '2026-10-22T10:00:00Z',
      );
      const tx2 = TransactionEntry(
        id: 'tx_trash_2',
        type: 'expense',
        amountMinor: 8800,
        merchantRaw: '阿迪达斯',
        occurredOn: '2026-10-22',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-22T11:00:00Z',
        updatedAt: '2026-10-22T11:00:00Z',
      );

      await tester.runAsync(() async {
        await db.insert('transactions', tx1.toMap());
        await db.insert('transactions', tx2.toMap());
        await ledgerRepo.softDeleteTransaction('tx_trash_1');
        await ledgerRepo.softDeleteTransaction('tx_trash_2');
      });

      await tester.pumpWidget(buildTestApp(
        home: const TransactionsScreen(),
      ));
      await pumpAsync(tester);

      // Active screen has no items
      expect(find.text('暂无流水记录'), findsOneWidget);

      // Open TrashBinDialog
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await pumpAsync(tester, 300);
      await tester.pumpAndSettle();

      expect(find.text('回收站'), findsOneWidget);
      expect(find.text('耐克专柜'), findsOneWidget);
      expect(find.text('阿迪达斯'), findsOneWidget);

      // Restore '耐克专柜' ('tx_trash_1')
      final nikeTile = find.ancestor(of: find.text('耐克专柜'), matching: find.byType(ListTile));
      final nikeRestoreBtn = find.descendant(of: nikeTile, matching: find.byIcon(Icons.restore));
      await tester.tap(nikeRestoreBtn);
      await pumpAsync(tester, 300);
      await tester.pumpAndSettle();

      // Close dialog
      await tester.tap(find.byIcon(Icons.close));
      await pumpAsync(tester, 300);
      await tester.pumpAndSettle();

      // Active screen now displays restored item
      expect(find.text('耐克专柜'), findsOneWidget);
      expect(find.text('阿迪达斯'), findsNothing);

      // Open TrashBin again
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await pumpAsync(tester, 300);
      await tester.pumpAndSettle();

      expect(find.text('阿迪达斯'), findsOneWidget);

      // Purge all
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();

      expect(find.text('确认清空'), findsOneWidget);
      await tester.tap(find.text('确认清空'));
      await pumpAsync(tester, 300);
      await tester.pumpAndSettle();

      expect(find.text('回收站为空'), findsOneWidget);
    });
  });
}

class _FixedMonthNotifier extends SelectedMonthNotifier {
  final String fixedMonth;
  _FixedMonthNotifier(this.fixedMonth);

  @override
  String build() => fixedMonth;
}
