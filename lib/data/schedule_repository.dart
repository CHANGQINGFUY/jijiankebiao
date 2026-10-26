import '../models/course.dart';
import '../models/day_override.dart';
import '../models/semester_config.dart';
import '../models/user_role.dart';
import 'schedule_backup.dart';

/// 课表数据仓储：多个学期、课程、日期覆盖，全部存放本地。
abstract class ScheduleRepository {
  /// 全部学期。
  List<SemesterConfig> get semesters;

  /// 当前学期 id。
  String get currentSemesterId;

  /// 当前学期配置。
  SemesterConfig get config;

  /// 指定学期、指定身份下的课程。
  List<Course> coursesInSemester(String semesterId, UserRole role);

  List<DayOverride> get overrides;

  Future<void> saveCourse(Course course);

  Future<void> saveCourses(Iterable<Course> courses);

  Future<void> deleteCourses(Set<String> ids);

  /// 新增或更新一个学期（按 id 匹配）。
  Future<void> saveSemester(SemesterConfig semester);

  /// 切换当前学期。
  Future<void> setCurrentSemester(String semesterId);

  Future<void> saveOverride(DayOverride override);

  Future<void> deleteOverride(DateTime date);

  /// 导出全部学期、课程、日期覆盖为 JSON 文本。
  String exportJson();

  /// 校验并预览导入文件，格式错误时抛出 [FormatException]。
  BackupPreview previewJson(String raw);

  /// 导入备份：覆盖或合并。
  Future<ImportSummary> importJson(String raw, {required bool overwrite});
}
