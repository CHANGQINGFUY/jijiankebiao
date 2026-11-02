import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/theme/course_colors.dart';
import '../../models/course.dart';
import '../../models/user_role.dart';
import '../../models/week_range.dart';
import '../../models/weekday.dart';
import '../import_excel/excel_import_models.dart';

/// 解析「教务系统整张课表」PDF（网格布局）。
///
/// 表格结构：表头一行是「时间段 节次 星期一 … 星期日」，
/// 下方每个单元格是一门课，单元格文本结构固定为：
/// ```
/// 课程名
/// (1-2节)1-5周,7-17周/校区:…/场地:…/教师:…/教学班:…/教学班组成:…/考核方式:…
/// ```
///
/// 实现思路（真实单元格归位）：
/// 1. 用 Syncfusion 抽出每个 [TextWord] 及其坐标（bounds）；
/// 2. 由表头「星期一…星期日」确定 7 个星期列的视觉 x 区间；
///    页面旋转 90° 时，词的视觉行起点对应 -bounds.bottom
///    （top 是行终点，长信息行会跨列，不能用来归列）；
/// 3. 每个词按视觉行起点归入星期列，列内再按行轴聚成视觉行、
///    按阅读顺序拼接，还原出与表格单元格一致的文本；
/// 4. 单元格内：以 `(x-y节)` 为信息锚点，锚点之前是课程名，
///    之后用 `/键:值` 正则提取 周次/场地/教师/教学班，
///    课程之间以固定结尾「课程总学时:数字」分隔；
/// 5. 周次含单双周、断档时取并集范围（min~max），并生成 warning 提示用户确认。
class PdfTimetableParser {
  const PdfTimetableParser._();

  /// 信息锚点，例如 `(1-2节)`。
  static final RegExp _anchor =
      RegExp(r'[（(]\s*(\d+)\s*[-~—–]\s*(\d+)\s*节\s*[)）]');

  static ExcelParseResult parse({
    required List<int> bytes,
    required String semesterId,
    required UserRole type,
    int colorBase = 0,
    int periodLimit = 0,
    int weekLimit = 0,
  }) {
    final PdfDocument doc;
    try {
      doc = PdfDocument(inputBytes: bytes);
    } catch (_) {
      throw const FormatException('不是有效的 .pdf 文件，或文件已损坏。');
    }

    final List<Course> drafts = <Course>[];
    final List<ExcelRowError> errors = <ExcelRowError>[];
    final List<String> warnings = <String>[];
    final Set<String> warnedMessages = <String>{};
    final Map<String, int> colorSeeds = <String, int>{};
    final int stamp = DateTime.now().microsecondsSinceEpoch;
    int cellCount = 0;

    try {
      final PdfTextExtractor extractor = PdfTextExtractor(doc);
      _Grid? grid;
      bool headerFound = false;
      final List<List<_Word>> columns =
          List<List<_Word>>.generate(7, (_) => <_Word>[]);

      for (int page = 0; page < doc.pages.count; page++) {
        final List<TextWord> words = <TextWord>[];
        final List<TextLine> lines = extractor.extractTextLines(
          startPageIndex: page,
          endPageIndex: page,
        );
        for (final TextLine line in lines) {
          words.addAll(line.wordCollection);
        }
        if (words.isEmpty) {
          continue;
        }

        // 续页没有「星期一…星期日」表头：沿用上一页的网格，
        // 且不做页眉过滤（续页顶部是上一页单元格被截断的下半截，
        // 从页面顶就开始了）。同列跨页文本首尾相接后，被页边界
        // 截断的课程信息自然拼合完整。
        final _Grid? detected = _Grid.detect(words);
        final _Grid? use = detected ?? grid;
        if (use == null) {
          continue; // 还没遇到表头页
        }
        grid = use;
        headerFound = headerFound || detected != null;
        use.collect(words, page, columns, skipHeader: detected != null);
      }

      if (!headerFound) {
        throw const FormatException(
          '未识别到课表网格。请确认这是从教务系统直接导出的整张课表 PDF'
          '（含「星期一…星期日」表头），而不是清单式或扫描件。',
        );
      }

      for (int col = 0; col < 7; col++) {
        final String text = _Grid.columnText(columns[col]);
        if (text.isEmpty) {
          continue;
        }
        final Weekday weekday = Weekday.fromIsoIndex(col + 1);
        for (final _CellCourse parsed in _parseCell(text)) {
          cellCount++;
          final int rowNumber = cellCount; // PDF 无行号，用课程序号代替

          final _WeekResult week = _weeksToRange(parsed.weeksText);
          if (week.start < 1) {
            errors.add(ExcelRowError(
                rowNumber: rowNumber, reason: '周次「${parsed.weeksText}」无效'));
            continue;
          }
          if (week.warning != null &&
              warnedMessages.add('${parsed.name}|${week.warning}')) {
            warnings.add('《${parsed.name}》：${week.warning}');
          }
          if (periodLimit > 0 &&
              parsed.endPeriod > periodLimit &&
              warnedMessages.add('${parsed.name}|period')) {
            warnings.add(
                '《${parsed.name}》：节次 ${parsed.startPeriod}-${parsed.endPeriod} '
                '超出当前学期作息（共 $periodLimit 节），请到学期设置补全节次时间。');
          }
          if (weekLimit > 0 &&
              week.end > weekLimit &&
              warnedMessages.add('${parsed.name}|week')) {
            warnings.add('《${parsed.name}》：周次 ${week.start}-${week.end} '
                '超出当前学期总周数（$weekLimit 周），导入后可能不显示。');
          }

          final int seed = colorSeeds.putIfAbsent(
              parsed.name,
              () =>
                  (colorBase + colorSeeds.length) % CourseColors.palette.length);

          drafts.add(Course(
            id: 'pdf-$stamp-$rowNumber',
            name: parsed.name,
            teacher: parsed.teacher,
            room: parsed.room,
            className: parsed.className.isEmpty ? null : parsed.className,
            semesterId: semesterId,
            weekdays: <Weekday>{weekday},
            startPeriod: parsed.startPeriod,
            endPeriod: parsed.endPeriod,
            weeks: WeekRange(start: week.start, end: week.end),
            colorSeed: seed,
            type: type,
          ));
        }
      }
    } finally {
      doc.dispose();
    }

    if (drafts.isEmpty) {
      throw const FormatException('PDF 里没有解析到任何课程。若是扫描件/图片型 PDF，无法识别文字。');
    }

    return ExcelParseResult(
      drafts: drafts,
      errors: errors,
      warnings: warnings,
      totalRows: cellCount,
      headerRow: 1,
    );
  }

  // -------------------------------------------------------------- 单元格文本

  /// 解析单个星期列的多门课。
  ///
  /// 列文本按行轴升序排列，一门课的结构为：
  /// ```
  /// 课程名            （可能换行，1~2 行）
  /// (x-y节)周次/校区:…/场地:…/教师:…/教学班:…/教学班组成:…/考核方式:…/…/课程总学时:数字
  /// ```
  /// 「课程总学时:数字」是每门课的固定结尾标记，用作课程之间的分隔。
  static List<_CellCourse> _parseCell(String text) {
    final String flat = text.replaceAll(RegExp(r'\s+'), '');
    if (flat.isEmpty) {
      return const <_CellCourse>[];
    }
    final List<RegExpMatch> anchors = _anchor.allMatches(flat).toList();
    if (anchors.isEmpty) {
      return const <_CellCourse>[];
    }
    final List<_CellCourse> result = <_CellCourse>[];

    for (int i = 0; i < anchors.length; i++) {
      final RegExpMatch info = anchors[i];
      final int startPeriod = int.parse(info.group(1)!);
      final int endPeriod = int.parse(info.group(2)!);

      // 课程名起点：上一门课的「课程总学时:数字」结尾；第一门课从段首开始。
      final int nameFrom =
          i == 0 ? 0 : _endOfLastField(flat, anchors[i - 1].end, info.start);
      final String name = _cleanName(flat.substring(nameFrom, info.start));
      if (name.isEmpty || _isNonCourse(name)) {
        continue;
      }

      // 信息段：当前锚点结尾 → 下一门课课程名起点（或全文末）。
      final int segEnd = i + 1 < anchors.length
          ? _endOfLastField(flat, info.end, anchors[i + 1].start)
          : flat.length;
      final String rest = flat.substring(info.end, segEnd);

      final int slashIndex = rest.indexOf('/');
      final String weeksText =
          slashIndex < 0 ? rest : rest.substring(0, slashIndex);

      result.add(_CellCourse(
        name: name,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        weeksText: weeksText,
        room: _field(rest, '场地'),
        teacher: _field(rest, '教师'),
        className: _field(rest, '教学班'),
      ));
    }
    return result;
  }

  /// 在 [from, to) 区间内，返回最后一个字段（`:数字` 或 `/词:值`）的结尾位置。
  ///
  /// 用于定位「上一门课信息段的结束」，即下一门课课程名的起点。
  static int _endOfLastField(String flat, int from, int to) {
    if (to <= from) {
      return from;
    }
    final String seg = flat.substring(from, to);
    // 优先以「课程总学时:数字」为分隔。
    final List<RegExpMatch> totals =
        RegExp(r'课程总学时[:：][\d.]+').allMatches(seg).toList();
    if (totals.isNotEmpty) {
      return from + totals.last.end;
    }
    // 退化：取最后一个 `:数字` 结尾。
    final List<RegExpMatch> fields =
        RegExp(r'[:：][\d.]+').allMatches(seg).toList();
    if (fields.isNotEmpty) {
      return from + fields.last.end;
    }
    return from;
  }

  /// 清洗课程名：去掉残留的 `/键:值`、`键:` 前缀与字段尾巴。
  static String _cleanName(String seg) {
    String s = seg;
    // 课程名可能在最后一个 `/` 字段值之后（如「/教学班:xx」后接下一课名）。
    final int slash = s.lastIndexOf('/');
    if (slash >= 0) {
      s = s.substring(slash + 1);
    }
    // 剥离结尾的 `:数字` 字段（如「…课程总学时:52」）。
    final int idx = s.indexOf(RegExp(r'[:：][\d.]'));
    if (idx >= 0) {
      s = s.substring(0, idx);
    }
    // 去掉「键:」前缀（残留的字段标签）。
    final int colon = s.indexOf(RegExp(r'[:：]'));
    if (colon >= 0) {
      s = s.substring(colon + 1);
    }
    return s.trim();
  }

  /// 提取 `/键:值` 形式的字段，值到下一个 `/键:` 或结尾为止。
  static String _field(String flat, String key) {
    final RegExp reg =
        RegExp('/$key[:：](.*?)(?=/[一-龥A-Za-z]+[:：]|课程总学时|\$)');
    final RegExpMatch? m = reg.firstMatch(flat);
    return m == null ? '' : m.group(1)!.trim();
  }

  static bool _isNonCourse(String text) {
    const Set<String> junk = <String>{
      '上午', '下午', '晚上', '时间段', '节次', '理论', '实践', '实验', '上机', '其它',
    };
    if (junk.contains(text)) {
      return true;
    }
    return RegExp(r'^\d+$').hasMatch(text);
  }

  // -------------------------------------------------------------- 周次

  /// 把 `1-5周,7-17周`、`第12周`、`2-4周(双)`、`1-3周(单),7周` 等
  /// 统一取并集范围（min~max），需要时给出提示。
  ///
  /// 注意：周次文本可能混入课程编号尾巴（如 `2-4周(双),8-14周(双告2502`），
  /// 先截掉第一个非数字/非周次关键字的杂质再提取数字。
  static _WeekResult _weeksToRange(String raw) {
    // 去掉「第」「周」「(单)」「(双)」「,」等分隔后逐个数字提取；
    // 但像「告2502」「经管楼6161」这类课程/场地尾巴里的数字要排除：
    // 只保留「周」字之前、或「(」之前的部分。
    String cleaned = raw;
    final int cut = cleaned.indexOf(RegExp(r'[^\d,，\-~—–单双第周()（）]'));
    if (cut >= 0) {
      cleaned = cleaned.substring(0, cut);
    }
    final List<int> numbers = <int>[
      for (final RegExpMatch m in RegExp(r'\d+').allMatches(cleaned))
        int.parse(m.group(0)!),
    ];
    if (numbers.isEmpty) {
      return const _WeekResult(start: 0, end: 0);
    }
    final int start = numbers.reduce((a, b) => a < b ? a : b);
    final int end = numbers.reduce((a, b) => a > b ? a : b);

    final bool oddEven = cleaned.contains('单') || cleaned.contains('双');
    final bool hasComma = cleaned.contains(',') || cleaned.contains('，');
    final bool singleRange = RegExp(r'^\s*第?\s*\d+\s*[-~—–]\s*\d+\s*周?\s*$')
        .hasMatch(cleaned);

    String? warning;
    if (oddEven) {
      warning = '含单双周「$raw」，已按第 $start-$end 周整周导入，请确认。';
    } else if (hasComma && !singleRange) {
      warning = '周次「$raw」不连续，已按第 $start-$end 周并集导入，请确认。';
    }
    return _WeekResult(start: start, end: end, warning: warning);
  }
}

// ================================================================== 网格归位

/// 课表网格：由表头「星期一…星期日」确定 7 个星期列的视觉 x 区间。
class _Grid {
  const _Grid._(this.rotated, this.colCenters, this.colTol, this.headerRow);

  /// true 表示页面旋转 90°：星期列沿用户坐标 y 分布（周一→周日递减），
  /// 文本行沿用户坐标 x 分布（自上而下递增）。
  final bool rotated;

  /// 7 个星期列中心的「视觉 x」坐标，递增排列，下标 0=周一 … 6=周日。
  ///
  /// 「视觉 x」是页面按人眼方向看时的水平坐标（取的是一个可比较的
  /// 单调量，省略了常量偏移）：旋转页用 -（top+bottom)/2，非旋转页用
  /// （left+right)/2。归列时另用词的**行起点**（见 [buildCells]）。
  final List<double> colCenters;

  /// 归列容差：相邻列间距的一半再加一点余量。
  final double colTol;

  /// 表头行的行轴坐标下限（旋转页取表头词的 left，否则取 top）。
  /// 表格正文只在这一线之下，之上的页眉标题不进单元格。
  final double headerRow;

  static const List<String> _weekdayNames = <String>[
    '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
  ];

  /// 从词集合里探测网格。找不到完整 7 列表头则返回 null。
  static _Grid? detect(List<TextWord> words) {
    final Map<String, TextWord> header = <String, TextWord>{};
    for (final TextWord w in words) {
      final String t = w.text.replaceAll(RegExp(r'\s+'), '');
      if (_weekdayNames.contains(t)) {
        header.putIfAbsent(t, () => w);
      }
    }
    if (header.length < 7) {
      return null;
    }

    double spread(List<double> v) {
      double mn = v.first, mx = v.first;
      for (final double x in v) {
        if (x < mn) mn = x;
        if (x > mx) mx = x;
      }
      return mx - mn;
    }

    final List<double> tops = <double>[
      for (final String n in _weekdayNames) header[n]!.bounds.top,
    ];
    final List<double> lefts = <double>[
      for (final String n in _weekdayNames) header[n]!.bounds.left,
    ];
    final bool rotated = spread(tops) > spread(lefts);

    // 列中心（视觉 x，递增即周一→周日）与表头行轴下限。
    final List<double> centers = <double>[
      for (final String n in _weekdayNames)
        rotated
            ? -(header[n]!.bounds.top + header[n]!.bounds.bottom) / 2
            : (header[n]!.bounds.left + header[n]!.bounds.right) / 2,
    ];
    final double headerRow = rotated
        ? lefts.reduce((double a, double b) => a < b ? a : b)
        : tops.reduce((double a, double b) => a < b ? a : b);

    double spacing = 0;
    for (int i = 0; i < centers.length - 1; i++) {
      spacing += (centers[i + 1] - centers[i]).abs();
    }
    spacing /= centers.length - 1;

    return _Grid._(rotated, centers, spacing / 2 + 8, headerRow);
  }

  /// 把一页的词按「星期列」收进 [columns]（跨页累积，由调用方保证页序）。
  ///
  /// 归列用词的**视觉行起点**：旋转页是 -bounds.bottom，非旋转页是
  /// bounds.left。长信息行虽然视觉终点跨进相邻列，但起点永远在自己
  /// 列的左缘，因此不会串列。[skipHeader] 为 true 时（表头页）丢弃
  /// 表头行以上的页眉文字；续页从页顶就是正文，不能过滤。
  void collect(
    List<TextWord> words,
    int page,
    List<List<_Word>> columns, {
    required bool skipHeader,
  }) {
    for (final TextWord w in words) {
      String t = w.text.replaceAll(RegExp(r'\s+'), '');
      if (t.isEmpty ||
          _weekdayNames.contains(t) ||
          t == '时间段' ||
          t == '节次' ||
          t == '上午' ||
          t == '下午' ||
          t == '晚上' ||
          t.contains('学号') ||
          t.startsWith('打印') ||
          RegExp(r'^\d+$').hasMatch(t)) {
        continue; // 表头、节次数字与页脚信息不进单元格
      }
      // 去掉乱码字符：Syncfusion 对个别字体子集解码失败会产出
      // 控制符/错误区段占位（如 U+08xx 块），课表文本不会用到这些字符。
      t = String.fromCharCodes(t.runes.where((int c) =>
          c > 0x1F &&
          !(c >= 0x7F && c <= 0x9F) &&
          !(c >= 0x0600 && c <= 0x08FF) &&
          !(c >= 0xFB50 && c <= 0xFDFF) &&
          c != 0xFFFD));
      if (t.isEmpty) {
        continue;
      }
      final double vx = rotated ? -w.bounds.bottom : w.bounds.left;
      final double row = rotated ? w.bounds.left : w.bounds.top;
      if (skipHeader && row < headerRow - 6) {
        continue; // 页眉（课表标题、学期说明等）
      }
      final int col = _columnOf(vx);
      if (col < 0) {
        continue; // 时间段/节次列与页面边缘
      }
      columns[col].add(
          _Word(page, row, rotated ? -w.bounds.top : w.bounds.left, t));
    }
  }

  /// 把一列跨页累积的词还原成单元格文本：按 (页, 行轴) 升序，
  /// 同页内行轴坐标相近（<=5pt）的词属于同一视觉行，
  /// 行内按阅读顺序（旋转页为 top 降序，否则 left 升序）拼接。
  ///
  /// 不强制按节次行拆分——同一星期里不同节次的课上下排列，
  /// 课程之间靠「课程总学时:数字」这一固定结尾分隔（见 [_parseCell]）。
  static String columnText(List<_Word> items) {
    if (items.isEmpty) {
      return '';
    }
    items.sort((_Word a, _Word b) {
      final int byPage = a.page.compareTo(b.page);
      if (byPage != 0) {
        return byPage;
      }
      final int byRow = a.row.compareTo(b.row);
      return byRow != 0 ? byRow : a.order.compareTo(b.order);
    });
    final StringBuffer buf = StringBuffer();
    int curPage = -1;
    double lineRow = double.negativeInfinity;
    for (final _Word w in items) {
      if (w.page != curPage || w.row - lineRow > 5) {
        buf.write('\n');
        curPage = w.page;
        lineRow = w.row;
      }
      buf.write(w.text);
    }
    return buf.toString().replaceAll(RegExp(r'^\n+'), '').trim();
  }

  /// 归列：取最近的列中心，距离超过容差则视为网格外。
  int _columnOf(double vx) {
    int best = -1;
    double bestDist = double.infinity;
    for (int i = 0; i < colCenters.length; i++) {
      final double d = (vx - colCenters[i]).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return bestDist <= colTol ? best : -1;
  }
}

/// 待归位的一个词：页码、行轴坐标、行内阅读顺序键、文本。
class _Word {
  const _Word(this.page, this.row, this.order, this.text);

  final int page;
  final double row;
  final double order;
  final String text;
}

class _CellCourse {
  const _CellCourse({
    required this.name,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeksText,
    required this.room,
    required this.teacher,
    required this.className,
  });

  final String name;
  final int startPeriod;
  final int endPeriod;
  final String weeksText;
  final String room;
  final String teacher;
  final String className;
}

class _WeekResult {
  const _WeekResult({required this.start, required this.end, this.warning});

  final int start;
  final int end;
  final String? warning;
}
