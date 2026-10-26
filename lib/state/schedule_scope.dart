import 'package:flutter/material.dart';

import 'schedule_controller.dart';

/// 把 [ScheduleController] 注入到 Widget 树。
///
/// 页面里用 `ScheduleScope.of(context)` 取用，controller 通知更新时依赖方会自动重建。
class ScheduleScope extends InheritedNotifier<ScheduleController> {
  const ScheduleScope({
    super.key,
    required ScheduleController controller,
    required super.child,
  }) : super(notifier: controller);

  static ScheduleController of(BuildContext context) {
    final ScheduleScope? scope =
        context.dependOnInheritedWidgetOfExactType<ScheduleScope>();
    assert(scope != null, '未找到 ScheduleScope，请确认已在根部包裹。');
    return scope!.notifier!;
  }
}
