import 'package:flutter/material.dart';

import '../../models/weekday.dart';

/// 本周日期栏：周一至周日横向滚动，点击切换当前查看的星期。
class WeekDateBar extends StatelessWidget {
  const WeekDateBar({
    super.key,
    required this.dates,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  /// 本周 7 天的日期，从周一开始。
  final List<DateTime> dates;

  /// 当前选中的星期。
  final Weekday selected;

  /// 今天（只比较年月日），用于高亮「今天」。
  final DateTime today;

  final ValueChanged<Weekday> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: dates.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final DateTime date = dates[index];
          final Weekday day = Weekday.fromIsoIndex(date.weekday);
          return _DayChip(
            day: day,
            date: date,
            isSelected: day == selected,
            isToday: _isSameDate(date, today),
            onTap: () => onSelect(day),
          );
        },
      ),
    );
  }

  /// 只比较年月日，忽略时分秒。
  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final Weekday day;
  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color foreground = isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Material(
      color: isSelected
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                isToday ? '今天' : day.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: isSelected ? FontWeight.w600 : null,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '${date.day}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isSelected ? colorScheme.onPrimary : null,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
