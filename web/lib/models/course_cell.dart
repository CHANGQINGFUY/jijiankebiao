import 'course.dart';
import 'weekday.dart';

/// 周视图中一个「格子」：某门课在某个星期、某个节次区间的呈现。
class CourseCell {
  const CourseCell({
    required this.course,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
  });

  final Course course;
  final Weekday weekday;
  final int startPeriod;
  final int endPeriod;

  int get periodCount => endPeriod - startPeriod + 1;

  String get periodLabel => startPeriod == endPeriod
      ? '第 $startPeriod 节'
      : '第 $startPeriod-$endPeriod 节';
}
