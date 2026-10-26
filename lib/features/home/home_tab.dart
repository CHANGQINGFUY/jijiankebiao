import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../../models/weekday.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';
import '../../widgets/role_banner.dart';
import '../../widgets/today_overview_card.dart';
import 'student_home_view.dart';
import 'teacher_home_view.dart';
import 'week_date_bar.dart';

/// 课表首页：顶部角色切换 + 本周日期栏 + 所选星期的课程网格。
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Weekday _selected = Weekday.fromIsoIndex(DateTime.now().weekday);

  /// 当前查看周次的 7 天日期（从周一开始），随手动/自动周次变化。
  static List<DateTime> _weekDates(ScheduleController controller) {
    return List<DateTime>.generate(
      7,
      (int index) => controller.config.dateOf(
        controller.currentWeek,
        Weekday.fromIsoIndex(index + 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final bool isStudent = controller.role == UserRole.student;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: RoleBanner(
            title: isStudent ? '你好，同学' : '你好，老师',
            subtitle: '${controller.weekSummary} · '
                '共 ${controller.courses.length} 门课',
            role: controller.role,
            onSwitchRole: () => controller.switchRole(
              isStudent ? UserRole.teacher : UserRole.student,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TodayOverviewCard(),
        ),
        WeekDateBar(
          dates: _weekDates(controller),
          selected: _selected,
          today: DateTime.now(),
          onSelect: (Weekday day) {
            if (day != _selected) {
              setState(() => _selected = day);
            }
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: isStudent
              ? StudentHomeView(weekday: _selected)
              : TeacherHomeView(weekday: _selected),
        ),
      ],
    );
  }
}
