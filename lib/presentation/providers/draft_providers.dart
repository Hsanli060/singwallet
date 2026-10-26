// lib/presentation/providers/draft_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/transaction_manager.dart';
import '../../data/models/models.dart';
import '../../data/repositories/draft_repository.dart';
import 'core_providers.dart';
import 'transaction_providers.dart';

/// Notifier managing pending OCR drafts in NEEDS_REVIEW or IMPORTED states.
class DraftsQueueNotifier extends AsyncNotifier<List<Draft>> {
  @override
  Future<List<Draft>> build() async {
    final repo = ref.watch(draftRepositoryProvider);
    return repo.getPendingDrafts();
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<Draft>>.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(draftRepositoryProvider);
      return repo.getPendingDrafts();
    });
  }

  Future<void> discard(String draftId) async {
    final repo = ref.read(draftRepositoryProvider);
    await repo.discardDraft(draftId);
    ref.invalidate(draftDetailProvider(draftId));
    await refresh();
  }

  Future<CommitDraftResult> commit(CommitDraftRequest request) async {
    final repo = ref.read(draftRepositoryProvider);
    final result = await repo.commitDraft(request);
    if (result.success) {
      final draftId = request.transaction.originDraftId;
      if (draftId != null) {
        ref.invalidate(draftDetailProvider(draftId));
      }
      ref.invalidate(transactionListProvider);
      ref.invalidate(monthlySummaryProvider);
      await refresh();
    }
    return result;
  }
}

/// Provider for pending OCR drafts queue.
final draftsQueueProvider =
    AsyncNotifierProvider<DraftsQueueNotifier, List<Draft>>(
  DraftsQueueNotifier.new,
);

/// Provider fetching full detail of a specific draft.
final draftDetailProvider =
    FutureProvider.family<DraftDetail?, String>((ref, draftId) async {
  final repo = ref.watch(draftRepositoryProvider);
  return repo.getDraftDetail(draftId);
});

/// Count of pending drafts awaiting user confirmation.
final pendingDraftsCountProvider = Provider<int>((ref) {
  final queueAsync = ref.watch(draftsQueueProvider);
  return queueAsync.maybeWhen(
    data: (drafts) => drafts.length,
    orElse: () => 0,
  );
});
