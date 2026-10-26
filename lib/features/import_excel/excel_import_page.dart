import 'package:flutter/material.dart';

import '../../core/schedule/course_conflict.dart';
import '../../core/theme/course_colors.dart';
import '../../models/course.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';
import 'excel_import_models.dart';

/// 导入预览页：Excel 与教务系统解析出的课程都走这一页。
///
/// 支持勾选/取消、批量删除、冲突标红并选择保留哪一条，
/// 确认导入时询问「覆盖当前学期」还是「追加」。
class CourseImportPreviewPage extends StatefulWidget {
  const CourseImportPreviewPage({
    super.key,
    required this.drafts,
    this.warnings = const <String>[],
    this.errors = const <ExcelRowError>[],
    this.sourceLabel = 'Excel',
  });

  /// 解析出的课程草稿（已带当前学期与身份）。
  final List<Course> drafts;

  /// 需要用户确认的提示（单双周、周次不连续等）。
  final List<String> warnings;

  /// 解析失败的行（仅用于提示数量）。
  final List<ExcelRowError> errors;

  /// 来源说明，例如 Excel 文件名。
  final String sourceLabel;

  @override
  State<CourseImportPreviewPage> createState() =>
      _CourseImportPreviewPageState();
}

class _CourseImportPreviewPageState extends State<CourseImportPreviewPage> {
  late List<Course> _items;
  late Set<String> _selected;

  /// 追加模式下，用户选择「保留现有课程」的草稿 id。
  final Set<String> _keepExisting = <String>{};

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = List<Course>.of(widget.drafts);
    _selected = <String>{for (final Course course in _items) course.id};
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final List<Course> existing = controller.courses;

    final Map<String, List<Course>> existingConflicts =
        <String, List<Course>>{};
    final Set<String> conflictingIds = <String>{};
    for (final Course draft in _items) {
      final List<Course> hits = existing
          .where((Course other) => CourseConflict.overlaps(draft, other))
          .toList();
      if (hits.isNotEmpty) {
        existingConflicts[draft.id] = hits;
        conflictingIds.add(draft.id);
      }
    }
    // 待导入课程之间的互相冲突。
    for (int i = 0; i < _items.length; i++) {
      for (int j = 0; j < _items.length; j++) {
        if (i == j) {
          continue;
        }
        if (CourseConflict.overlaps(_items[i], _items[j])) {
          conflictingIds.add(_items[i].id);
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入预览'),
        actions: <Widget>[
          IconButton(
            tooltip: '全选',
            onPressed: _items.isEmpty
                ? null
                : () => setState(() {
                      _selected = <String>{
                        for (final Course course in _items) course.id,
                      };
                    }),
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: '批量删除',
            onPressed: _selected.isEmpty ? null : _deleteSelected,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _SummaryCard(
              sourceLabel: widget.sourceLabel,
              total: _items.length,
              selected: _selected.length,
              conflictCount: conflictingIds.length,
              warningCount: widget.warnings.length,
              errorCount: widget.errors.length,
            ),
            if (widget.warnings.isNotEmpty)
              _WarningCard(messages: widget.warnings),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('待导入列表已清空'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: _items.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final Course course = _items[index];
                        final bool hasConflict =
                            conflictingIds.contains(course.id);
                        final List<Course>? hits = existingConflicts[course.id];
                        return _DraftTile(
                          course: course,
                          selected: _selected.contains(course.id),
                          hasConflict: hasConflict,
                          conflictNames: <String>[
                            for (final Course other in hits ?? <Course>[])
                              other.name,
                          ],
                          keepExisting: _keepExisting.contains(course.id),
                          onToggle: () {
                            setState(() {
                              if (_selected.contains(course.id)) {
                                _selected.remove(course.id);
                              } else {
                                _selected.add(course.id);
                              }
                            });
                          },
                          onKeepExisting: (bool keep) {
                            setState(() {
                              if (keep) {
                                _keepExisting.add(course.id);
                              } else {
                                _keepExisting.remove(course.id);
                              }
                            });
                          },
                          onDelete: () {
                            setState(() {
                              _items.removeAt(index);
                              _selected.remove(course.id);
                              _keepExisting.remove(course.id);
                            });
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed:
                          _selected.isEmpty || _busy ? null : _startImport,
                      icon: const Icon(Icons.download_done),
                      label: Text(
                        _busy ? '正在导入…' : '导入选中 ${_selected.length} 条',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定从待导入列表移除选中的 ${_selected.length} 条课程吗？'
            '（不会影响已保存的课表）'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _items = <Course>[
        for (final Course course in _items)
          if (!_selected.contains(course.id)) course,
      ];
      _selected = <String>{};
      _keepExisting.clear();
    });
  }

  Future<void> _startImport() async {
    final ScheduleController controller = ScheduleScope.of(context);
    final List<Course> selected = <Course>[
      for (final Course course in _items)
        if (_selected.contains(course.id)) course,
    ];
    if (selected.isEmpty) {
      return;
    }

    final String? mode = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('导入方式'),
        content: Text(
          '将导入 ${selected.length} 条课程到「${controller.config.name}」\n\n'
          '覆盖：先清空当前学期、当前身份的课程，再写入本次导入的内容。\n'
          '追加：保留已有课程，冲突的课程由你选择保留哪一条。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('append'),
            child: const Text('追加'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('overwrite'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) {
      return;
    }
    final bool overwrite = mode == 'overwrite';

    if (overwrite) {
      final int existingCount = controller.courses.length;
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('确认覆盖'),
          content: Text(
            existingCount == 0
                ? '当前学期还没有课程，将直接写入 ${selected.length} 条课程。'
                : '当前学期已有 $existingCount 条课程，覆盖后会全部删除并写入本次导入的 '
                    '${selected.length} 条课程，且无法撤销。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认覆盖'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    final List<Course> effective = <Course>[
      for (final Course course in selected)
        if (overwrite || !_keepExisting.contains(course.id)) course,
    ];
    final Set<String> replaceIds = <String>{};
    if (!overwrite) {
      for (final Course course in effective) {
        for (final Course other in controller.courses) {
          if (CourseConflict.overlaps(course, other)) {
            replaceIds.add(other.id);
          }
        }
      }
    }
    if (effective.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有需要写入的课程（全部选择了保留现有）')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await controller.importCourses(
        courses: effective,
        overwrite: overwrite,
        replaceIds: replaceIds,
      );
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      final String tail = widget.sourceLabel.startsWith('教务')
          ? '请核对周次与节次时间是否与教务系统一致；'
              '如开学日期或节次时间不同，请到「设置 → 当前学期设置」调整。'
          : 'Excel 通常不含开学日期与节次时间，请到「设置 → 当前学期设置」'
              '补全开学第一天、总周数与每天节次时间，否则今日页与周课表可能显示不完整。';
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '已导入 ${effective.length} 条课程到「${controller.config.name}」。\n\n$tail',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('导入失败'),
          content: Text('$error'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.sourceLabel,
    required this.total,
    required this.selected,
    required this.conflictCount,
    required this.warningCount,
    required this.errorCount,
  });

  final String sourceLabel;
  final int total;
  final int selected;
  final int conflictCount;
  final int warningCount;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '来源：$sourceLabel',
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            '待导入 $total 条 · 已选 $selected 条'
            '${conflictCount > 0 ? ' · 冲突 $conflictCount 条' : ''}'
            '${warningCount > 0 ? ' · 待确认 $warningCount 项' : ''}'
            '${errorCount > 0 ? ' · 跳过 $errorCount 行' : ''}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int shown = messages.length > 6 ? 6 : messages.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '需要手动确认（${messages.length}）',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (int index = 0; index < shown; index++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('· ${messages[index]}', style: theme.textTheme.bodySmall),
            ),
          if (messages.length > shown)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '…还有 ${messages.length - shown} 条',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.course,
    required this.selected,
    required this.hasConflict,
    required this.conflictNames,
    required this.keepExisting,
    required this.onToggle,
    required this.onKeepExisting,
    required this.onDelete,
  });

  final Course course;
  final bool selected;
  final bool hasConflict;
  final List<String> conflictNames;
  final bool keepExisting;
  final VoidCallback onToggle;
  final ValueChanged<bool> onKeepExisting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = CourseColors.of(course.colorSeed);
    return Container(
      decoration: BoxDecoration(
        color: hasConflict
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasConflict
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              Container(
                width: 8,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      course.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${course.weekdayLabel} · ${course.periodLabel} · '
                      '${course.weeks.label}'
                      '${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}'
                      '${course.room.isEmpty ? '' : ' · ${course.room}'}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '从列表移除',
                onPressed: onDelete,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (hasConflict) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 4, 12, 0),
              child: Text(
                conflictNames.isEmpty
                    ? '与本次导入中的其它课程冲突，请取消勾选或删除其中一条。'
                    : '与现有课程冲突：${conflictNames.join('、')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            if (conflictNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 4, 12, 0),
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('保留现有'),
                      selected: keepExisting,
                      onSelected: selected ? (_) => onKeepExisting(true) : null,
                    ),
                    ChoiceChip(
                      label: const Text('用导入课程替换'),
                      selected: !keepExisting,
                      onSelected:
                          selected ? (_) => onKeepExisting(false) : null,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
