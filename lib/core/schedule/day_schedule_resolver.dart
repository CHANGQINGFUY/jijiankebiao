import '../../models/course.dart';
import '../../models/course_cell.dart';
import '../../models/day_override.dart';
import '../../models/period_slot.dart';
import '../../models/semester_config.dart';
import '../../models/weekday.dart';
import 'course_expander.dart';
import 'week_calculator.dart';

/// 某一天的一节课（常规课程或当天的调课覆盖）。
class DayClass {
  const DayClass({
    required this.date,
    required this.weekday,
    required this.name,
    required this.teacher,
    required this.room,
    required this.startPeriod,
    required this.endPeriod,
    required this.start,
    required this.end,
    this.course,
    this.isOverride = false,
  });

  final DateTime date;
  final Weekday weekday;
  final String name;
  final String teacher;
  final String room;
  final int startPeriod;
  final int endPeriod;
  final DateTime start;
  final DateTime end;

  /// 常规课程；当天的调课覆盖为 null。
  final Course? course;

  /// 是否来自日期覆盖。
  final bool isOverride;

  String get periodLabel => startPeriod == endPeriod
      ? '第 $startPeriod 节'
      : '第 $startPeriod-$endPeriod 节';

  bool isOngoing(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  bool isFinished(DateTime now) => !now.isBefore(end);

  int minutesUntil(DateTime now) =>
      (start.difference(now).inSeconds / 60).ceil();
}

/// 某一天的完整安排与状态。
class DaySchedule {
  const DaySchedule({
    required this.status,
    required this.date,
    required this.weekday,
    required this.classes,
    required this.isHoliday,
    this.override,
    this.ongoing,
    this.next,
  });

  final WeekStatus status;
  final DateTime date;
  final Weekday weekday;
  final List<DayClass> classes;

  /// 当天是否被设为放假。
  final bool isHoliday;

  /// 当天生效的覆盖（放假或调课）。
  final DayOverride? override;

  final DayClass? ongoing;
  final DayClass? next;

  bool get isEmpty => classes.isEmpty;

  bool get isFinished => classes.isNotEmpty && next == null && ongoing == null;
}

/// 计算某一天的课程安排：常规课表 + 按日期的覆盖（覆盖优先）。
class DayScheduleResolver {
  const DayScheduleResolver._();

  static DaySchedule resolve({
    required List<Course> courses,
    required List<DayOverride> overrides,
    required SemesterConfig config,
    required DateTime now,
    int? weekOverride,
  }) {
    final WeekStatus status = config.weekStatus(now);
    final int week = (weekOverride ?? status.week ?? 1).clamp(1, config.totalWeeks);
    final DateTime date = WeekCalculator.dateOf(
      config.firstMonday,
      week,
      now.weekday,
    );
    final Weekday weekday = Weekday.fromIsoIndex(now.weekday);

    final DayOverride? override = _findOverride(overrides, date);

    if (override != null && override.isHoliday) {
      return DaySchedule(
        status: status,
        date: date,
        weekday: weekday,
        classes: const <DayClass>[],
        isHoliday: true,
        override: override,
      );
    }

    final List<DayClass> classes = override != null
        ? _classesFromOverride(override, date, weekday, config)
        : _classesFromCourses(courses, date, weekday, week, config);

    classes.sort((DayClass a, DayClass b) => a.start.compareTo(b.start));

    DayClass? ongoing;
    DayClass? next;
    for (final DayClass item in classes) {
      if (item.isOngoing(now)) {
        ongoing = item;
        break;
      }
      if (now.isBefore(item.start)) {
        next = item;
        break;
      }
    }

    return DaySchedule(
      status: status,
      date: date,
      weekday: weekday,
      classes: classes,
      isHoliday: false,
      override: override,
      ongoing: ongoing,
      next: next,
    );
  }

  static DayOverride? _findOverride(List<DayOverride> overrides, DateTime date) {
    final String key = DayOverride.dateKey(date);
    for (final DayOverride item in overrides) {
      if (item.key == key) {
        return item;
      }
    }
    return null;
  }

  static List<DayClass> _classesFromOverride(
    DayOverride override,
    DateTime date,
    Weekday weekday,
    SemesterConfig config,
  ) {
    final int startPeriod = override.startPeriod ?? 1;
    final int endPeriod = override.endPeriod ?? startPeriod;
    final DateTime? start = config.startTimeOf(date, startPeriod);
    final DateTime? end = config.endTimeOf(date, endPeriod);
    if (start == null || end == null) {
      return const <DayClass>[];
    }
    return <DayClass>[
      DayClass(
        date: date,
        weekday: weekday,
        name: override.courseName ?? '调课',
        teacher: override.teacher ?? '',
        room: override.room ?? '',
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        start: start,
        end: end,
        isOverride: true,
      ),
    ];
  }

  static List<DayClass> _classesFromCourses(
    List<Course> courses,
    DateTime date,
    Weekday weekday,
    int week,
    SemesterConfig config,
  ) {
    final List<DayClass> result = <DayClass>[];
    for (final CourseCell cell
        in CourseExpander.cellsForDay(courses, weekday, week)) {
      final PeriodSlot? first = config.periodOf(cell.startPeriod);
      final PeriodSlot? last = config.periodOf(cell.endPeriod);
      if (first == null || last == null) {
        continue;
      }
      final Course course = cell.course;
      result.add(
        DayClass(
          date: date,
          weekday: weekday,
          name: course.name,
          teacher: course.teacher,
          room: course.room,
          startPeriod: cell.startPeriod,
          endPeriod: cell.endPeriod,
          start: WeekCalculator.dateOnly(date).add(
            _minutesOfDay(first.start),
          ),
          end: WeekCalculator.dateOnly(date).add(
            _minutesOfDay(last.end),
          ),
          course: course,
        ),
      );
    }
    return result;
  }

  static Duration _minutesOfDay(String time) {
    final List<String> parts = time.split(':');
    final int hour = int.tryParse(parts.first.trim()) ?? 0;
    final int minute = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    return Duration(hours: hour, minutes: minute);
  }
}
