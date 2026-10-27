// test/presentation/repositories_and_providers_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/state_machine.dart';
import 'package:singwallet/data/database/transaction_manager.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/data/repositories/draft_repository.dart';
import 'package:singwallet/data/repositories/ledger_repository.dart';
import 'package:singwallet/data/repositories/rule_repository.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/presentation/navigation/app_scaffold.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/providers/draft_providers.dart';
import 'package:singwallet/presentation/providers/rule_account_providers.dart';
import 'package:singwallet/presentation/providers/transaction_providers.dart';
import 'package:singwallet/presentation/screens/drafts/drafts_queue_screen.dart';
import 'package:singwallet/presentation/screens/rules_accounts/rules_accounts_screen.dart';
import 'package:singwallet/presentation/screens/transactions/transactions_screen.dart';
import 'package:singwallet/presentation/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestTransactionListNotifier extends TransactionListNotifier {
  @override
  Future<List<TransactionGroup>> build() async => const <TransactionGroup>[];
}

class _TestDraftsQueueNotifier extends DraftsQueueNotifier {
  @override
  Future<List<Draft>> build() async => const <Draft>[];
}

class _TestRulesListNotifier extends RulesListNotifier {
  @override
  Future<List<ClassificationRule>> build() async => const <ClassificationRule>[];
}

class _TestAccountsListNotifier extends AccountsListNotifier {
  @override
  Future<List<Account>> build() async => const <Account>[];
}

class _TestProjectsListNotifier extends ProjectsListNotifier {
  @override
  Future<List<Project>> build() async => const <Project>[];
}

void main() {
  late Database db;
  late TransactionManager txManager;
  late LedgerRepository ledgerRepo;
  late DraftRepository draftRepo;
  late RuleRepository ruleRepo;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    txManager = TransactionManager();
    ledgerRepo = LedgerRepository(db, txManager: txManager);
    draftRepo = DraftRepository(db, txManager: txManager);
    ruleRepo = RuleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DatabaseSeeder', () {
    test('seeds default categories, accounts, and projects idempotently', () async {
      await DatabaseSeeder.seedIfNeeded(db);

      final categories = await ledgerRepo.getCategories();
      expect(categories.length, equals(8));
      expect(categories.any((c) => c.id == 'cat_food' && c.name == '餐饮美食'), isTrue);
      expect(categories.any((c) => c.id == 'cat_transport' && c.name == '交通出行'), isTrue);
      expect(categories.any((c) => c.id == 'cat_shopping' && c.name == '日常购物'), isTrue);
      expect(categories.any((c) => c.id == 'cat_entertainment'), isTrue);
      expect(categories.any((c) => c.id == 'cat_bills'), isTrue);
      expect(categories.any((c) => c.id == 'cat_medical'), isTrue);
      expect(categories.any((c) => c.id == 'cat_other'), isTrue);
      expect(categories.any((c) => c.id == 'cat_income'), isTrue);

      final accounts = await ledgerRepo.getAccounts();
      expect(accounts.length, equals(4));
      expect(accounts.any((a) => a.id == 'acc_wechat' && a.kind == 'e_wallet'), isTrue);
      expect(accounts.any((a) => a.id == 'acc_alipay' && a.kind == 'e_wallet'), isTrue);
      expect(accounts.any((a) => a.id == 'acc_bank' && a.kind == 'debit_card'), isTrue);
      expect(accounts.any((a) => a.id == 'acc_cash' && a.kind == 'cash'), isTrue);

      final projects = await ledgerRepo.getProjects();
      expect(projects.length, equals(2));
      expect(projects.any((p) => p.id == 'proj_travel'), isTrue);
      expect(projects.any((p) => p.id == 'proj_home'), isTrue);

      // Re-run seed to test strict idempotence
      await DatabaseSeeder.seedIfNeeded(db);
      final categoriesAfter = await ledgerRepo.getCategories();
      final accountsAfter = await ledgerRepo.getAccounts();
      final projectsAfter = await ledgerRepo.getProjects();

      expect(categoriesAfter.length, equals(8));
      expect(accountsAfter.length, equals(4));
      expect(projectsAfter.length, equals(2));
    });

    test('seeds initial balances for accounts if provided', () async {
      await DatabaseSeeder.seedIfNeeded(
        db,
        initialBalances: {
          'acc_cash': 50000, // 500.00 CNY
          'acc_bank': 1200000, // 12,000.00 CNY
        },
      );

      final txs = await ledgerRepo.getTransactions();
      expect(txs.length, equals(2));
      expect(txs.every((t) => t.merchantRaw == '初始余额' && t.type == 'income'), isTrue);

      final balances = await ledgerRepo.getAccountBalances();
      expect(balances['acc_cash'], equals(50000));
      expect(balances['acc_bank'], equals(1200000));
      expect(balances['acc_wechat'], equals(0));

      // Re-run to ensure initial balances are not duplicated
      await DatabaseSeeder.seedIfNeeded(
        db,
        initialBalances: {
          'acc_cash': 50000,
          'acc_bank': 1200000,
        },
      );
      final txsAfter = await ledgerRepo.getTransactions();
      expect(txsAfter.length, equals(2));
    });
  });

  group('LedgerRepository', () {
    setUp(() async {
      await DatabaseSeeder.seedIfNeeded(db);
    });

    test('query transactions with multidimensional filters and grouping', () async {
      // Insert sample transactions
      const tx1 = TransactionEntry(
        id: 'tx_1',
        type: 'expense',
        amountMinor: 3800,
        merchantRaw: '星巴克咖啡',
        merchantNormalized: '星巴克',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        projectId: 'proj_travel',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
      );

      const tx2 = TransactionEntry(
        id: 'tx_2',
        type: 'expense',
        amountMinor: 1500,
        merchantRaw: '麦当劳',
        merchantNormalized: '麦当劳',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T12:00:00Z',
        updatedAt: '2026-10-23T12:00:00Z',
      );

      const tx3 = TransactionEntry(
        id: 'tx_3',
        type: 'income',
        amountMinor: 200000,
        merchantRaw: '公司工资',
        occurredOn: '2026-10-20',
        eventTimeSource: 'user_selected',
        eventTimePrecision: 'day',
        paymentChannel: 'bank',
        accountId: 'acc_bank',
        categoryId: 'cat_income',
        createdAt: '2026-10-20T09:00:00Z',
        updatedAt: '2026-10-20T09:00:00Z',
      );

      const tx4 = TransactionEntry(
        id: 'tx_4',
        type: 'refund',
        amountMinor: 1000,
        merchantRaw: '星巴克退款',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T14:00:00Z',
        updatedAt: '2026-10-23T14:00:00Z',
      );

      await db.insert('transactions', tx1.toMap());
      await db.insert('transactions', tx2.toMap());
      await db.insert('transactions', tx3.toMap());
      await db.insert('transactions', tx4.toMap());

      // 1. Grouped transactions
      final groups = await ledgerRepo.getGroupedTransactions(const TransactionFilter());
      expect(groups.length, equals(2));
      // First group: 2026-10-23
      expect(groups[0].date, equals('2026-10-23'));
      expect(groups[0].transactions.length, equals(3));
      expect(groups[0].totalExpenseMinor, equals(3800 + 1500));
      expect(groups[0].totalRefundMinor, equals(1000));
      expect(groups[0].netSubtotalMinor, equals(5300 - 1000));

      // Second group: 2026-10-20
      expect(groups[1].date, equals('2026-10-20'));
      expect(groups[1].transactions.length, equals(1));
      expect(groups[1].totalIncomeMinor, equals(200000));

      // 2. Filter by keyword
      final kwGroups = await ledgerRepo.getGroupedTransactions(
        const TransactionFilter(keyword: '星巴克'),
      );
      expect(kwGroups.length, equals(1));
      expect(kwGroups[0].transactions.length, equals(2));

      // 3. Filter by account
      final accTxs = await ledgerRepo.getTransactions(
        const TransactionFilter(accountId: 'acc_alipay'),
      );
      expect(accTxs.length, equals(1));
      expect(accTxs.first.id, equals('tx_2'));

      // 4. Monthly summary
      final summary = await ledgerRepo.getMonthlySummary('2026-10');
      expect(summary.totalExpenseMinor, equals(5300));
      expect(summary.totalRefundMinor, equals(1000));
      expect(summary.netExpenseMinor, equals(4300));
      expect(summary.totalIncomeMinor, equals(200000));
      expect(summary.netBalanceMinor, equals(200000 - 4300));
      expect(summary.transactionCount, equals(3)); // 2 expenses + 1 refund
    });

    test('soft delete, restore, permanent delete, and purge lifecycle', () async {
      const tx = TransactionEntry(
        id: 'tx_delete_test',
        type: 'expense',
        amountMinor: 9900,
        merchantRaw: '优衣库',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
      );
      await db.insert('transactions', tx.toMap());

      // Initial active state
      var activeTxs = await ledgerRepo.getTransactions();
      expect(activeTxs.length, equals(1));

      // 1. Soft delete
      await ledgerRepo.softDeleteTransaction('tx_delete_test');
      activeTxs = await ledgerRepo.getTransactions();
      expect(activeTxs.isEmpty, isTrue);

      var trashTxs = await ledgerRepo.getTrashBinTransactions();
      expect(trashTxs.length, equals(1));
      expect(trashTxs.first.id, equals('tx_delete_test'));

      // 2. Restore
      await ledgerRepo.restoreTransaction('tx_delete_test');
      activeTxs = await ledgerRepo.getTransactions();
      expect(activeTxs.length, equals(1));

      trashTxs = await ledgerRepo.getTrashBinTransactions();
      expect(trashTxs.isEmpty, isTrue);

      // 3. Permanent delete
      await ledgerRepo.permanentlyDeleteTransaction('tx_delete_test');
      activeTxs = await ledgerRepo.getTransactions();
      expect(activeTxs.isEmpty, isTrue);
      final rawTx = await ledgerRepo.getTransactionById('tx_delete_test');
      expect(rawTx, isNull);
    });

    test('link refund to original expense and verify cascading', () async {
      const expTx = TransactionEntry(
        id: 'tx_exp_orig',
        type: 'expense',
        amountMinor: 5000,
        merchantRaw: '网购服饰',
        occurredOn: '2026-10-15',
        eventTimeSource: 'user_selected',
        eventTimePrecision: 'day',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-15T10:00:00Z',
        updatedAt: '2026-10-15T10:00:00Z',
      );
      const refTx = TransactionEntry(
        id: 'tx_ref_item',
        type: 'refund',
        amountMinor: 5000,
        merchantRaw: '网购退款',
        occurredOn: '2026-10-18',
        eventTimeSource: 'user_selected',
        eventTimePrecision: 'day',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-18T10:00:00Z',
        updatedAt: '2026-10-18T10:00:00Z',
      );

      await db.insert('transactions', expTx.toMap());
      await db.insert('transactions', refTx.toMap());

      await ledgerRepo.linkRefund(
        refundTxId: 'tx_ref_item',
        originalExpenseTxId: 'tx_exp_orig',
      );

      final linkRows = await db.query(
        'refund_links',
        where: 'refund_transaction_id = ?',
        whereArgs: ['tx_ref_item'],
      );
      expect(linkRows.length, equals(1));
      expect(linkRows.first['original_expense_id'], equals('tx_exp_orig'));

      // If original expense is permanently deleted, refund_links row cascades ON DELETE CASCADE
      // but refund transaction tx_ref_item remains intact!
      await ledgerRepo.permanentlyDeleteTransaction('tx_exp_orig');

      final linkRowsAfter = await db.query('refund_links');
      expect(linkRowsAfter.isEmpty, isTrue);

      final refundStillExists = await ledgerRepo.getTransactionById('tx_ref_item');
      expect(refundStillExists, isNotNull);
    });
  });

  group('DraftRepository', () {
    test('getPendingDrafts, getDraftDetail, commitDraft, and discardDraft', () async {
      await DatabaseSeeder.seedIfNeeded(db);

      // Create a capture job and draft
      const job = CaptureJob(
        id: 'job_draft_test',
        contentHash: 'hash_test_123',
        sourceKind: 'screenshot',
        importedAt: '2026-10-23T08:00:00Z',
        privateImageRef: '/storage/test.png',
        state: 'NEEDS_REVIEW',
        createdAt: '2026-10-23T08:00:00Z',
        updatedAt: '2026-10-23T08:00:00Z',
      );
      await db.insert('capture_jobs', job.toMap());

      final draft = Draft(
        id: 'draft_test_1',
        captureId: 'job_draft_test',
        candidateFields: jsonEncode({
          'amount_minor': 4500,
          'merchant_raw': '喜茶',
          'occurred_on': '2026-10-23',
          'payment_channel': 'wechat',
          'suggested_category_id': 'cat_food',
        }),
        fieldEvidence: jsonEncode({
          'merchant': {'rawText': '喜茶', 'source': 'ocr_extracted'},
        }),
        validationIssues: jsonEncode(['missing_order_id']),
        duplicateCandidates: jsonEncode([]),
        createdAt: '2026-10-23T08:01:00Z',
        updatedAt: '2026-10-23T08:01:00Z',
      );
      await db.insert('drafts', draft.toMap());

      // 1. Pending drafts query
      final pending = await draftRepo.getPendingDrafts();
      expect(pending.length, equals(1));
      expect(pending.first.id, equals('draft_test_1'));

      // 2. Draft detail query
      final detail = await draftRepo.getDraftDetail('draft_test_1');
      expect(detail, isNotNull);
      expect(detail!.captureJob?.privateImageRef, equals('/storage/test.png'));
      expect(detail.candidateFields['amount_minor'], equals(4500));
      expect(detail.validationIssues.contains('missing_order_id'), isTrue);

      // 3. Commit draft
      const commitReq = CommitDraftRequest(
        transaction: TransactionEntry(
          id: 'tx_committed_1',
          originDraftId: 'draft_test_1',
          type: 'expense',
          amountMinor: 4500,
          merchantRaw: '喜茶',
          merchantNormalized: '喜茶',
          occurredOn: '2026-10-23',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'minute',
          paymentChannel: 'wechat',
          accountId: 'acc_wechat',
          categoryId: 'cat_food',
          createdAt: '2026-10-23T08:05:00Z',
          updatedAt: '2026-10-23T08:05:00Z',
        ),
      );

      final commitResult = await draftRepo.commitDraft(commitReq);
      expect(commitResult.success, isTrue);
      expect(commitResult.transaction?.id, equals('tx_committed_1'));

      // Pending queue should now be empty
      final pendingAfter = await draftRepo.getPendingDrafts();
      expect(pendingAfter.isEmpty, isTrue);

      // 4. Discard draft test with another draft
      const job2 = CaptureJob(
        id: 'job_discard_test',
        contentHash: 'hash_test_456',
        sourceKind: 'screenshot',
        importedAt: '2026-10-23T08:00:00Z',
        privateImageRef: '/storage/test2.png',
        state: 'NEEDS_REVIEW',
        createdAt: '2026-10-23T08:00:00Z',
        updatedAt: '2026-10-23T08:00:00Z',
      );
      await db.insert('capture_jobs', job2.toMap());

      const draft2 = Draft(
        id: 'draft_test_2',
        captureId: 'job_discard_test',
        candidateFields: '{}',
        fieldEvidence: '{}',
        validationIssues: '[]',
        duplicateCandidates: '[]',
        createdAt: '2026-10-23T08:02:00Z',
        updatedAt: '2026-10-23T08:02:00Z',
      );
      await db.insert('drafts', draft2.toMap());

      await draftRepo.discardDraft('draft_test_2');

      final job2Rows = await db.query(
        'capture_jobs',
        where: 'id = ?',
        whereArgs: ['job_discard_test'],
      );
      expect(job2Rows.first['state'], equals(CaptureJobState.discarded.value));
    });
  });

  group('RuleRepository', () {
    test('getAllRules, toggleEnabled, updatePriority, save, delete, reorder', () async {
      await DatabaseSeeder.seedIfNeeded(db);

      const rule1 = ClassificationRule(
        id: 'rule_1',
        priority: 100,
        merchantPattern: '星巴克*',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T00:00:00Z',
        updatedAt: '2026-10-23T00:00:00Z',
      );

      const rule2 = ClassificationRule(
        id: 'rule_2',
        priority: 50,
        merchantPattern: '滴滴出行',
        categoryId: 'cat_transport',
        createdAt: '2026-10-23T00:00:00Z',
        updatedAt: '2026-10-23T00:00:00Z',
      );

      await ruleRepo.saveRule(rule1);
      await ruleRepo.saveRule(rule2);

      // 1. Get all rules ordered by priority DESC
      var rules = await ruleRepo.getAllRules();
      expect(rules.length, equals(2));
      expect(rules.first.id, equals('rule_1'));
      expect(rules.last.id, equals('rule_2'));

      // 2. Toggle enabled
      await ruleRepo.setRuleEnabled('rule_1', false);
      rules = await ruleRepo.getAllRules();
      expect(rules.first.isEnabled, isFalse);

      // 3. Update priority
      await ruleRepo.updateRulePriority('rule_2', 150);
      rules = await ruleRepo.getAllRules();
      expect(rules.first.id, equals('rule_2')); // rule_2 is now higher priority

      // 4. Reorder rules
      await ruleRepo.reorderRules([rule1, rule2]);
      rules = await ruleRepo.getAllRules();
      expect(rules.first.id, equals('rule_1'));
      expect(rules.first.priority, equals(20));
      expect(rules.last.priority, equals(10));

      // 5. Delete rule
      await ruleRepo.deleteRule('rule_1');
      rules = await ruleRepo.getAllRules();
      expect(rules.length, equals(1));
      expect(rules.first.id, equals('rule_2'));
    });
  });

  group('Riverpod Providers Bus', () {
    test('ProviderContainer reactive interactions', () async {
      await DatabaseSeeder.seedIfNeeded(db);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      // 1. Initial filter state
      final initialFilter = container.read(transactionFilterProvider);
      expect(initialFilter.hasActiveFilters, isFalse);

      container.read(transactionFilterProvider.notifier).setKeyword('咖啡');
      expect(container.read(transactionFilterProvider).keyword, equals('咖啡'));

      // 2. Transaction list notifier initial read
      final txListAsync = await container.read(transactionListProvider.future);
      expect(txListAsync, isEmpty);

      // 3. Selected month and monthly summary
      final currentMonth = container.read(selectedMonthProvider);
      expect(currentMonth.contains('-'), isTrue);

      container.read(selectedMonthProvider.notifier).setMonth('2026-10');
      expect(container.read(selectedMonthProvider), equals('2026-10'));

      final summary = await container.read(monthlySummaryProvider.future);
      expect(summary.totalExpenseMinor, equals(0));

      // 4. Rules notifier
      final rulesAsync = await container.read(rulesListProvider.future);
      expect(rulesAsync, isEmpty);

      await container.read(rulesListProvider.notifier).save(
            const ClassificationRule(
              id: 'rule_bus_test',
              priority: 100,
              merchantPattern: '肯德基',
              categoryId: 'cat_food',
              createdAt: '2026-10-23T00:00:00Z',
              updatedAt: '2026-10-23T00:00:00Z',
            ),
          );

      final rulesAfter = await container.read(rulesListProvider.future);
      expect(rulesAfter.length, equals(1));
      expect(rulesAfter.first.merchantPattern, equals('肯德基'));

      // 5. Accounts list notifier
      final accounts = await container.read(accountsListProvider.future);
      expect(accounts.length, equals(4));

      // 6. Projects list notifier
      final projects = await container.read(projectsListProvider.future);
      expect(projects.length, equals(2));
    });
  });

  group('AppScaffold Widget Tests', () {
    List<Override> buildScaffoldOverrides({int pendingCount = 0}) => [
          databaseProvider.overrideWithValue(db),
          pendingDraftsCountProvider.overrideWithValue(pendingCount),
          transactionListProvider.overrideWith(() => _TestTransactionListNotifier()),
          draftsQueueProvider.overrideWith(() => _TestDraftsQueueNotifier()),
          rulesListProvider.overrideWith(() => _TestRulesListNotifier()),
          accountsListProvider.overrideWith(() => _TestAccountsListNotifier()),
          projectsListProvider.overrideWith(() => _TestProjectsListNotifier()),
          categoriesListProvider.overrideWith((ref) async => const <Category>[]),
          accountBalancesProvider.overrideWith((ref) async => const <String, int>{}),
          monthlySummaryProvider.overrideWith((ref) async => const MonthlyAccountingSummary(
                totalExpenseMinor: 0,
                totalRefundMinor: 0,
                netExpenseMinor: 0,
                totalIncomeMinor: 0,
                transactionCount: 0,
              )),
        ];

    testWidgets('AppScaffold renders NavigationBar and switches tabs', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: buildScaffoldOverrides(pendingCount: 2),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AppScaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top title
      expect(find.text('SingWallet'), findsOneWidget);

      // Navigation bar labels
      expect(find.text('流水明细'), findsOneWidget);
      expect(find.text('草稿箱'), findsOneWidget);
      expect(find.text('规则账户'), findsOneWidget);

      // Badge count
      expect(find.text('2'), findsWidgets);

      // Initial tab is TransactionsScreen
      expect(find.byType(TransactionsScreen), findsOneWidget);

      // Tap on '草稿箱' tab
      await tester.tap(find.text('草稿箱'));
      await tester.pumpAndSettle();
      expect(find.byType(DraftsQueueScreen), findsOneWidget);

      // Tap on '规则账户' tab
      await tester.tap(find.text('规则账户'));
      await tester.pumpAndSettle();
      expect(find.byType(RulesAccountsScreen), findsOneWidget);
    });

    testWidgets('AppScaffold switches to NavigationRail on wide viewport', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildScaffoldOverrides(pendingCount: 0),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AppScaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
