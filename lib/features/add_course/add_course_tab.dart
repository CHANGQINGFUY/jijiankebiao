import 'package:flutter/material.dart';

import '../../core/constants/schedule_constants.dart';
import '../../core/theme/course_colors.dart';
import '../../models/course.dart';
import '../../models/period_slot.dart';
import '../../models/semester_config.dart';
import '../../models/week_range.dart';
import '../../models/weekday.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';
import '../../widgets/section_title.dart';

/// 添加 / 编辑课程页。
///
/// 传入 [editing] 时为编辑模式：表单预填原课程，保存后更新整门课（含所有星期）。
/// 传入 [initialWeekday] / [initialStartPeriod] 时从周课表空格快速添加。
class AddCourseTab extends StatefulWidget {
  const AddCourseTab({
    super.key,
    this.editing,
    this.onSaved,
    this.initialWeekday,
    this.initialStartPeriod,
  });

  final Course? editing;

  /// 保存成功后的回调：Tab 模式下切回课表，路由模式下关闭页面。
  final VoidCallback? onSaved;

  /// 快速添加时预选的星期。
  final Weekday? initialWeekday;

  /// 快速添加时预选的开始节次。
  final int? initialStartPeriod;

  @override
  State<AddCourseTab> createState() => _AddCourseTabState();
}

class _AddCourseTabState extends State<AddCourseTab> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _teacherController = TextEditingController();
  final TextEditingController _classController = TextEditingController();
  final TextEditingController _termController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  /// 选中的星期，支持多选。
  final Set<Weekday> _weekdays = <Weekday>{};

  int _startPeriod = 1;
  int _endPeriod = 2;
  int _startWeek = 1;
  int _endWeek = 20;

  /// 所属学期 id；为空表示跟随当前学期。
  String? _semesterId;

  /// 手动选择的配色种子；为空表示跟随「下一门课」的默认色。
  int? _colorSeed;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startWeek = 1;
    _endWeek = ScheduleConstants.totalWeeks;
    final Course? editing = widget.editing;
    if (editing != null) {
      _nameController.text = editing.name;
      _teacherController.text = editing.teacher;
      _locationController.text = editing.room;
      _classController.text = editing.className ?? '';
      _termController.text = editing.academicTerm;
      _noteController.text = editing.remark ?? '';
      _weekdays.addAll(editing.weekdays);
      _startPeriod = editing.startPeriod;
      _endPeriod = editing.endPeriod;
      _semesterId = editing.semesterId.isEmpty ? null : editing.semesterId;
      _startWeek = editing.weeks.start;
      _endWeek = editing.weeks.end;
      _colorSeed = editing.colorSeed;
    } else {
      _weekdays.add(widget.initialWeekday ?? Weekday.monday);
      if (widget.initialStartPeriod != null) {
        _startPeriod = widget.initialStartPeriod!;
        _endPeriod = widget.initialStartPeriod!;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _teacherController.dispose();
    _classController.dispose();
    _termController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit(ScheduleController controller) async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate() || _weekdays.isEmpty) {
      if (_weekdays.isEmpty) {
        setState(() {});
      }
      return;
    }

    final Course? editing = widget.editing;
    final int periodCount = controller.periods.length;
    final int totalWeeks = controller.totalWeeks;
    final int startPeriod = _startPeriod.clamp(1, periodCount);
    final int endPeriod = _endPeriod.clamp(startPeriod, periodCount);
    final int startWeek = _startWeek.clamp(1, totalWeeks);
    final int endWeek = _endWeek.clamp(startWeek, totalWeeks);
    final String semesterId =
        _semesterId != null &&
                controller.semesters
                    .any((SemesterConfig item) => item.id == _semesterId)
            ? _semesterId!
            : controller.currentSemesterId;
    final Course course = Course(
      id: editing?.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}',
      groupId: editing?.groupId,
      name: _nameController.text.trim(),
      teacher: _teacherController.text.trim(),
      room: _locationController.text.trim(),
      className: _classController.text.trim().isEmpty
          ? null
          : _classController.text.trim(),
      semesterId: semesterId,
      academicTerm: _termController.text.trim(),
      weekdays: Set<Weekday>.of(_weekdays),
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: WeekRange(start: startWeek, end: endWeek),
      colorSeed: _colorSeed ?? controller.nextColorSeed,
      remark: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      type: editing?.type ?? controller.role,
    );

    // 同一学期、同一星期、节次重叠时提示冲突，不静默覆盖。
    final List<Course> conflicts = controller.conflictsFor(course);
    if (conflicts.isNotEmpty) {
      final bool? proceed = await _askConflict(conflicts);
      if (proceed != true) {
        return;
      }
    }

    setState(() => _saving = true);

    if (widget.editing != null) {
      final String? apply = await _askApplyToGroupOrNull(controller, editing);
      if (apply == null || apply == 'cancelled') {
        if (mounted) {
          setState(() => _saving = false);
        }
        return;
      }
      await controller.updateCourse(course, applyToGroup: apply == 'group');
    } else {
      await controller.addCourse(course);
    }

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(editing == null ? '已添加课程「${course.name}」' : '已更新课程「${course.name}」')),
    );

    if (widget.onSaved != null) {
      widget.onSaved!();
      return;
    }
    // Tab 模式：保存后清空表单，便于继续录入。
    form.reset();
    _nameController.clear();
    _locationController.clear();
    _teacherController.clear();
    _classController.clear();
    _termController.clear();
    _noteController.clear();
    setState(() {
      _weekdays
        ..clear()
        ..add(Weekday.monday);
      _startPeriod = 1;
      _endPeriod = 2;
      _semesterId = null;
      _startWeek = 1;
      _endWeek = ScheduleConstants.totalWeeks;
      _colorSeed = null;
    });
  }

  /// 存在同组其它时段时询问修改范围；返回 group / one / cancelled。
  Future<String?> _askApplyToGroupOrNull(
    ScheduleController controller,
    Course? editing,
  ) {
    if (editing == null ||
        controller.groupMembers(editing.group).length <= 1) {
      return Future<String?>.value('one');
    }
    return _askApplyToGroup(editing.name);
  }

  /// 课程时间冲突确认框。
  Future<bool?> _askConflict(List<Course> conflicts) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final int shown = conflicts.length > 8 ? 8 : conflicts.length;
        return AlertDialog(
          title: const Text('课程时间冲突'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('同一学期、同星期的节次已有 ${conflicts.length} 门课程：'),
                const SizedBox(height: 8),
                for (int index = 0; index < shown; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '· ${conflicts[index].name}'
                      '（${conflicts[index].weekdayLabel} '
                      '${conflicts[index].periodLabel} '
                      '${conflicts[index].weeks.label}）',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                if (conflicts.length > shown)
                  Text('…… 还有 ${conflicts.length - shown} 门课程'),
                const SizedBox(height: 8),
                const Text('继续保存后两门课会同时显示在同一格，是否仍然保存？'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('返回修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('仍然保存'),
            ),
          ],
        );
      },
    );
  }

  /// 同组课程存在多个时段时，询问修改范围。
  Future<String?> _askApplyToGroup(String name) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('修改范围'),
        content: Text('「$name」还有其它时段的课程，本次修改应用到哪些课程？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('one'),
            child: const Text('只改这条'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('group'),
            child: const Text('全部改'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final ThemeData theme = Theme.of(context);
    final List<PeriodSlot> periods = controller.periods;
    final int periodCount = periods.length;
    final int startPeriod = _startPeriod.clamp(1, periodCount);
    final int endPeriod = _endPeriod.clamp(startPeriod, periodCount);
    final int totalWeeks = controller.totalWeeks;
    final int startWeek = _startWeek.clamp(1, totalWeeks);
    final int endWeek = _endWeek.clamp(startWeek, totalWeeks);
    final List<SemesterConfig> semesters = controller.semesters;
    final String selectedSemesterId =
        semesters.any((SemesterConfig item) => item.id == _semesterId)
            ? _semesterId!
            : controller.currentSemesterId;
    final int activeColorSeed =
        _colorSeed ?? controller.nextColorSeed % CourseColors.palette.length;
    final bool editing = widget.editing != null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Text(
            editing
                ? '正在编辑「${widget.editing!.name}」，修改会同步到这条课程的所有星期。'
                : '当前身份：${controller.role.label}，新增的课程只会出现在这一侧的课表里。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SectionTitle('课程信息'),
          TextFormField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '课程名',
              hintText: '如：高等数学',
              prefixIcon: Icon(Icons.menu_book_outlined),
            ),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? '请输入课程名' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _teacherController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '教师',
              hintText: '如：王老师',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? '请输入教师姓名' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _locationController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '教室',
              hintText: '如：教三楼 201',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? '请输入上课教室' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _classController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '班级（选填）',
              hintText: '如：计科 2301',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _termController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '学年学期（选填）',
              hintText: '如：2026-2027 第一学期',
              prefixIcon: Icon(Icons.school_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('semester-$selectedSemesterId'),
            initialValue: selectedSemesterId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '所属学期',
              prefixIcon: Icon(Icons.calendar_month_outlined),
            ),
            items: <DropdownMenuItem<String>>[
              for (final SemesterConfig semester in semesters)
                DropdownMenuItem<String>(
                  value: semester.id,
                  child: Text(
                    semester.id == controller.currentSemesterId
                        ? '${semester.name}（当前）'
                        : semester.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (String? value) =>
                setState(() => _semesterId = value),
          ),
          const SectionTitle('上课时间'),
          _WeekdayPicker(
            selected: _weekdays,
            onToggle: (Weekday day) {
              setState(() {
                if (!_weekdays.remove(day)) {
                  _weekdays.add(day);
                }
              });
            },
          ),
          if (_weekdays.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '请至少选择一个上课的星期',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey<String>('start-period-$startPeriod'),
                  initialValue: startPeriod,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '开始节次'),
                  items: _periodItems(periods),
                  validator: (int? value) {
                    if (value == null) {
                      return '请选择开始节次';
                    }
                    if (value > _endPeriod) {
                      return '开始节次不能大于结束节次';
                    }
                    return null;
                  },
                  onChanged: (int? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _startPeriod = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey<String>('end-period-$endPeriod'),
                  initialValue: endPeriod,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '结束节次'),
                  items: _periodItems(periods),
                  validator: (int? value) {
                    if (value == null) {
                      return '请选择结束节次';
                    }
                    if (value < _startPeriod) {
                      return '结束节次不能小于开始节次';
                    }
                    return null;
                  },
                  onChanged: (int? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _endPeriod = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${periods[startPeriod - 1].start} - ${periods[endPeriod - 1].end}'
            '（共 ${endPeriod - startPeriod + 1} 节）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SectionTitle('上课周次'),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey<String>('start-$startWeek'),
                  initialValue: startWeek,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '起始周'),
                  items: _weekItems(totalWeeks),
                  validator: (int? value) {
                    if (value == null) {
                      return '请选择起始周';
                    }
                    if (value > _endWeek) {
                      return '起始周不能大于结束周';
                    }
                    return null;
                  },
                  onChanged: (int? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _startWeek = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey<String>('end-$endWeek'),
                  initialValue: endWeek,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '结束周'),
                  items: _weekItems(totalWeeks),
                  validator: (int? value) {
                    if (value == null) {
                      return '请选择结束周';
                    }
                    if (value < _startWeek) {
                      return '结束周不能小于起始周';
                    }
                    return null;
                  },
                  onChanged: (int? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _endWeek = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '只要当前周次落在起始周和结束周之间，这门课就会在所选星期显示。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SectionTitle('课程颜色'),
          _ColorPicker(
            colors: CourseColors.palette,
            selected: activeColorSeed,
            onSelect: (int seed) => setState(() => _colorSeed = seed),
          ),
          const SectionTitle('备注'),
          TextFormField(
            controller: _noteController,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '如：记得带计算器 / 第 8 周交大作业',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : () => _submit(controller),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(
              _saving ? '保存中…' : (editing ? '保存修改' : '保存课程'),
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<int>> _periodItems(List<PeriodSlot> periods) =>
      <DropdownMenuItem<int>>[
        for (final PeriodSlot slot in periods)
          DropdownMenuItem<int>(
            value: slot.index,
            child: Text(
              '第 ${slot.index} 节 ${slot.start}-${slot.end}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ];

  List<DropdownMenuItem<int>> _weekItems(int totalWeeks) =>
      <DropdownMenuItem<int>>[
        for (int week = 1; week <= totalWeeks; week++)
          DropdownMenuItem<int>(
            value: week,
            child: Text('第 $week 周'),
          ),
      ];
}

/// 星期选择：横向一排按钮，可多选。
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onToggle});

  final Set<Weekday> selected;
  final ValueChanged<Weekday> onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        for (final Weekday day in Weekday.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _WeekdayButton(
                label: day.label.substring(1),
                selected: selected.contains(day),
                onTap: () => onToggle(day),
                theme: theme,
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekdayButton extends StatelessWidget {
  const _WeekdayButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 课程配色选择：一排圆形色块，选中显示对勾。
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        for (int i = 0; i < colors.length; i++)
          GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      i == selected ? theme.colorScheme.onSurface : Colors.transparent,
                  width: 2,
                ),
              ),
              child: i == selected
                  ? const Icon(Icons.check, size: 20, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}
