/// 一周中的星期。课表按周循环，因此这里只保留星期维度。
enum Weekday {
  monday('周一', 1),
  tuesday('周二', 2),
  wednesday('周三', 3),
  thursday('周四', 4),
  friday('周五', 5),
  saturday('周六', 6),
  sunday('周日', 7);

  const Weekday(this.label, this.isoIndex);

  /// 显示用文案，如「周一」。
  final String label;

  /// ISO 8601 中的序号，周一为 1、周日为 7。
  final int isoIndex;

  static Weekday fromIsoIndex(int isoIndex) =>
      Weekday.values.firstWhere((day) => day.isoIndex == isoIndex);

  /// 周一到周五，周视图默认展示的工作日。
  static List<Weekday> get weekdays =>
      Weekday.values.where((day) => day.isoIndex <= 5).toList();
}
