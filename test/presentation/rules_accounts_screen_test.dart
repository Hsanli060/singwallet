// test/presentation/rules_accounts_screen_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/state_machine.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/screens/rules_accounts/rules_accounts_screen.dart';
import 'package:singwallet/presentation/screens/rules_accounts/widgets/accounts_tab.dart';
import 'package:singwallet/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart';
import 'package:singwallet/presentation/screens/rules_accounts/widgets/projects_tab.dart';
import 'package:singwallet/presentation/screens/rules_accounts/widgets/refund_link_dialog.dart';
import 'package:singwallet/presentation/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    await DatabaseSeeder.seedIfNeeded(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestWidget({Widget? child}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child ?? const RulesAccountsScreen(showAppBar: true),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  group('RulesAccountsScreen Structure & Tab Navigation', () {
    testWidgets('renders all 3 tabs: 分类规则, 资产账户, 项目管理', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildTestWidget());
        await settle(tester);

        expect(find.text('分类规则'), findsWidgets);
        expect(find.text('资产账户'), findsWidgets);
        expect(find.text('项目管理'), findsWidgets);
        expect(find.byType(ClassificationRulesTab), findsOneWidget);
      });
    });

    testWidgets('switches smoothly between tabs', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildTestWidget());
        await settle(tester);

        // Switch to 资产账户
        await tester.tap(find.text('资产账户').first);
        await settle(tester);
        expect(find.byType(AccountsTab), findsOneWidget);

        // Switch to 项目管理
        await tester.tap(find.text('项目管理').first);
        await settle(tester);
        expect(find.byType(ProjectsTab), findsOneWidget);

        // Switch back to 分类规则
        await tester.tap(find.text('分类规则').first);
        await settle(tester);
        expect(find.byType(ClassificationRulesTab), findsOneWidget);
      });
    });
  });

  group('ClassificationRulesTab Features', () {
    testWidgets('displays rules sorted by priority DESC and toggles active switch',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        // Insert test rules with different priorities inside runAsync
        await db.insert('classification_rules', {
          'id': 'rule_starbucks',
          'priority': 80,
          'merchant_pattern': '星巴克',
          'category_id': 'cat_food',
          'enabled': 1,
          'version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        await db.insert('classification_rules', {
          'id': 'rule_subway',
          'priority': 120,
          'merchant_pattern': '地铁出行',
          'category_id': 'cat_transport',
          'enabled': 1,
          'version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        await tester.pumpWidget(buildTestWidget());
        await settle(tester);

        expect(find.text('星巴克'), findsOneWidget);
        expect(find.text('地铁出行'), findsOneWidget);
        expect(find.text('优先级: 120'), findsOneWidget);
        expect(find.text('优先级: 80'), findsOneWidget);

        // Find switches and toggle one
        final switches = find.byType(Switch);
        expect(switches, findsWidgets);
        await tester.tap(switches.first);
        await settle(tester);

        final rows = await db.query(
          'classification_rules',
          where: 'id = ?',
          whereArgs: ['rule_subway'],
        );
        expect(rows.first['enabled'], equals(0));
      });
    });

    testWidgets('adds a new classification rule via dialog', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildTestWidget());
        await settle(tester);

        // Tap 添加规则
        await tester.tap(find.text('添加规则').first);
        await settle(tester);

        expect(find.text('添加分类规则'), findsOneWidget);

        // Fill in form
        await tester.enterText(
          find.widgetWithText(TextFormField, '商户关键字 / 通配符 *'),
          '瑞幸咖啡',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, '规则优先级 (越大匹配次序越靠前)'),
          '150',
        );

        // Tap 保存
        await tester.tap(find.text('保存'));
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 400));

        final rules = await db.query(
          'classification_rules',
          where: 'merchant_pattern = ?',
          whereArgs: ['瑞幸咖啡'],
        );
        expect(rules, isNotEmpty);
        expect(rules.first['priority'], equals(150));
        expect(find.widgetWithText(Card, '瑞幸咖啡'), findsOneWidget);
      });
    });

    testWidgets('re-match re-evaluates pending drafts non-retroactively',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final nowIso = DateTime.now().toUtc().toIso8601String();

        // 1. Insert a classification rule for 肯德基 -> cat_food
        await db.insert('classification_rules', {
          'id': 'rule_kfc',
          'priority': 200,
          'merchant_pattern': '肯德基',
          'category_id': 'cat_food',
          'enabled': 1,
          'version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 2. Insert a pending capture job & draft with fallback category cat_other
        await db.insert('capture_jobs', {
          'id': 'job_pending_1',
          'content_hash': 'hash_123',
          'source_kind': 'screenshot',
          'imported_at': nowIso,
          'private_image_ref': 'img_123',
          'state': CaptureJobState.needsReview.value,
          'attempt_count': 0,
          'parser_version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        final candidateJson = jsonEncode({
          'merchant_raw': '肯德基宅急送',
          'suggested_category_id': 'cat_other',
          'type': 'expense',
        });

        await db.insert('drafts', {
          'id': 'draft_kfc_1',
          'capture_id': 'job_pending_1',
          'candidate_fields': candidateJson,
          'field_evidence': '{}',
          'validation_issues': '[]',
          'duplicate_candidates': '[]',
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 3. Insert an existing committed transaction (must NOT be altered!)
        await db.insert('transactions', {
          'id': 'tx_committed_1',
          'type': 'expense',
          'amount_minor': 3500,
          'currency': 'CNY',
          'merchant_raw': '肯德基宅急送',
          'occurred_on': '2026-10-20',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'second',
          'payment_channel': 'alipay',
          'category_id': 'cat_other',
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        await tester.pumpWidget(buildTestWidget());
        await settle(tester);

        // Tap 重新匹配 button
        await tester.tap(find.text('重新匹配'));
        await settle(tester);

        // Check draft candidate_fields was updated to cat_food
        final draftRows = await db.query(
          'drafts',
          where: 'id = ?',
          whereArgs: ['draft_kfc_1'],
        );
        final updatedCandidate =
            jsonDecode(draftRows.first['candidate_fields'] as String) as Map<String, dynamic>;
        expect(updatedCandidate['suggested_category_id'], equals('cat_food'));

        // Check committed transaction was STRICTLY untouched!
        final txRows = await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx_committed_1'],
        );
        expect(txRows.first['category_id'], equals('cat_other'));
      });
    });
  });

  group('AccountsTab Features', () {
    testWidgets('shows Total Assets card, accounts list and adds new account',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildTestWidget(child: const Scaffold(body: AccountsTab())));
        await settle(tester);

        expect(find.byType(AccountsTab), findsOneWidget);
        expect(find.textContaining('总资产'), findsWidgets);
        expect(find.text('微信支付'), findsOneWidget);
        expect(find.text('支付宝'), findsOneWidget);

        // Tap 添加账户 button
        await tester.tap(find.text('添加账户'));
        await settle(tester);

        expect(find.text('添加资产账户'), findsOneWidget);

        // Fill form
        await tester.enterText(
          find.widgetWithText(TextFormField, '账户名称 *'),
          '招商储蓄卡',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, '初始余额 (元)'),
          '5000.00',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, '卡号后四位 (选填)'),
          '6688',
        );

        // Save
        await tester.tap(find.text('保存'));
        await settle(tester);

        // Verify account added to DB
        final accounts = await db.query(
          'accounts',
          where: 'name = ?',
          whereArgs: ['招商储蓄卡'],
        );
        expect(accounts, isNotEmpty);
        expect(accounts.first['card_last4'], equals('6688'));

        // Verify initial balance transaction created
        final initTx = await db.query(
          'transactions',
          where: 'merchant_raw = ? AND account_id = ?',
          whereArgs: ['初始余额', accounts.first['id']],
        );
        expect(initTx, isNotEmpty);
        expect(initTx.first['amount_minor'], equals(500000));
      });
    });
  });

  group('ProjectsTab Features', () {
    testWidgets('lists projects and adds new lifecycle project', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildTestWidget(child: const Scaffold(body: ProjectsTab())));
        await settle(tester);

        expect(find.byType(ProjectsTab), findsOneWidget);
        expect(find.text('旅行出游'), findsOneWidget);
        expect(find.text('家居装修'), findsOneWidget);

        // Tap 添加项目 button
        await tester.tap(find.text('添加项目'));
        await settle(tester);

        expect(find.text('添加项目'), findsWidgets);

        await tester.enterText(
          find.widgetWithText(TextFormField, '项目名称 *'),
          '云南西双版纳之旅',
        );

        await tester.tap(find.text('保存'));
        await settle(tester);

        final projects = await db.query(
          'projects',
          where: 'name = ?',
          whereArgs: ['云南西双版纳之旅'],
        );
        expect(projects, isNotEmpty);
        expect(find.text('云南西双版纳之旅'), findsOneWidget);
      });
    });
  });

  group('RefundLinkDialog & FK Cascade Integrity', () {
    testWidgets('links refund to expense and verifies refund_links ON DELETE CASCADE',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final nowIso = DateTime.now().toUtc().toIso8601String();

        // Insert original expense transaction
        final expenseTx = TransactionEntry(
          id: 'tx_expense_100',
          type: 'expense',
          amountMinor: 19900,
          currency: 'CNY',
          merchantRaw: '优衣库在线商城',
          occurredOn: '2026-10-15',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'second',
          paymentChannel: 'wechat',
          categoryId: 'cat_shopping',
          createdAt: nowIso,
          updatedAt: nowIso,
        );
        await db.insert('transactions', expenseTx.toMap());

        // Insert refund transaction
        final refundTx = TransactionEntry(
          id: 'tx_refund_200',
          type: 'refund',
          amountMinor: 19900,
          currency: 'CNY',
          merchantRaw: '优衣库退款',
          occurredOn: '2026-10-18',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'second',
          paymentChannel: 'wechat',
          categoryId: 'cat_shopping',
          createdAt: nowIso,
          updatedAt: nowIso,
        );
        await db.insert('transactions', refundTx.toMap());

        await tester.pumpWidget(
          buildTestWidget(
            child: Scaffold(
              body: RefundLinkDialog(
                refundTxId: refundTx.id,
                refundTransaction: refundTx,
              ),
            ),
          ),
        );
        await settle(tester);

        // Verify foreign key cascade safety note is displayed
        expect(find.textContaining('外键级联安全机制说明'), findsOneWidget);
        expect(find.textContaining('refund_links ON DELETE CASCADE'), findsOneWidget);

        // Verify candidate expense is displayed
        expect(find.text('优衣库在线商城'), findsOneWidget);

        // Tap candidate expense to select
        await tester.tap(find.text('优衣库在线商城'));
        await settle(tester);

        // Tap 确认关联
        await tester.tap(find.text('确认关联'));
        await settle(tester);

        // Verify refund_links entry was persisted
        final links = await db.query(
          'refund_links',
          where: 'refund_transaction_id = ?',
          whereArgs: [refundTx.id],
        );
        expect(links, isNotEmpty);
        expect(links.first['original_expense_id'], equals(expenseTx.id));

        // Purge the original expense to test CASCADE integrity
        await db.delete(
          'transactions',
          where: 'id = ?',
          whereArgs: [expenseTx.id],
        );

        // Foreign key cascade unlinks refund relationship
        final linksAfterPurge = await db.query(
          'refund_links',
          where: 'refund_transaction_id = ?',
          whereArgs: [refundTx.id],
        );
        expect(linksAfterPurge, isEmpty);

        // The refund transaction itself MUST NOT be deleted!
        final refundStillExists = await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: [refundTx.id],
        );
        expect(refundStillExists, isNotEmpty);
      });
    });
  });
}
