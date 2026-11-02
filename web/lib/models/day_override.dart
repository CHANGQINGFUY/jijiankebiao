/// 按具体日期生效的覆盖类型。
enum DayOverrideKind {
  /// 当天放假：清空当天的常规课程。
  holiday,

  /// 当天把课程替换成另一门课（或同一门课的临时时间/教室）。
  replacement;

  String get label => this == DayOverrideKind.holiday ? '放假' : '调课';
}

/// 某一天的特殊安排，按具体日期（年月日）存储，优先级高于常规课表。
class DayOverride {
  DayOverride({
    required DateTime date,
    required this.kind,
    this.courseName,
    this.teacher,
    this.room,
    this.startPeriod,
    this.endPeriod,
    this.note,
  }) : date = dateOnly(date);

  /// 生效日期（只保留年月日）。
  final DateTime date;

  final DayOverrideKind kind;

  /// 调课时替换成的课程名。
  final String? courseName;

  final String? teacher;
  final String? room;
  final int? startPeriod;
  final int? endPeriod;
  final String? note;

  bool get isHoliday => kind == DayOverrideKind.holiday;

  String get key => dateKey(date);

  /// 日期键，形如 `2026-10-23`。
  static String dateKey(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 显示用摘要，如「放假」或「调课：高等数学 第 7-8 节」。
  String get summary {
    if (isHoliday) {
      return '放假';
    }
    final String name = (courseName == null || courseName!.isEmpty)
        ? '调课'
        : courseName!;
    final int? start = startPeriod;
    final int? end = endPeriod;
    if (start != null && end != null) {
      return '调课：$name 第 $start-$end 节';
    }
    return '调课：$name';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'date': key,
        'kind': kind.name,
        'courseName': courseName,
        'teacher': teacher,
        'room': room,
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'note': note,
      };

  factory DayOverride.fromJson(Map<String, Object?> json) {
    return DayOverride(
      date: DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      kind: DayOverrideKind.values.firstWhere(
        (DayOverrideKind value) => value.name == json['kind'],
        orElse: () => DayOverrideKind.holiday,
      ),
      courseName: json['courseName'] as String?,
      teacher: json['teacher'] as String?,
      room: json['room'] as String?,
      startPeriod: json['startPeriod'] as int?,
      endPeriod: json['endPeriod'] as int?,
      note: json['note'] as String?,
    );
  }
}
