import 'package:flutter/material.dart';

import '../features/add_course/add_course_tab.dart';
import '../features/course_detail/course_detail_page.dart';
import '../features/shell/home_shell.dart';
import '../features/week/week_view_tab.dart';
import '../models/course.dart';
import '../models/new_course_request.dart';

/// 全局路由表。
class AppRoutes {
  const AppRoutes._();

  /// 主容器（课表 / 添加 / 设置）。
  static const String home = '/';

  /// 周视图页。
  static const String weekView = '/week-view';

  /// 课程详情页，需要传 [Course] 作为 arguments。
  static const String courseDetail = '/course-detail';

  /// 编辑课程页，需要传 [Course] 作为 arguments。
  static const String courseEdit = '/course-edit';

  /// 新增课程页，可传 [NewCourseRequest] 预填星期与节次。
  static const String courseAdd = '/course-add';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const HomeShell(),
          settings: settings,
        );
      case weekView:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => Scaffold(
            appBar: AppBar(title: const Text('周视图')),
            body: const SafeArea(child: WeekViewTab()),
          ),
          settings: settings,
        );
      case courseDetail:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              CourseDetailPage(course: settings.arguments! as Course),
          settings: settings,
        );
      case courseEdit:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => Scaffold(
            appBar: AppBar(title: const Text('编辑课程')),
            body: SafeArea(
              child: AddCourseTab(
                editing: settings.arguments! as Course,
                onSaved: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          settings: settings,
        );
      case courseAdd: {
        final Object? rawArgs = settings.arguments;
        final NewCourseRequest? request =
            rawArgs is NewCourseRequest ? rawArgs : null;
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => Scaffold(
            appBar: AppBar(title: const Text('添加课程')),
            body: SafeArea(
              child: AddCourseTab(
                initialWeekday: request?.weekday,
                initialStartPeriod: request?.startPeriod,
                onSaved: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          settings: settings,
        );
      }
      default:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => Scaffold(
            body: Center(child: Text('未找到路由：${settings.name}')),
          ),
          settings: settings,
        );
    }
  }
}
