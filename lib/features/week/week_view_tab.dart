import 'package:flutter/material.dart';

import '../../core/theme/course_colors.dart';
import '../../models/course_cell.dart';
import '../../models/new_course_request.dart';
import '../../models/period_slot.dart';
import '../../models/weekday.dart';
import '../../routing/app_routes.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';

/// 周视图：按「星期 × 节次」渲染某一周的全部格子。
class WeekViewTab extends StatelessWidget {
  const WeekViewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);

    return Column(
      children: <Widget>[
        const _WeekSelector(),
        const Divider(height: 1),
        Expanded(child: _WeekGrid(controller: controller)),
      ],
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector();

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final ThemeData theme = Theme.of(context);
    final int week = controller.currentWeek;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '上一周',
            onPressed: week > 1 ? () => controller.selectWeek(week - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  controller.weekText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${controller.config.name} · 共 ${controller.totalWeeks} 周',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: week < controller.totalWeeks
                ? () => controller.selectWeek(week + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.controller});

  final ScheduleController controller;

  static const double _rowHeight = 64;
  static const double _headerHeight = 44;

  /// 七列在竖屏上尽量铺满一屏，只有极窄屏幕才横向滚动。
  static const double _minDayWidth = 44;

  @override
  Widget build(BuildContext context) {
    final int week = controller.currentWeek;
    final Map<Weekday, Map<int, List<CourseCell>>> grid =
        controller.gridOfWeek(week);
    final List<PeriodSlot> periods = controller.periods;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double timeWidth =
            (constraints.maxWidth * 0.14).clamp(44.0, 66.0);
        final double dayWidth =
            ((constraints.maxWidth - timeWidth) / Weekday.values.length)
                .clamp(_minDayWidth, 220.0);
        final double tableWidth = timeWidth + dayWidth * Weekday.values.length;
        final double tableHeight = _headerHeight + periods.length * _rowHeight;

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: tableHeight,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _GridBackground(
                      timeWidth: timeWidth,
                      dayWidth: dayWidth,
                      periods: periods,
                    ),
                  ),
                  // 空格点击层：点空白格可快速添加该星期、该节次的课程。
                  for (int dayIndex = 0;
                      dayIndex < Weekday.values.length;
                      dayIndex++)
                    for (final PeriodSlot period in periods)
                      Positioned(
                        left: timeWidth + dayIndex * dayWidth,
                        top: _headerHeight + (period.index - 1) * _rowHeight,
                        width: dayWidth,
                        height: _rowHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openAdd(
                            context,
                            Weekday.values[dayIndex],
                            period.index,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                  for (final MapEntry<Weekday, Map<int, List<CourseCell>>> day
                      in grid.entries)
                    for (final MapEntry<int, List<CourseCell>> slot
                        in day.value.entries)
                      Positioned(
                        left: timeWidth +
                            Weekday.values.indexOf(day.key) * dayWidth +
                            2,
                        top: _headerHeight + (slot.key - 1) * _rowHeight + 2,
                        width: dayWidth - 4,
                        height: _cellHeight(slot.value) - 4,
                        child: _CourseCellCard(cells: slot.value),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  double _cellHeight(List<CourseCell> cells) {
    int count = 1;
    for (final CourseCell cell in cells) {
      if (cell.periodCount > count) {
        count = cell.periodCount;
      }
    }
    return count * _rowHeight;
  }

  /// 点击空格：带着星期和节次进入添加页。
  void _openAdd(BuildContext context, Weekday weekday, int period) {
    Navigator.of(context).pushNamed(
      AppRoutes.courseAdd,
      arguments: NewCourseRequest(weekday: weekday, startPeriod: period),
    );
  }
}

class _GridBackground extends StatelessWidget {
  const _GridBackground({
    required this.timeWidth,
    required this.dayWidth,
    required this.periods,
  });

  final double timeWidth;
  final double dayWidth;
  final List<PeriodSlot> periods;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BorderSide border = BorderSide(
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
    );

    return Column(
      children: <Widget>[
        SizedBox(
          height: _WeekGrid._headerHeight,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: timeWidth,
                child: Center(
                  child: Text(
                    '节次',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              for (final Weekday day in Weekday.values)
                Container(
                  width: dayWidth,
                  decoration: BoxDecoration(
                    border: Border(left: border),
                  ),
                  child: Center(
                    child: Text(
                      day.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final PeriodSlot period in periods)
          SizedBox(
            height: _WeekGrid._rowHeight,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: timeWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        '${period.index}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        period.start,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                for (int i = 0; i < Weekday.values.length; i++)
                  Container(
                    width: dayWidth,
                    decoration: BoxDecoration(
                      border: Border(left: border, top: border),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一个格子：可能同时有多门课占用同一节次，只展示第一门并标注数量。
class _CourseCellCard extends StatelessWidget {
  const _CourseCellCard({required this.cells});

  final List<CourseCell> cells;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CourseCell cell = cells.first;
    final Color color = CourseColors.of(cell.course.colorSeed);

    return Material(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        // 调课产生的临时格子没有真实课程记录，只提示来源，不进入编辑。
        onTap: () {
          if (cell.course.id.startsWith('override:')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('这是「日期覆盖」中的调课，请到设置页修改')),
            );
            return;
          }
          Navigator.of(context).pushNamed(
            AppRoutes.courseEdit,
            arguments: cell.course,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      cell.course.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                cell.course.room,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (cells.length > 1)
                Text(
                  '另有 ${cells.length - 1} 门',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
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
