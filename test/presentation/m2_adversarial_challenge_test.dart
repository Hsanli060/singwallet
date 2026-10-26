// test/presentation/m2_adversarial_challenge_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/utils/currency_utils.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/state_machine.dart';
import 'package:singwallet/data/database/transaction_manager.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/data/repositories/ledger_repository.dart';
import 'package:singwallet/data/repositories/rule_repository.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/providers/rule_account_providers.dart';
import 'package:singwallet/presentation/screens/rules_accounts/widgets/classification_rules_tab.dart';
import 'package:singwallet/presentation/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late TransactionManager txManager;
  late LedgerRepository ledgerRepo;
  late RuleRepository ruleRepo;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    txManager = TransactionManager();
    ledgerRepo = LedgerRepository(db, txManager: txManager);
    ruleRepo = RuleRepository(db);
    await DatabaseSeeder.seedIfNeeded(db);
  });

  tearDown(() async {
    await db.close();
  });

  // =========================================================================
  // Challenge 1: Rules Reordering Monotonicity & Empty Handling
  // =========================================================================
  group('Adversarial Challenge 1: Rules Reordering Monotonicity & Empty Rules', () {
    test('reorderRules handles empty rules list without crash or side-effects', () async {
      // Reordering empty list
      await ruleRepo.reorderRules(<ClassificationRule>[]);
      final rules = await ruleRepo.getAllRules();
      expect(rules, isEmpty);
    });

    test('reorderRules on a single rule assigns priority 10 monotonically', () async {
      const rule = ClassificationRule(
        id: 'rule_single',
        priority: 9999,
        merchantPattern: '单条测试',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T00:00:00Z',
        updatedAt: '2026-10-23T00:00:00Z',
      );
      await ruleRepo.saveRule(rule);

      await ruleRepo.reorderRules([rule]);
      final rules = await ruleRepo.getAllRules();
      expect(rules.length, equals(1));
      expect(rules.first.id, equals('rule_single'));
      expect(rules.first.priority, equals(10)); // (1 - 0) * 10 = 10
    });

    test('reorderRules enforces strictly descending monotonic priorities across 25 rules', () async {
      final inputRules = <ClassificationRule>[];
      for (var i = 0; i < 25; i++) {
        final r = ClassificationRule(
          id: 'rule_adv_$i',
          // Start with chaotic/colliding initial priorities
          priority: (i % 3 == 0) ? -50 : 100,
          merchantPattern: '商户模式_$i',
          categoryId: 'cat_shopping',
          createdAt: '2026-10-23T00:00:00Z',
          updatedAt: '2026-10-23T00:00:00Z',
        );
        inputRules.add(r);
        await ruleRepo.saveRule(r);
      }

      // Desired new order: inverted list
      final desiredOrder = inputRules.reversed.toList();
      await ruleRepo.reorderRules(desiredOrder);

      // Re-query from SQLite
      final queriedRules = await ruleRepo.getAllRules();
      expect(queriedRules.length, equals(25));

      // 1. Verify exact sequence alignment with desiredOrder
      for (var i = 0; i < 25; i++) {
        expect(
          queriedRules[i].id,
          equals(desiredOrder[i].id),
          reason: 'Item at index $i must match desired reordered sequence',
        );
      }

      // 2. Verify strict monotonicity: priority[i] > priority[i+1] for all i
      for (var i = 0; i < queriedRules.length - 1; i++) {
        final curr = queriedRules[i].priority;
        final next = queriedRules[i + 1].priority;
        expect(
          curr > next,
          isTrue,
          reason: 'Priority at index $i ($curr) must be strictly greater than index ${i + 1} ($next)',
        );
        expect(
          curr - next,
          equals(10),
          reason: 'Step difference must be exactly 10',
        );
      }

      // 3. Lowest priority must be strictly positive
      expect(queriedRules.last.priority, equals(10));
      // 4. Highest priority must equal total * 10
      expect(queriedRules.first.priority, equals(250));
    });

    test('RulesListNotifier reorder handles empty and multi-rule sequences', () async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ruleRepositoryProvider.overrideWithValue(ruleRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(rulesListProvider.notifier);
      await notifier.reorder(<ClassificationRule>[]);
      final emptyState = await container.read(rulesListProvider.future);
      expect(emptyState, isEmpty);

      // Insert 2 rules and reorder
      final r1 = ClassificationRule(
        id: 'r_alpha',
        priority: 50,
        merchantPattern: 'Alpha',
        categoryId: 'cat_food',
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      final r2 = ClassificationRule(
        id: 'r_beta',
        priority: 100,
        merchantPattern: 'Beta',
        categoryId: 'cat_transport',
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      await ruleRepo.saveRule(r1);
      await ruleRepo.saveRule(r2);

      // Reorder placing r1 first then r2
      await notifier.reorder([r1, r2]);
      final state = await container.read(rulesListProvider.future);
      expect(state.first.id, equals('r_alpha'));
      expect(state.first.priority, equals(20));
      expect(state.last.id, equals('r_beta'));
      expect(state.last.priority, equals(10));
    });
  });

  // =========================================================================
  // Challenge 2: Draft Rematching Non-Retroactivity & SQLite Immutability
  // =========================================================================
  group('Adversarial Challenge 2: Rematching Pending Drafts Immutability on Historical Transactions', () {
    testWidgets('rematch strictly isolates pending drafts and NEVER mutates historical transactions',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        final nowIso = DateTime.now().toUtc().toIso8601String();

        // 1. Insert multiple historical committed transactions
        final historicalTx1 = {
          'id': 'tx_hist_expense',
          'type': 'expense',
          'amount_minor': 8800,
          'currency': 'CNY',
          'merchant_raw': '美团外卖-星巴克',
          'merchant_normalized': '星巴克',
          'occurred_on': '2026-10-10',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'second',
          'payment_channel': 'wechat',
          'category_id': 'cat_other', // Currently cat_other
          'project_id': null,
          'note': '历史账目不可修改',
          'created_at': '2026-10-10T12:00:00.000Z',
          'updated_at': '2026-10-10T12:00:00.000Z',
          'deleted_at': null,
        };
        final historicalTx2 = {
          'id': 'tx_hist_refund',
          'type': 'refund',
          'amount_minor': 3000,
          'currency': 'CNY',
          'merchant_raw': '星巴克退款',
          'merchant_normalized': '星巴克',
          'occurred_on': '2026-10-11',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'second',
          'payment_channel': 'wechat',
          'category_id': 'cat_food',
          'project_id': null,
          'note': '历史退款',
          'created_at': '2026-10-11T12:00:00.000Z',
          'updated_at': '2026-10-11T12:00:00.000Z',
          'deleted_at': null,
        };
        final historicalTx3Trash = {
          'id': 'tx_hist_trash',
          'type': 'expense',
          'amount_minor': 1500,
          'currency': 'CNY',
          'merchant_raw': '星巴克早餐',
          'merchant_normalized': '星巴克',
          'occurred_on': '2026-10-12',
          'event_time_source': 'ocr_extracted',
          'event_time_precision': 'second',
          'payment_channel': 'alipay',
          'category_id': 'cat_other',
          'project_id': null,
          'note': '回收站流水',
          'created_at': '2026-10-12T12:00:00.000Z',
          'updated_at': '2026-10-12T12:00:00.000Z',
          'deleted_at': '2026-10-12T14:00:00.000Z',
        };

        await db.insert('transactions', historicalTx1);
        await db.insert('transactions', historicalTx2);
        await db.insert('transactions', historicalTx3Trash);

        final beforeRematchTx1 = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_hist_expense'])).first;
        final beforeRematchTx2 = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_hist_refund'])).first;
        final beforeRematchTx3 = (await db.query('transactions', where: 'id = ?', whereArgs: ['tx_hist_trash'])).first;

        // 2. Insert Committed Draft (state = COMMITTED, saved_transaction_id set)
        await db.insert('capture_jobs', {
          'id': 'job_committed',
          'content_hash': 'hash_committed',
          'source_kind': 'screenshot',
          'imported_at': nowIso,
          'private_image_ref': 'img_committed',
          'state': CaptureJobState.committed.value,
          'attempt_count': 1,
          'parser_version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        final committedCandidateJson = jsonEncode({
          'merchant_raw': '星巴克',
          'suggested_category_id': 'cat_other',
          'type': 'expense',
        });
        await db.insert('drafts', {
          'id': 'draft_committed_1',
          'capture_id': 'job_committed',
          'candidate_fields': committedCandidateJson,
          'field_evidence': '{}',
          'validation_issues': '[]',
          'duplicate_candidates': '[]',
          'saved_transaction_id': 'tx_hist_expense',
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 3. Insert Discarded Draft (state = DISCARDED)
        await db.insert('capture_jobs', {
          'id': 'job_discarded',
          'content_hash': 'hash_discarded',
          'source_kind': 'screenshot',
          'imported_at': nowIso,
          'private_image_ref': 'img_discarded',
          'state': CaptureJobState.discarded.value,
          'attempt_count': 1,
          'parser_version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        final discardedCandidateJson = jsonEncode({
          'merchant_raw': '星巴克',
          'suggested_category_id': 'cat_other',
          'type': 'expense',
        });
        await db.insert('drafts', {
          'id': 'draft_discarded_1',
          'capture_id': 'job_discarded',
          'candidate_fields': discardedCandidateJson,
          'field_evidence': '{}',
          'validation_issues': '[]',
          'duplicate_candidates': '[]',
          'saved_transaction_id': null,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 4. Insert 2 Pending Drafts (NEEDS_REVIEW and IMPORTED)
        await db.insert('capture_jobs', {
          'id': 'job_pending_review',
          'content_hash': 'hash_pending_1',
          'source_kind': 'screenshot',
          'imported_at': nowIso,
          'private_image_ref': 'img_p1',
          'state': CaptureJobState.needsReview.value,
          'attempt_count': 0,
          'parser_version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        final pendingCandidate1 = jsonEncode({
          'merchant_raw': '星巴克咖啡厅',
          'suggested_category_id': 'cat_other',
          'type': 'expense',
        });
        await db.insert('drafts', {
          'id': 'draft_pending_1',
          'capture_id': 'job_pending_review',
          'candidate_fields': pendingCandidate1,
          'field_evidence': '{}',
          'validation_issues': '[]',
          'duplicate_candidates': '[]',
          'saved_transaction_id': null,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        await db.insert('capture_jobs', {
          'id': 'job_pending_imported',
          'content_hash': 'hash_pending_2',
          'source_kind': 'screenshot',
          'imported_at': nowIso,
          'private_image_ref': 'img_p2',
          'state': CaptureJobState.imported.value,
          'attempt_count': 0,
          'parser_version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        final pendingCandidate2 = jsonEncode({
          'merchant_raw': '星巴克臻选',
          'suggested_category_id': 'cat_shopping',
          'type': 'expense',
        });
        await db.insert('drafts', {
          'id': 'draft_pending_2',
          'capture_id': 'job_pending_imported',
          'candidate_fields': pendingCandidate2,
          'field_evidence': '{}',
          'validation_issues': '[]',
          'duplicate_candidates': '[]',
          'saved_transaction_id': null,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 5. Add a high-priority rule matching '星巴克*' -> cat_food
        await db.insert('classification_rules', {
          'id': 'rule_starbucks_high',
          'priority': 999,
          'merchant_pattern': '星巴克*',
          'category_id': 'cat_food',
          'enabled': 1,
          'version': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 6. Launch ClassificationRulesTab UI and trigger rematch button
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(body: ClassificationRulesTab()),
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }

        // Tap 重新匹配
        await tester.tap(find.text('重新匹配'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }

        // 7. EMPIRICAL VERIFICATION: Historical transactions must be 100% UNTOUCHED!
        final queriedTx1 = (await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx_hist_expense'],
        )).first;
        expect(
          queriedTx1,
          equals(beforeRematchTx1),
          reason: 'Historical active transaction tx_hist_expense must be strictly identical',
        );

        final queriedTx2 = (await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx_hist_refund'],
        )).first;
        expect(
          queriedTx2,
          equals(beforeRematchTx2),
          reason: 'Historical refund transaction tx_hist_refund must be strictly identical',
        );

        final queriedTx3 = (await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx_hist_trash'],
        )).first;
        expect(
          queriedTx3,
          equals(beforeRematchTx3),
          reason: 'Historical soft-deleted trash transaction tx_hist_trash must be strictly identical',
        );

        // 8. EMPIRICAL VERIFICATION: Committed and Discarded drafts must be UNTOUCHED!
        final queriedCommittedDraft = (await db.query(
          'drafts',
          where: 'id = ?',
          whereArgs: ['draft_committed_1'],
        )).first;
        final decodedCommitted = jsonDecode(queriedCommittedDraft['candidate_fields'] as String);
        expect(
          decodedCommitted['suggested_category_id'],
          equals('cat_other'),
          reason: 'Committed draft suggestion must NOT be retroactively modified',
        );

        final queriedDiscardedDraft = (await db.query(
          'drafts',
          where: 'id = ?',
          whereArgs: ['draft_discarded_1'],
        )).first;
        final decodedDiscarded = jsonDecode(queriedDiscardedDraft['candidate_fields'] as String);
        expect(
          decodedDiscarded['suggested_category_id'],
          equals('cat_other'),
          reason: 'Discarded draft suggestion must NOT be modified',
        );

        // 9. EMPIRICAL VERIFICATION: Pending drafts in NEEDS_REVIEW and IMPORTED MUST be updated!
        final queriedPending1 = (await db.query(
          'drafts',
          where: 'id = ?',
          whereArgs: ['draft_pending_1'],
        )).first;
        final decodedPending1 = jsonDecode(queriedPending1['candidate_fields'] as String);
        expect(
          decodedPending1['suggested_category_id'],
          equals('cat_food'),
          reason: 'Pending draft draft_pending_1 must receive new suggested category cat_food',
        );

        final queriedPending2 = (await db.query(
          'drafts',
          where: 'id = ?',
          whereArgs: ['draft_pending_2'],
        )).first;
        final decodedPending2 = jsonDecode(queriedPending2['candidate_fields'] as String);
        expect(
          decodedPending2['suggested_category_id'],
          equals('cat_food'),
          reason: 'Pending draft draft_pending_2 must receive new suggested category cat_food',
        );
      });
    });
  });

  // =========================================================================
  // Challenge 3: Refund Links Cascading Integrity & Transaction Non-Corruption
  // =========================================================================
  group('Adversarial Challenge 3: Deleting Original Expense Cascades Cleanly to refund_links', () {
    test('soft delete of original expense preserves refund_links relation', () async {
      // Create expense and refund
      const expense = TransactionEntry(
        id: 'tx_exp_casc_1',
        type: 'expense',
        amountMinor: 29900,
        merchantRaw: '耐克旗舰店',
        occurredOn: '2026-10-05',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-05T10:00:00Z',
        updatedAt: '2026-10-05T10:00:00Z',
      );
      const refund = TransactionEntry(
        id: 'tx_ref_casc_1',
        type: 'refund',
        amountMinor: 29900,
        merchantRaw: '耐克退款',
        occurredOn: '2026-10-06',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-06T10:00:00Z',
        updatedAt: '2026-10-06T10:00:00Z',
      );

      await db.insert('transactions', expense.toMap());
      await db.insert('transactions', refund.toMap());
      await ledgerRepo.linkRefund(refundTxId: refund.id, originalExpenseTxId: expense.id);

      // Verify initial link exists
      var links = await db.query('refund_links', where: 'refund_transaction_id = ?', whereArgs: [refund.id]);
      expect(links.length, equals(1));
      expect(links.first['original_expense_id'], equals(expense.id));

      // Soft delete expense
      await ledgerRepo.softDeleteTransaction(expense.id);

      // Link MUST remain intact during soft-delete retention
      links = await db.query('refund_links', where: 'refund_transaction_id = ?', whereArgs: [refund.id]);
      expect(links.length, equals(1), reason: 'Soft delete must retain refund_links for 30-day recovery');

      // Refund transaction itself must be active
      final refundTx = await ledgerRepo.getTransactionById(refund.id);
      expect(refundTx, isNotNull);
      expect(refundTx!.isInTrash, isFalse);

      // Restore expense
      await ledgerRepo.restoreTransaction(expense.id);
      final restoredExpense = await ledgerRepo.getTransactionById(expense.id);
      expect(restoredExpense, isNotNull);
      expect(restoredExpense!.isInTrash, isFalse);
    });

    test('permanent purge of original expense cascades refund_links without corrupting refund transaction', () async {
      const expense = TransactionEntry(
        id: 'tx_exp_purge',
        type: 'expense',
        amountMinor: 50000,
        merchantRaw: '苹果专卖店',
        occurredOn: '2026-10-01',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'bank',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-01T10:00:00Z',
        updatedAt: '2026-10-01T10:00:00Z',
      );
      const refund1 = TransactionEntry(
        id: 'tx_ref_purge_1',
        type: 'refund',
        amountMinor: 20000,
        merchantRaw: '部分退款1',
        occurredOn: '2026-10-02',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'bank',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-02T10:00:00Z',
        updatedAt: '2026-10-02T10:00:00Z',
      );
      const refund2 = TransactionEntry(
        id: 'tx_ref_purge_2',
        type: 'refund',
        amountMinor: 30000,
        merchantRaw: '部分退款2',
        occurredOn: '2026-10-03',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'bank',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-03T10:00:00Z',
        updatedAt: '2026-10-03T10:00:00Z',
      );

      await db.insert('transactions', expense.toMap());
      await db.insert('transactions', refund1.toMap());
      await db.insert('transactions', refund2.toMap());

      await ledgerRepo.linkRefund(refundTxId: refund1.id, originalExpenseTxId: expense.id);
      await ledgerRepo.linkRefund(refundTxId: refund2.id, originalExpenseTxId: expense.id);

      // Verify both links exist
      final links = await db.query('refund_links');
      expect(links.length, equals(2));

      // Permanently delete original expense via repository
      await ledgerRepo.permanentlyDeleteTransaction(expense.id);

      // Verify expense is gone
      final expCheck = await db.query('transactions', where: 'id = ?', whereArgs: [expense.id]);
      expect(expCheck, isEmpty);

      // CASCADE INTEGRITY CHECK: All refund_links associated with this original expense are removed!
      final linksAfter = await db.query(
        'refund_links',
        where: 'original_expense_id = ?',
        whereArgs: [expense.id],
      );
      expect(linksAfter, isEmpty, reason: 'Foreign key CASCADE must clean up refund_links');

      // CRITICAL NON-CORRUPTION CHECK: Both refund transactions MUST be fully intact!
      final ref1Rows = await db.query('transactions', where: 'id = ?', whereArgs: [refund1.id]);
      expect(ref1Rows.length, equals(1));
      final queriedRef1 = TransactionEntry.fromMap(ref1Rows.first);
      expect(queriedRef1.type, equals('refund'));
      expect(queriedRef1.amountMinor, equals(20000));
      expect(queriedRef1.merchantRaw, equals('部分退款1'));
      expect(queriedRef1.isInTrash, isFalse);

      final ref2Rows = await db.query('transactions', where: 'id = ?', whereArgs: [refund2.id]);
      expect(ref2Rows.length, equals(1));
      final queriedRef2 = TransactionEntry.fromMap(ref2Rows.first);
      expect(queriedRef2.type, equals('refund'));
      expect(queriedRef2.amountMinor, equals(30000));
      expect(queriedRef2.merchantRaw, equals('部分退款2'));
      expect(queriedRef2.isInTrash, isFalse);
    });

    test('permanent delete of refund transaction cascades refund_links and preserves original expense', () async {
      const expense = TransactionEntry(
        id: 'tx_exp_rev',
        type: 'expense',
        amountMinor: 10000,
        merchantRaw: '原消费',
        occurredOn: '2026-10-01',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        categoryId: 'cat_food',
        createdAt: '2026-10-01T10:00:00Z',
        updatedAt: '2026-10-01T10:00:00Z',
      );
      const refund = TransactionEntry(
        id: 'tx_ref_rev',
        type: 'refund',
        amountMinor: 10000,
        merchantRaw: '退款记录',
        occurredOn: '2026-10-02',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'alipay',
        categoryId: 'cat_food',
        createdAt: '2026-10-02T10:00:00Z',
        updatedAt: '2026-10-02T10:00:00Z',
      );

      await db.insert('transactions', expense.toMap());
      await db.insert('transactions', refund.toMap());
      await ledgerRepo.linkRefund(refundTxId: refund.id, originalExpenseTxId: expense.id);

      // Permanently delete the refund transaction
      await ledgerRepo.permanentlyDeleteTransaction(refund.id);

      // refund_links must be cascade deleted
      final links = await db.query('refund_links', where: 'refund_transaction_id = ?', whereArgs: [refund.id]);
      expect(links, isEmpty);

      // Original expense MUST remain untouched
      final expRows = await db.query('transactions', where: 'id = ?', whereArgs: [expense.id]);
      expect(expRows.length, equals(1));
      expect(expRows.first['id'], equals(expense.id));
      expect(expRows.first['amount_minor'], equals(10000));
    });
  });

  // =========================================================================
  // Challenge 4: Monthly Summary with Negative/Zero Balances and Transfers
  // =========================================================================
  group('Adversarial Challenge 4: Monthly Summary with Negative/Zero Balances & Transfers', () {
    test('internal transfers are strictly excluded from monthly summary and conserve account balances', () async {
      // 1. Initial balances: acc_bank = 100,000 cents (1,000 CNY), acc_wechat = 0
      const initialBank = TransactionEntry(
        id: 'tx_init_bank',
        type: 'income',
        amountMinor: 100000,
        merchantRaw: '初始余额',
        occurredOn: '2026-10-01',
        eventTimeSource: 'manual',
        eventTimePrecision: 'day',
        paymentChannel: 'bank',
        accountId: 'acc_bank',
        categoryId: 'cat_income',
        createdAt: '2026-10-01T00:00:00Z',
        updatedAt: '2026-10-01T00:00:00Z',
      );
      await db.insert('transactions', initialBank.toMap());

      // 2. Transfer: Transfer 40,000 cents from acc_bank to acc_wechat
      const transferTx = TransactionEntry(
        id: 'tx_transfer_1',
        type: 'transfer',
        amountMinor: 40000,
        merchantRaw: '银行转账至微信零钱',
        occurredOn: '2026-10-05',
        eventTimeSource: 'manual',
        eventTimePrecision: 'minute',
        paymentChannel: 'bank',
        accountId: 'acc_bank',
        transferToAccountId: 'acc_wechat',
        createdAt: '2026-10-05T10:00:00Z',
        updatedAt: '2026-10-05T10:00:00Z',
      );
      await db.insert('transactions', transferTx.toMap());

      // 3. Monthly Summary verification:
      final summary = await ledgerRepo.getMonthlySummary('2026-10');
      // Transfers MUST NOT appear as expense, refund, or income!
      expect(summary.totalExpenseMinor, equals(0));
      expect(summary.totalRefundMinor, equals(0));
      expect(summary.netExpenseMinor, equals(0));
      expect(summary.totalIncomeMinor, equals(100000)); // Only initial income
      expect(summary.transactionCount, equals(0)); // Transfers do not count towards expense/refund count

      // 4. Account balances verification:
      final balances = await ledgerRepo.getAccountBalances();
      expect(balances['acc_bank'], equals(60000)); // 100,000 - 40,000 = 60,000
      expect(balances['acc_wechat'], equals(40000)); // 0 + 40,000 = 40,000
      // Sum of balances equals total initial deposit
      final totalSum = (balances['acc_bank'] ?? 0) +
          (balances['acc_wechat'] ?? 0) +
          (balances['acc_alipay'] ?? 0) +
          (balances['acc_cash'] ?? 0);
      expect(totalSum, equals(100000));
    });

    test('monthly summary handles completely empty month with zero balances', () async {
      final summary = await ledgerRepo.getMonthlySummary('2025-01');
      expect(summary.totalExpenseMinor, equals(0));
      expect(summary.totalRefundMinor, equals(0));
      expect(summary.netExpenseMinor, equals(0));
      expect(summary.totalIncomeMinor, equals(0));
      expect(summary.transactionCount, equals(0));
      expect(summary.netBalanceMinor, equals(0));

      expect(CurrencyUtils.centsToYuanString(summary.totalExpenseMinor), equals('0.00'));
      expect(CurrencyUtils.centsToYuanString(summary.netBalanceMinor), equals('0.00'));
    });

    test('monthly summary correctly calculates negative net expense when refunds exceed expenses', () async {
      // Small expense 1,500 cents (15.00 CNY)
      const expense = TransactionEntry(
        id: 'tx_exp_small',
        type: 'expense',
        amountMinor: 1500,
        merchantRaw: '便民小店',
        occurredOn: '2026-10-10',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-10T10:00:00Z',
        updatedAt: '2026-10-10T10:00:00Z',
      );
      // Large refund from prior month: 8,000 cents (80.00 CNY)
      const largeRefund = TransactionEntry(
        id: 'tx_ref_large',
        type: 'refund',
        amountMinor: 8000,
        merchantRaw: '上月大额退款',
        occurredOn: '2026-10-12',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'second',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-12T10:00:00Z',
        updatedAt: '2026-10-12T10:00:00Z',
      );
      // Income: 50,000 cents (500.00 CNY)
      const income = TransactionEntry(
        id: 'tx_inc_salary',
        type: 'income',
        amountMinor: 50000,
        merchantRaw: '兼职收入',
        occurredOn: '2026-10-15',
        eventTimeSource: 'manual',
        eventTimePrecision: 'day',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_income',
        createdAt: '2026-10-15T10:00:00Z',
        updatedAt: '2026-10-15T10:00:00Z',
      );

      await db.insert('transactions', expense.toMap());
      await db.insert('transactions', largeRefund.toMap());
      await db.insert('transactions', income.toMap());

      final summary = await ledgerRepo.getMonthlySummary('2026-10');

      expect(summary.totalExpenseMinor, equals(1500));
      expect(summary.totalRefundMinor, equals(8000));
      // Net expense is negative: 1,500 - 8,000 = -6,500 cents (-65.00 CNY)
      expect(summary.netExpenseMinor, equals(-6500));
      expect(summary.totalIncomeMinor, equals(50000));
      // Net balance = 50,000 - (-6,500) = 56,500 cents (565.00 CNY)
      expect(summary.netBalanceMinor, equals(56500));
      expect(summary.transactionCount, equals(2));

      // Test formatting of negative net expense
      final formattedNet = CurrencyUtils.centsToYuanString(summary.netExpenseMinor);
      expect(formattedNet, equals('-65.00'));
    });

    test('negative account balances are computed accurately when expenses exceed initial balance', () async {
      // acc_cash has 0 balance, but incurs an expense of 4,500 cents
      const cashExpense = TransactionEntry(
        id: 'tx_cash_overdraft',
        type: 'expense',
        amountMinor: 4500,
        merchantRaw: '现金垫付',
        occurredOn: '2026-10-18',
        eventTimeSource: 'manual',
        eventTimePrecision: 'minute',
        paymentChannel: 'cash',
        accountId: 'acc_cash',
        categoryId: 'cat_other',
        createdAt: '2026-10-18T10:00:00Z',
        updatedAt: '2026-10-18T10:00:00Z',
      );
      await db.insert('transactions', cashExpense.toMap());

      final balances = await ledgerRepo.getAccountBalances();
      expect(balances['acc_cash'], equals(-4500));
      expect(CurrencyUtils.centsToYuanString(balances['acc_cash']!), equals('-45.00'));
    });

    test('monthly summary strictly enforces date boundaries and excludes soft-deleted items', () async {
      // 1. Transaction on 2026-09-30 (Previous month boundary)
      const txSep30 = TransactionEntry(
        id: 'tx_sep_30',
        type: 'expense',
        amountMinor: 9999,
        merchantRaw: '九月末消费',
        occurredOn: '2026-09-30',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'day',
        paymentChannel: 'wechat',
        categoryId: 'cat_food',
        createdAt: '2026-09-30T23:59:59Z',
        updatedAt: '2026-09-30T23:59:59Z',
      );
      // 2. Transaction on 2026-10-01 (October start boundary)
      const txOct01 = TransactionEntry(
        id: 'tx_oct_01',
        type: 'expense',
        amountMinor: 1000,
        merchantRaw: '十月初消费',
        occurredOn: '2026-10-01',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'day',
        paymentChannel: 'wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-01T00:00:01Z',
        updatedAt: '2026-10-01T00:00:01Z',
      );
      // 3. Transaction on 2026-10-31 (October end boundary)
      const txOct31 = TransactionEntry(
        id: 'tx_oct_31',
        type: 'expense',
        amountMinor: 2000,
        merchantRaw: '十月末消费',
        occurredOn: '2026-10-31',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'day',
        paymentChannel: 'wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-31T23:59:59Z',
        updatedAt: '2026-10-31T23:59:59Z',
      );
      // 4. Transaction on 2026-11-01 (Next month boundary)
      const txNov01 = TransactionEntry(
        id: 'tx_nov_01',
        type: 'expense',
        amountMinor: 8888,
        merchantRaw: '十一月初消费',
        occurredOn: '2026-11-01',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'day',
        paymentChannel: 'wechat',
        categoryId: 'cat_food',
        createdAt: '2026-11-01T00:00:01Z',
        updatedAt: '2026-11-01T00:00:01Z',
      );
      // 5. Soft-deleted transaction in October
      const txOctDeleted = TransactionEntry(
        id: 'tx_oct_deleted',
        type: 'expense',
        amountMinor: 77777,
        merchantRaw: '十月已软删除消费',
        occurredOn: '2026-10-15',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'day',
        paymentChannel: 'wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-15T12:00:00Z',
        updatedAt: '2026-10-15T12:00:00Z',
        deletedAt: '2026-10-15T13:00:00Z',
      );

      await db.insert('transactions', txSep30.toMap());
      await db.insert('transactions', txOct01.toMap());
      await db.insert('transactions', txOct31.toMap());
      await db.insert('transactions', txNov01.toMap());
      await db.insert('transactions', txOctDeleted.toMap());

      final summaryOct = await ledgerRepo.getMonthlySummary('2026-10');
      // Should include ONLY txOct01 (1,000) and txOct31 (2,000) = 3,000 cents
      expect(summaryOct.totalExpenseMinor, equals(3000));
      expect(summaryOct.transactionCount, equals(2));

      final summarySep = await ledgerRepo.getMonthlySummary('2026-09');
      expect(summarySep.totalExpenseMinor, equals(9999));
      expect(summarySep.transactionCount, equals(1));

      final summaryNov = await ledgerRepo.getMonthlySummary('2026-11');
      expect(summaryNov.totalExpenseMinor, equals(8888));
      expect(summaryNov.transactionCount, equals(1));
    });
  });
}
