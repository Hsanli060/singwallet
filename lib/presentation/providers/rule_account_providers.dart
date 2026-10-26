// lib/presentation/providers/rule_account_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/models.dart';
import 'core_providers.dart';

/// Notifier managing classification rules list and modifications.
class RulesListNotifier extends AsyncNotifier<List<ClassificationRule>> {
  @override
  Future<List<ClassificationRule>> build() async {
    final repo = ref.watch(ruleRepositoryProvider);
    return repo.getAllRules();
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<ClassificationRule>>.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(ruleRepositoryProvider);
      return repo.getAllRules();
    });
  }

  Future<void> toggleEnabled(String ruleId, bool enabled) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.setRuleEnabled(ruleId, enabled);
    await refresh();
  }

  Future<void> updatePriority(String ruleId, int priority) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.updateRulePriority(ruleId, priority);
    await refresh();
  }

  Future<void> save(ClassificationRule rule) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.saveRule(rule);
    await refresh();
  }

  Future<void> delete(String ruleId) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.deleteRule(ruleId);
    await refresh();
  }

  Future<void> reorder(List<ClassificationRule> reordered) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.reorderRules(reordered);
    await refresh();
  }
}

/// Provider for classification rules list ordered by priority.
final rulesListProvider =
    AsyncNotifierProvider<RulesListNotifier, List<ClassificationRule>>(
  RulesListNotifier.new,
);

/// Notifier managing financial accounts list.
class AccountsListNotifier extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() async {
    final repo = ref.watch(ledgerRepositoryProvider);
    return repo.getAccounts();
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<Account>>.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(ledgerRepositoryProvider);
      return repo.getAccounts();
    });
  }
}

/// Provider for financial accounts list.
final accountsListProvider =
    AsyncNotifierProvider<AccountsListNotifier, List<Account>>(
  AccountsListNotifier.new,
);

/// Notifier managing project budgets/labels list.
class ProjectsListNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    final repo = ref.watch(ledgerRepositoryProvider);
    return repo.getProjects();
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<Project>>.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(ledgerRepositoryProvider);
      return repo.getProjects();
    });
  }
}

/// Provider for project budget tags list.
final projectsListProvider =
    AsyncNotifierProvider<ProjectsListNotifier, List<Project>>(
  ProjectsListNotifier.new,
);

/// Provider fetching all transaction categories.
final categoriesListProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getCategories();
});

/// Provider computing dynamic live balances across accounts.
final accountBalancesProvider = FutureProvider<Map<String, int>>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getAccountBalances();
});
