import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local_schedule_repository.dart';
import 'state/schedule_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 读取本地课表数据（全部来自本地存储，不使用内置示例数据）。
  final LocalScheduleRepository repository = LocalScheduleRepository();
  await repository.load();

  runApp(ScheduleApp(controller: ScheduleController(repository)));
}
