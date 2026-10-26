import 'package:flutter/material.dart';

import '../core/theme/course_colors.dart';
import '../models/course_cell.dart';
import '../models/user_role.dart';
import '../routing/app_routes.dart';
import '../state/schedule_controller.dart';
import '../state/schedule_scope.dart';
import 'empty_state.dart';

/// 课程网格：按屏幕宽度自适应列数，展示某一天的排课。
class CourseGrid extends StatelessWidget {
  const CourseGrid({
    super.key,
    required this.cells,
    required this.emptyMessage,
    this.emptyHint,
    this.date,
  });

  final List<CourseCell> cells;

  final String emptyMessage;
  final String? emptyHint;

  /// 这批格子对应的具体日期；用于显示「已结束 / 上课中」状态。
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) {
      return EmptyState(
        icon: Icons.event_available_outlined,
        message: emptyMessage,
        hint: emptyHint,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 首帧或者窗口尺寸为 0 时，网格无法计算列宽，先返回占位避免断言报错。
        if (constraints.maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 140,
          ),
          itemCount: cells.length,
          itemBuilder: (BuildContext context, int index) {
            return CourseGridCard(
              cell: cells[index],
              date: date,
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.courseDetail,
                arguments: cells[index].course,
              ),
            );
          },
        );
      },
    );
  }
}

/// 课程网格卡片：课程名、节次、教室，底色为课程配色。
class CourseGridCard extends StatelessWidget {
  const CourseGridCard({super.key, required this.cell, this.onTap, this.date});

  final CourseCell cell;
  final VoidCallback? onTap;
  final DateTime? date;

  /// 只有「今天」的课程才显示上课状态。
  _ClassState? _stateOf(BuildContext context) {
    final DateTime? day = date;
    if (day == null) {
      return null;
    }
    final DateTime now = DateTime.now();
    final bool isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    if (!isToday) {
      return null;
    }
    final ScheduleController controller = ScheduleScope.of(context);
    final DateTime? start = controller.config.startTimeOf(
      day,
      cell.startPeriod,
    );
    final DateTime? end = controller.config.endTimeOf(day, cell.endPeriod);
    if (start == null || end == null) {
      return null;
    }
    if (!now.isBefore(end)) {
      return _ClassState.finished;
    }
    if (!now.isBefore(start)) {
      return _ClassState.ongoing;
    }
    return _ClassState.upcoming;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = CourseColors.of(cell.course.colorSeed);
    final String subtitle = cell.course.type == UserRole.teacher
        ? (cell.course.className ?? cell.course.teacher)
        : cell.course.teacher;
    final _ClassState? state = _stateOf(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      cell.course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (state != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        state.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: state == _ClassState.ongoing
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _IconLine(icon: Icons.schedule, text: cell.periodLabel),
              const SizedBox(height: 4),
              _IconLine(icon: Icons.place_outlined, text: cell.course.room),
              const Spacer(),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 今天某节课的状态。
enum _ClassState {
  upcoming('未开始'),
  ongoing('上课中'),
  finished('已结束');

  const _ClassState(this.label);

  final String label;
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
