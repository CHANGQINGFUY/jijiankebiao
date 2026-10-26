import '../../models/course.dart';
import '../../models/user_role.dart';
import '../../models/week_range.dart';
import '../../models/weekday.dart';

/// 教务个人课表解析（正方 V-9.0 列表视图）。
///
/// 实测页面结构：课表在 `#kblist_table` 中，结构为
/// 星期标题行（单 td，如「星期一」）→ 若干课程行（[节次 td, 课表信息 td]），
/// 同一节次的多门课共用节次单元格，后续行只剩一个 td。
/// 课表信息单元格文本形如：
/// `【调】课程名 周数：1-5周,7-17周 校区:示例校区 上课地点：A101
///   教师：张老师 教学班：xxx-0001 教学班组成：示例专业2401 ...`
class AcademicTimetableParser {
  const AcademicTimetableParser._();

  /// 在课表页执行，把原始行结构回传给 Flutter。
  static const String extractScript = r'''
(function () {
  var out = {
    url: String(location.href),
    title: String(document.title || ''),
    source: '',
    term: '',
    entries: [],
    errors: []
  };

  function clean(text) {
    return String(text == null ? '' : text)
      .replace(/\u00a0/g, ' ')
      .replace(/[\r\n\t]+/g, ' ')
      .replace(/\s{2,}/g, ' ')
      .trim();
  }

  function send() {
    try {
      AcademicImport.postMessage('COURSE:' + JSON.stringify(out));
    } catch (e) {
      try { AcademicImport.postMessage('ERROR:' + String(e)); } catch (e2) {}
    }
  }

  var WEEKDAY = { '星期一': 1, '星期二': 2, '星期三': 3, '星期四': 4, '星期五': 5, '星期六': 6, '星期日': 7, '星期天': 7 };

  function collect(listTable) {
    var rows = listTable.querySelectorAll('tr');
    var weekday = 0;
    var lastPeriod = '';
    for (var i = 0; i < rows.length; i++) {
      var cells = rows[i].children;
      var texts = [];
      for (var c = 0; c < cells.length; c++) { texts.push(clean(cells[c].innerText)); }
      if (!texts.length) { continue; }

      if (texts.length === 1) {
        var single = texts[0];
        var day = WEEKDAY[single.replace(/\s/g, '')];
        if (day) { weekday = day; lastPeriod = ''; continue; }
        if (weekday > 0 && lastPeriod && single) {
          out.entries.push({
            weekday: weekday,
            period: lastPeriod,
            text: single,
            html: String(cells[0].innerHTML || '').slice(0, 1200)
          });
        }
        continue;
      }

      var period = texts[0].replace(/\s/g, '');
      var info = texts.slice(1).join(' ');
      if (/^\d+(-\d+)?$/.test(period)) { lastPeriod = period; }
      if (weekday > 0 && lastPeriod && info) {
        out.entries.push({
          weekday: weekday,
          period: lastPeriod,
          text: info,
          html: String(cells[1].innerHTML || '').slice(0, 1200)
        });
      }
    }
  }

  try {
    var listTable = document.getElementById('kblist_table');
    if (listTable && listTable.querySelectorAll('tr').length > 2) {
      out.source = 'kblist_table';
      collect(listTable);
    } else {
      var grid = document.querySelector('table[id^="kbgrid_table"]');
      if (grid) {
        out.source = 'kbgrid_table';
        out.errors.push('当前是「表格」视图，请在网页上切换到「列表」后重新解析。');
      } else {
        out.errors.push('未找到课表表格 #kblist_table，请确认已进入「个人课表查询」结果页。');
      }
    }
  } catch (e) {
    out.errors.push(String(e));
  }

  try {
    var head = document.getElementById('kblist_table');
    var firstRow = head ? head.querySelector('tr') : null;
    var first = firstRow ? clean(firstRow.innerText) : '';
    var m = first.match(/(\d{4}-\d{4})\s*学年\s*第?\s*(\d)\s*学期/);
    if (m) { out.term = m[1] + ' 第' + m[2] + '学期'; }
  } catch (e) {}

  send();
})();
''';

  /// 课表信息单元格里出现的字段名，用于切分字段值。
  static const List<String> _labels = <String>[
    '周数',
    '校区',
    '上课地点',
    '教师',
    '教学班组成',
    '教学班',
    '考核方式',
    '选课备注',
    '课程学时组成',
    '周学时',
    '学分',
    '课程总学时',
  ];

  static AcademicParseResult parse(
    Map<String, dynamic> payload, {
    required String semesterId,
    required String academicTerm,
    required int totalWeeks,
    required int totalPeriods,
    required int colorSeedBase,
  }) {
    final List<String> warnings = <String>[];
    final List<String> errors = <String>[];
    final List<Course> courses = <Course>[];

    final Object? rawErrors = payload['errors'];
    if (rawErrors is List) {
      for (final Object? item in rawErrors) {
        final String text = item.toString().trim();
        if (text.isNotEmpty) {
          errors.add(text);
        }
      }
    }

    final Object? rawEntries = payload['entries'];
    final List<Object?> entries =
        rawEntries is List ? rawEntries : const <Object?>[];

    final String pageTerm = (payload['term'] ?? '').toString().trim();
    final String term = pageTerm.isEmpty ? academicTerm : pageTerm;

    // 同一门课使用同一个配色，避免同一课程在周视图里颜色不一致。
    final Map<String, int> colorByName = <String, int>{};
    final int safeTotalWeeks = totalWeeks < 1 ? 1 : totalWeeks;
    final int safeTotalPeriods = totalPeriods < 1 ? 1 : totalPeriods;
    final String stamp = DateTime.now().microsecondsSinceEpoch.toString();

    for (int index = 0; index < entries.length; index++) {
      final Object? raw = entries[index];
      if (raw is! Map) {
        continue;
      }
      final Map<Object?, Object?> entry = raw;
      final int weekday = _asInt(entry['weekday']) ?? 0;
      final String periodText = (entry['period'] ?? '').toString().trim();
      final String text = (entry['text'] ?? '').toString().trim();

      if (weekday < 1 || weekday > 7) {
        errors.add('第 ${index + 1} 条：星期无法识别（$weekday）');
        continue;
      }
      final (int, int)? periods = _parsePeriods(periodText);
      if (periods == null) {
        errors.add('第 ${index + 1} 条：节次无法识别（$periodText）');
        continue;
      }
      if (text.isEmpty) {
        continue;
      }

      final String name = _courseName(text);
      if (name.isEmpty) {
        errors.add('第 ${index + 1} 条：课程名为空，原始文本「${_clip(text)}」');
        continue;
      }

      final Set<int> rawWeeks = _parseWeeks(_field(text, '周数'));
      if (rawWeeks.isEmpty) {
        errors.add('《$name》：周次无法识别（${_field(text, '周数')}）');
        continue;
      }
      final Set<int> weeks =
          rawWeeks.where((int w) => w >= 1 && w <= safeTotalWeeks).toSet();
      if (weeks.isEmpty) {
        errors.add('《$name》：周次全部超出本学期总周数（$safeTotalWeeks）');
        continue;
      }
      if (weeks.length != rawWeeks.length) {
        warnings.add('《$name》：部分周次超出本学期总周数（$safeTotalWeeks），已忽略');
      }
      if (_field(text, '周数').contains(RegExp(r'[(（]\s*[单双]'))) {
        warnings.add('《$name》：原周次含单双周（${_field(text, '周数')}），已按实际上课周拆分');
      }

      int startPeriod = periods.$1;
      int endPeriod = periods.$2;
      if (startPeriod > safeTotalPeriods) {
        errors.add('《$name》：节次 $periodText 超出作息表（共 $safeTotalPeriods 节），已跳过');
        continue;
      }
      if (endPeriod > safeTotalPeriods) {
        endPeriod = safeTotalPeriods;
        warnings.add('《$name》：结束节次超出作息表，已截断到第 $safeTotalPeriods 节');
      }

      final String room = _field(text, '上课地点');
      final String teacher = _field(text, '教师');
      final String className = _field(text, '教学班组成');
      final bool adjusted = text.startsWith('【调】');
      final int colorSeed =
          colorByName.putIfAbsent(name, () => (colorSeedBase + colorByName.length) % 12);

      if (weeks.length != _maxRunLength(weeks)) {
        warnings.add('《$name》：周次不连续，已拆成多条记录（组内可一起编辑）');
      }

      final String groupId = 'academic_g_${stamp}_$index';
      int seq = 0;
      for (final (int, int) run in _runs(weeks)) {
        courses.add(
          Course(
            id: 'academic_${stamp}_${index}_${seq++}',
            groupId: groupId,
            name: name,
            teacher: teacher,
            room: room,
            weekdays: <Weekday>{Weekday.fromIsoIndex(weekday)},
            startPeriod: startPeriod,
            endPeriod: endPeriod,
            weeks: WeekRange(start: run.$1, end: run.$2),
            type: UserRole.student,
            className: className.isEmpty ? null : className,
            semesterId: semesterId,
            academicTerm: term,
            colorSeed: colorSeed,
            remark: adjusted ? '教务系统标记为调课' : null,
          ),
        );
      }
    }

    if (entries.isEmpty && errors.isEmpty) {
      errors.add('未检测到课表数据，请确认已在课表查询结果页面');
    }

    return AcademicParseResult(
      courses: courses,
      warnings: warnings,
      errors: errors,
      term: term,
      source: (payload['source'] ?? '').toString(),
    );
  }

  static String _courseName(String text) {
    String value = text.replaceFirst(RegExp(r'^【[^】]*】'), '').trim();
    final int cut = value.indexOf(RegExp('周数\\s*[:：]'));
    if (cut > 0) {
      value = value.substring(0, cut);
    }
    return value.trim();
  }

  static String _field(String text, String label) {
    final String others = _labels.join('|');
    final RegExp re = RegExp(
      '$label\\s*[:：]\\s*([\\s\\S]*?)(?=\\s*(?:$others)\\s*[:：]|\$)',
    );
    final Match? match = re.firstMatch(text);
    return match == null ? '' : match.group(1)!.trim();
  }

  static (int, int)? _parsePeriods(String raw) {
    final Match? match = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(raw);
    if (match == null) {
      return null;
    }
    final int start = int.parse(match.group(1)!);
    final int end =
        match.group(2) == null ? start : int.parse(match.group(2)!);
    if (start < 1 || end < start) {
      return null;
    }
    return (start, end);
  }

  static Set<int> _parseWeeks(String raw) {
    final Set<int> weeks = <int>{};
    for (final String part in raw.split(RegExp(r'[,，、]'))) {
      final String token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final bool oddOnly = token.contains('单');
      final bool evenOnly = token.contains('双');
      final Match? match =
          RegExp(r'(\d+)(?:\s*-\s*(\d+))?').firstMatch(token);
      if (match == null) {
        continue;
      }
      int start = int.parse(match.group(1)!);
      int end = match.group(2) == null ? start : int.parse(match.group(2)!);
      if (end < start) {
        final int swap = start;
        start = end;
        end = swap;
      }
      for (int week = start; week <= end; week++) {
        if (oddOnly && week.isEven) {
          continue;
        }
        if (evenOnly && week.isOdd) {
          continue;
        }
        weeks.add(week);
      }
    }
    return weeks;
  }

  /// 把周次集合拆成连续区间，例如 {1,2,3,7,8} → [(1,3), (7,8)]。
  static List<(int, int)> _runs(Set<int> weeks) {
    final List<int> sorted = weeks.toList()..sort();
    final List<(int, int)> runs = <(int, int)>[];
    int? start;
    int? previous;
    for (final int week in sorted) {
      if (start == null) {
        start = week;
        previous = week;
        continue;
      }
      if (previous != null && week == previous + 1) {
        previous = week;
        continue;
      }
      runs.add((start, previous!));
      start = week;
      previous = week;
    }
    if (start != null && previous != null) {
      runs.add((start, previous));
    }
    return runs;
  }

  static int _maxRunLength(Set<int> weeks) {
    int best = 0;
    for (final (int, int) run in _runs(weeks)) {
      final int length = run.$2 - run.$1 + 1;
      if (length > best) {
        best = length;
      }
    }
    return best;
  }

  static int? _asInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '');
  }

  static String _clip(String text) =>
      text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 解析结果：课程草稿 + 需要用户确认的提示 + 无法解析的条目。
class AcademicParseResult {
  const AcademicParseResult({
    required this.courses,
    required this.warnings,
    required this.errors,
    required this.term,
    required this.source,
  });

  final List<Course> courses;
  final List<String> warnings;
  final List<String> errors;
  final String term;
  final String source;
}
