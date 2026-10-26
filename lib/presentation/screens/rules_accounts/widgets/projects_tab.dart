// lib/presentation/screens/rules_accounts/widgets/projects_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:singwallet/data/models/models.dart';
import 'package:singwallet/presentation/providers/core_providers.dart';
import 'package:singwallet/presentation/providers/rule_account_providers.dart';

/// Tab displaying lifecycle projects (e.g. Travel, Renovation)
/// and supporting creation of new project labels/codes.
class ProjectsTab extends ConsumerStatefulWidget {
  const ProjectsTab({super.key});

  @override
  ConsumerState<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<ProjectsTab> {
  void _showAddProjectDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.folder_special_outlined),
              SizedBox(width: 8),
              Text('添加项目'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '项目用于跨分类追踪特定生活阶段或事件的支出（如差旅、装修、婚礼等）。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '项目名称 *',
                      hintText: '如：日本关西旅行、新家硬装',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '请输入项目名称';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: '项目编码 (选填)',
                      hintText: '如：proj_japan_trip（留空自动生成）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final navigator = Navigator.of(dialogCtx);
                  final messenger = ScaffoldMessenger.of(context);
                  final db = ref.read(databaseProvider);
                  final nowIso = DateTime.now().toUtc().toIso8601String();
                  final code = codeController.text.trim();
                  final projectId = code.isNotEmpty
                      ? code
                      : 'proj_${DateTime.now().millisecondsSinceEpoch}';

                  await db.insert('projects', {
                    'id': projectId,
                    'name': nameController.text.trim(),
                    'created_at': nowIso,
                    'updated_at': nowIso,
                  });

                  await ref.read(projectsListProvider.notifier).refresh();

                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('项目 "${nameController.text.trim()}" 创建成功')),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectsAsync = ref.watch(projectsListProvider);

    return Scaffold(
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('加载项目列表失败: $err'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.read(projectsListProvider.notifier).refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (List<Project> projects) {
          return CustomScrollView(
            slivers: [
              // Header Summary Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.view_timeline_outlined,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '生命周期项目管理 (${projects.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '项目标签用于支持跨分类的正交生活事件汇总（如差旅出差、房屋装修、婚礼等）。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加项目'),
                            onPressed: _showAddProjectDialog,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Project List or Empty View
              if (projects.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_off_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无项目配置',
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add),
                          label: const Text('立即添加新项目'),
                          onPressed: _showAddProjectDialog,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final project = projects[index];
                        final dateStr = project.createdAt.contains('T')
                            ? project.createdAt.split('T').first
                            : project.createdAt;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant.withAlpha(128),
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              foregroundColor: theme.colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.folder_special, size: 20),
                            ),
                            title: Text(
                              project.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '代码: ${project.id} • 创建于: $dateStr',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer.withAlpha(128),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '活动中',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: projects.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
