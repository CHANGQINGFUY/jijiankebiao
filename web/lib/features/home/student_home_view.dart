import 'package:flutter/material.dart';

import '../../core/schedule/week_calculator.dart';
import '../../models/course_cell.dart';
import '../../models/day_override.dart';
import '../../models/weekday.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';
import '../../widgets/course_grid.dart';

/// 学生端视图：查看所选星期「我的课程」。
class StudentHomeView extends StatelessWidget {
  const StudentHomeView({super.key, required this.weekday});

  final Weekday weekday;

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final WeekStatus status = controller.weekStatus;
    if (!status.isInTerm && controller.weekSource == WeekSource.automatic) {
      return CourseGrid(
        cells: const <CourseCell>[],
        emptyMessage: status.label,
        emptyHint: '可在「设置」页调整开学日期或总周数，也可开启手动周次。',
        date: null,
      );
    }

    final List<CourseCell> cells = controller.cellsOf(weekday);
    final DateTime date =
        controller.config.dateOf(controller.currentWeek, weekday);
    final DateTime now = DateTime.now();
    final bool isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final DayOverride? override = controller.overrideFor(date);
    final bool isHoliday = override?.isHoliday ?? false;

    String message;
    String? hint;
    if (isHoliday) {
      message = isToday ? '今天放假' : '${weekday.label}放假';
      hint = '删除日期覆盖即可恢复常规课表。';
    } else if (isToday) {
      message = '今天没有课';
      hint = '去「添加」页新增课程，或切换其它日期看看。';
    } else {
      message = '${weekday.label}没有课';
      hint = '点上方日期栏切换其它日期，或到「添加」页新增课程。';
    }

    return CourseGrid(
      cells: cells,
      emptyMessage: message,
      emptyHint: hint,
      date: date,
    );
  }
}
