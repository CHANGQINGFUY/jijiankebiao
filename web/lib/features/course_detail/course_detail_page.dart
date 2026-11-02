import 'package:flutter/material.dart';

import '../../core/theme/course_colors.dart';
import '../../models/course.dart';
import '../../models/user_role.dart';
import '../../routing/app_routes.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';
import '../../widgets/section_title.dart';

/// 课程详情页：展示课程信息，并提供编辑 / 删除入口。
class CourseDetailPage extends StatelessWidget {
  const CourseDetailPage({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    // 课程可能刚被编辑过，优先取仓储里的最新版本。
    final Course current = controller.courseById(course.id) ?? course;
    final ThemeData theme = Theme.of(context);
    final Color color = CourseColors.of(current.colorSeed);
    final List<Course> group = controller.groupMembers(current.group);

    return Scaffold(
      appBar: AppBar(
        title: Text(current.name),
        actions: <Widget>[
          IconButton(
            tooltip: '编辑课程',
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoutes.courseEdit,
              arguments: current,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除课程',
            onPressed: () => _confirmDelete(context, controller, current),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            Card(
              margin: EdgeInsets.zero,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(width: 6, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    current.name,
                                    style: theme.textTheme.headlineSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                Chip(label: Text(current.weekdayLabel)),
                                Chip(label: Text(current.periodLabel)),
                                Chip(label: Text(current.weeks.label)),
                                Chip(
                                  label: Text(
                                    current.type == UserRole.teacher
                                        ? '教师视角'
                                        : '学生视角',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SectionTitle('课程信息'),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: <Widget>[
                    _InfoRow(
                      icon: Icons.person_outline,
                      label: '授课教师',
                      value: current.teacher,
                    ),
                    _InfoRow(
                      icon: Icons.groups_outlined,
                      label: '班级',
                      value: current.className ?? '未指定',
                    ),
                    _InfoRow(
                      icon: Icons.school_outlined,
                      label: '学年学期',
                      value: current.academicTerm.isEmpty
                          ? '未指定'
                          : current.academicTerm,
                    ),
                    _InfoRow(
                      icon: Icons.place_outlined,
                      label: '上课教室',
                      value: current.room,
                    ),
                    _InfoRow(
                      icon: Icons.sticky_note_2_outlined,
                      label: '备注',
                      value: (current.remark?.isNotEmpty ?? false)
                          ? current.remark!
                          : '暂无备注',
                    ),
                  ],
                ),
              ),
            ),
            if (group.length > 1) ...<Widget>[
              const SectionTitle('同组课程'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '这门课还有 ${group.length - 1} 个时段（'
                    '${group.where((Course item) => item.id != current.id).map((Course item) => '${item.weekdayLabel} ${item.periodLabel}').join('、')}）。'
                    '编辑或删除时可以选择只处理本条，或整组一起处理。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '课表数据保存在本地，修改会立即写入本机存储。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ScheduleController controller,
    Course course,
  ) async {
    final List<Course> group = controller.groupMembers(course.group);
    final bool hasGroup = group.length > 1;

    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除课程'),
        content: Text(
          hasGroup
              ? '确定删除「${course.name}」吗？这门课共有 ${group.length} 个时段。'
              : '确定删除「${course.name}」吗？此操作不可恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          if (hasGroup)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('group'),
              child: Text('删除整组（${group.length} 条）'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('one'),
            child: const Text('仅删除本条'),
          ),
        ],
      ),
    );
    if (choice == null) {
      return;
    }

    await controller.deleteCourse(course, wholeGroup: choice == 'group');
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice == 'group'
              ? '已删除「${course.name}」的全部 ${group.length} 个时段'
              : '已删除「${course.name}」',
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
