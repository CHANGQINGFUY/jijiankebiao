import 'dart:convert';

import '../models/course.dart';
import '../models/day_override.dart';
import '../models/semester_config.dart';
import '../models/user_role.dart';

/// 导入预览：用于在询问「覆盖 / 合并」之前展示文件内容规模。
class BackupPreview {
  const BackupPreview({
    required this.semesterCount,
    required this.courseCount,
    required this.overrideCount,
  });

  final int semesterCount;
  final int courseCount;
  final int overrideCount;
}

/// 导入结果：记录实际新增 / 覆盖了多少数据。
class ImportSummary {
  const ImportSummary({
    required this.semesters,
    required this.courses,
    required this.overrides,
    required this.overwrite,
  });

  final int semesters;
  final int courses;
  final int overrides;
  final bool overwrite;

  String get message => overwrite
      ? '已覆盖导入：$semesters 个学期、$courses 门课程、$overrides 条日期覆盖'
      : '已合并导入：新增 $semesters 个学期、$courses 门课程、$overrides 条日期覆盖';
}

/// 课表备份文件（JSON）的编解码与格式校验。
///
/// 所有校验失败都会抛出带有明确中文说明的 [FormatException]，调用方只需捕获它。
class ScheduleBackup {
  const ScheduleBackup({
    required this.semesters,
    required this.currentSemesterId,
    required this.courses,
    required this.overrides,
  });

  static const String appTag = 'schedule_app';
  static const int version = 4;

  final List<SemesterConfig> semesters;
  final String currentSemesterId;
  final List<Course> courses;
  final List<DayOverride> overrides;

  BackupPreview get preview => BackupPreview(
        semesterCount: semesters.length,
        courseCount: courses.length,
        overrideCount: overrides.length,
      );

  String encode() {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'app': appTag,
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'currentSemesterId': currentSemesterId,
      'semesters': <Object?>[
        for (final SemesterConfig semester in semesters) semester.toJson(),
      ],
      'courses': <Object?>[for (final Course course in courses) course.toJson()],
      'overrides': <Object?>[
        for (final DayOverride item in overrides) item.toJson(),
      ],
    });
  }

  /// 解析并校验备份文本；格式错误时抛出 [FormatException]。
  static ScheduleBackup decode(String raw) {
    if (raw.trim().isEmpty) {
      throw const FormatException('文件内容为空');
    }

    dynamic data;
    try {
      data = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException('文件不是有效的 JSON：${error.message}');
    }
    if (data is! Map) {
      throw const FormatException('JSON 顶层必须是一个对象');
    }
    final Map<String, Object?> map = data.cast<String, Object?>();

    final Object? rawVersion = map['version'];
    if (rawVersion is int && rawVersion > version) {
      throw FormatException('备份版本 $rawVersion 高于当前支持的版本 $version，请升级 App 后再导入');
    }

    final List<SemesterConfig> semesters = _decodeSemesters(map);
    final String currentSemesterId =
        _resolveCurrentSemesterId(map, semesters);

    final List<Course> courses = _decodeCourses(map, currentSemesterId, semesters);
    final List<DayOverride> overrides = _decodeOverrides(map);

    return ScheduleBackup(
      semesters: semesters,
      currentSemesterId: currentSemesterId,
      courses: courses,
      overrides: overrides,
    );
  }

  static List<SemesterConfig> _decodeSemesters(Map<String, Object?> map) {
    Object? rawSemesters = map['semesters'];
    if (rawSemesters == null) {
      // 兼容早期只存单个 config 的备份。
      final Object? legacyConfig = map['config'];
      if (legacyConfig is! Map) {
        throw const FormatException('缺少 semesters 字段，无法识别该备份');
      }
      rawSemesters = <Object?>[legacyConfig];
    }
    if (rawSemesters is! List || rawSemesters.isEmpty) {
      throw const FormatException('semesters 必须是非空数组');
    }

    final List<SemesterConfig> result = <SemesterConfig>[];
    final Set<String> ids = <String>{};
    for (int index = 0; index < rawSemesters.length; index++) {
      final Object? item = rawSemesters[index];
      if (item is! Map) {
        throw FormatException('第 ${index + 1} 个学期不是有效的对象');
      }
      final Map<String, Object?> semesterMap = item.cast<String, Object?>();
      final String name = (semesterMap['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        throw FormatException('第 ${index + 1} 个学期缺少名称');
      }
      final String startDateRaw =
          (semesterMap['startDate'] as String?)?.trim() ?? '';
      final DateTime? startDate = DateTime.tryParse(startDateRaw);
      if (startDate == null) {
        throw FormatException('学期「$name」的开学日期格式无效：$startDateRaw');
      }
      final int totalWeeks = (semesterMap['totalWeeks'] as int?) ?? 0;
      if (totalWeeks <= 0 || totalWeeks > 60) {
        throw FormatException('学期「$name」的总周数必须在 1-60 之间');
      }
      final Object? rawPeriods = semesterMap['periods'];
      if (rawPeriods is! List || rawPeriods.isEmpty) {
        throw FormatException('学期「$name」缺少节次时间');
      }
      for (final Object? period in rawPeriods) {
        if (period is! Map) {
          throw FormatException('学期「$name」的节次时间格式无效');
        }
        final Map<String, Object?> periodMap = period.cast<String, Object?>();
        final String start = (periodMap['start'] as String?) ?? '';
        final String end = (periodMap['end'] as String?) ?? '';
        if (!_isClock(start) || !_isClock(end)) {
          throw FormatException('学期「$name」的节次时间必须是 HH:mm 格式');
        }
      }

      SemesterConfig semester = SemesterConfig.fromJson(semesterMap);
      if (ids.contains(semester.id)) {
        semester = semester.copyWith(
          id: '${semester.id}-$index',
        );
      }
      ids.add(semester.id);
      result.add(semester);
    }
    return result;
  }

  static String _resolveCurrentSemesterId(
    Map<String, Object?> map,
    List<SemesterConfig> semesters,
  ) {
    final String candidate =
        (map['currentSemesterId'] as String?)?.trim() ?? '';
    if (candidate.isNotEmpty &&
        semesters.any((SemesterConfig item) => item.id == candidate)) {
      return candidate;
    }
    return semesters.first.id;
  }

  static List<Course> _decodeCourses(
    Map<String, Object?> map,
    String currentSemesterId,
    List<SemesterConfig> semesters,
  ) {
    final Object? rawCourses = map['courses'];
    if (rawCourses == null) {
      return <Course>[];
    }
    if (rawCourses is! List) {
      throw const FormatException('courses 必须是数组');
    }

    final Set<String> semesterIds =
        semesters.map((SemesterConfig item) => item.id).toSet();
    final List<Course> result = <Course>[];
    final Set<String> ids = <String>{};
    for (int index = 0; index < rawCourses.length; index++) {
      final Object? item = rawCourses[index];
      if (item is! Map) {
        throw FormatException('第 ${index + 1} 门课程不是有效的对象');
      }
      final Map<String, Object?> courseMap = item.cast<String, Object?>();
      final String name = (courseMap['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        throw FormatException('第 ${index + 1} 门课程缺少课程名');
      }
      final Object? rawWeekdays = courseMap['weekdays'];
      if (rawWeekdays is! List || rawWeekdays.isEmpty) {
        throw FormatException('课程「$name」缺少上课星期');
      }
      for (final Object? day in rawWeekdays) {
        if (day is! int || day < 1 || day > 7) {
          throw FormatException('课程「$name」的星期数据无效');
        }
      }
      final Object? rawStartPeriod = courseMap['startPeriod'];
      final Object? rawEndPeriod = courseMap['endPeriod'];
      if (rawStartPeriod is! int || rawEndPeriod is! int) {
        throw FormatException('课程「$name」的节次必须是整数');
      }
      if (rawEndPeriod < rawStartPeriod) {
        throw FormatException('课程「$name」的结束节次不能小于开始节次');
      }
      final Object? rawWeeks = courseMap['weeks'];
      if (rawWeeks is! Map) {
        throw FormatException('课程「$name」缺少周次范围');
      }
      final Map<String, Object?> weeksMap = rawWeeks.cast<String, Object?>();
      final Object? startWeek = weeksMap['start'];
      final Object? endWeek = weeksMap['end'];
      if (startWeek is! int || endWeek is! int) {
        throw FormatException('课程「$name」的周次范围必须是整数');
      }
      if (startWeek <= 0 || endWeek < startWeek || endWeek > 60) {
        throw FormatException('课程「$name」的周次范围无效');
      }
      final String type = (courseMap['type'] as String?) ?? 'student';
      if (!UserRole.values.any((UserRole role) => role.name == type)) {
        throw FormatException('课程「$name」的身份类型无效：$type');
      }

      String semesterId = (courseMap['semesterId'] as String?)?.trim() ?? '';
      if (semesterId.isEmpty || !semesterIds.contains(semesterId)) {
        semesterId = currentSemesterId;
      }

      final String id = (courseMap['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) {
        throw FormatException('课程「$name」缺少 id');
      }
      if (ids.contains(id)) {
        throw FormatException('课程「$name」的 id 与其它课程重复');
      }

      final Course course = Course.fromJson(<String, Object?>{
        ...courseMap,
        'semesterId': semesterId,
      });
      if (course.weekdays.isEmpty) {
        throw FormatException('课程「$name」的星期数据无效');
      }
      if (course.weeks.end > 60) {
        throw FormatException('课程「$name」的周次超出范围');
      }
      ids.add(id);
      result.add(course);
    }
    return result;
  }

  static List<DayOverride> _decodeOverrides(Map<String, Object?> map) {
    final Object? rawOverrides = map['overrides'];
    if (rawOverrides == null) {
      return <DayOverride>[];
    }
    if (rawOverrides is! List) {
      throw const FormatException('overrides 必须是数组');
    }
    final List<DayOverride> result = <DayOverride>[];
    for (int index = 0; index < rawOverrides.length; index++) {
      final Object? item = rawOverrides[index];
      if (item is! Map) {
        throw FormatException('第 ${index + 1} 条日期覆盖不是有效的对象');
      }
      final Map<String, Object?> overrideMap = item.cast<String, Object?>();
      final String date = (overrideMap['date'] as String?)?.trim() ?? '';
      if (DateTime.tryParse(date) == null) {
        throw FormatException('第 ${index + 1} 条日期覆盖的日期无效：$date');
      }
      final String kind = (overrideMap['kind'] as String?) ?? '';
      if (!DayOverrideKind.values.any((DayOverrideKind value) => value.name == kind)) {
        throw FormatException('第 ${index + 1} 条日期覆盖的类型无效：$kind');
      }
      result.add(DayOverride.fromJson(overrideMap));
    }
    return result;
  }

  static bool _isClock(String value) {
    return RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value);
  }
}
