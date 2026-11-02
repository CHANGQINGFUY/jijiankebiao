import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/data/academic/fjlzy_timetable_parser.dart';
import 'package:schedule_app/models/course.dart';

Map<String, dynamic> _payload(List<Map<String, Object?>> entries) {
  return <String, dynamic>{
    'url': 'https://zfjw.fjlzy.com/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html',
    'source': 'kblist_table',
    'term': '2026-2027 第1学期',
    'errors': <String>[],
    'entries': entries,
  };
}

void main() {
  test('解析断档周与调课标记，同一原始时段共用一个 groupId', () {
    final FjlzyParseResult result = FjlzyTimetableParser.parse(
      _payload(<Map<String, Object?>>[
        <String, Object?>{
          'weekday': 1,
          'period': '1-2',
          'text': '【调】智慧化税费申报与管理 周数：1-5周,7-17周 校区:天麟校区 '
              '上课地点：科904 教师：陈家伟 教学班：xxx-0001 '
              '教学班组成：大数据与会计2501 考核方式:考查 学分:3.0',
        },
      ]),
      semesterId: 's1',
      academicTerm: '2026-2027 第1学期',
      totalWeeks: 20,
      totalPeriods: 8,
      colorSeedBase: 0,
    );

    expect(result.courses.length, 2);
    expect(result.courses.first.name, '智慧化税费申报与管理');
    expect(result.courses.first.teacher, '陈家伟');
    expect(result.courses.first.room, '科904');
    expect(result.courses.first.className, '大数据与会计2501');
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
    final FjlzyParseResult result = FjlzyTimetableParser.parse(
      _payload(<Map<String, Object?>>[
        <String, Object?>{
          'weekday': 3,
          'period': '3-4',
          'text': '大学英语3 周数：2-4周(双),8-14周(双) 上课地点：科101 教师：李四',
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
    final FjlzyParseResult result = FjlzyTimetableParser.parse(
      _payload(<Map<String, Object?>>[
        <String, Object?>{
          'weekday': 5,
          'period': '7-10',
          'text': '劳动教育3 周数：第12周 上课地点：操场 教师：王五',
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
    final FjlzyParseResult result = FjlzyTimetableParser.parse(
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
