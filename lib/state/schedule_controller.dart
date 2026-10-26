import 'package:flutter/material.dart';

import '../core/schedule/course_conflict.dart';
import '../core/schedule/course_expander.dart';
import '../core/schedule/day_schedule_resolver.dart';
import '../core/schedule/week_calculator.dart';
import '../data/schedule_backup.dart';
import '../data/schedule_repository.dart';
import '../models/course.dart';
import '../models/course_cell.dart';
import '../models/day_override.dart';
import '../models/period_slot.dart';
import '../models/semester_config.dart';
import '../models/user_role.dart';
import '../models/week_range.dart';
import '../models/weekday.dart';

/// 周次来源，用于界面上标注「自动 / 手动」。
enum WeekSource { automatic, manual }

/// 课表状态：当前身份、周次、学期配置、课程与日期覆盖。
class ScheduleController extends ChangeNotifier {
  ScheduleController(this._repository)
      : _config = _repository.config,
        _overrides = _repository.overrides;

  final ScheduleRepository _repository;

  SemesterConfig _config;
  List<DayOverride> _overrides;
  UserRole _role = UserRole.student;
  ThemeMode _themeMode = ThemeMode.system;

  /// 周视图当前浏览的周次。
  int _viewWeek = 0;

  SemesterConfig get config => _config;

  /// 全部学期。
  List<SemesterConfig> get semesters => _repository.semesters;

  /// 当前学期 id。
  String get currentSemesterId => _config.id;

  List<DayOverride> get overrides => List<DayOverride>.unmodifiable(_overrides);

  UserRole get role => _role;

  ThemeMode get themeMode => _themeMode;

  List<Course> get courses => _repository.coursesInSemester(_config.id, _role);

  List<PeriodSlot> get periods => _config.periods;

  int get totalWeeks => _config.totalWeeks;

  /// 自动计算出的学期状态。
  WeekStatus get weekStatus => _config.weekStatus(DateTime.now());

  WeekSource get weekSource =>
      _config.manualWeekEnabled ? WeekSource.manual : WeekSource.automatic;

  /// 当前用于渲染的周次：手动开启时以手动值为准；否则跟随周视图浏览。
  int get currentWeek {
    if (_config.manualWeekEnabled) {
      return _config.manualWeek.clamp(1, _config.totalWeeks);
    }
    if (_viewWeek > 0) {
      return _viewWeek.clamp(1, _config.totalWeeks);
    }
    return weekStatus.week ?? 1;
  }

  /// 界面展示的周次文案，如「第 3 周（自动）」。
  String get weekText => '第 $currentWeek 周（${weekSource.label}）';

  /// 顶部横幅的说明文案：自动模式下如果还没开学/已结束会直接提示。
  String get weekSummary {
    if (_config.manualWeekEnabled) {
      return '第 $currentWeek 周（手动）';
    }
    final WeekStatus status = weekStatus;
    if (status.isInTerm) {
      return '第 ${status.week} 周（自动）';
    }
    return '${status.label}（自动）';
  }

  Weekday get today => Weekday.fromIsoIndex(DateTime.now().weekday);

  // ---------------------------------------------------------------- 周次

  void selectWeek(int week) {
    final int value = week.clamp(1, _config.totalWeeks);
    if (value == currentWeek) {
      return;
    }
    _viewWeek = value;
    notifyListeners();
  }

  /// 手动周次：开启后所有页面都以该周次为准。
  Future<void> setManualWeekEnabled(bool enabled) async {
    if (!enabled) {
      await updateConfig(
        _config.copyWith(manualWeekEnabled: false, manualWeek: currentWeek),
      );
      return;
    }
    await updateConfig(
      _config.copyWith(manualWeekEnabled: true, manualWeek: currentWeek),
    );
  }

  Future<void> setManualWeek(int week) async {
    await updateConfig(
      _config.copyWith(manualWeek: week.clamp(1, _config.totalWeeks)),
    );
  }

  /// 一键恢复自动计算。
  Future<void> resetToAutoWeek() async {
    _viewWeek = 0;
    await updateConfig(_config.copyWith(manualWeekEnabled: false));
  }

  // ---------------------------------------------------------------- 配置

  Future<void> updateConfig(SemesterConfig config) async {
    _config = config;
    await _repository.saveSemester(config);
    notifyListeners();
  }

  /// 切换当前学期：今日页、周课表立即跟随，各学期数据互不干扰。
  Future<void> switchSemester(String semesterId) async {
    if (semesterId == _config.id) {
      return;
    }
    if (!semesters.any((SemesterConfig item) => item.id == semesterId)) {
      return;
    }
    await _repository.setCurrentSemester(semesterId);
    _config = _repository.config;
    _overrides = _repository.overrides;
    _viewWeek = 0;
    notifyListeners();
  }

  /// 新建学期并自动切换过去；作息表沿用当前学期。
  Future<void> createSemester({
    required String name,
    required DateTime startDate,
    required int totalWeeks,
  }) async {
    final SemesterConfig semester = SemesterConfig.create(
      name: name,
      startDate: startDate,
      periods: List<PeriodSlot>.of(_config.periods),
      totalWeeks: totalWeeks.clamp(1, 60),
    );
    await _repository.saveSemester(semester);
    await _repository.setCurrentSemester(semester.id);
    _config = _repository.config;
    _viewWeek = 0;
    notifyListeners();
  }

  /// 重命名当前学期。
  Future<void> renameSemester(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await updateConfig(_config.copyWith(name: trimmed));
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> switchRole(UserRole role) async {
    if (_role == role) {
      return;
    }
    _role = role;
    _viewWeek = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 课程

  Course? courseById(String id) {
    for (final Course course in courses) {
      if (course.id == id) {
        return course;
      }
    }
    return null;
  }

  /// 查找与草稿课程冲突的课程。
  ///
  /// 判定条件：同一学期、同一身份、有共同星期、节次区间重叠、周次区间重叠。
  List<Course> conflictsFor(Course draft) {
    final String semesterId =
        draft.semesterId.isEmpty ? _config.id : draft.semesterId;
    return _repository
        .coursesInSemester(semesterId, draft.type)
        .where((Course other) => CourseConflict.overlaps(draft, other))
        .toList();
  }

  List<Course> groupMembers(String group) =>
      courses.where((Course course) => course.group == group).toList();

  int get nextColorSeed {
    final List<Course> current = courses;
    if (current.isEmpty) {
      return 0;
    }
    return current.length % 12;
  }

  Future<void> addCourse(Course course) async {
    await _repository.saveCourse(course);
    notifyListeners();
  }

  Future<void> updateCourse(Course course, {bool applyToGroup = false}) async {
    if (!applyToGroup) {
      await _repository.saveCourse(course);
      notifyListeners();
      return;
    }
    final List<Course> updated = <Course>[
      for (final Course item in groupMembers(course.group))
        if (item.id == course.id) course else item,
    ];
    await _repository.saveCourses(updated);
    notifyListeners();
  }

  Future<void> deleteCourse(Course course, {bool wholeGroup = false}) async {
    final Set<String> ids = wholeGroup
        ? <String>{for (final Course item in groupMembers(course.group)) item.id}
        : <String>{course.id};
    await _repository.deleteCourses(ids);
    notifyListeners();
  }

  /// 批量导入课程（Excel / 教务系统共用）。
  ///
  /// [overwrite] 为 true 时先清空当前学期、当前身份的课程；
  /// [replaceIds] 用于「追加」模式下用户选择「替换现有」的那些课程。
  Future<void> importCourses({
    required List<Course> courses,
    bool overwrite = false,
    Set<String> replaceIds = const <String>{},
  }) async {
    if (overwrite) {
      final Set<String> existing = <String>{
        for (final Course item in _repository.coursesInSemester(
          _config.id,
          _role,
        ))
          item.id,
      };
      if (existing.isNotEmpty) {
        await _repository.deleteCourses(existing);
      }
    } else if (replaceIds.isNotEmpty) {
      await _repository.deleteCourses(replaceIds);
    }
    if (courses.isEmpty) {
      notifyListeners();
      return;
    }
    final List<Course> normalized = <Course>[
      for (final Course course in courses)
        if (course.semesterId == _config.id && course.type == _role)
          course
        else
          course.copyWith(semesterId: _config.id, type: _role),
    ];
    await _repository.saveCourses(normalized);
    _viewWeek = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 日期覆盖

  DayOverride? overrideFor(DateTime date) {
    final String key = DayOverride.dateKey(date);
    for (final DayOverride item in _overrides) {
      if (item.key == key) {
        return item;
      }
    }
    return null;
  }

  Future<void> saveOverride(DayOverride override) async {
    await _repository.saveOverride(override);
    _overrides = _repository.overrides;
    notifyListeners();
  }

  Future<void> removeOverride(DateTime date) async {
    await _repository.deleteOverride(date);
    _overrides = _repository.overrides;
    notifyListeners();
  }

  /// 快速切换某天是否为放假。
  Future<void> toggleHoliday(DateTime date) async {
    final DayOverride? existing = overrideFor(date);
    if (existing != null && existing.isHoliday) {
      await removeOverride(date);
      return;
    }
    await saveOverride(DayOverride(date: date, kind: DayOverrideKind.holiday));
  }

  // ---------------------------------------------------------------- 备份

  /// 导出全部数据为 JSON 文本。
  String exportBackup() => _repository.exportJson();

  /// 校验导入文件并返回规模预览；格式错误时抛出 [FormatException]。
  BackupPreview previewImport(String raw) => _repository.previewJson(raw);

  /// 导入备份（覆盖或合并），完成后刷新当前学期与覆盖列表。
  Future<ImportSummary> importBackup(
    String raw, {
    required bool overwrite,
  }) async {
    final ImportSummary summary =
        await _repository.importJson(raw, overwrite: overwrite);
    _config = _repository.config;
    _overrides = _repository.overrides;
    _viewWeek = 0;
    notifyListeners();
    return summary;
  }

  // ---------------------------------------------------------------- 渲染

  /// 某星期的课程格子；[week] 缺省使用当前周次。
  ///
  /// 若该日期被设为放假则返回空，若是调课则返回覆盖后的单个格子。
  List<CourseCell> cellsOf(Weekday weekday, {int? week}) {
    final int weekNumber = week ?? currentWeek;
    final DateTime date = _config.dateOf(weekNumber, weekday);
    final DayOverride? override = overrideFor(date);
    if (override != null) {
      if (override.isHoliday) {
        return const <CourseCell>[];
      }
      return <CourseCell>[_overrideCell(override, weekday, date)];
    }
    return CourseExpander.cellsForDay(courses, weekday, weekNumber);
  }

  Map<Weekday, Map<int, List<CourseCell>>> gridOfWeek(int week) {
    final Map<Weekday, Map<int, List<CourseCell>>> grid =
        <Weekday, Map<int, List<CourseCell>>>{};
    for (final Weekday day in Weekday.values) {
      final List<CourseCell> cells = cellsOf(day, week: week);
      for (final CourseCell cell in cells) {
        final Map<int, List<CourseCell>> slots =
            grid.putIfAbsent(day, () => <int, List<CourseCell>>{});
        slots.putIfAbsent(cell.startPeriod, () => <CourseCell>[]).add(cell);
      }
    }
    return grid;
  }

  bool hasCoursesInWeek(int week) {
    for (final Weekday day in Weekday.values) {
      if (cellsOf(day, week: week).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// 今日安排（含放假/调课覆盖、每节课是否已结束、下一节课）。
  DaySchedule todaySchedule({DateTime? now}) {
    final DateTime moment = now ?? DateTime.now();
    return DayScheduleResolver.resolve(
      courses: courses,
      overrides: _overrides,
      config: _config,
      now: moment,
      weekOverride: currentWeek,
    );
  }

  Weekday dayOfWeek(int isoIndex) => Weekday.fromIsoIndex(isoIndex);

  /// 把日期覆盖包装成周视图可渲染的格子。
  CourseCell _overrideCell(
    DayOverride override,
    Weekday weekday,
    DateTime date,
  ) {
    final int startPeriod = override.startPeriod ?? 1;
    final int endPeriod = override.endPeriod ?? startPeriod;
    final Course synthetic = Course(
      id: 'override:${override.key}',
      name: override.courseName?.isNotEmpty == true
          ? override.courseName!
          : '调课',
      teacher: override.teacher ?? '',
      room: override.room ?? '',
      weekdays: <Weekday>{weekday},
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: WeekRange(start: 1, end: _config.totalWeeks),
      type: _role,
    );
    return CourseCell(
      course: synthetic,
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
    );
  }
}

extension WeekSourceLabel on WeekSource {
  String get label => this == WeekSource.manual ? '手动' : '自动';
}
