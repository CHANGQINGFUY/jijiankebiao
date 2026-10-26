import '../../models/course.dart';
import '../../models/course_cell.dart';
import '../../models/weekday.dart';

/// 把「一门课一条 Course」按需展开成一格一格的排课。
class CourseExpander {
  const CourseExpander._();

  /// 展开某门课在第 [weekNumber] 周的格子。
  ///
  /// 只要周次落在 [Course.weeks] 区间内就显示，不做单双周过滤。
  static List<CourseCell> expandForWeek(Course course, int weekNumber) {
    if (!course.weeks.contains(weekNumber)) {
      return const <CourseCell>[];
    }
    return <CourseCell>[
      for (final Weekday day in course.sortedWeekdays)
        CourseCell(
          course: course,
          weekday: day,
          startPeriod: course.startPeriod,
          endPeriod: course.endPeriod,
        ),
    ];
  }

  /// 展开所有课程在第 [weekNumber] 周的格子，并按「星期 → 起始节次」建索引。
  static Map<Weekday, Map<int, List<CourseCell>>> gridForWeek(
    Iterable<Course> courses,
    int weekNumber,
  ) {
    final Map<Weekday, Map<int, List<CourseCell>>> grid =
        <Weekday, Map<int, List<CourseCell>>>{};

    for (final Course course in courses) {
      for (final CourseCell cell in expandForWeek(course, weekNumber)) {
        grid
            .putIfAbsent(cell.weekday, () => <int, List<CourseCell>>{})
            .putIfAbsent(cell.startPeriod, () => <CourseCell>[])
            .add(cell);
      }
    }

    for (final Map<int, List<CourseCell>> dayGrid in grid.values) {
      for (final List<CourseCell> cells in dayGrid.values) {
        cells.sort((CourseCell a, CourseCell b) =>
            a.course.name.compareTo(b.course.name));
      }
    }
    return grid;
  }

  /// 某一天在某周需要显示的格子，按起始节次排序。
  static List<CourseCell> cellsForDay(
    Iterable<Course> courses,
    Weekday weekday,
    int weekNumber,
  ) {
    final List<CourseCell> cells = <CourseCell>[];
    for (final Course course in courses) {
      for (final CourseCell cell in expandForWeek(course, weekNumber)) {
        if (cell.weekday == weekday) {
          cells.add(cell);
        }
      }
    }
    cells.sort((CourseCell a, CourseCell b) =>
        a.startPeriod.compareTo(b.startPeriod));
    return cells;
  }

  /// 某周是否至少有一格排课。
  static bool hasCells(Iterable<Course> courses, int weekNumber) {
    for (final Course course in courses) {
      if (expandForWeek(course, weekNumber).isNotEmpty) {
        return true;
      }
    }
    return false;
  }
}
