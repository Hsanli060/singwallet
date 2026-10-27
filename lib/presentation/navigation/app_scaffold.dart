// lib/presentation/navigation/app_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/draft_providers.dart';
import '../screens/drafts/drafts_queue_screen.dart';
import '../screens/rules_accounts/rules_accounts_screen.dart';
import '../screens/transactions/transactions_screen.dart';

/// Top-level Material 3 navigation scaffold for SingWallet.
///
/// Provides responsive navigation between:
/// - Index 0: Transactions (流水明细 / 资产大盘)
/// - Index 1: Drafts (截图草稿箱 / OCR 视觉高亮确认)
/// - Index 2: Rules & Accounts (分类规则中心与账户/项目配置)
///
/// Automatically switches between [NavigationBar] on compact screens
/// and [NavigationRail] on wide tablet/desktop viewports.
class AppScaffold extends ConsumerStatefulWidget {
  final int initialIndex;

  const AppScaffold({
    super.key,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onDestinationSelected(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingDraftsCount = ref.watch(pendingDraftsCountProvider);
    final isWide = MediaQuery.of(context).size.width >= 600;

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: '流水明细',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: pendingDraftsCount > 0,
          label: Text('$pendingDraftsCount'),
          child: const Icon(Icons.inbox_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pendingDraftsCount > 0,
          label: Text('$pendingDraftsCount'),
          child: const Icon(Icons.inbox),
        ),
        label: '草稿箱',
      ),
      const NavigationDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: '规则账户',
      ),
    ];

    final railDestinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: Text('流水明细'),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: pendingDraftsCount > 0,
          label: Text('$pendingDraftsCount'),
          child: const Icon(Icons.inbox_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pendingDraftsCount > 0,
          label: Text('$pendingDraftsCount'),
          child: const Icon(Icons.inbox),
        ),
        label: const Text('草稿箱'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: Text('规则账户'),
      ),
    ];

    final pages = <Widget>[
      const TransactionsScreen(),
      const DraftsQueueScreen(),
      const RulesAccountsScreen(),
    ];

    const appTitleWidget = Text('SingWallet');

    if (isWide) {
      return Scaffold(
        appBar: AppBar(
          title: appTitleWidget,
          centerTitle: false,
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: railDestinations,
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: pages[_currentIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: appTitleWidget,
        centerTitle: true,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: destinations,
      ),
    );
  }
}
