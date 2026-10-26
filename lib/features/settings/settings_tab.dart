import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/schedule/week_calculator.dart';
import '../../data/schedule_backup.dart';
import '../../models/day_override.dart';
import '../../models/period_slot.dart';
import '../../models/semester_config.dart';
import '../../models/user_role.dart';
import '../../services/backup_file_service.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';
import '../academic/academic_probe_page.dart';
import '../import_excel/excel_import_models.dart';
import '../import_excel/excel_import_page.dart';
import '../import_excel/excel_timetable_parser.dart';

/// 设置页：身份、学期与周次、日期覆盖、主题。
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _Section(
          title: '身份',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SegmentedButton<UserRole>(
                segments: <ButtonSegment<UserRole>>[
                  for (final UserRole role in UserRole.values)
                    ButtonSegment<UserRole>(
                      value: role,
                      label: Text(role.label),
                    ),
                ],
                selected: <UserRole>{controller.role},
                onSelectionChanged: (Set<UserRole> selection) {
                  controller.switchRole(selection.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                '首页会随身份切换视图：${controller.role.description}。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _Section(
          title: '学期管理',
          child: _SemesterSection(controller: controller),
        ),
        _Section(
          title: '当前学期设置',
          child: Column(
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('学期名称'),
                subtitle: Text(controller.config.name),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _renameSemester(context, controller),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开学第一天'),
                subtitle: Text(_formatDate(controller.config.startDate)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () => _pickStartDate(context, controller),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('总周数'),
                subtitle: Text('共 ${controller.totalWeeks} 周'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editTotalWeeks(context, controller),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('每天节次时间'),
                subtitle: Text(
                  '第 1 节 ${controller.periods.first.start} 起，'
                  '共 ${controller.periods.length} 节',
                ),
                trailing: const Icon(Icons.schedule),
                onTap: () => _editPeriods(context, controller),
              ),
              const Divider(height: 20),
              _WeekSection(controller: controller),
            ],
          ),
        ),
        _Section(
          title: '日期覆盖（放假 / 调课）',
          child: _OverrideSection(controller: controller),
        ),
        _Section(
          title: '数据',
          child: Column(
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('导出为 JSON'),
                subtitle: const Text('保存到手机「下载」目录'),
                onTap: () => _exportData(context, controller),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: const Text('从 JSON 导入'),
                subtitle: const Text('导入前可选择覆盖或合并'),
                onTap: () => _importData(context, controller),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('从 Excel 导入课表'),
                subtitle: const Text('选择 .xlsx 文件，自动识别表头'),
                onTap: () => _importExcel(context, controller),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.school_outlined),
                title: const Text('从教务系统导入'),
                subtitle: const Text('网页登录教务系统后探测并导入课表'),
                onTap: () => _openAcademicImport(context),
              ),
            ],
          ),
        ),
        _Section(
          title: '主题',
          child: SegmentedButton<ThemeMode>(
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('跟随系统'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('浅色'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('深色'),
              ),
            ],
            selected: <ThemeMode>{controller.themeMode},
            onSelectionChanged: (Set<ThemeMode> selection) {
              controller.updateThemeMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '所有数据仅保存在本机，不会上传服务器。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// 弹窗关闭动画期间仍会重建输入框，立即 dispose 会触发
  /// 「TextEditingController was used after being disposed」，因此延后释放。
  static void _releaseControllers(List<TextEditingController> controllers) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        for (final TextEditingController controller in controllers) {
          controller.dispose();
        }
      });
    });
  }

  Future<void> _renameSemester(
    BuildContext context,
    ScheduleController controller,
  ) async {
    final TextEditingController input =
        TextEditingController(text: controller.config.name);
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('学期名称'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如：2026-2027 第一学期',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final String text = input.text.trim();
              if (text.isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop(text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    _releaseControllers(<TextEditingController>[input]);
    if (value == null) {
      return;
    }
    await controller.renameSemester(value);
  }

  /// 导出全部数据到手机「下载」目录。
  Future<void> _exportData(
    BuildContext context,
    ScheduleController controller,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final String json = controller.exportBackup();
      final DateTime now = DateTime.now();
      final String fileName = 'schedule_backup_${now.year}'
          '${_two(now.month)}${_two(now.day)}_'
          '${_two(now.hour)}${_two(now.minute)}.json';
      final String path = await BackupFileService.exportJson(
        json: json,
        fileName: fileName,
      );
      messenger.showSnackBar(SnackBar(content: Text('已导出到 $path')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  /// 选择 JSON 文件导入，先校验格式，再询问覆盖或合并。
  Future<void> _importData(
    BuildContext context,
    ScheduleController controller,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    String? raw;
    try {
      raw = await BackupFileService.pickJson();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('无法打开文件选择器：$error')));
      return;
    }
    if (raw == null) {
      return;
    }

    BackupPreview preview;
    try {
      preview = controller.previewImport(raw);
    } on FormatException catch (error) {
      if (context.mounted) {
        await _showImportError(context, error.message);
      }
      return;
    } catch (error) {
      if (context.mounted) {
        await _showImportError(context, '$error');
      }
      return;
    }

    if (!context.mounted) {
      return;
    }
    final String? mode = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('导入方式'),
        content: Text(
          '该文件包含 ${preview.semesterCount} 个学期、'
          '${preview.courseCount} 门课程、'
          '${preview.overrideCount} 条日期覆盖。\n\n'
          '覆盖：清空现有数据后完全写入文件内容。\n'
          '合并：保留现有数据，只补充文件里的新条目。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('merge'),
            child: const Text('合并'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('overwrite'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    if (mode == null) {
      return;
    }

    try {
      final ImportSummary summary = await controller.importBackup(
        raw,
        overwrite: mode == 'overwrite',
      );
      messenger.showSnackBar(SnackBar(content: Text(summary.message)));
    } on FormatException catch (error) {
      if (context.mounted) {
        await _showImportError(context, error.message);
      }
    } catch (error) {
      if (context.mounted) {
        await _showImportError(context, '$error');
      }
    }
  }

  Future<void> _showImportError(BuildContext context, String message) async {
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('导入失败'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 选择 .xlsx 文件，解析后进入导入预览页。
  Future<void> _importExcel(
    BuildContext context,
    ScheduleController controller,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    String fileName = '';
    List<int> bytes;
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        dialogTitle: '选择课表 Excel',
        type: FileType.custom,
        allowedExtensions: <String>['xlsx'],
      );
      if (files.isEmpty) {
        return;
      }
      final PlatformFile file = files.first;
      fileName = file.name;
      bytes = await file.readAsBytes();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('无法打开文件选择器：$error')));
      return;
    }
    ExcelParseResult parsed;
    try {
      parsed = ExcelTimetableParser.parse(
        bytes: bytes,
        semesterId: controller.currentSemesterId,
        type: controller.role,
        colorBase: controller.nextColorSeed,
        periodLimit: controller.periods.length,
        weekLimit: controller.totalWeeks,
      );
    } on FormatException catch (error) {
      if (context.mounted) {
        await _showImportError(context, error.message);
      }
      return;
    } catch (error) {
      if (context.mounted) {
        await _showImportError(context, '$error');
      }
      return;
    }

    if (!context.mounted) {
      return;
    }
    if (parsed.drafts.isEmpty) {
      await _showImportError(
        context,
        parsed.errors.isEmpty
            ? '这个工作表里没有可导入的课程。'
            : '所有行都无法解析，共 ${parsed.errors.length} 行出错：\n\n'
                '${parsed.errors.take(8).map((ExcelRowError e) => e.label).join('\n')}',
      );
      return;
    }
    if (parsed.errors.isNotEmpty) {
      final bool? proceed = await _showParseErrors(context, parsed);
      if (proceed != true || !context.mounted) {
        return;
      }
    }

    final bool? imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext routeContext) => CourseImportPreviewPage(
          drafts: parsed.drafts,
          warnings: parsed.warnings,
          errors: parsed.errors,
          sourceLabel: fileName,
        ),
      ),
    );
    if (imported == true && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('课表已导入，建议检查开学日期与节次时间。')),
      );
    }
  }

  /// 打开教务系统导入页（适配器与学校列表都在该页内完成选择）。
  Future<void> _openAcademicImport(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => const AcademicProbePage(),
      ),
    );
  }

  /// 展示无法解析的行，用户可选择取消或继续预览其余行。
  Future<bool?> _showParseErrors(
    BuildContext context,
    ExcelParseResult parsed,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('部分行无法解析'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '共 ${parsed.totalRows} 行，成功 ${parsed.drafts.length} 行，'
                '失败 ${parsed.errors.length} 行。失败行会被跳过：',
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: parsed.errors.length,
                  itemBuilder: (BuildContext itemContext, int index) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      parsed.errors[index].label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续预览'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStartDate(
    BuildContext context,
    ScheduleController controller,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: controller.config.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择开学第一天（可以是任意星期）',
    );
    if (picked == null) {
      return;
    }
    await controller.updateConfig(
      controller.config.copyWith(startDate: picked),
    );
  }

  Future<void> _editTotalWeeks(
    BuildContext context,
    ScheduleController controller,
  ) async {
    final TextEditingController input =
        TextEditingController(text: '${controller.totalWeeks}');
    final int? value = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('总周数'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '周数（1-40）'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(input.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    _releaseControllers(<TextEditingController>[input]);
    if (value == null || value < 1) {
      return;
    }
    final int total = value.clamp(1, 40);
    await controller.updateConfig(
      controller.config.copyWith(
        totalWeeks: total,
        manualWeek: controller.config.manualWeek.clamp(1, total),
      ),
    );
  }

  Future<void> _editPeriods(
    BuildContext context,
    ScheduleController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                Text(
                  '每天节次时间',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final PeriodSlot slot in controller.periods)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('第 ${slot.index} 节'),
                    subtitle: Text(slot.range),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () async {
                      final PeriodSlot? updated =
                          await _editSlot(context, slot);
                      if (updated == null) {
                        return;
                      }
                      final List<PeriodSlot> periods = <PeriodSlot>[
                        for (final PeriodSlot item in controller.periods)
                          if (item.index == updated.index) updated else item,
                      ];
                      await controller.updateConfig(
                        controller.config.copyWith(periods: periods),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<PeriodSlot?> _editSlot(BuildContext context, PeriodSlot slot) async {
    final TextEditingController start =
        TextEditingController(text: slot.start);
    final TextEditingController end = TextEditingController(text: slot.end);
    final PeriodSlot? result = await showDialog<PeriodSlot>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('第 ${slot.index} 节'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: start,
              decoration: const InputDecoration(labelText: '开始时间 HH:mm'),
            ),
            TextField(
              controller: end,
              decoration: const InputDecoration(labelText: '结束时间 HH:mm'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!_isValidTime(start.text) || !_isValidTime(end.text)) {
                return;
              }
              Navigator.of(context).pop(
                PeriodSlot(
                  index: slot.index,
                  start: start.text.trim(),
                  end: end.text.trim(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    _releaseControllers(<TextEditingController>[start, end]);
    return result;
  }

  static bool _isValidTime(String value) =>
      RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value.trim());
}

/// 周次区域：显示自动/手动来源，支持手动修正与恢复自动。
class _WeekSection extends StatelessWidget {
  const _WeekSection({required this.controller});

  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WeekStatus status = controller.weekStatus;
    final bool manual = controller.weekSource == WeekSource.manual;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                manual
                    ? '当前周次：第 ${controller.currentWeek} 周（手动）'
                    : '当前周次：${status.isInTerm ? '第 ${status.week} 周' : status.label}（自动）',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              manual ? '手动' : '自动',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('手动修正周次'),
          subtitle: const Text('开启后以手动周次为准，关闭后恢复自动计算'),
          value: manual,
          onChanged: (bool value) => controller.setManualWeekEnabled(value),
        ),
        if (manual)
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: controller.currentWeek.toDouble(),
                  min: 1,
                  max: controller.totalWeeks.toDouble(),
                  divisions: controller.totalWeeks > 1
                      ? controller.totalWeeks - 1
                      : null,
                  label: '第 ${controller.currentWeek} 周',
                  onChanged: (double value) =>
                      controller.setManualWeek(value.round()),
                ),
              ),
              Text('第 ${controller.currentWeek} 周'),
            ],
          ),
        if (manual)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.resetToAutoWeek,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('恢复自动计算'),
            ),
          ),
        Text(
          '开学日 ${_dateText(controller.config.startDate)}，'
          '第一周周一 ${_dateText(controller.config.firstMonday)}；'
          '自动计算只比较年月日，使用本地时区。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _dateText(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

/// 日期覆盖列表：按具体日期生效的放假 / 调课。
class _OverrideSection extends StatelessWidget {
  const _OverrideSection({required this.controller});

  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final List<DayOverride> overrides = controller.overrides.toList()
      ..sort((DayOverride a, DayOverride b) => a.date.compareTo(b.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (overrides.isEmpty)
          Text(
            '还没有日期覆盖。可以给某天放假，或把某天的课替换成另一门课。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (final DayOverride item in overrides)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              item.isHoliday ? Icons.beach_access_outlined : Icons.swap_horiz,
            ),
            title: Text(DayOverride.dateKey(item.date)),
            subtitle: Text(item.summary),
            trailing: IconButton(
              tooltip: '删除覆盖，恢复常规课表',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => controller.removeOverride(item.date),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addOverride(context, controller),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加日期覆盖'),
          ),
        ),
      ],
    );
  }

  Future<void> _addOverride(
    BuildContext context,
    ScheduleController controller,
  ) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择要覆盖的日期',
    );
    if (date == null || !context.mounted) {
      return;
    }

    DayOverrideKind kind = DayOverrideKind.holiday;
    final TextEditingController name = TextEditingController();
    final TextEditingController room = TextEditingController();
    final TextEditingController teacher = TextEditingController();
    int startPeriod = 1;
    int endPeriod = 2;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('${DayOverride.dateKey(date)} 的安排'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SegmentedButton<DayOverrideKind>(
                      segments: const <ButtonSegment<DayOverrideKind>>[
                        ButtonSegment<DayOverrideKind>(
                          value: DayOverrideKind.holiday,
                          label: Text('放假'),
                        ),
                        ButtonSegment<DayOverrideKind>(
                          value: DayOverrideKind.replacement,
                          label: Text('调课'),
                        ),
                      ],
                      selected: <DayOverrideKind>{kind},
                      onSelectionChanged: (Set<DayOverrideKind> selection) {
                        setState(() => kind = selection.first);
                      },
                    ),
                    if (kind == DayOverrideKind.replacement) ...<Widget>[
                      TextField(
                        controller: name,
                        decoration:
                            const InputDecoration(labelText: '课程名（替换成）'),
                      ),
                      TextField(
                        controller: room,
                        decoration: const InputDecoration(labelText: '教室'),
                      ),
                      TextField(
                        controller: teacher,
                        decoration: const InputDecoration(labelText: '教师'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: startPeriod,
                              decoration:
                                  const InputDecoration(labelText: '开始节次'),
                              items: _periodItems(controller),
                              onChanged: (int? value) {
                                if (value != null) {
                                  setState(() => startPeriod = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: endPeriod,
                              decoration:
                                  const InputDecoration(labelText: '结束节次'),
                              items: _periodItems(controller),
                              onChanged: (int? value) {
                                if (value != null) {
                                  setState(() => endPeriod = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      SettingsTab._releaseControllers(
        <TextEditingController>[name, room, teacher],
      );
      return;
    }

    await controller.saveOverride(
      DayOverride(
        date: date,
        kind: kind,
        courseName: kind == DayOverrideKind.replacement ? name.text.trim() : null,
        room: kind == DayOverrideKind.replacement ? room.text.trim() : null,
        teacher:
            kind == DayOverrideKind.replacement ? teacher.text.trim() : null,
        startPeriod: kind == DayOverrideKind.replacement ? startPeriod : null,
        endPeriod: kind == DayOverrideKind.replacement ? endPeriod : null,
      ),
    );
    SettingsTab._releaseControllers(
      <TextEditingController>[name, room, teacher],
    );
  }

  static List<DropdownMenuItem<int>> _periodItems(ScheduleController controller) {
    return <DropdownMenuItem<int>>[
      for (final PeriodSlot slot in controller.periods)
        DropdownMenuItem<int>(
          value: slot.index,
          child: Text('第 ${slot.index} 节'),
        ),
    ];
  }
}

/// 学期列表：展示全部学期，支持切换与新建。
class _SemesterSection extends StatelessWidget {
  const _SemesterSection({required this.controller});

  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final SemesterConfig semester in controller.semesters)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              semester.id == controller.currentSemesterId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: semester.id == controller.currentSemesterId
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(semester.name),
            subtitle: Text(
              '开学 ${_dateText(semester.startDate)} · 共 ${semester.totalWeeks} 周',
            ),
            trailing: semester.id == controller.currentSemesterId
                ? Chip(
                    label: Text(
                      '当前',
                      style: theme.textTheme.labelSmall,
                    ),
                  )
                : TextButton(
                    onPressed: () => controller.switchSemester(semester.id),
                    child: const Text('切换'),
                  ),
            onTap: semester.id == controller.currentSemesterId
                ? null
                : () => controller.switchSemester(semester.id),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _createSemester(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建学期'),
          ),
        ),
        Text(
          '切换学期后，今日页与周课表都会跟随；课程、节次表、手动周次互不影响。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _createSemester(BuildContext context) async {
    final TextEditingController name =
        TextEditingController(text: '新学期待命名');
    final TextEditingController weeks =
        TextEditingController(text: '${controller.totalWeeks}');
    DateTime startDate = DateTime.now();
    String? error;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext dialogContext, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('新建学期'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '学期名称',
                        hintText: '如：2026-2027 第一学期',
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开学第一天'),
                      subtitle: Text(_dateText(startDate)),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: startDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          helpText: '选择开学第一天（可以是任意星期）',
                        );
                        if (picked != null) {
                          setDialogState(() => startDate = picked);
                        }
                      },
                    ),
                    TextField(
                      controller: weeks,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '总周数（1-60）',
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final String trimmed = name.text.trim();
                    final int? total = int.tryParse(weeks.text.trim());
                    if (trimmed.isEmpty) {
                      setDialogState(() => error = '请输入学期名称');
                      return;
                    }
                    if (total == null || total < 1 || total > 60) {
                      setDialogState(() => error = '总周数需在 1-60 之间');
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('创建并切换'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      await controller.createSemester(
        name: name.text.trim(),
        startDate: startDate,
        totalWeeks: int.tryParse(weeks.text.trim()) ?? controller.totalWeeks,
      );
    }
    SettingsTab._releaseControllers(
      <TextEditingController>[name, weeks],
    );
  }

  static String _dateText(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
