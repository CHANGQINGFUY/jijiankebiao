/// 学期所处的阶段。
enum TermState {
  /// 当前日期早于开学第一天。
  beforeStart,

  /// 处于学期内。
  inTerm,

  /// 晚于学期最后一天。
  afterEnd,
}

/// 周次计算结果：不会返回 0 或负数，也不会抛异常。
class WeekStatus {
  const WeekStatus({
    required this.state,
    required this.firstMonday,
    required this.lastDate,
    this.week,
    this.daysUntilStart,
    this.daysAfterEnd,
  });

  final TermState state;

  /// 第一周的周一（开学日所在周的周一）。
  final DateTime firstMonday;

  /// 学期最后一天。
  final DateTime lastDate;

  /// 学期内的周次（1..totalWeeks）；非学期内为 null。
  final int? week;

  /// 开学前距离开学还有多少天。
  final int? daysUntilStart;

  /// 学期结束后已经过了多少天。
  final int? daysAfterEnd;

  bool get isInTerm => state == TermState.inTerm;

  bool get isBeforeStart => state == TermState.beforeStart;

  bool get isAfterEnd => state == TermState.afterEnd;

  /// 显示用文案，如「还没开学」「第 3 周」「本学期已结束」。
  String get label {
    switch (state) {
      case TermState.beforeStart:
        return '还没开学';
      case TermState.afterEnd:
        return '本学期已结束';
      case TermState.inTerm:
        return '第 $week 周';
    }
  }
}

/// 周次计算工具：以「开学日所在周的周一」为第一周周一，按自然周切分。
///
/// 全部使用本地时区，且只比较年月日，不受时分秒影响。
class WeekCalculator {
  const WeekCalculator._();

  /// 只保留年月日。
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 取 [value] 所在自然周的周一。
  static DateTime mondayOf(DateTime value) {
    final DateTime day = dateOnly(value);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// 第 [week] 周的周一。
  static DateTime startOfWeek(DateTime firstMonday, int week) =>
      firstMonday.add(Duration(days: (week - 1) * 7));

  /// 第 [week] 周里某个星期的日期。
  static DateTime dateOf(DateTime firstMonday, int week, int weekdayIso) =>
      startOfWeek(firstMonday, week).add(Duration(days: weekdayIso - 1));

  /// 计算 [now] 所处的学期阶段与周次。
  static WeekStatus resolve({
    required DateTime now,
    required DateTime startDate,
    required int totalWeeks,
  }) {
    final DateTime today = dateOnly(now);
    final DateTime start = dateOnly(startDate);
    final DateTime firstMonday = mondayOf(start);
    final DateTime lastDate =
        firstMonday.add(Duration(days: totalWeeks * 7 - 1));

    if (today.isBefore(start)) {
      return WeekStatus(
        state: TermState.beforeStart,
        firstMonday: firstMonday,
        lastDate: lastDate,
        daysUntilStart: _daysBetween(today, start),
      );
    }
    if (today.isAfter(lastDate)) {
      return WeekStatus(
        state: TermState.afterEnd,
        firstMonday: firstMonday,
        lastDate: lastDate,
        daysAfterEnd: _daysBetween(lastDate, today),
      );
    }

    final int week = _daysBetween(firstMonday, today) ~/ 7 + 1;
    return WeekStatus(
      state: TermState.inTerm,
      firstMonday: firstMonday,
      lastDate: lastDate,
      week: week.clamp(1, totalWeeks),
    );
  }

  /// 两个日期之间相差的天数，四舍五入规避夏令时造成的 23/25 小时。
  static int _daysBetween(DateTime from, DateTime to) =>
      (dateOnly(to).difference(dateOnly(from)).inHours / 24).round();
}
