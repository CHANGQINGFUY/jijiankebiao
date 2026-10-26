/// 周次范围（含端点），如第 1 周至第 16 周。
class WeekRange {
  const WeekRange({required this.start, required this.end})
      : assert(start >= 1, '起始周次必须从 1 开始'),
        assert(end >= start, '结束周次不能小于起始周次');

  final int start;
  final int end;

  /// [week] 是否落在范围内。
  bool contains(int week) => week >= start && week <= end;

  String get label => start == end ? '第 $start 周' : '第 $start-$end 周';

  Map<String, Object?> toJson() => <String, Object?>{'start': start, 'end': end};

  factory WeekRange.fromJson(Map<String, Object?> json) => WeekRange(
        start: json['start']! as int,
        end: json['end']! as int,
      );
}
