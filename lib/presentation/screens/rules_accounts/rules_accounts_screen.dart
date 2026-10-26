// lib/presentation/screens/rules_accounts/rules_accounts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/accounts_tab.dart';
import 'widgets/classification_rules_tab.dart';
import 'widgets/projects_tab.dart';
import 'widgets/refund_link_dialog.dart';

/// Milestone M2-4: Classification Rules & Accounts/Projects Configuration Center.
///
/// Tabbed container containing 3 tabs:
/// - "分类规则" (Classification Rules): Priority ordering, toggle active switch, rematching, adding rules.
/// - "资产账户" (Asset Accounts): Total Assets card, channel type icons, real-time balances, adding accounts.
/// - "项目管理" (Project Management): Lifecycle event project management, adding projects.
///
/// Also provides integrated launcher for [RefundLinkDialog].
class RulesAccountsScreen extends ConsumerWidget {
  final bool showAppBar;

  const RulesAccountsScreen({
    super.key,
    this.showAppBar = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: showAppBar
            ? AppBar(
                title: const Text('规则与配置中心'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.link),
                    tooltip: '关联退款账目',
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        builder: (ctx) => const RefundLinkDialog(),
                      );
                    },
                  ),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.rule), text: '分类规则'),
                    Tab(icon: Icon(Icons.account_balance), text: '资产账户'),
                    Tab(icon: Icon(Icons.folder_special), text: '项目管理'),
                  ],
                ),
              )
            : null,
        body: Column(
          children: [
            if (!showAppBar)
              Material(
                color: theme.colorScheme.surface,
                elevation: 1,
                child: Row(
                  children: [
                    const Expanded(
                      child: TabBar(
                        tabs: [
                          Tab(icon: Icon(Icons.rule), text: '分类规则'),
                          Tab(icon: Icon(Icons.account_balance), text: '资产账户'),
                          Tab(icon: Icon(Icons.folder_special), text: '项目管理'),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.link),
                      tooltip: '关联退款账目',
                      onPressed: () {
                        showDialog<bool>(
                          context: context,
                          builder: (ctx) => const RefundLinkDialog(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            const Expanded(
              child: TabBarView(
                children: [
                  ClassificationRulesTab(),
                  AccountsTab(),
                  ProjectsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
