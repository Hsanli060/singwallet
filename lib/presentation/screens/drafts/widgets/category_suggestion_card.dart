// lib/presentation/screens/drafts/widgets/category_suggestion_card.dart
import 'package:flutter/material.dart';
import '../../../../data/models/models.dart';

/// Helper to resolve category icons from iconKey or category name.
IconData resolveCategoryIcon(String? iconKey, String categoryName) {
  final key = (iconKey ?? '').toLowerCase();
  final name = categoryName.toLowerCase();

  if (key.contains('food') || name.contains('餐饮') || name.contains('吃') || name.contains('美食')) {
    return Icons.restaurant;
  }
  if (key.contains('transport') || name.contains('交通') || name.contains('出行') || name.contains('车')) {
    return Icons.directions_subway;
  }
  if (key.contains('shop') || name.contains('购物') || name.contains('超市') || name.contains('日用')) {
    return Icons.shopping_bag_outlined;
  }
  if (key.contains('entertainment') || name.contains('娱乐') || name.contains('玩') || name.contains('影')) {
    return Icons.sports_esports_outlined;
  }
  if (key.contains('bill') || name.contains('生活缴费') || name.contains('账单') || name.contains('水电') || name.contains('费')) {
    return Icons.receipt_long_outlined;
  }
  if (key.contains('medical') || name.contains('医疗') || name.contains('药') || name.contains('健康')) {
    return Icons.medical_services_outlined;
  }
  if (key.contains('income') || name.contains('收入') || name.contains('工资') || name.contains('红包')) {
    return Icons.savings_outlined;
  }
  if (key.contains('other') || name.contains('其他')) {
    return Icons.more_horiz;
  }
  return Icons.category_outlined;
}

/// Category Suggestion Card displaying AI/rule classification with confidence %
/// and quick one-tap accept or category picker modal.
class CategorySuggestionCard extends StatelessWidget {
  final String? suggestedCategoryId;
  final double? confidenceScore;
  final String? selectedCategoryId;
  final List<Category> categories;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback? onAcceptSuggestion;

  const CategorySuggestionCard({
    super.key,
    this.suggestedCategoryId,
    this.confidenceScore,
    this.selectedCategoryId,
    required this.categories,
    required this.onCategorySelected,
    this.onAcceptSuggestion,
  });

  void _openCategoryPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '选择交易分类',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final isSelected = cat.id == selectedCategoryId;
                        final isSuggested = cat.id == suggestedCategoryId;
                        final icon = resolveCategoryIcon(cat.iconKey, cat.name);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: Icon(
                              icon,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            cat.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSuggested)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'AI推荐',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onCategorySelected(cat.id);
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Resolve suggested category object
    Category? suggestedCat;
    if (suggestedCategoryId != null) {
      for (final cat in categories) {
        if (cat.id == suggestedCategoryId) {
          suggestedCat = cat;
          break;
        }
      }
    }

    // Resolve currently selected category object
    Category? selectedCat;
    if (selectedCategoryId != null) {
      for (final cat in categories) {
        if (cat.id == selectedCategoryId) {
          selectedCat = cat;
          break;
        }
      }
    }

    final bool isAccepted = suggestedCategoryId != null &&
        selectedCategoryId != null &&
        suggestedCategoryId == selectedCategoryId;

    final confidencePercent = ((confidenceScore ?? 0.95) * 100).toInt();
    final suggestedName = suggestedCat?.name ?? '餐饮美食';
    final suggestedIcon = resolveCategoryIcon(suggestedCat?.iconKey, suggestedName);

    return Card(
      key: const ValueKey('category_suggestion_card'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isAccepted
              ? theme.colorScheme.primary.withAlpha(120)
              : theme.colorScheme.outlineVariant.withAlpha(100),
          width: isAccepted ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '智能推荐分类',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(150),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$confidencePercent% 置信度',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  radius: 22,
                  child: Icon(
                    suggestedIcon,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestedName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAccepted
                            ? '已采纳此推荐分类'
                            : (selectedCat != null ? '当前选中: ${selectedCat.name}' : '点击右侧快速采纳'),
                        style: TextStyle(
                          fontSize: 12,
                          color: isAccepted
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isAccepted && suggestedCat != null)
                  FilledButton.tonal(
                    key: const ValueKey('accept_category_button'),
                    onPressed: () {
                      onCategorySelected(suggestedCat!.id);
                      onAcceptSuggestion?.call();
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('一键采纳'),
                  )
                else if (isAccepted)
                  Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('change_category_button'),
                onPressed: () => _openCategoryPicker(context),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text(
                  '选择其他分类',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
