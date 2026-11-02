/// 一天中的一节课（节次 + 起止时间）。
class PeriodSlot {
  const PeriodSlot({
    required this.index,
    required this.start,
    required this.end,
  });

  /// 第几节课，从 1 开始。
  final int index;

  /// 开始时间，格式 HH:mm。
  final String start;

  /// 结束时间，格式 HH:mm。
  final String end;

  /// 形如「08:00 - 08:45」。
  String get range => '$start - $end';

  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'start': start,
        'end': end,
      };

  factory PeriodSlot.fromJson(Map<String, Object?> json) => PeriodSlot(
        index: (json['index'] as int?) ?? 0,
        start: (json['start'] as String?) ?? '08:00',
        end: (json['end'] as String?) ?? '08:45',
      );
}
