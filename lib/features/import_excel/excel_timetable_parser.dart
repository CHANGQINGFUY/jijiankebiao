import 'package:justkawal_excel_updated/justkawal_excel_updated.dart';

import '../../core/theme/course_colors.dart';
import '../../models/course.dart';
import '../../models/user_role.dart';
import '../../models/week_range.dart';
import '../../models/weekday.dart';
import 'excel_import_models.dart';

/// 解析 Excel 课表。
///
/// - 自动在表格前 20 行内寻找表头（不区分大小写、空格与全角字符）；
/// - 支持「课程名/教师/教室/星期/节次/开始节次/结束节次/起始周/结束周/周次」等列名；
/// - 周次只支持连续区间，遇到单双周或断续周次时取并集范围并提示用户确认；
/// - 单行出错只记录行号与原因，不影响其它行导入。
class ExcelTimetableParser {
  const ExcelTimetableParser._();

  static const int _headerScanRows = 20;

  static ExcelParseResult parse({
    required List<int> bytes,
    required String semesterId,
    required UserRole type,
    int colorBase = 0,
    int periodLimit = 0,
    int weekLimit = 0,
  }) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        '不是有效的 .xlsx 文件。请用 Excel 打开后另存为 .xlsx 再试。',
      );
    }

    final Map<String, Sheet> tables = excel.tables;
    if (tables.isEmpty) {
      throw const FormatException('Excel 中没有可读取的工作表。');
    }
    final Sheet sheet = tables.values.first;
    final List<List<String>> grid = <List<String>>[
      for (final List<Data?> row in sheet.rows)
        <String>[for (final Data? cell in row) _cellText(cell)],
    ];

    _Header? header;
    for (int index = 0;
        index < grid.length && index < _headerScanRows;
        index++) {
      final _Header? candidate = _detectHeader(grid[index], index);
      if (candidate != null) {
        header = candidate;
        break;
      }
    }
    if (header == null) {
      throw const FormatException(
        '未找到可识别的表头行。请确保表头包含「课程名」以及「星期/节次/周次」等列名'
        '（列名不区分大小写和空格）。',
      );
    }

    final List<Course> drafts = <Course>[];
    final List<ExcelRowError> errors = <ExcelRowError>[];
    final List<String> warnings = <String>[];
    final Map<String, int> colorSeeds = <String, int>{};
    final Set<String> warnedMessages = <String>{};
    final int stamp = DateTime.now().microsecondsSinceEpoch;
    int totalRows = 0;

    for (int index = header.row + 1; index < grid.length; index++) {
      final List<String> row = grid[index];
      if (row.every((String cell) => cell.isEmpty)) {
        continue;
      }
      totalRows++;
      final int rowNumber = index + 1;

      final String name = header.cell(row, _Column.name).trim();
      if (name.isEmpty) {
        errors.add(ExcelRowError(rowNumber: rowNumber, reason: '课程名不能为空'));
        continue;
      }

      final String weekdayText = header.cell(row, _Column.weekday).trim();
      final Set<Weekday>? weekdays = _parseWeekdays(weekdayText);
      if (weekdays == null) {
        errors.add(
          ExcelRowError(
            rowNumber: rowNumber,
            reason: weekdayText.isEmpty
                ? '缺少星期（应为 1-7 或 周一~周日）'
                : '无法识别的星期「$weekdayText」（应为 1-7 或 周一~周日）',
          ),
        );
        continue;
      }

      final _PeriodParse? period = _parsePeriods(header, row);
      if (period == null) {
        errors.add(
          ExcelRowError(
            rowNumber: rowNumber,
            reason: '无法识别的节次「${header.cell(row, _Column.period)}」'
                '（可为 3、3-4、第3-4节，或使用开始/结束节次列）',
          ),
        );
        continue;
      }
      if (period.start < 1 || period.end < 1) {
        errors.add(
          ExcelRowError(rowNumber: rowNumber, reason: '节次必须为正整数'),
        );
        continue;
      }
      if (period.end < period.start) {
        errors.add(
          ExcelRowError(
            rowNumber: rowNumber,
            reason: '结束节次（${period.end}）不能小于开始节次（${period.start}）',
          ),
        );
        continue;
      }

      final _WeekParse? week = _parseWeeks(header, row);
      if (week == null) {
        errors.add(
          ExcelRowError(
            rowNumber: rowNumber,
            reason: '无法识别周次「${header.cell(row, _Column.weeks)}」'
                '（可为 1-16、1-16周、1,3,5周，或使用起始/结束周列）',
          ),
        );
        continue;
      }
      if (week.start < 1) {
        errors.add(
          ExcelRowError(rowNumber: rowNumber, reason: '起始周必须为正整数'),
        );
        continue;
      }
      if (week.end < week.start) {
        errors.add(
          ExcelRowError(
            rowNumber: rowNumber,
            reason: '结束周（${week.end}）不能小于起始周（${week.start}）',
          ),
        );
        continue;
      }

      if (week.warning != null &&
          warnedMessages.add('$name|${week.warning}')) {
        warnings.add('《$name》：${week.warning}');
      }
      if (periodLimit > 0 &&
          period.end > periodLimit &&
          warnedMessages.add('$name|period')) {
        warnings.add(
          '《$name》：节次 ${period.start}-${period.end} 超出当前学期作息'
          '（共 $periodLimit 节），请到「设置 → 当前学期设置」补全节次时间。',
        );
      }
      if (weekLimit > 0 &&
          week.end > weekLimit &&
          warnedMessages.add('$name|week')) {
        warnings.add(
          '《$name》：周次 ${week.start}-${week.end} 超出当前学期总周数'
          '（$weekLimit 周），导入后可能不显示，可在学期设置中调整总周数。',
        );
      }

      final String teacher = header.cell(row, _Column.teacher).trim();
      final String room = header.cell(row, _Column.room).trim();
      final String className = header.cell(row, _Column.className).trim();
      final int seed = colorSeeds.putIfAbsent(
        name,
        () => (colorBase + colorSeeds.length) % CourseColors.palette.length,
      );

      drafts.add(
        Course(
          id: 'xlsx-$stamp-$index',
          name: name,
          teacher: teacher,
          room: room,
          className: className.isEmpty ? null : className,
          semesterId: semesterId,
          weekdays: weekdays,
          startPeriod: period.start,
          endPeriod: period.end,
          weeks: WeekRange(start: week.start, end: week.end),
          colorSeed: seed,
          type: type,
        ),
      );
    }

    return ExcelParseResult(
      drafts: drafts,
      errors: errors,
      warnings: warnings,
      totalRows: totalRows,
      headerRow: header.row + 1,
    );
  }

  // ---------------------------------------------------------------- 表头

  static _Header? _detectHeader(List<String> cells, int rowIndex) {
    final Map<_Column, int> mapping = <_Column, int>{};
    // 第一轮：列名完全匹配。
    for (int index = 0; index < cells.length; index++) {
      final String normalized = _normalizeHeader(cells[index]);
      if (normalized.isEmpty) {
        continue;
      }
      for (final _Column column in _Column.values) {
        if (mapping.containsKey(column)) {
          continue;
        }
        final List<String> aliases = _aliases[column]!;
        if (aliases.any((String alias) => alias == normalized)) {
          mapping[column] = index;
          break;
        }
      }
    }
    // 第二轮：列名包含别名（如「上课星期」），补全未识别的列。
    for (int index = 0; index < cells.length; index++) {
      if (mapping.containsValue(index)) {
        continue;
      }
      final String normalized = _normalizeHeader(cells[index]);
      if (normalized.length < 2) {
        continue;
      }
      for (final _Column column in _Column.values) {
        if (mapping.containsKey(column)) {
          continue;
        }
        final List<String> aliases = _aliases[column]!;
        if (aliases.any(
          (String alias) => alias.length >= 2 && normalized.contains(alias),
        )) {
          mapping[column] = index;
          break;
        }
      }
    }

    if (!mapping.containsKey(_Column.name)) {
      return null;
    }
    final bool hasScheduleInfo = mapping.containsKey(_Column.weekday) ||
        mapping.containsKey(_Column.period) ||
        mapping.containsKey(_Column.startPeriod) ||
        mapping.containsKey(_Column.weeks) ||
        mapping.containsKey(_Column.startWeek);
    if (!hasScheduleInfo) {
      return null;
    }
    return _Header(mapping, rowIndex);
  }

  static String _normalizeHeader(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\u3000]+'), '')
        .replaceAll(RegExp(r'[（(【\[].*?[)）】\]]'), '')
        .replaceAll(RegExp(r'[:：]'), '')
        .trim();
  }

  static const Map<_Column, List<String>> _aliases = <_Column, List<String>>{
    _Column.name: <String>['课程名', '课程名称', '课名', '课程', 'coursename'],
    _Column.teacher: <String>['教师', '老师', '任课教师', '授课教师', '教师姓名', 'teacher'],
    _Column.room: <String>['教室', '地点', '上课地点', '上课教室', 'room', 'location'],
    _Column.className: <String>['班级', '教学班', '上课班级', 'class'],
    _Column.weekday: <String>['星期', '周几', '星期几', '上课星期', '上课日', 'weekday'],
    _Column.startPeriod: <String>[
      '开始节次',
      '起始节次',
      '开始节',
      '起始节',
      'startperiod',
    ],
    _Column.endPeriod: <String>[
      '结束节次',
      '终止节次',
      '结束节',
      '终止节',
      'endperiod',
    ],
    _Column.startWeek: <String>[
      '起始周',
      '开始周',
      '起始周次',
      '开始周次',
      'startweek',
    ],
    _Column.endWeek: <String>[
      '结束周',
      '终止周',
      '结束周次',
      '终止周次',
      'endweek',
    ],
    _Column.weeks: <String>['周次', '上课周次', '周', 'weeks'],
    _Column.period: <String>[
      '节次',
      '第几节',
      '节',
      '上课节次',
      '节数',
      'period',
      'section',
    ],
  };

  // ---------------------------------------------------------------- 单元格

  static String _cellText(Data? data) {
    final CellValue? value = data?.value;
    if (value == null) {
      return '';
    }
    if (value is TextCellValue) {
      return value.value.toString().trim();
    }
    if (value is IntCellValue) {
      return value.value.toString();
    }
    if (value is DoubleCellValue) {
      final double number = value.value;
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toString();
    }
    return value.toString().trim();
  }

  static int? _parseInt(String raw) => int.tryParse(raw.trim());

  static List<int> _numbersIn(String raw) {
    return <int>[
      for (final RegExpMatch match in RegExp(r'\d+').allMatches(raw))
        int.parse(match.group(0)!),
    ];
  }

  // ---------------------------------------------------------------- 字段

  static Set<Weekday>? _parseWeekdays(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    final String text = raw.replaceAll(RegExp(r'[，,、/;；\s]+'), ',');
    final Set<Weekday> result = <Weekday>{};
    for (final String part in text.split(',')) {
      final String value = part
          .replaceAll('星期', '')
          .replaceAll('礼拜', '')
          .replaceAll('周', '')
          .trim();
      if (value.isEmpty) {
        continue;
      }
      final int? number = int.tryParse(value);
      if (number != null) {
        if (number < 1 || number > 7) {
          return null;
        }
        result.add(Weekday.fromIsoIndex(number));
        continue;
      }
      final int? index = _weekdayNames[value];
      if (index == null) {
        return null;
      }
      result.add(Weekday.fromIsoIndex(index));
    }
    return result.isEmpty ? null : result;
  }

  static const Map<String, int> _weekdayNames = <String, int>{
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
  };

  static _PeriodParse? _parsePeriods(_Header header, List<String> row) {
    final bool hasStart = header.has(_Column.startPeriod);
    final bool hasEnd = header.has(_Column.endPeriod);
    if (hasStart || hasEnd) {
      final int? start = _parseInt(header.cell(row, _Column.startPeriod));
      final int? end = _parseInt(header.cell(row, _Column.endPeriod));
      final int? resolvedStart = start ?? end;
      final int? resolvedEnd = end ?? start;
      if (resolvedStart == null || resolvedEnd == null) {
        return null;
      }
      return _PeriodParse(resolvedStart, resolvedEnd);
    }
    final String raw = header.cell(row, _Column.period);
    final List<int> numbers = _numbersIn(raw);
    if (numbers.isEmpty) {
      return null;
    }
    return _PeriodParse(numbers.first, numbers.last);
  }

  static _WeekParse? _parseWeeks(_Header header, List<String> row) {
    final bool hasStart = header.has(_Column.startWeek);
    final bool hasEnd = header.has(_Column.endWeek);
    if (hasStart || hasEnd) {
      final int? start = _parseInt(header.cell(row, _Column.startWeek));
      final int? end = _parseInt(header.cell(row, _Column.endWeek));
      final int? resolvedStart = start ?? end;
      final int? resolvedEnd = end ?? start;
      if (resolvedStart == null || resolvedEnd == null) {
        return null;
      }
      return _WeekParse(start: resolvedStart, end: resolvedEnd);
    }

    final String raw = header.cell(row, _Column.weeks).trim();
    if (raw.isEmpty) {
      return null;
    }
    final List<int> numbers = _numbersIn(raw);
    if (numbers.isEmpty) {
      return null;
    }
    final bool oddEven = raw.contains('单') || raw.contains('双');
    final RegExpMatch? range =
        RegExp(r'(\d+)\s*[-~—–至到]\s*(\d+)').firstMatch(raw);
    final int start;
    final int end;
    bool nonContiguous = false;
    if (range != null) {
      start = int.parse(range.group(1)!);
      end = int.parse(range.group(2)!);
      nonContiguous = numbers.length > 2;
    } else {
      start = numbers.first;
      end = numbers.last;
      nonContiguous = numbers.length != end - start + 1;
    }

    String? warning;
    if (oddEven) {
      warning = '单双周课程已按第 $start-$end 周整周导入（项目不支持单双周），请确认。';
    } else if (nonContiguous) {
      warning = '周次「${raw.replaceAll(RegExp(r'\s+'), '')}」不连续，'
          '已按第 $start-$end 周并集导入，请确认。';
    }
    return _WeekParse(start: start, end: end, warning: warning);
  }
}

enum _Column {
  name,
  teacher,
  room,
  className,
  weekday,
  startPeriod,
  endPeriod,
  startWeek,
  endWeek,
  weeks,
  period,
}

class _Header {
  const _Header(this.mapping, this.row);

  final Map<_Column, int> mapping;

  /// 表头所在行的下标（从 0 开始）。
  final int row;

  bool has(_Column column) => mapping.containsKey(column);

  String cell(List<String> row, _Column column) {
    final int? index = mapping[column];
    if (index == null || index >= row.length) {
      return '';
    }
    return row[index];
  }
}

class _PeriodParse {
  const _PeriodParse(this.start, this.end);

  final int start;
  final int end;
}

class _WeekParse {
  const _WeekParse({required this.start, required this.end, this.warning});

  final int start;
  final int end;
  final String? warning;
}
