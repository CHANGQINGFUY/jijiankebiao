import 'weekday.dart';

/// 从周课表空格进入添加页时携带的预填信息。
class NewCourseRequest {
  const NewCourseRequest({this.weekday, this.startPeriod});

  /// 预选星期。
  final Weekday? weekday;

  /// 预选开始节次。
  final int? startPeriod;
}
