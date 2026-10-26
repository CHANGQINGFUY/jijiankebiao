import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/day_override.dart';
import '../models/semester_config.dart';
import '../models/user_role.dart';
import 'schedule_backup.dart';
import 'schedule_repository.dart';

/// 基于 shared_preferences 的本地存储。
///
/// 所有数据（多个学期、课程、日期覆盖）以单个 JSON 字符串保存在本地，
/// 不依赖网络、不上传服务器。
class LocalScheduleRepository implements ScheduleRepository {
  LocalScheduleRepository();

  static const String _dataKey = 'schedule_data_v4';
  static const String _legacyKey = 'schedule_data_v3';
  static const String _backupKey = 'schedule_backup_legacy';

  /// 当前存储结构版本：v4 开始支持多学期。
  static const int _version = 4;

  List<SemesterConfig> _semesters = <SemesterConfig>[];
  String _currentSemesterId = '';
  final List<Course> _courses = <Course>[];
  List<DayOverride> _overrides = <DayOverride>[];

  bool _loaded = false;

  @override
  List<SemesterConfig> get semesters =>
      List<SemesterConfig>.unmodifiable(_semesters);

  @override
  String get currentSemesterId => _currentSemesterId;

  @override
  SemesterConfig get config {
    for (final SemesterConfig semester in _semesters) {
      if (semester.id == _currentSemesterId) {
        return semester;
      }
    }
    return _semesters.isEmpty
        ? SemesterConfig.initial(DateTime.now())
        : _semesters.first;
  }

  @override
  List<DayOverride> get overrides => List<DayOverride>.unmodifiable(_overrides);

  @override
  List<Course> coursesInSemester(String semesterId, UserRole role) {
    return List<Course>.unmodifiable(
      _courses.where(
        (Course course) =>
            course.type == role &&
            (course.semesterId == semesterId ||
                (course.semesterId.isEmpty && semesterId == _currentSemesterId)),
      ),
    );
  }

  /// 读取本地数据；首次运行或数据损坏时创建默认学期。
  Future<void> load() async {
    if (_loaded) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? rawV4 = prefs.getString(_dataKey);
    final String? rawLegacy = rawV4 == null ? prefs.getString(_legacyKey) : null;
    final String? raw = rawV4 ?? rawLegacy;

    if (raw == null || raw.isEmpty) {
      _initDefaultSemester();
      _loaded = true;
      return;
    }

    Map<String, Object?>? decoded;
    try {
      final Object? value = jsonDecode(raw);
      if (value is Map) {
        decoded = value.cast<String, Object?>();
      }
    } catch (error, stack) {
      debugPrint('读取课表数据失败，已忽略旧数据：$error\n$stack');
    }

    if (decoded == null) {
      _initDefaultSemester();
      _loaded = true;
      return;
    }

    final int version = (decoded['version'] as int?) ?? 2;
    if (version < _version) {
      // 旧结构：先保留一份原始副本，再按新结构尽力迁移。
      await prefs.setString(_backupKey, raw);
      debugPrint('检测到旧版课表数据（v$version），已备份到 $_backupKey 并自动迁移。');
    }

    _semesters = _parseSemesters(decoded);
    if (_semesters.isEmpty) {
      _initDefaultSemester();
      _loaded = true;
      return;
    }

    final String candidate = (decoded['currentSemesterId'] as String?) ?? '';
    _currentSemesterId = _semesters.any(
      (SemesterConfig semester) => semester.id == candidate,
    )
        ? candidate
        : _semesters.first.id;

    final Object? rawCourses = decoded['courses'];
    if (rawCourses is List) {
      _courses
        ..clear()
        ..addAll(
          rawCourses.whereType<Map>().map((Map item) {
            final Course course = Course.fromJson(item.cast<String, Object?>());
            // 旧数据没有学期 id：归入当前学期，之后随迁移持久化。
            return course.semesterId.isEmpty
                ? course.copyWith(semesterId: _currentSemesterId)
                : course;
          }),
        );
    }

    final Object? rawOverrides = decoded['overrides'];
    if (rawOverrides is List) {
      _overrides = rawOverrides.whereType<Map>().map((Map item) {
        return DayOverride.fromJson(item.cast<String, Object?>());
      }).toList();
    }

    _loaded = true;
    if (version < _version || rawLegacy != null) {
      await _persist();
    }
  }

  void _initDefaultSemester() {
    final SemesterConfig semester = SemesterConfig.initial(DateTime.now());
    _semesters = <SemesterConfig>[semester];
    _currentSemesterId = semester.id;
  }

  List<SemesterConfig> _parseSemesters(Map<String, Object?> decoded) {
    final Object? rawSemesters = decoded['semesters'];
    if (rawSemesters is List && rawSemesters.isNotEmpty) {
      return rawSemesters.whereType<Map>().map((Map item) {
        return SemesterConfig.fromJson(item.cast<String, Object?>());
      }).toList();
    }
    final Object? rawConfig = decoded['config'];
    if (rawConfig is Map) {
      return <SemesterConfig>[
        SemesterConfig.fromJson(rawConfig.cast<String, Object?>()),
      ];
    }
    return <SemesterConfig>[];
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
    await _persist();
  }

  @override
  Future<void> deleteCourses(Set<String> ids) async {
    _courses.removeWhere((Course course) => ids.contains(course.id));
    await _persist();
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
    await _persist();
  }

  @override
  Future<void> setCurrentSemester(String semesterId) async {
    if (!_semesters.any((SemesterConfig item) => item.id == semesterId)) {
      return;
    }
    _currentSemesterId = semesterId;
    await _persist();
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
    await _persist();
  }

  @override
  Future<void> deleteOverride(DateTime date) async {
    final String key = DayOverride.dateKey(date);
    _overrides.removeWhere((DayOverride item) => item.key == key);
    await _persist();
  }

  @override
  String exportJson() {
    return ScheduleBackup(
      semesters: _semesters,
      currentSemesterId: _currentSemesterId,
      courses: _courses,
      overrides: _overrides,
    ).encode();
  }

  @override
  BackupPreview previewJson(String raw) => ScheduleBackup.decode(raw).preview;

  @override
  Future<ImportSummary> importJson(
    String raw, {
    required bool overwrite,
  }) async {
    final ScheduleBackup backup = ScheduleBackup.decode(raw);

    if (overwrite) {
      _semesters = List<SemesterConfig>.of(backup.semesters);
      _courses
        ..clear()
        ..addAll(backup.courses);
      _overrides = List<DayOverride>.of(backup.overrides);
      _currentSemesterId = backup.currentSemesterId;
      await _persist();
      return ImportSummary(
        semesters: backup.semesters.length,
        courses: backup.courses.length,
        overrides: backup.overrides.length,
        overwrite: true,
      );
    }

    // 合并：按 id / 日期去重，已存在的条目保持原样，不静默覆盖。
    int addedSemesters = 0;
    for (final SemesterConfig semester in backup.semesters) {
      if (!_semesters.any((SemesterConfig item) => item.id == semester.id)) {
        _semesters.add(semester);
        addedSemesters++;
      }
    }
    if (_semesters.isEmpty) {
      _semesters = List<SemesterConfig>.of(backup.semesters);
      addedSemesters = backup.semesters.length;
    }
    if (!_semesters.any(
      (SemesterConfig item) => item.id == _currentSemesterId,
    )) {
      _currentSemesterId = _semesters.first.id;
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

    await _persist();
    return ImportSummary(
      semesters: addedSemesters,
      courses: addedCourses,
      overrides: addedOverrides,
      overwrite: false,
    );
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String payload = jsonEncode(<String, Object?>{
      'version': _version,
      'currentSemesterId': _currentSemesterId,
      'semesters': <Object?>[
        for (final SemesterConfig semester in _semesters) semester.toJson(),
      ],
      'courses': <Object?>[for (final Course course in _courses) course.toJson()],
      'overrides': <Object?>[
        for (final DayOverride override in _overrides) override.toJson(),
      ],
    });
    await prefs.setString(_dataKey, payload);
  }
}
