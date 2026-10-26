import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/data/academic/academic_timetable_parser.dart';
import 'package:schedule_app/models/course.dart';

Map<String, dynamic> _payload(List<Map<String, Object?>> entries) {
  return <String, dynamic>{
    'url': 'https://jw.example.edu.cn/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html',
    'source': 'kblist_table',
    'term': '2026-2027 第1学期',
    'errors': <String>[],
    'entries': entries,
  };
}

void main() {
  test('解析断档周与调课标记，同一原始时段共用一个 groupId', () {
    final AcademicParseResult result = AcademicTimetableParser.parse(
      _payload(<Map<String, Object?>>[
        <String, Object?>{
          'weekday': 1,
          'period': '1-2',
          'text': '【调】示例课程甲 周数：1-5周,7-17周 校区:示例校区 '
              '上课地点：A101 教师：张老师 教学班：xxx-0001 '
              '教学班组成：示例专业2401 考核方式:考查 学分:3.0',
        },
      ]),
      semesterId: 's1',
      academicTerm: '2026-2027 第1学期',
      totalWeeks: 20,
      totalPeriods: 8,
      colorSeedBase: 0,
    );

    expect(result.courses.length, 2);
    expect(result.courses.first.name, '示例课程甲');
    expect(result.courses.first.teacher, '张老师');
    expect(result.courses.first.room, 'A101');
    expect(result.courses.first.className, '示例专业2401');
    expect(result.courses.first.startPeriod, 1);
    expect(result.courses.first.endPeriod, 2);
    expect(result.courses.first.weeks.start, 1);
    expect(result.courses.first.weeks.end, 5);
    expect(result.courses.last.weeks.start, 7);
    expect(result.courses.last.weeks.end, 17);
    expect(result.courses.first.groupId, result.courses.last.groupId);
    expect(result.courses.first.remark, contains('调课'));
    expect(result.warnings.any((String w) => w.contains('不连续')), isTrue);
  });

  test('单双周按实际周次拆分，并给出提示', () {
    final AcademicParseResult result = AcademicTimetableParser.parse(
      _payload(<Map<String, Object?>>[
        <String, Object?>{
          'weekday': 3,
          'period': '3-4',
          'text': '示例课程乙 周数：2-4周(双),8-14周(双) 上课地点：B203 教师：李老师',
        },
      ]),
      semesterId: 's1',
      academicTerm: '2026-2027 第1学期',
      totalWeeks: 20,
      totalPeriods: 8,
      colorSeedBase: 3,
    );

    final Set<int> weeks = <int>{
      for (final Course course in result.courses) course.weeks.start,
    };
    expect(weeks, <int>{2, 4, 8, 10, 12, 14});
    expect(result.warnings.any((String w) => w.contains('单双周')), isTrue);
  });

  test('单周「第12周」与超出作息表的节次截断', () {
    final AcademicParseResult result = AcademicTimetableParser.parse(
      _payload(<Map<String, Object?>>[
        <String, Object?>{
          'weekday': 5,
          'period': '7-10',
          'text': '示例课程丙 周数：第12周 上课地点：操场 教师：王老师',
        },
      ]),
      semesterId: 's1',
      academicTerm: '2026-2027 第1学期',
      totalWeeks: 20,
      totalPeriods: 8,
      colorSeedBase: 0,
    );

    expect(result.courses.length, 1);
    expect(result.courses.single.weeks.start, 12);
    expect(result.courses.single.weeks.end, 12);
    expect(result.courses.single.endPeriod, 8);
    expect(result.warnings.any((String w) => w.contains('截断')), isTrue);
  });

  test('找不到课表时给出明确错误', () {
    final AcademicParseResult result = AcademicTimetableParser.parse(
      _payload(<Map<String, Object?>>[]),
      semesterId: 's1',
      academicTerm: '2026-2027 第1学期',
      totalWeeks: 20,
      totalPeriods: 8,
      colorSeedBase: 0,
    );

    expect(result.courses, isEmpty);
    expect(result.errors.single, contains('未检测到课表数据'));
  });
}
