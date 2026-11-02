import '../../core/constants/schedule_constants.dart';
import '../../core/schedule/week_calculator.dart';
import 'period_slot.dart';
import 'weekday.dart';

/// 学期配置：名称、开学第一天、节次作息、总周数，以及手动周次设置。
///
/// 每个学期拥有独立的 id、开学日期、节次表与手动周次，互不影响。
class SemesterConfig {
  SemesterConfig({
    String? id,
    String? name,
    required DateTime startDate,
    required this.periods,
    this.totalWeeks = ScheduleConstants.totalWeeks,
    this.manualWeekEnabled = false,
    this.manualWeek = 1,
  })  : id = id ?? 'sem-default',
        name = name ?? '默认学期',
        startDate = WeekCalculator.dateOnly(startDate);

  /// 学期唯一标识。
  final String id;

  /// 学期名称，如「2026-2027 第一学期」。
  final String name;

  /// 开学第一天，可以是任意星期（例如周三）。
  final DateTime startDate;

  /// 每天每节课的起止时间。
  final List<PeriodSlot> periods;

  /// 学期总周数。
  final int totalWeeks;

  /// 是否使用手动周次。
  final bool manualWeekEnabled;

  /// 手动指定的周次（1..totalWeeks）。
  final int manualWeek;

  /// 默认配置：本周一开学，使用内置作息表。
  factory SemesterConfig.initial(DateTime now) => SemesterConfig(
        id: 'sem-default',
        name: '默认学期',
        startDate: WeekCalculator.mondayOf(now),
        periods: ScheduleConstants.defaultPeriods,
        totalWeeks: ScheduleConstants.totalWeeks,
      );

  /// 新建一个学期（使用当前学期相同的默认作息表）。
  factory SemesterConfig.create({
    required String name,
    required DateTime startDate,
    required List<PeriodSlot> periods,
    int totalWeeks = ScheduleConstants.totalWeeks,
  }) =>
      SemesterConfig(
        id: 'sem-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        startDate: startDate,
        periods: periods,
        totalWeeks: totalWeeks,
      );

  /// 第一周的周一。
  DateTime get firstMonday => WeekCalculator.mondayOf(startDate);

  /// 学期最后一天。
  DateTime get lastDate =>
      firstMonday.add(Duration(days: totalWeeks * 7 - 1));

  /// 兼容旧调用：学期前或结束后返回 null。
  int? currentWeek(DateTime now) => WeekCalculator.resolve(
        now: now,
        startDate: startDate,
        totalWeeks: totalWeeks,
      ).week;

  /// 完整的阶段与周次信息。
  WeekStatus weekStatus(DateTime now) => WeekCalculator.resolve(
        now: now,
        startDate: startDate,
        totalWeeks: totalWeeks,
      );

  /// 第 [week] 周的周一。
  DateTime startOfWeek(int week) => WeekCalculator.startOfWeek(firstMonday, week);

  /// 第 [week] 周某个星期对应的日期。
  DateTime dateOf(int week, Weekday weekday) =>
      WeekCalculator.dateOf(firstMonday, week, weekday.isoIndex);

  /// 按节次序号查找作息。
  PeriodSlot? periodOf(int index) {
    for (final PeriodSlot slot in periods) {
      if (slot.index == index) {
        return slot;
      }
    }
    return null;
  }

  /// 某个日期第 [index] 节课的开始时间。
  DateTime? startTimeOf(DateTime date, int index) {
    final PeriodSlot? slot = periodOf(index);
    if (slot == null) {
      return null;
    }
    return WeekCalculator.dateOnly(date).add(_minutesOfDay(slot.start));
  }

  /// 某个日期第 [index] 节课的结束时间。
  DateTime? endTimeOf(DateTime date, int index) {
    final PeriodSlot? slot = periodOf(index);
    if (slot == null) {
      return null;
    }
    return WeekCalculator.dateOnly(date).add(_minutesOfDay(slot.end));
  }

  SemesterConfig copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    List<PeriodSlot>? periods,
    int? totalWeeks,
    bool? manualWeekEnabled,
    int? manualWeek,
  }) {
    return SemesterConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      periods: periods ?? this.periods,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      manualWeekEnabled: manualWeekEnabled ?? this.manualWeekEnabled,
      manualWeek: manualWeek ?? this.manualWeek,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'startDate': WeekCalculator.dateOnly(startDate).toIso8601String(),
        'periods': <Object?>[for (final PeriodSlot slot in periods) slot.toJson()],
        'totalWeeks': totalWeeks,
        'manualWeekEnabled': manualWeekEnabled,
        'manualWeek': manualWeek,
      };

  factory SemesterConfig.fromJson(Map<String, Object?> json) {
    final List<Object?>? rawPeriods = json['periods'] as List<Object?>?;
    final List<PeriodSlot> periods = rawPeriods == null || rawPeriods.isEmpty
        ? ScheduleConstants.defaultPeriods
        : <PeriodSlot>[
            for (final Object? item in rawPeriods)
              if (item is Map) PeriodSlot.fromJson(item.cast<String, Object?>()),
          ];
    final DateTime startDate =
        DateTime.tryParse((json['startDate'] as String?) ?? '') ??
            WeekCalculator.mondayOf(DateTime.now());
    final String id = (json['id'] as String?)?.trim() ?? '';
    final String name = (json['name'] as String?)?.trim() ?? '';
    return SemesterConfig(
      id: id.isEmpty ? 'sem-${startDate.millisecondsSinceEpoch}' : id,
      name: name.isEmpty ? '默认学期' : name,
      startDate: startDate,
      periods: periods,
      totalWeeks: (json['totalWeeks'] as int?) ?? ScheduleConstants.totalWeeks,
      manualWeekEnabled: (json['manualWeekEnabled'] as bool?) ?? false,
      manualWeek: (json['manualWeek'] as int?) ?? 1,
    );
  }

  static Duration _minutesOfDay(String time) {
    final List<String> parts = time.split(':');
    final int hour = int.tryParse(parts.first.trim()) ?? 0;
    final int minute = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    return Duration(hours: hour, minutes: minute);
  }
}
