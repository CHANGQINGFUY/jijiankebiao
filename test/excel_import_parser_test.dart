import 'package:flutter_test/flutter_test.dart';
import 'package:justkawal_excel_updated/justkawal_excel_updated.dart';
import 'package:schedule_app/features/import_excel/excel_import_models.dart';
import 'package:schedule_app/features/import_excel/excel_timetable_parser.dart';
import 'package:schedule_app/models/course.dart';
import 'package:schedule_app/models/user_role.dart';
import 'package:schedule_app/models/weekday.dart';

List<int> _buildWorkbook(List<List<CellValue?>> rows) {
  final Excel excel = Excel.createExcel();
  final String sheetName = excel.tables.keys.first;
  final Sheet sheet = excel[sheetName];
  for (final List<CellValue?> row in rows) {
    sheet.appendRow(row);
  }
  final List<int>? bytes = excel.encode();
  expect(bytes, isNotNull);
  return bytes!;
}

CellValue? _text(Object? value) =>
    value == null ? null : TextCellValue('$value');

ExcelParseResult _parse(List<List<CellValue?>> rows) {
  return ExcelTimetableParser.parse(
    bytes: _buildWorkbook(rows),
    semesterId: 'sem-test',
    type: UserRole.student,
    periodLimit: 8,
    weekLimit: 20,
  );
}

void main() {
  test('识别标准表头并解析单行课程', () {
    final ExcelParseResult result = _parse(<List<CellValue?>>[
      <CellValue?>[
        _text('课程名'),
        _text('教师'),
        _text('教室'),
        _text('星期'),
        _text('开始节次'),
        _text('结束节次'),
        _text('起始周'),
        _text('结束周'),
      ],
      <CellValue?>[
        _text('高等数学'),
        _text('张老师'),
        _text('教101'),
        const IntCellValue(1),
        const IntCellValue(1),
        const IntCellValue(2),
        const IntCellValue(1),
        const IntCellValue(16),
      ],
    ]);

    expect(result.headerRow, 1);
    expect(result.totalRows, 1);
    expect(result.errors, isEmpty);
    expect(result.drafts, hasLength(1));
    final Course course = result.drafts.first;
    expect(course.name, '高等数学');
    expect(course.teacher, '张老师');
    expect(course.room, '教101');
    expect(course.weekdays, <Weekday>{Weekday.monday});
    expect(course.startPeriod, 1);
    expect(course.endPeriod, 2);
    expect(course.weeks.start, 1);
    expect(course.weeks.end, 16);
    expect(course.semesterId, 'sem-test');
  });

  test('表头不在第一行也能识别，列名不区分大小写和空格', () {
    final ExcelParseResult result = _parse(<List<CellValue?>>[
      <CellValue?>[_text('2026-2027 学年第一学期课表')],
      <CellValue?>[_text('Course Name'), _text(' 星期 '), _text('节次'), _text('周次')],
      <CellValue?>[
        _text('程序设计'),
        _text('周一'),
        _text('第3-4节'),
        _text('1-16周'),
      ],
    ]);

    expect(result.headerRow, 2);
    expect(result.errors, isEmpty);
    expect(result.drafts, hasLength(1));
    expect(result.drafts.first.startPeriod, 3);
    expect(result.drafts.first.endPeriod, 4);
    expect(result.drafts.first.weeks.end, 16);
    expect(result.warnings, isEmpty);
  });

  test('只有周次列时：1,3,5周 取并集并提示确认', () {
    final ExcelParseResult result = _parse(<List<CellValue?>>[
      <CellValue?>[_text('课程名称'), _text('周几'), _text('第几节'), _text('周次')],
      <CellValue?>[_text('单双周课程'), const IntCellValue(2), _text('5-6'), _text('1,3,5周')],
      <CellValue?>[_text('单周课程'), const IntCellValue(3), _text('7'), _text('2-16周(单)')],
    ]);

    expect(result.errors, isEmpty);
    expect(result.drafts, hasLength(2));
    expect(result.drafts[0].weeks.start, 1);
    expect(result.drafts[0].weeks.end, 5);
    expect(result.drafts[1].weeks.start, 2);
    expect(result.drafts[1].weeks.end, 16);
    expect(result.warnings, hasLength(2));
    expect(result.warnings.first, contains('不连续'));
    expect(result.warnings.last, contains('单双周'));
  });

  test('错误行只记录行号和原因，不影响其它行', () {
    final ExcelParseResult result = _parse(<List<CellValue?>>[
      <CellValue?>[_text('课程名'), _text('星期'), _text('节次'), _text('周次')],
      <CellValue?>[_text(''), const IntCellValue(1), _text('1-2'), _text('1-16')],
      <CellValue?>[_text('星期越界'), const IntCellValue(8), _text('1-2'), _text('1-16')],
      <CellValue?>[_text('节次倒置'), const IntCellValue(1), _text('4-2'), _text('1-16')],
      <CellValue?>[_text('周次倒置'), const IntCellValue(1), _text('1-2'), _text('16-1')],
      <CellValue?>[_text('正常的课'), const IntCellValue(4), _text('1-2'), _text('1-16')],
    ]);

    expect(result.totalRows, 5);
    expect(result.drafts, hasLength(1));
    expect(result.drafts.first.name, '正常的课');
    expect(result.errors, hasLength(4));
    expect(result.errors[0].rowNumber, 2);
    expect(result.errors[0].reason, contains('课程名'));
    expect(result.errors[1].rowNumber, 3);
    expect(result.errors[1].reason, contains('星期'));
    expect(result.errors[2].rowNumber, 4);
    expect(result.errors[2].reason, contains('结束节次'));
    expect(result.errors[3].rowNumber, 5);
    expect(result.errors[3].reason, contains('结束周'));
  });

  test('节次超出当前作息时给出提示而不是报错', () {
    final ExcelParseResult result = _parse(<List<CellValue?>>[
      <CellValue?>[_text('课程名'), _text('星期'), _text('节次'), _text('周次')],
      <CellValue?>[_text('晚课'), const IntCellValue(5), _text('9-10'), _text('1-16')],
    ]);

    expect(result.errors, isEmpty);
    expect(result.drafts, hasLength(1));
    expect(result.warnings.single, contains('超出当前学期作息'));
  });

  test('无法识别表头时抛出 FormatException', () {
    expect(
      () => _parse(<List<CellValue?>>[
        <CellValue?>[_text('随便'), _text('写点'), _text('东西')],
      ]),
      throwsA(isA<FormatException>()),
    );
  });
}
