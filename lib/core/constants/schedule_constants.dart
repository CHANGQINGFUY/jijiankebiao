import '../../models/period_slot.dart';

/// 课表相关的静态配置。后续可由设置页覆盖，再落盘到本地。
class ScheduleConstants {
  const ScheduleConstants._();

  /// 一学期默认周数。
  static const int totalWeeks = 20;

  /// 每天默认 8 节课的作息时间。
  static const List<PeriodSlot> defaultPeriods = <PeriodSlot>[
    PeriodSlot(index: 1, start: '08:00', end: '08:45'),
    PeriodSlot(index: 2, start: '08:55', end: '09:40'),
    PeriodSlot(index: 3, start: '10:00', end: '10:45'),
    PeriodSlot(index: 4, start: '10:55', end: '11:40'),
    PeriodSlot(index: 5, start: '13:30', end: '14:15'),
    PeriodSlot(index: 6, start: '14:25', end: '15:10'),
    PeriodSlot(index: 7, start: '15:30', end: '16:15'),
    PeriodSlot(index: 8, start: '16:25', end: '17:10'),
  ];
}
