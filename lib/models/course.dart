import 'user_role.dart';
import 'week_range.dart';
import 'weekday.dart';

/// 一门课程：同一门课在多个星期上同一节次，必要时用 [groupId] 关联不同节次的时段。
class Course {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.room,
    required this.weekdays,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    required this.type,
    this.groupId,
    this.className,
    this.semesterId = '',
    this.academicTerm = '',
    this.colorSeed = 0,
    this.remark,
  });

  /// 唯一标识。
  final String id;

  /// 同一门课不同时段的关联标识；为空时以自身 [id] 作为分组。
  final String? groupId;

  final String name;
  final String teacher;
  final String room;

  /// 班级，教师视图用。
  final String? className;

  /// 所属学期的 id；为空时视为当前学期（兼容旧数据）。
  final String semesterId;

  /// 学年学期，如「2026-2027 第一学期」。
  final String academicTerm;

  /// 上课星期，支持多选。
  final Set<Weekday> weekdays;

  final int startPeriod;
  final int endPeriod;

  /// 起始周与结束周（含端点）。
  final WeekRange weeks;

  /// 配色种子，映射到 CourseColors 调色板。
  final int colorSeed;

  final String? remark;

  /// 身份类型：学生或老师。
  final UserRole type;

  /// 分组标识，未显式设置时等同于 [id]。
  String get group => groupId ?? id;

  int get startWeek => weeks.start;

  int get endWeek => weeks.end;

  int get periodCount => endPeriod - startPeriod + 1;

  String get periodLabel =>
      startPeriod == endPeriod ? '第 $startPeriod 节' : '第 $startPeriod-$endPeriod 节';

  /// 星期按周一至周日排序。
  List<Weekday> get sortedWeekdays => weekdays.toList()
    ..sort((Weekday a, Weekday b) => a.isoIndex.compareTo(b.isoIndex));

  String get weekdayLabel =>
      sortedWeekdays.map((Weekday day) => day.label).join('、');

  Course copyWith({
    String? id,
    String? groupId,
    String? name,
    String? teacher,
    String? room,
    String? className,
    String? semesterId,
    String? academicTerm,
    Set<Weekday>? weekdays,
    int? startPeriod,
    int? endPeriod,
    WeekRange? weeks,
    int? colorSeed,
    String? remark,
    UserRole? type,
  }) {
    return Course(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      teacher: teacher ?? this.teacher,
      room: room ?? this.room,
      className: className ?? this.className,
      semesterId: semesterId ?? this.semesterId,
      academicTerm: academicTerm ?? this.academicTerm,
      weekdays: weekdays ?? this.weekdays,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      weeks: weeks ?? this.weeks,
      colorSeed: colorSeed ?? this.colorSeed,
      remark: remark ?? this.remark,
      type: type ?? this.type,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'groupId': groupId,
        'name': name,
        'teacher': teacher,
        'room': room,
        'className': className,
        'semesterId': semesterId,
        'academicTerm': academicTerm,
        'weekdays': sortedWeekdays.map((Weekday day) => day.isoIndex).toList(),
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'weeks': weeks.toJson(),
        'colorSeed': colorSeed,
        'remark': remark,
        'type': type.name,
      };

  factory Course.fromJson(Map<String, Object?> json) {
    return Course(
      id: json['id']! as String,
      groupId: json['groupId'] as String?,
      name: json['name']! as String,
      teacher: (json['teacher'] as String?) ?? '',
      room: (json['room'] as String?) ?? '',
      className: json['className'] as String?,
      semesterId: (json['semesterId'] as String?) ?? '',
      academicTerm: (json['academicTerm'] as String?) ?? '',
      weekdays: (json['weekdays'] as List<Object?>? ?? const <Object?>[])
          .map((Object? value) => Weekday.fromIsoIndex(value! as int))
          .toSet(),
      startPeriod: json['startPeriod']! as int,
      endPeriod: json['endPeriod']! as int,
      weeks: WeekRange.fromJson(json['weeks']! as Map<String, Object?>),
      colorSeed: (json['colorSeed'] as int?) ?? 0,
      remark: json['remark'] as String?,
      type: UserRole.values.firstWhere(
        (UserRole role) => role.name == json['type'],
        orElse: () => UserRole.student,
      ),
    );
  }
}
