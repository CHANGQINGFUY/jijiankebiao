import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'routing/app_routes.dart';
import 'state/schedule_controller.dart';
import 'state/schedule_scope.dart';

/// App 根组件：注入全局课表状态，并监听状态变化刷新主题。
class ScheduleApp extends StatelessWidget {
  const ScheduleApp({super.key, required this.controller});

  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    return ScheduleScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            title: '极简课表',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: controller.themeMode,
            initialRoute: AppRoutes.home,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          );
        },
      ),
    );
  }
}
