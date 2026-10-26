import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/app.dart';
import 'package:schedule_app/core/schedule/week_calculator.dart';
import 'package:schedule_app/data/schedule_backup.dart';
import 'package:schedule_app/data/schedule_repository.dart';
import 'package:schedule_app/models/course.dart';
import 'package:schedule_app/models/day_override.dart';
import 'package:schedule_app/models/period_slot.dart';
import 'package:schedule_app/models/semester_config.dart';
import 'package:schedule_app/models/user_role.dart';
import 'package:schedule_app/models/week_range.dart';
import 'package:schedule_app/models/weekday.dart';
import 'package:schedule_app/state/schedule_controller.dart';

/// 内存仓储：不依赖 shared_preferences，便于在测试里验证持久化语义。
class _MemoryRepository implements ScheduleRepository {
  _MemoryRepository({required SemesterConfig config})
      : _semesters = <SemesterConfig>[config],
        _currentSemesterId = config.id;

  final List<SemesterConfig> _semesters;
  String _currentSemesterId;
  final List<Course> _courses = <Course>[];
  final List<DayOverride> _overrides = <DayOverride>[];

  @override
  List<SemesterConfig> get semesters =>
      List<SemesterConfig>.unmodifiable(_semesters);

  @override
  String get currentSemesterId => _currentSemesterId;

  @override
  SemesterConfig get config => _semesters.firstWhere(
        (SemesterConfig item) => item.id == _currentSemesterId,
        orElse: () => _semesters.first,
      );

  @override
  List<DayOverride> get overrides => List<DayOverride>.of(_overrides);

  @override
  List<Course> coursesInSemester(String semesterId, UserRole role) {
    return _courses
        .where(
          (Course course) =>
              course.type == role &&
              (course.semesterId == semesterId ||
                  (course.semesterId.isEmpty &&
                      semesterId == _currentSemesterId)),
        )
        .toList();
  }

  @override
  Future<void> saveCourse(Course course) => saveCourses(<Course>[course]);

  @override
  Future<void> saveCourses(Iterable<Course> courses) async {
    for (final Course course in courses) {
      final int index =
          _courses.indexWhere((Course item) => item.id == course.id);
      if (index >= 0) {
        _courses[index] = course;
      } else {
        _courses.add(course);
      }
    }
  }

  @override
  Future<void> deleteCourses(Set<String> ids) async {
    _courses.removeWhere((Course course) => ids.contains(course.id));
  }

  @override
  Future<void> saveSemester(SemesterConfig semester) async {
    final int index =
        _semesters.indexWhere((SemesterConfig item) => item.id == semester.id);
    if (index >= 0) {
      _semesters[index] = semester;
    } else {
      _semesters.add(semester);
    }
  }

  @override
  Future<void> setCurrentSemester(String semesterId) async {
    if (_semesters.any((SemesterConfig item) => item.id == semesterId)) {
      _currentSemesterId = semesterId;
    }
  }

  @override
  Future<void> saveOverride(DayOverride override) async {
    final int index =
        _overrides.indexWhere((DayOverride item) => item.key == override.key);
    if (index >= 0) {
      _overrides[index] = override;
    } else {
      _overrides.add(override);
    }
  }

  @override
  Future<void> deleteOverride(DateTime date) async {
    final String key = DayOverride.dateKey(date);
    _overrides.removeWhere((DayOverride item) => item.key == key);
  }

  @override
  String exportJson() => ScheduleBackup(
        semesters: _semesters,
        currentSemesterId: _currentSemesterId,
        courses: _courses,
        overrides: _overrides,
      ).encode();

  @override
  BackupPreview previewJson(String raw) => ScheduleBackup.decode(raw).preview;

  @override
  Future<ImportSummary> importJson(
    String raw, {
    required bool overwrite,
  }) async {
    final ScheduleBackup backup = ScheduleBackup.decode(raw);
    if (overwrite) {
      _semesters
        ..clear()
        ..addAll(backup.semesters);
      _courses
        ..clear()
        ..addAll(backup.courses);
      _overrides
        ..clear()
        ..addAll(backup.overrides);
      _currentSemesterId = backup.currentSemesterId;
      return ImportSummary(
        semesters: backup.semesters.length,
        courses: backup.courses.length,
        overrides: backup.overrides.length,
        overwrite: true,
      );
    }

    int addedSemesters = 0;
    for (final SemesterConfig semester in backup.semesters) {
      if (!_semesters.any((SemesterConfig item) => item.id == semester.id)) {
        _semesters.add(semester);
        addedSemesters++;
      }
    }
    int addedCourses = 0;
    for (final Course course in backup.courses) {
      if (!_courses.any((Course item) => item.id == course.id)) {
        _courses.add(course);
        addedCourses++;
      }
    }
    int addedOverrides = 0;
    for (final DayOverride override in backup.overrides) {
      if (!_overrides.any((DayOverride item) => item.key == override.key)) {
        _overrides.add(override);
        addedOverrides++;
      }
    }
    return ImportSummary(
      semesters: addedSemesters,
      courses: addedCourses,
      overrides: addedOverrides,
      overwrite: false,
    );
  }
}

Course _course({
  String id = 'course-1',
  String name = '高等数学',
  String semesterId = '',
  Set<Weekday> weekdays = const <Weekday>{Weekday.monday},
  int startWeek = 1,
  int endWeek = 20,
  int startPeriod = 1,
  int endPeriod = 2,
}) {
  return Course(
    id: id,
    name: name,
    teacher: '王老师',
    room: '教三楼 201',
    semesterId: semesterId,
    weekdays: weekdays,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    weeks: WeekRange(start: startWeek, end: endWeek),
    type: UserRole.student,
  );
}

SemesterConfig _configStarting(
  DateTime startDate, {
  int totalWeeks = 20,
  String id = 'sem-default',
  String name = '默认学期',
}) {
  return SemesterConfig(
    id: id,
    name: name,
    startDate: startDate,
    periods: const <PeriodSlot>[
      PeriodSlot(index: 1, start: '08:00', end: '08:45'),
      PeriodSlot(index: 2, start: '08:55', end: '09:40'),
      PeriodSlot(index: 3, start: '10:00', end: '10:45'),
      PeriodSlot(index: 4, start: '10:55', end: '11:40'),
    ],
    totalWeeks: totalWeeks,
  );
}

void main() {
  group('周次计算（自然周，只比较年月日）', () {
    test('开学日为周三时，当周仍算第 1 周', () {
      final DateTime startDate = DateTime(2026, 9, 2); // 周三
      final WeekStatus status = WeekCalculator.resolve(
        now: DateTime(2026, 9, 2),
        startDate: startDate,
        totalWeeks: 20,
      );
      expect(status.firstMonday, DateTime(2026, 8, 31));
      expect(status.isInTerm, isTrue);
      expect(status.week, 1);

      expect(
        WeekCalculator.resolve(
          now: DateTime(2026, 9, 6), // 周日
          startDate: startDate,
          totalWeeks: 20,
        ).week,
        1,
      );
      expect(
        WeekCalculator.resolve(
          now: DateTime(2026, 9, 7), // 下周一
          startDate: startDate,
          totalWeeks: 20,
        ).week,
        2,
      );
    });

    test('早于开学日返回「还没开学」而不是 0 或负数', () {
      final WeekStatus status = WeekCalculator.resolve(
        now: DateTime(2026, 8, 31),
        startDate: DateTime(2026, 9, 2),
        totalWeeks: 20,
      );
      expect(status.isBeforeStart, isTrue);
      expect(status.week, isNull);
      expect(status.label, '还没开学');
      expect(status.daysUntilStart, 2);
    });

    test('晚于学期最后一天返回「本学期已结束」', () {
      final WeekStatus status = WeekCalculator.resolve(
        now: DateTime(2026, 9, 14),
        startDate: DateTime(2026, 9, 2),
        totalWeeks: 2,
      );
      expect(status.isAfterEnd, isTrue);
      expect(status.week, isNull);
      expect(status.label, '本学期已结束');
    });

    test('跨年学期按自然周连续递增', () {
      final WeekStatus status = WeekCalculator.resolve(
        now: DateTime(2027, 1, 4),
        startDate: DateTime(2026, 12, 30),
        totalWeeks: 20,
      );
      expect(status.firstMonday, DateTime(2026, 12, 28));
      expect(status.week, 2);
    });
  });

  group('ScheduleController', () {
    test('区间过滤：1-8 周的课在第 9 周不显示', () {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController controller = ScheduleController(repository);
      controller.addCourse(_course(startWeek: 1, endWeek: 8));

      expect(controller.cellsOf(Weekday.monday, week: 8), hasLength(1));
      expect(controller.cellsOf(Weekday.monday, week: 9), isEmpty);
    });

    test('手动周次生效并持久化，恢复自动后回到真实周次', () async {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController first = ScheduleController(repository);
      await first.setManualWeekEnabled(true);
      await first.setManualWeek(10);

      expect(first.currentWeek, 10);
      expect(first.weekSource, WeekSource.manual);
      expect(first.weekText, '第 10 周（手动）');

      final ScheduleController restarted = ScheduleController(repository);
      expect(restarted.config.manualWeekEnabled, isTrue);
      expect(restarted.currentWeek, 10);

      await restarted.resetToAutoWeek();
      expect(restarted.config.manualWeekEnabled, isFalse);
      expect(restarted.weekSource, WeekSource.automatic);
      expect(restarted.weekSummary, contains('自动'));
    });

    test('手动周次超出总周数会被限制在 1..totalWeeks', () async {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2), totalWeeks: 12),
      );
      final ScheduleController controller = ScheduleController(repository);
      await controller.setManualWeekEnabled(true);
      await controller.setManualWeek(99);
      expect(controller.currentWeek, 12);

      await controller.setManualWeek(-3);
      expect(controller.currentWeek, 1);
    });

    test('放假覆盖优先，删除后恢复常规课表', () async {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController controller = ScheduleController(repository);
      await controller.addCourse(_course());

      final DateTime monday = controller.config.dateOf(1, Weekday.monday);
      expect(controller.cellsOf(Weekday.monday, week: 1), hasLength(1));

      await controller.toggleHoliday(monday);
      expect(controller.cellsOf(Weekday.monday, week: 1), isEmpty);

      await controller.toggleHoliday(monday);
      expect(controller.cellsOf(Weekday.monday, week: 1), hasLength(1));
    });

    test('某天放假又调课时，放假优先', () async {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController controller = ScheduleController(repository);
      final DateTime monday = controller.config.dateOf(1, Weekday.monday);

      await controller.saveOverride(
        DayOverride(
          date: monday,
          kind: DayOverrideKind.replacement,
          courseName: '临时调课',
        ),
      );
      expect(
        controller.cellsOf(Weekday.monday, week: 1).single.course.name,
        '临时调课',
      );

      await controller.saveOverride(
        DayOverride(date: monday, kind: DayOverrideKind.holiday),
      );
      expect(controller.cellsOf(Weekday.monday, week: 1), isEmpty);
    });

    test('今日安排：没课时返回空列表', () {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController controller = ScheduleController(repository);
      expect(controller.todaySchedule(now: DateTime(2026, 9, 3)).isEmpty, isTrue);
    });

    test('课程冲突：同星期节次重叠才提示', () async {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController controller = ScheduleController(repository);
      await controller.addCourse(_course(id: 'a', startPeriod: 1, endPeriod: 2));

      expect(
        controller.conflictsFor(_course(id: 'b', startPeriod: 2, endPeriod: 3)),
        hasLength(1),
      );
      expect(
        controller.conflictsFor(_course(id: 'c', startPeriod: 3, endPeriod: 4)),
        isEmpty,
      );
      expect(
        controller.conflictsFor(
          _course(
            id: 'd',
            weekdays: const <Weekday>{Weekday.tuesday},
          ),
        ),
        isEmpty,
      );
      expect(
        controller.conflictsFor(
          _course(id: 'e', startWeek: 21, endWeek: 22),
        ),
        isEmpty,
      );
      // 编辑自己不算冲突。
      expect(
        controller.conflictsFor(_course(id: 'a', startPeriod: 1, endPeriod: 2)),
        isEmpty,
      );
    });

    test('切换学期后课程互不干扰，手动周次只影响当前学期', () async {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController controller = ScheduleController(repository);
      await controller.addCourse(_course(id: 's1', semesterId: 'sem-default'));

      await controller.setManualWeekEnabled(true);
      await controller.setManualWeek(4);

      await controller.createSemester(
        name: '2027 春季学期',
        startDate: DateTime(2027, 2, 22),
        totalWeeks: 18,
      );
      expect(controller.config.name, '2027 春季学期');
      expect(controller.courses, isEmpty);
      expect(controller.weekSource, WeekSource.automatic);
      expect(controller.semesters, hasLength(2));

      await controller.addCourse(
        _course(
          id: 's2',
          name: '线性代数',
          semesterId: controller.currentSemesterId,
        ),
      );
      expect(controller.courses.single.name, '线性代数');

      await controller.switchSemester('sem-default');
      expect(controller.courses.single.name, '高等数学');
      expect(controller.config.manualWeekEnabled, isTrue);
      expect(controller.currentWeek, 4);

      await controller.switchSemester(controller.semesters.last.id);
      expect(controller.courses.single.name, '线性代数');
      expect(controller.config.manualWeekEnabled, isFalse);
    });

    test('导出后可以覆盖导入，课程与覆盖都能恢复', () async {
      final _MemoryRepository repository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController controller = ScheduleController(repository);
      await controller.addCourse(_course(id: 'backup-1'));
      await controller.toggleHoliday(DateTime(2026, 9, 7));

      final String json = controller.exportBackup();
      final _MemoryRepository target = _MemoryRepository(
        config: _configStarting(DateTime(2026, 1, 5), id: 'other'),
      );
      final ScheduleController imported = ScheduleController(target);
      await imported.importBackup(json, overwrite: true);

      expect(imported.semesters, hasLength(1));
      expect(imported.semesters.single.id, 'sem-default');
      expect(imported.courses, hasLength(1));
      expect(imported.overrides, hasLength(1));
    });

    test('合并导入只补充新条目，不覆盖已有课程', () async {
      final _MemoryRepository sourceRepository = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController source = ScheduleController(sourceRepository);
      await source.addCourse(_course(id: 'keep', name: '已有课程'));
      await source.addCourse(_course(id: 'new', name: '新增课程'));

      final _MemoryRepository target = _MemoryRepository(
        config: _configStarting(DateTime(2026, 9, 2)),
      );
      final ScheduleController targetController = ScheduleController(target);
      await targetController.addCourse(_course(id: 'keep', name: '本地课程'));

      await targetController.importBackup(
        source.exportBackup(),
        overwrite: false,
      );
      expect(targetController.courses, hasLength(2));
      final Course kept = targetController.courses
          .firstWhere((Course course) => course.id == 'keep');
      expect(kept.name, '本地课程');
    });

    test('导入格式错误给出明确提示而不是崩溃', () {
      expect(
        () => ScheduleBackup.decode('{ not json'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('JSON'),
          ),
        ),
      );
      expect(
        () => ScheduleBackup.decode('{"version":4}'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('semesters'),
          ),
        ),
      );
      final Map<String, Object?> broken = <String, Object?>{
        'version': 4,
        'semesters': <Object?>[
          <String, Object?>{
            'id': 'sem-1',
            'name': '测试学期',
            'startDate': '2026-09-02',
            'totalWeeks': 20,
            'periods': <Object?>[
              <String, Object?>{'index': 1, 'start': '08:00', 'end': '08:45'},
            ],
          },
        ],
        'courses': <Object?>[
          <String, Object?>{
            'id': 'bad',
            'name': '坏课程',
            'weekdays': <Object?>[1],
            'startPeriod': 3,
            'endPeriod': 2,
            'weeks': <String, Object?>{'start': 1, 'end': 8},
            'type': 'student',
          },
        ],
      };
      expect(
        () => ScheduleBackup.decode(
          const JsonEncoder().convert(broken),
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('结束节次不能小于开始节次'),
          ),
        ),
      );
    });
  });

  testWidgets('App 正常渲染首页与三个 Tab', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final _MemoryRepository repository = _MemoryRepository(
      config: SemesterConfig.initial(DateTime.now()),
    );
    await tester.pumpWidget(
      ScheduleApp(controller: ScheduleController(repository)),
    );

    expect(find.text('你好，同学'), findsOneWidget);
    expect(find.text('课表'), findsWidgets);
    expect(find.text('添加'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('今天没有课'), findsWidgets);
  });
}
