import 'dart:async';

import 'package:flutter/material.dart';

import '../core/schedule/day_schedule_resolver.dart';
import '../state/schedule_controller.dart';
import '../state/schedule_scope.dart';

/// 首页顶部的今日概览：当前周次（自动/手动）、下一节课与倒计时、放假/没课提示。
class TodayOverviewCard extends StatefulWidget {
  const TodayOverviewCard({super.key});

  @override
  State<TodayOverviewCard> createState() => _TodayOverviewCardState();
}

class _TodayOverviewCardState extends State<TodayOverviewCard> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // 每分钟刷新一次倒计时。
    _timer = Timer.periodic(const Duration(minutes: 1), (Timer timer) {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final ThemeData theme = Theme.of(context);
    final DaySchedule schedule = controller.todaySchedule(now: _now);
    final bool outOfTerm = schedule.status.isBeforeStart ||
        schedule.status.isAfterEnd;
    final bool manual = controller.weekSource == WeekSource.manual;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${controller.weekText} · ${schedule.weekday.label}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!outOfTerm)
                  IconButton(
                    tooltip: schedule.isHoliday ? '取消放假' : '把今天设为放假',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        controller.toggleHoliday(schedule.date),
                    icon: Icon(
                      schedule.isHoliday
                          ? Icons.event_available
                          : Icons.event_busy,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (outOfTerm && !manual)
              Text(
                schedule.status.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._buildBody(context, controller, schedule),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    ScheduleController controller,
    DaySchedule schedule,
  ) {
    final ThemeData theme = Theme.of(context);

    if (schedule.isHoliday) {
      return <Widget>[
        _Headline(
          icon: Icons.beach_access_outlined,
          title: '今天放假',
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Text(
          '当天的常规课程已全部取消，删除日期覆盖即可恢复。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    if (schedule.classes.isEmpty) {
      return <Widget>[
        _Headline(
          icon: Icons.free_breakfast_outlined,
          title: '今天没有课',
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Text(
          '好好休息，或者去「添加」里排一门新课。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    final DayClass? ongoing = schedule.ongoing;
    if (ongoing != null) {
      final int minutes = ongoing.end.difference(_now).inSeconds ~/ 60 + 1;
      return <Widget>[
        _Headline(
          icon: Icons.play_circle_outline,
          title: '正在上课 · ${ongoing.name}',
          color: theme.colorScheme.primary,
        ),
        Text(
          '${ongoing.room} · ${ongoing.periodLabel} · 还有 $minutes 分钟下课',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    final DayClass? next = schedule.next;
    if (next != null) {
      final int minutes = next.minutesUntil(_now);
      final String countdown =
          minutes <= 0 ? '即将上课' : '还有 $minutes 分钟上课';
      return <Widget>[
        _Headline(
          icon: Icons.schedule,
          title: '下一节 · ${next.name}',
          color: theme.colorScheme.primary,
        ),
        Text(
          '${next.room.isEmpty ? '教室待定' : next.room} · '
          '${next.periodLabel} · ${_hhmm(next.start)} 开始',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Text(
              countdown,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (next.isOverride) ...<Widget>[
              const SizedBox(width: 8),
              _Tag(text: '调课', color: theme.colorScheme.tertiary),
            ],
          ],
        ),
      ];
    }

    return <Widget>[
      _Headline(
        icon: Icons.nightlight_outlined,
        title: '今天课程已结束',
        color: theme.colorScheme.onSurfaceVariant,
      ),
      Text(
        '共 ${schedule.classes.length} 节课，辛苦了。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  static String _hhmm(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.icon, required this.title, required this.color});

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
