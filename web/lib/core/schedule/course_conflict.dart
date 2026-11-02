import '../../models/course.dart';
import '../../models/weekday.dart';

/// 课程冲突判定：同一学期、同一身份、有共同星期、节次重叠、周次重叠。
///
/// Excel 导入、教务导入与手动添加课程共用这一套判定，避免出现两套规则。
class CourseConflict {
  const CourseConflict._();

  static bool overlaps(Course a, Course b) {
    if (a.id == b.id) {
      return false;
    }
    if (a.type != b.type) {
      return false;
    }
    // 空 semesterId 代表旧数据，视为同一学期。
    if (a.semesterId.isNotEmpty &&
        b.semesterId.isNotEmpty &&
        a.semesterId != b.semesterId) {
      return false;
    }
    final bool sameDay =
        a.weekdays.any((Weekday day) => b.weekdays.contains(day));
    if (!sameDay) {
      return false;
    }
    final bool periodOverlap =
        a.startPeriod <= b.endPeriod && a.endPeriod >= b.startPeriod;
    if (!periodOverlap) {
      return false;
    }
    return a.weeks.start <= b.weeks.end && a.weeks.end >= b.weeks.start;
  }
}
