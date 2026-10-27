// test/presentation/draft_confirmation_screen_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/native_bridge.g.dart';
import 'package:singwallet/data/database/app_database.dart';
import 'package:singwallet/data/database/transaction_manager.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/data/repositories/draft_repository.dart';
import 'package:singwallet/data/repositories/ledger_repository.dart';
import 'package:singwallet/data/seeder/database_seeder.dart';
import 'package:singwallet/features/deduplication/deduplication_engine.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/providers/draft_providers.dart';
import 'package:singwallet/presentation/providers/rule_account_providers.dart';
import 'package:singwallet/presentation/screens/drafts/draft_confirmation_screen.dart';
import 'package:singwallet/presentation/screens/drafts/drafts_queue_screen.dart';
import 'package:singwallet/presentation/screens/drafts/widgets/category_suggestion_card.dart';
import 'package:singwallet/presentation/screens/drafts/widgets/deduplication_dialogs.dart';
import 'package:singwallet/presentation/screens/drafts/widgets/ocr_bounding_box_overlay.dart';
import 'package:singwallet/presentation/screens/drafts/widgets/smart_transaction_form.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeDraftsQueueNotifier extends DraftsQueueNotifier {
  final List<Draft> _items;
  _FakeDraftsQueueNotifier(this._items);

  @override
  Future<List<Draft>> build() async => _items;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_items);
  }
}

class _FakeAccountsListNotifier extends AccountsListNotifier {
  final List<Account> _items;
  _FakeAccountsListNotifier(this._items);

  @override
  Future<List<Account>> build() async => _items;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoundingBoxMapper Unit Tests', () {
    test('accurate letterbox coordinate mapping without distortion', () {
      const imageSize = Size(1000, 2000);
      const viewportSize = Size(600, 1000);

      final box = OcrBoundingBox(
        left: 0.1,
        top: 0.2,
        width: 0.5,
        height: 0.1,
      );

      final mappedRect = BoundingBoxMapper.mapNormalizedToViewport(
        box: box,
        imageSize: imageSize,
        viewportSize: viewportSize,
      );

      expect(mappedRect.left, closeTo(50 + (0.1 * 500), 0.001));
      expect(mappedRect.top, closeTo(0 + (0.2 * 1000), 0.001));
      expect(mappedRect.width, closeTo(0.5 * 500, 0.001));
      expect(mappedRect.height, closeTo(0.1 * 1000, 0.001));
    });

    test('accurate pillarbox mapping for wide images in tall viewports', () {
      const imageSize = Size(2000, 1000);
      const viewportSize = Size(1000, 1000);

      final box = OcrBoundingBox(
        left: 0.0,
        top: 0.0,
        width: 1.0,
        height: 1.0,
      );

      final mappedRect = BoundingBoxMapper.mapNormalizedToViewport(
        box: box,
        imageSize: imageSize,
        viewportSize: viewportSize,
      );

      expect(mappedRect.left, closeTo(0.0, 0.001));
      expect(mappedRect.top, closeTo(250.0, 0.001));
      expect(mappedRect.width, closeTo(1000.0, 0.001));
      expect(mappedRect.height, closeTo(500.0, 0.001));
    });

    test('handles zero dimensions safely by returning Rect.zero', () {
      final box = OcrBoundingBox(left: 0.1, top: 0.1, width: 0.2, height: 0.2);
      expect(
        BoundingBoxMapper.mapNormalizedToViewport(
          box: box,
          imageSize: Size.zero,
          viewportSize: const Size(100, 100),
        ),
        equals(Rect.zero),
      );
    });
  });

  group('OcrBoundingBoxOverlay Widget Tests', () {
    testWidgets('renders placeholder canvas gracefully and triggers touch callback',
        (tester) async {
      String? tappedText;
      String? filledText;
      String? filledField;

      final items = [
        OcrBoundingBoxItem(
          text: '星巴克咖啡 (上海陆家嘴店)',
          boundingBox: OcrBoundingBox(left: 0.1, top: 0.1, width: 0.8, height: 0.1),
        ),
        OcrBoundingBoxItem(
          text: '38.00',
          boundingBox: OcrBoundingBox(left: 0.2, top: 0.3, width: 0.6, height: 0.1),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: OcrBoundingBoxOverlay(
                  items: items,
                  originalImageSize: const Size(400, 300),
                  height: 300,
                  onBoxTapped: (text) => tappedText = text,
                  onFillField: (text, field) {
                    filledText = text;
                    filledField = field;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Verify canvas text
      expect(find.text('OCR 证据快照预览'), findsOneWidget);
      expect(find.text('2 个文本证据锚点就绪'), findsOneWidget);

      // Tap on the first bounding box using relative offset
      final overlayFinder = find.byType(OcrBoundingBoxOverlay);
      final overlayTopLeft = tester.getTopLeft(overlayFinder);
      await tester.tapAt(overlayTopLeft + const Offset(200, 45));
      await tester.pumpAndSettle();

      expect(tappedText, equals('星巴克咖啡 (上海陆家嘴店)'));

      // Check quick fill modal bottom sheet
      expect(find.text('快速回填: "星巴克咖啡 (上海陆家嘴店)"'), findsOneWidget);
      expect(find.text('填入商户名称'), findsOneWidget);
      expect(find.text('填入交易金额'), findsOneWidget);

      // Tap '填入商户名称'
      await tester.tap(find.text('填入商户名称'));
      await tester.pumpAndSettle();

      expect(filledText, equals('星巴克咖啡 (上海陆家嘴店)'));
      expect(filledField, equals('merchant'));
    });
  });

  group('SmartTransactionForm Widget Tests', () {
    testWidgets('renders 36pt amount, type selector, and merchant clear button',
        (tester) async {
      final amountCtrl = TextEditingController(text: '45.50');
      final merchantCtrl = TextEditingController(text: '喜茶 (万象城店)');
      final noteCtrl = TextEditingController();
      String selectedType = 'expense';
      String selectedChannel = 'wechat';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SmartTransactionForm(
                amountController: amountCtrl,
                merchantController: merchantCtrl,
                noteController: noteCtrl,
                selectedType: selectedType,
                onTypeChanged: (t) => selectedType = t,
                selectedChannel: selectedChannel,
                onChannelChanged: (ch) => selectedChannel = ch,
                selectedAccountId: 'acc_wechat',
                onAccountChanged: (_) {},
                accounts: const [
                  Account(
                    id: 'acc_wechat',
                    name: '微信零钱',
                    kind: 'e_wallet',
                    createdAt: '2026-10-23T00:00:00Z',
                    updatedAt: '2026-10-23T00:00:00Z',
                  ),
                ],
                selectedProjectId: null,
                onProjectChanged: (_) {},
                projects: const [],
                selectedDateTime: DateTime(2026, 10, 23, 14, 30),
                onDateTimeChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Check 36pt amount and converted cents preview
      expect(find.text('45.50'), findsOneWidget);
      expect(find.textContaining('4550 分 (45.50 元)'), findsOneWidget);

      // Check merchant input
      expect(find.text('喜茶 (万象城店)'), findsOneWidget);

      // Clear button should exist and empty the field
      final clearBtn = find.byIcon(Icons.clear);
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pump();
      expect(merchantCtrl.text, isEmpty);

      // Switch type to 'income'
      await tester.tap(find.text('收入'));
      await tester.pump();
      expect(selectedType, equals('income'));
    });
  });

  group('CategorySuggestionCard Widget Tests', () {
    testWidgets('displays confidence percentage and supports quick accept or modal',
        (tester) async {
      String? selectedCatId;
      bool suggestionAccepted = false;

      const categories = [
        Category(
          id: 'cat_food',
          name: '餐饮美食',
          applicableType: 'expense',
          iconKey: 'restaurant',
          createdAt: '2026-10-23T00:00:00Z',
          updatedAt: '2026-10-23T00:00:00Z',
        ),
        Category(
          id: 'cat_transport',
          name: '交通出行',
          applicableType: 'expense',
          iconKey: 'subway',
          createdAt: '2026-10-23T00:00:00Z',
          updatedAt: '2026-10-23T00:00:00Z',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategorySuggestionCard(
              suggestedCategoryId: 'cat_food',
              confidenceScore: 0.95,
              selectedCategoryId: selectedCatId,
              categories: categories,
              onCategorySelected: (id) => selectedCatId = id,
              onAcceptSuggestion: () => suggestionAccepted = true,
            ),
          ),
        ),
      );

      expect(find.text('智能推荐分类'), findsOneWidget);
      expect(find.text('95% 置信度'), findsOneWidget);
      expect(find.text('餐饮美食'), findsOneWidget);
      expect(find.text('一键采纳'), findsOneWidget);

      // Click '一键采纳'
      await tester.tap(find.text('一键采纳'));
      await tester.pump();
      expect(selectedCatId, equals('cat_food'));
      expect(suggestionAccepted, isTrue);

      // Click '选择其他分类'
      await tester.tap(find.text('选择其他分类'));
      await tester.pumpAndSettle();

      expect(find.text('选择交易分类'), findsOneWidget);
      expect(find.text('交通出行'), findsOneWidget);

      await tester.tap(find.text('交通出行'));
      await tester.pumpAndSettle();

      expect(selectedCatId, equals('cat_transport'));
    });
  });

  group('DeduplicationDialogs Interception Tests', () {
    testWidgets('Tier 3 Active Duplicate shows Red blocking dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  DeduplicationDialogs.showTier3ActiveDialog(
                    context,
                    transactionId: 'tx_existing_123',
                    transaction: {
                      'merchant_raw': '美团外卖',
                      'amount_minor': 3500,
                      'occurred_on': '2026-10-23',
                    },
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('发现重复交易'), findsOneWidget);
      expect(find.text('发现完全相同订单号的已确认交易，禁止重复入账。'), findsOneWidget);
      expect(find.text('商户: 美团外卖'), findsOneWidget);
      expect(find.text('金额: ¥35.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('tier3_active_dialog_ok')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tier3_active_dialog_ok')));
      await tester.pumpAndSettle();
      expect(find.text('发现重复交易'), findsNothing);
    });

    testWidgets('Tier 3 Trash Duplicate shows Amber restore dialog', (tester) async {
      bool? userRestored;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  userRestored = await DeduplicationDialogs.showTier3TrashDialog(
                    context,
                    trashTransactionId: 'tx_trash_456',
                    transaction: {
                      'merchant_raw': '滴滴出行',
                      'amount_minor': 2250,
                    },
                  );
                },
                child: const Text('Show Trash Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Trash Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('回收站存在相同交易'), findsOneWidget);
      expect(find.text('此订单号曾被删除，存在于回收站中，是否直接恢复？'), findsOneWidget);
      expect(find.text('原商户: 滴滴出行'), findsOneWidget);
      expect(find.text('原金额: ¥22.50'), findsOneWidget);

      // Tap '直接恢复'
      await tester.tap(find.byKey(const ValueKey('tier3_trash_dialog_restore')));
      await tester.pumpAndSettle();

      expect(userRestored, isTrue);
    });

    testWidgets('Tier 4 Heuristic Duplicate shows Secondary Confirmation modal',
        (tester) async {
      bool? userProceeded;

      final candidates = [
        {
          'merchant_raw': '瑞幸咖啡',
          'amount_minor': 1800,
          'occurred_on': '2026-10-23',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  userProceeded = await DeduplicationDialogs.showTier4FuzzyDialog(
                    context,
                    candidates: candidates,
                  );
                },
                child: const Text('Show Tier4 Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Tier4 Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('疑似重复交易'), findsOneWidget);
      expect(
        find.text('24小时内发现相同金额的相似交易，是否确认这笔交易不是重复记录？'),
        findsOneWidget,
      );
      expect(find.text('瑞幸咖啡'), findsOneWidget);
      expect(find.text('¥18.00'), findsOneWidget);

      // Tap '继续入账'
      await tester.tap(find.byKey(const ValueKey('tier4_fuzzy_dialog_proceed')));
      await tester.pumpAndSettle();

      expect(userProceeded, isTrue);
    });
  });

  group('DraftsQueueScreen Widget Tests', () {
    testWidgets('displays empty state when draft queue is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            draftsQueueProvider.overrideWith(() => _FakeDraftsQueueNotifier([])),
          ],
          child: const MaterialApp(
            home: DraftsQueueScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('待确认草稿箱'), findsOneWidget);
      expect(find.text('当前暂无待确认草稿'), findsOneWidget);
      expect(find.text('截图或分享导入的账单将显示在此处，等待确认入账'), findsOneWidget);
    });

    testWidgets('renders list of pending drafts and navigates on tap', (tester) async {
      final draft = Draft(
        id: 'draft_list_test',
        captureId: 'job_1',
        candidateFields: jsonEncode({
          'amount_minor': 5200,
          'merchant_raw': '盒马鲜生',
          'occurred_on': '2026-10-23',
          'payment_channel': 'alipay',
        }),
        fieldEvidence: jsonEncode({}),
        validationIssues: jsonEncode([]),
        duplicateCandidates: jsonEncode([]),
        createdAt: '2026-10-23T11:00:00Z',
        updatedAt: '2026-10-23T11:00:00Z',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            draftsQueueProvider.overrideWith(() => _FakeDraftsQueueNotifier([draft])),
          ],
          child: const MaterialApp(
            home: DraftsQueueScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('盒马鲜生'), findsOneWidget);
      expect(find.text('¥52.00'), findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      expect(find.text('待确认'), findsOneWidget);

      await tester.tap(find.text('盒马鲜生'));
      await tester.pumpAndSettle();
      expect(find.byType(DraftConfirmationScreen), findsOneWidget);
    });
  });

  group('DraftConfirmationScreen UI and Interaction Tests', () {
    const sampleJob = CaptureJob(
      id: 'job_sample',
      contentHash: 'hash_sample',
      sourceKind: 'screenshot',
      importedAt: '2026-10-23T10:00:00Z',
      privateImageRef: '',
      state: 'NEEDS_REVIEW',
      createdAt: '2026-10-23T10:00:00Z',
      updatedAt: '2026-10-23T10:00:00Z',
    );

    final sampleDraft = Draft(
      id: 'draft_sample_1',
      captureId: 'job_sample',
      candidateFields: jsonEncode({
        'amount_minor': 3280,
        'merchant_raw': '星巴克烘焙工坊',
        'occurred_on': '2026-10-23',
        'occurred_at': '2026-10-23T14:30:00Z',
        'payment_channel': 'wechat',
        'suggested_category_id': 'cat_food',
        'confidence_score': 0.98,
      }),
      fieldEvidence: jsonEncode({
        'merchant': {
          'raw_text': '星巴克烘焙工坊',
          'bounding_box': {'left': 0.1, 'top': 0.1, 'width': 0.8, 'height': 0.1},
        },
      }),
      validationIssues: jsonEncode([]),
      duplicateCandidates: jsonEncode([]),
      createdAt: '2026-10-23T10:05:00Z',
      updatedAt: '2026-10-23T10:05:00Z',
    );

    final sampleDetail = DraftDetail.fromDraftAndJob(sampleDraft, sampleJob);

    const testCategories = [
      Category(
        id: 'cat_food',
        name: '餐饮美食',
        applicableType: 'expense',
        iconKey: 'restaurant',
        createdAt: '2026-10-23T00:00:00Z',
        updatedAt: '2026-10-23T00:00:00Z',
      ),
      Category(
        id: 'cat_shopping',
        name: '日常购物',
        applicableType: 'expense',
        iconKey: 'shopping_bag',
        createdAt: '2026-10-23T00:00:00Z',
        updatedAt: '2026-10-23T00:00:00Z',
      ),
    ];

    const testAccounts = [
      Account(
        id: 'acc_wechat',
        name: '微信支付',
        kind: 'e_wallet',
        createdAt: '2026-10-23T00:00:00Z',
        updatedAt: '2026-10-23T00:00:00Z',
      ),
    ];

    testWidgets('renders prefilled form, category card, and overlay from initialDetail',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriesListProvider.overrideWith((ref) async => testCategories),
            accountsListProvider.overrideWith(() => _FakeAccountsListNotifier(testAccounts)),
          ],
          child: MaterialApp(
            home: DraftConfirmationScreen(
              draftId: 'draft_sample_1',
              initialDetail: sampleDetail,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('确认交易入账'), findsOneWidget);
      expect(find.text('32.80'), findsOneWidget);
      expect(find.text('星巴克烘焙工坊'), findsWidgets);
      expect(find.text('98% 置信度'), findsOneWidget);
      expect(find.text('餐饮美食'), findsOneWidget);
      expect(find.byType(OcrBoundingBoxOverlay), findsOneWidget);
      expect(find.byType(CategorySuggestionCard), findsOneWidget);
      expect(find.byType(SmartTransactionForm), findsOneWidget);
    });

    testWidgets('validation prevents commit on empty merchant and shows error',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriesListProvider.overrideWith((ref) async => testCategories),
            accountsListProvider.overrideWith(() => _FakeAccountsListNotifier(testAccounts)),
          ],
          child: MaterialApp(
            home: DraftConfirmationScreen(
              draftId: 'draft_sample_1',
              initialDetail: sampleDetail,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clear merchant input
      await tester.ensureVisible(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Click commit
      await tester.tap(find.byKey(const ValueKey('commit_draft_button')));
      await tester.pumpAndSettle();

      expect(find.text('商户名称不能为空'), findsOneWidget);
    });

    testWidgets('discard button shows dialog and discards on confirm', (tester) async {
      bool discardCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriesListProvider.overrideWith((ref) async => testCategories),
            accountsListProvider.overrideWith(() => _FakeAccountsListNotifier(testAccounts)),
            draftRepositoryProvider.overrideWith((ref) => _MockDraftRepo(
                  onDiscard: (id) => discardCalled = true,
                )),
          ],
          child: MaterialApp(
            home: DraftConfirmationScreen(
              draftId: 'draft_sample_1',
              initialDetail: sampleDetail,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap '放弃草稿'
      await tester.tap(find.byKey(const ValueKey('bottom_discard_button')));
      await tester.pumpAndSettle();

      expect(find.text('放弃草稿'), findsWidgets);
      expect(find.text('确定要放弃此笔识别草稿吗？放弃后草稿将从队列移除且不可恢复。'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('discard_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(discardCalled, isTrue);
    });
  });

  group('Full SQLite End-to-End Repository & Deduplication Integration', () {
    late Database db;
    late TransactionManager txManager;
    late DraftRepository draftRepo;
    late LedgerRepository ledgerRepo;
    late DeduplicationEngine dedupEngine;

    setUp(() async {
      db = await AppDatabase.openInMemory();
      txManager = TransactionManager();
      draftRepo = DraftRepository(db, txManager: txManager);
      ledgerRepo = LedgerRepository(db, txManager: txManager);
      dedupEngine = DeduplicationEngine(db);
      await DatabaseSeeder.seedIfNeeded(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Draft commitment inserts transaction, identifier, metadata and updates job state',
        () async {
      const job = CaptureJob(
        id: 'job_full_test',
        contentHash: 'hash_full_1',
        sourceKind: 'screenshot',
        importedAt: '2026-10-23T10:00:00Z',
        privateImageRef: '',
        state: 'NEEDS_REVIEW',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
      );
      await db.insert('capture_jobs', job.toMap());

      final draft = Draft(
        id: 'draft_full_1',
        captureId: 'job_full_test',
        candidateFields: jsonEncode({
          'amount_minor': 12800,
          'merchant_raw': 'Apple Store',
          'occurred_on': '2026-10-23',
          'payment_channel': 'wechat',
          'suggested_category_id': 'cat_shopping',
        }),
        fieldEvidence: jsonEncode({}),
        validationIssues: jsonEncode([]),
        duplicateCandidates: jsonEncode([]),
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
      );
      await db.insert('drafts', draft.toMap());

      const commitReq = CommitDraftRequest(
        transaction: TransactionEntry(
          id: 'tx_full_1',
          originDraftId: 'draft_full_1',
          type: 'expense',
          amountMinor: 12800,
          currency: 'CNY',
          merchantRaw: 'Apple Store',
          merchantNormalized: 'Apple Store',
          occurredOn: '2026-10-23',
          eventTimeSource: 'ocr_extracted',
          eventTimePrecision: 'minute',
          paymentChannel: 'wechat',
          accountId: 'acc_wechat',
          categoryId: 'cat_shopping',
          createdAt: '2026-10-23T10:00:00Z',
          updatedAt: '2026-10-23T10:00:00Z',
        ),
        identifier: ConfirmedIdentifier(
          transactionId: 'tx_full_1',
          namespace: 'wechat',
          identifierType: 'platform_transaction_no',
          completeValue: '4200002131202610230001',
          stableEventKind: 'payment',
        ),
      );

      final result = await draftRepo.commitDraft(commitReq);
      expect(result.success, isTrue);

      // Verify transaction committed
      final tx = await ledgerRepo.getTransactionById('tx_full_1');
      expect(tx, isNotNull);
      expect(tx!.amountMinor, equals(12800));

      // Verify Tier 3 deduplication engine detects hard duplicate now
      final platformId = PlatformIdentifier(
        namespace: 'wechat',
        identifierType: 'platform_transaction_no',
        completeValue: '4200002131202610230001',
        stableEventKind: 'payment',
      );
      final eval = await dedupEngine.evaluate(
        platformIdentifier: platformId,
        merchantRaw: 'Apple Store',
        amountMinor: 12800,
        occurredOn: '2026-10-23',
      );
      expect(eval.hasHardDuplicate, isTrue);
      expect(eval.tier3.isMatched, isTrue);
      expect(eval.tier3.matchedTransactionId, equals('tx_full_1'));

      // Verify capture job transitioned to COMMITTED
      final jobRows = await db.query('capture_jobs', where: 'id = ?', whereArgs: ['job_full_test']);
      expect(jobRows.first['state'], equals('COMMITTED'));
    });

    test('Tier 3 trash duplicate detection when colliding transaction is in trash', () async {
      const tx = TransactionEntry(
        id: 'tx_trashed_order',
        type: 'expense',
        amountMinor: 8800,
        merchantRaw: '优衣库旗舰店',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'alipay',
        accountId: 'acc_alipay',
        categoryId: 'cat_shopping',
        createdAt: '2026-10-23T10:00:00Z',
        updatedAt: '2026-10-23T10:00:00Z',
        deletedAt: '2026-10-23T12:00:00Z', // in trash!
      );
      await db.insert('transactions', tx.toMap());

      const id = ConfirmedIdentifier(
        transactionId: 'tx_trashed_order',
        namespace: 'alipay',
        identifierType: 'platform_transaction_no',
        completeValue: '202610232200149999',
        stableEventKind: 'payment',
      );
      await db.insert('confirmed_identifiers', id.toMap());

      final platformId = PlatformIdentifier(
        namespace: 'alipay',
        identifierType: 'platform_transaction_no',
        completeValue: '202610232200149999',
        stableEventKind: 'payment',
      );

      final eval = await dedupEngine.evaluate(
        platformIdentifier: platformId,
        merchantRaw: '优衣库旗舰店',
        amountMinor: 8800,
        occurredOn: '2026-10-23',
      );

      expect(eval.hasTrashDuplicate, isTrue);
      expect(eval.tier3.isMatched, isTrue);
      expect(eval.tier3.isInTrash, isTrue);
      expect(eval.tier3.matchedTransactionId, equals('tx_trashed_order'));
    });

    test('Tier 4 24h heuristic duplicate detection for same merchant and amount', () async {
      const tx = TransactionEntry(
        id: 'tx_recent_coffee',
        type: 'expense',
        amountMinor: 1500,
        merchantRaw: '瑞幸咖啡 (大厦店)',
        merchantNormalized: '瑞幸咖啡',
        occurredOn: '2026-10-23',
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: 'wechat',
        accountId: 'acc_wechat',
        categoryId: 'cat_food',
        createdAt: '2026-10-23T08:00:00Z',
        updatedAt: '2026-10-23T08:00:00Z',
      );
      await db.insert('transactions', tx.toMap());

      final eval = await dedupEngine.evaluate(
        merchantRaw: '瑞幸咖啡 (大厦店)',
        merchantNormalized: '瑞幸咖啡',
        amountMinor: 1500,
        occurredOn: '2026-10-23',
      );

      expect(eval.hasSoftDuplicate, isTrue);
      expect(eval.tier4.hasSuspectedDuplicates, isTrue);
      expect(eval.tier4.candidateTransactionIds.contains('tx_recent_coffee'), isTrue);
    });
  });
}

class _MockDraftRepo implements IDraftRepository {
  final void Function(String id)? onDiscard;

  _MockDraftRepo({this.onDiscard});

  @override
  Future<CommitDraftResult> commitDraft(CommitDraftRequest request) async {
    return CommitDraftResult.ok(request.transaction);
  }

  @override
  Future<void> discardDraft(String draftId) async {
    onDiscard?.call(draftId);
  }

  @override
  Future<DraftDetail?> getDraftDetail(String draftId) async => null;

  @override
  Future<List<DraftEntry>> getPendingDrafts() async => [];
}
