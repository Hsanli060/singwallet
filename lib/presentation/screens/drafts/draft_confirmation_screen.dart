// lib/presentation/screens/drafts/draft_confirmation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/native/native_bridge.g.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../data/database/transaction_manager.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/draft_repository.dart';
import '../../../features/deduplication/deduplication_engine.dart';
import '../../providers/core_providers.dart';
import '../../providers/draft_providers.dart';
import '../../providers/rule_account_providers.dart';
import 'widgets/category_suggestion_card.dart';
import 'widgets/deduplication_dialogs.dart';
import 'widgets/ocr_bounding_box_overlay.dart';
import 'widgets/smart_transaction_form.dart';

/// Screen for reviewing OCR captured bill drafts and committing them to the ledger.
///
/// Features:
/// 1. Visual evidence overlay displaying bounding boxes with touch-to-fill capability.
/// 2. Category recommendation card with confidence percentage and modal picker.
/// 3. Smart transaction form with 36pt amount, channel, type, datetime, account, and project.
/// 4. 4-tier deduplication check interception before committing.
/// 5. Atomic draft commitment and draft discarding.
class DraftConfirmationScreen extends ConsumerStatefulWidget {
  final String draftId;
  final DraftDetail? initialDetail;
  final List<OcrBoundingBoxItem>? customOcrLines;

  const DraftConfirmationScreen({
    super.key,
    required this.draftId,
    this.initialDetail,
    this.customOcrLines,
  });

  @override
  ConsumerState<DraftConfirmationScreen> createState() => _DraftConfirmationScreenState();
}

class _DraftConfirmationScreenState extends ConsumerState<DraftConfirmationScreen> {
  late TextEditingController _amountController;
  late TextEditingController _merchantController;
  late TextEditingController _noteController;

  String _selectedType = 'expense';
  String _selectedChannel = 'wechat';
  String? _selectedAccountId;
  String? _selectedProjectId;
  String? _selectedCategoryId;
  String? _suggestedCategoryId;
  double? _confidenceScore;
  DateTime _selectedDateTime = DateTime.now();

  String? _platformTransactionNo;
  String? _merchantOrderNo;
  IdentifierCompleteness _identifierCompleteness = IdentifierCompleteness.none;
  String? _imagePath;
  List<OcrBoundingBoxItem> _boundingBoxItems = [];

  bool _isInitialized = false;
  bool _isCommitting = false;
  String? _amountErrorText;
  String? _merchantErrorText;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _merchantController = TextEditingController();
    _noteController = TextEditingController();

    if (widget.initialDetail != null) {
      _initFromDetail(widget.initialDetail!);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _initFromDetail(DraftDetail detail) {
    if (_isInitialized) return;
    _isInitialized = true;

    final fields = detail.candidateFields;
    _imagePath = detail.captureJob?.privateImageRef;

    // 1. Amount minor to yuan
    final rawAmountMinor = fields['amount_minor'] ?? fields['amountMinor'];
    if (rawAmountMinor is int && rawAmountMinor > 0) {
      _amountController.text = CurrencyUtils.centsToYuanString(rawAmountMinor);
    }

    // 2. Merchant
    final rawMerchant = fields['merchant_raw'] ?? fields['merchantRaw'];
    if (rawMerchant is String) {
      _merchantController.text = rawMerchant;
    }

    // 3. Type
    final rawType = fields['type'] as String?;
    if (rawType != null && rawType.isNotEmpty) {
      _selectedType = rawType;
    }

    // 4. Payment channel
    final rawChannel = (fields['payment_channel'] ?? fields['paymentChannel']) as String?;
    if (rawChannel != null && rawChannel.isNotEmpty) {
      _selectedChannel = rawChannel;
    }

    // 5. Date & Time
    final occurredAtStr = (fields['occurred_at'] ?? fields['occurredAt']) as String?;
    final occurredOnStr = (fields['occurred_on'] ?? fields['occurredOn']) as String?;
    if (occurredAtStr != null && occurredAtStr.isNotEmpty) {
      final parsed = DateTime.tryParse(occurredAtStr);
      if (parsed != null) _selectedDateTime = parsed.toLocal();
    } else if (occurredOnStr != null && occurredOnStr.isNotEmpty) {
      final parsed = DateTime.tryParse(occurredOnStr);
      if (parsed != null) _selectedDateTime = parsed;
    }

    // 6. Category recommendation
    _suggestedCategoryId =
        (fields['suggested_category_id'] ?? fields['suggestedCategoryId']) as String?;
    _selectedCategoryId = _suggestedCategoryId;

    final rawScore = fields['confidence_score'] ?? fields['confidenceScore'];
    if (rawScore is num) {
      _confidenceScore = rawScore.toDouble();
    }

    // 7. Project
    _selectedProjectId =
        (fields['suggested_project_id'] ?? fields['suggestedProjectId']) as String?;

    // 8. Platform identifiers
    _platformTransactionNo =
        (fields['platform_transaction_no'] ?? fields['platformTransactionNo']) as String?;
    _merchantOrderNo =
        (fields['merchant_order_no'] ?? fields['merchantOrderNo']) as String?;
    final rawCompleteness =
        (fields['identifier_completeness'] ?? fields['identifierCompleteness']) as String?;
    _identifierCompleteness = IdentifierCompletenessExtension.fromDbValue(rawCompleteness);

    // 9. Field evidence bounding boxes
    _extractBoundingBoxes(detail.fieldEvidence);
  }

  void _extractBoundingBoxes(Map<String, dynamic> evidenceMap) {
    final List<OcrBoundingBoxItem> items = [];

    // Include custom OCR lines if provided
    if (widget.customOcrLines != null && widget.customOcrLines!.isNotEmpty) {
      items.addAll(widget.customOcrLines!);
    }

    evidenceMap.forEach((key, val) {
      if (val is Map<String, dynamic>) {
        final rawBox = val['bounding_box'] ?? val['boundingBox'];
        if (rawBox is Map) {
          final box = OcrBoundingBox(
            left: (rawBox['left'] as num?)?.toDouble() ?? 0.0,
            top: (rawBox['top'] as num?)?.toDouble() ?? 0.0,
            width: (rawBox['width'] as num?)?.toDouble() ?? 0.0,
            height: (rawBox['height'] as num?)?.toDouble() ?? 0.0,
          );
          final text = (val['raw_text'] ?? val['rawText'] ?? val['matched_substring'] ?? '')
              as String;
          final conf = (val['confidence'] as num?)?.toDouble();

          items.add(
            OcrBoundingBoxItem(
              text: text,
              boundingBox: box,
              confidence: conf,
              fieldKey: key,
            ),
          );
        }
      }
    });

    _boundingBoxItems = items;
  }

  void _handleFillField(String text, String targetField) {
    if (targetField == 'merchant') {
      setState(() {
        _merchantController.text = text;
        _merchantErrorText = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已回填商户名称: "$text"'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (targetField == 'amount') {
      try {
        final cents = CurrencyUtils.parseToMinorUnits(text);
        setState(() {
          _amountController.text = CurrencyUtils.centsToYuanString(cents);
          _amountErrorText = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已回填交易金额: ¥${_amountController.text}'),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (_) {
        setState(() {
          _amountController.text = text;
        });
      }
    }
  }

  Future<void> _handleCommit(
    List<Account> accounts,
    List<Category> categories,
  ) async {
    setState(() {
      _amountErrorText = null;
      _merchantErrorText = null;
    });

    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() => _amountErrorText = '请输入交易金额');
      return;
    }

    int parsedAmountMinor;
    try {
      parsedAmountMinor = CurrencyUtils.parseToMinorUnits(amountText);
      if (parsedAmountMinor <= 0) {
        setState(() => _amountErrorText = '金额必须大于 0');
        return;
      }
    } catch (_) {
      setState(() => _amountErrorText = '金额格式不正确');
      return;
    }

    final merchantText = _merchantController.text.trim();
    if (merchantText.isEmpty) {
      setState(() => _merchantErrorText = '商户名称不能为空');
      return;
    }

    // Default category fallback
    final effectiveCategoryId = _selectedCategoryId ??
        (_suggestedCategoryId ?? (categories.isNotEmpty ? categories.first.id : 'cat_food'));

    // Default account fallback
    final effectiveAccountId = _selectedAccountId ??
        (accounts.isNotEmpty ? accounts.first.id : 'acc_wechat');

    final occurredOnStr =
        '${_selectedDateTime.year.toString().padLeft(4, '0')}-${_selectedDateTime.month.toString().padLeft(2, '0')}-${_selectedDateTime.day.toString().padLeft(2, '0')}';
    final occurredAtStr = _selectedDateTime.toUtc().toIso8601String();

    setState(() => _isCommitting = true);

    try {
      // 1. Prepare PlatformIdentifier for Tier 3 check if available
      PlatformIdentifier? platformId;
      if (_platformTransactionNo != null && _platformTransactionNo!.trim().isNotEmpty) {
        platformId = PlatformIdentifier(
          namespace: _selectedChannel,
          identifierType: 'platform_transaction_no',
          completeValue: _platformTransactionNo!.trim(),
          stableEventKind: _selectedType == 'refund' ? 'refund' : 'payment',
          completeness: _identifierCompleteness,
        );
      }

      // 2. Run pre-commit 4-tier deduplication check
      final dedupEngine = ref.read(deduplicationEngineProvider);
      final dedupResolution = await DeduplicationDialogs.evaluateAndIntercept(
        context: context,
        engine: dedupEngine,
        originDraftId: widget.draftId,
        platformIdentifier: platformId,
        merchantRaw: merchantText,
        amountMinor: parsedAmountMinor,
        occurredOn: occurredOnStr,
        occurredAt: occurredAtStr,
      );

      if (!mounted) return;

      if (dedupResolution is DedupBlocked || dedupResolution is DedupCancelled) {
        setState(() => _isCommitting = false);
        return;
      }

      if (dedupResolution is DedupRestoreRequested) {
        // User chose to directly restore from trash bin
        final ledgerRepo = ref.read(ledgerRepositoryProvider);
        await ledgerRepo.restoreTransaction(dedupResolution.transactionId);
        await ref.read(draftsQueueProvider.notifier).discard(widget.draftId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已从回收站直接恢复原交易，当前草稿已清理'),
              backgroundColor: Colors.amber,
            ),
          );
          Navigator.of(context).pop(true);
        }
        return;
      }

      // 3. Construct and commit transaction
      final nowUtcIso = DateTime.now().toUtc().toIso8601String();
      final newTxId = 'tx_${DateTime.now().millisecondsSinceEpoch}';

      final tx = TransactionEntry(
        id: newTxId,
        originDraftId: widget.draftId,
        type: _selectedType,
        amountMinor: parsedAmountMinor,
        currency: 'CNY',
        merchantRaw: merchantText,
        merchantNormalized: merchantText,
        occurredOn: occurredOnStr,
        occurredAt: occurredAtStr,
        eventTimeSource: 'ocr_extracted',
        eventTimePrecision: 'minute',
        paymentChannel: _selectedChannel,
        accountId: effectiveAccountId,
        categoryId: effectiveCategoryId,
        projectId: _selectedProjectId,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        createdAt: nowUtcIso,
        updatedAt: nowUtcIso,
      );

      ConfirmedIdentifier? confirmedId;
      if (platformId != null && platformId.isEligibleForHardDedup) {
        confirmedId = ConfirmedIdentifier(
          transactionId: newTxId,
          namespace: platformId.namespace,
          identifierType: platformId.identifierType,
          completeValue: platformId.completeValue,
          stableEventKind: platformId.stableEventKind,
        );
      }

      final metadata = TransactionMetadata(
        transactionId: newTxId,
        platformTransactionNo: _platformTransactionNo,
        merchantOrderNo: _merchantOrderNo,
        identifierCompleteness: _identifierCompleteness.toDbValue(),
      );

      final commitReq = CommitDraftRequest(
        transaction: tx,
        metadata: metadata,
        identifier: confirmedId,
      );

      final result = await ref.read(draftsQueueProvider.notifier).commit(commitReq);

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('确认入账成功！已添加至正式账目'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        if (result.isHardDuplicate) {
          await DeduplicationDialogs.showTier3ActiveDialog(
            context,
            transactionId: result.collidingTransactionId,
          );
        } else if (result.isTrashCollision) {
          await DeduplicationDialogs.showTier3TrashDialog(
            context,
            trashTransactionId: result.collidingTransactionId!,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? '入账失败，请检查填写内容'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作异常: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  Future<void> _handleDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('放弃草稿'),
          content: const Text('确定要放弃此笔识别草稿吗？放弃后草稿将从队列移除且不可恢复。'),
          actions: [
            TextButton(
              key: const ValueKey('discard_dialog_cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('discard_dialog_confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定放弃'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await ref.read(draftsQueueProvider.notifier).discard(widget.draftId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已放弃该识别草稿')),
        );
        Navigator.of(context).pop(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailAsync = ref.watch(draftDetailProvider(widget.draftId));
    final accountsAsync = ref.watch(accountsListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final projectsAsync = ref.watch(projectsListProvider);

    final accounts = accountsAsync.maybeWhen(
      data: (list) => list,
      orElse: () => const <Account>[],
    );
    final categories = categoriesAsync.maybeWhen(
      data: (list) => list,
      orElse: () => const <Category>[],
    );
    final projects = projectsAsync.maybeWhen(
      data: (list) => list,
      orElse: () => const <Project>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('确认交易入账'),
        actions: [
          IconButton(
            key: const ValueKey('discard_draft_button'),
            icon: const Icon(Icons.delete_outline),
            tooltip: '放弃草稿',
            onPressed: _isCommitting ? null : _handleDiscard,
          ),
        ],
      ),
      body: widget.initialDetail != null
          ? _buildContent(theme, accounts, categories, projects)
          : detailAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text('获取草稿详情失败: $err'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(draftDetailProvider(widget.draftId)),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (detail) {
                if (detail != null && !_isInitialized) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _initFromDetail(detail);
                      setState(() {});
                    }
                  });
                }
                return _buildContent(theme, accounts, categories, projects);
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  key: const ValueKey('bottom_discard_button'),
                  onPressed: _isCommitting ? null : _handleDiscard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error.withAlpha(150)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('放弃草稿'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const ValueKey('commit_draft_button'),
                  onPressed: _isCommitting
                      ? null
                      : () => _handleCommit(accounts, categories),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isCommitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '确认入账',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    List<Account> accounts,
    List<Category> categories,
    List<Project> projects,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. OCR BoundingBox Overlay & Screenshot Canvas
          OcrBoundingBoxOverlay(
            key: const ValueKey('ocr_overlay_widget'),
            imagePath: _imagePath,
            items: _boundingBoxItems,
            onFillField: _handleFillField,
          ),
          const SizedBox(height: 16),

          // 2. Category Suggestion Card with AI Confidence
          CategorySuggestionCard(
            suggestedCategoryId: _suggestedCategoryId,
            confidenceScore: _confidenceScore,
            selectedCategoryId: _selectedCategoryId,
            categories: categories,
            onCategorySelected: (catId) {
              setState(() => _selectedCategoryId = catId);
            },
            onAcceptSuggestion: () {
              if (_suggestedCategoryId != null) {
                setState(() => _selectedCategoryId = _suggestedCategoryId);
              }
            },
          ),
          const SizedBox(height: 16),

          // 3. Smart Transaction Input Form
          SmartTransactionForm(
            amountController: _amountController,
            merchantController: _merchantController,
            noteController: _noteController,
            selectedType: _selectedType,
            onTypeChanged: (type) => setState(() => _selectedType = type),
            selectedChannel: _selectedChannel,
            onChannelChanged: (ch) => setState(() => _selectedChannel = ch),
            selectedAccountId: _selectedAccountId,
            onAccountChanged: (acc) => setState(() => _selectedAccountId = acc),
            accounts: accounts,
            selectedProjectId: _selectedProjectId,
            onProjectChanged: (proj) => setState(() => _selectedProjectId = proj),
            projects: projects,
            selectedDateTime: _selectedDateTime,
            onDateTimeChanged: (dt) => setState(() => _selectedDateTime = dt),
            amountErrorText: _amountErrorText,
            merchantErrorText: _merchantErrorText,
          ),
        ],
      ),
    );
  }
}
