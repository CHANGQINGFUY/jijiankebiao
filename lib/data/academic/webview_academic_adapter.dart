import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/course.dart';
import '../../models/user_role.dart';
import '../../models/week_range.dart';
import '../../models/weekday.dart';
import 'academic_adapter.dart';

/// 基于 WebView 的通用教务适配器。
///
/// 登录在 WebView 内手动完成，之后在同一个 WebView 里用 JS fetch 请求课表，
/// 这样 httpOnly Cookie 也会随请求带上，无需自行抓取 Cookie。
class WebViewAcademicAdapter implements AcademicAdapter {
  WebViewAcademicAdapter(this._config);

  final AcademicSchoolConfig _config;
  WebViewController? _webView;

  static const Duration _fetchTimeout = Duration(seconds: 45);
  static const Duration _pollInterval = Duration(milliseconds: 250);
  static const int _maxBodyLength = 200000;

  @override
  String get schoolId => _config.id;

  @override
  AcademicSchoolConfig get config => _config;

  // ---------------------------------------------------------------- 登录

  @override
  Future<AcademicLoginResult> login(BuildContext context) async {
    final String homeUrl = _config.homeUrl.trim();
    if (homeUrl.isEmpty) {
      return const AcademicLoginResult(
        success: false,
        message: '该学校尚未配置教务首页地址，无法登录。',
      );
    }
    final Uri? uri = Uri.tryParse(homeUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const AcademicLoginResult(
        success: false,
        message: '教务首页地址格式不正确，请检查学校配置。',
      );
    }

    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF));

    final bool? completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (BuildContext pageContext) => _AcademicLoginPage(
          config: _config,
          controller: controller,
          initialUrl: uri,
        ),
      ),
    );

    if (completed == true) {
      _webView = controller;
      return const AcademicLoginResult(success: true);
    }
    return const AcademicLoginResult(success: false, message: '已取消登录');
  }

  // ---------------------------------------------------------------- 拉取课表

  @override
  Future<List<Course>> fetchTimetable({
    required String semesterId,
    required String semesterName,
    required int totalWeeks,
    required int colorSeedBase,
  }) async {
    if (_config.homeUrl.trim().isEmpty || _config.apiUrl.trim().isEmpty) {
      throw const AcademicImportException(
        AcademicErrorKind.notConfigured,
        '该学校尚未配置教务接口地址，暂不支持自动导入，请改用 Excel 导入或联系维护者补充配置。',
      );
    }
    final WebViewController? webView = _webView;
    if (webView == null) {
      throw const AcademicImportException(
        AcademicErrorKind.loginRequired,
        AcademicMessages.loginRequired,
      );
    }
    if (!_config.isJson) {
      throw const AcademicImportException(
        AcademicErrorKind.unsupportedFormat,
        '该学校返回 HTML 页面，暂不支持自动解析，请改用 Excel 导入。',
      );
    }

    final String rawResponse = await _runFetch(webView);
    return _parseCourses(
      rawResponse,
      semesterId: semesterId,
      semesterName: semesterName,
      totalWeeks: totalWeeks,
      colorSeedBase: colorSeedBase,
    );
  }

  /// 在 WebView 内发起 fetch，并轮询等待 JS 把结果写到全局变量。
  Future<String> _runFetch(WebViewController webView) async {
    final Map<String, Object?> options = <String, Object?>{
      'method': _config.normalizedHttpMethod,
      'credentials': 'include',
    };
    if (_config.normalizedHttpMethod == 'POST') {
      options['headers'] = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      };
    }

    // 返回格式固定为 {status,url,body}，body 截断到 200000 字符。
    final String script = '''
(function() {
  window.__academicResult = '';
  try {
    fetch(${jsonEncode(_config.apiUrl)}, ${jsonEncode(options)})
      .then(function(response) {
        return response.text().then(function(text) {
          window.__academicResult = JSON.stringify({
            status: response.status,
            url: response.url,
            body: String(text || '').slice(0, $_maxBodyLength)
          });
        });
      })
      .catch(function(error) {
        window.__academicResult = JSON.stringify({
          status: 0,
          url: '',
          body: '',
          error: String(error)
        });
      });
  } catch (error) {
    window.__academicResult = JSON.stringify({
      status: 0,
      url: '',
      body: '',
      error: String(error)
    });
  }
})();
''';

    try {
      await webView.runJavaScript(script);
    } catch (_) {
      throw const AcademicImportException(
        AcademicErrorKind.network,
        '无法向教务系统发起请求，请检查网络后重试。',
      );
    }

    String result = '';
    final DateTime deadline = DateTime.now().add(_fetchTimeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        final Object raw = await webView
            .runJavaScriptReturningResult("window.__academicResult || ''");
        result = _decodeJsString(raw);
        if (result.trim().isNotEmpty) {
          break;
        }
        await Future<void>.delayed(_pollInterval);
      }
    } catch (_) {
      throw const AcademicImportException(
        AcademicErrorKind.network,
        '读取教务系统响应失败，请检查网络后重试。',
      );
    }

    if (result.trim().isEmpty) {
      throw const AcademicImportException(
        AcademicErrorKind.network,
        '请求教务系统超时，请检查网络后重试。',
      );
    }
    return result;
  }

  /// Android 的 runJavaScriptReturningResult 会把字符串再 JSON 编码一次。
  String _decodeJsString(Object? raw) {
    if (raw == null) {
      return '';
    }
    if (raw is! String) {
      return raw.toString();
    }
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is String) {
          return decoded;
        }
      } catch (_) {
        // 不是 JSON 字符串时按原样返回。
      }
    }
    return raw;
  }

  // ---------------------------------------------------------------- 解析

  List<Course> _parseCourses(
    String rawResponse, {
    required String semesterId,
    required String semesterName,
    required int totalWeeks,
    required int colorSeedBase,
  }) {
    try {
      final Map<String, Object?> payload = _decodePayload(rawResponse);
      final int status = _readInt(payload['status']) ?? 0;
      final String body = _asString(payload['body']);

      if (status >= 300 && status < 400) {
        throw const AcademicImportException(
          AcademicErrorKind.loginRequired,
          AcademicMessages.loginRequired,
        );
      }
      if (body.trimLeft().startsWith('<')) {
        throw const AcademicImportException(
          AcademicErrorKind.loginRequired,
          AcademicMessages.loginRequired,
        );
      }
      if (status == 0) {
        throw const AcademicImportException(
          AcademicErrorKind.network,
          '请求教务系统失败，请检查网络后重试。',
        );
      }
      if (status >= 400) {
        throw AcademicImportException(
          AcademicErrorKind.network,
          '教务系统返回 HTTP $status，请稍后重试。',
        );
      }
      if (body.trim().isEmpty) {
        throw const AcademicImportException(
          AcademicErrorKind.parse,
          '教务系统返回内容为空，请确认已登录并检查接口地址。',
        );
      }

      final Object? decodedBody = _decodeBody(body);
      final List<Object?>? rows = _resolveRows(decodedBody);
      if (rows == null) {
        final String listPath = (_config.fieldMap['listPath'] ?? '').trim();
        throw AcademicImportException(
          AcademicErrorKind.parse,
          listPath.isEmpty
              ? '未在教务系统返回的数据中找到课程列表，请检查接口地址或改用 Excel 导入。'
              : '未在教务系统返回的数据中找到课程列表（listPath：$listPath），请检查字段映射或改用 Excel 导入。',
        );
      }

      final int maxWeek = totalWeeks < 1 ? 1 : totalWeeks;
      final List<Course> courses = <Course>[];
      int skipped = 0;

      for (final Object? row in rows) {
        if (row is! Map) {
          skipped++;
          continue;
        }
        final String name = _readMapped(row, 'name', 'name').trim();
        if (name.isEmpty) {
          skipped++;
          continue;
        }
        final Set<Weekday> weekdays =
            _parseWeekdays(_readMapped(row, 'weekday', 'weekday'));
        if (weekdays.isEmpty) {
          skipped++;
          continue;
        }
        final (int, int)? periods = _parsePeriods(row);
        if (periods == null) {
          skipped++;
          continue;
        }
        final WeekRange? weeks = _parseWeeks(row, maxWeek);
        if (weeks == null) {
          skipped++;
          continue;
        }

        final int sequence = courses.length + 1;
        courses.add(
          Course(
            id: 'academic-${_config.id}-$sequence',
            name: name,
            teacher: _readMapped(row, 'teacher', 'teacher').trim(),
            room: _readMapped(row, 'room', 'room').trim(),
            weekdays: weekdays,
            startPeriod: periods.$1,
            endPeriod: periods.$2,
            weeks: weeks,
            semesterId: semesterId,
            academicTerm: semesterName,
            colorSeed: colorSeedBase + sequence % 12,
            type: UserRole.student,
          ),
        );
      }

      if (courses.isEmpty) {
        throw AcademicImportException(
          AcademicErrorKind.parse,
          '未能从教务系统返回内容中解析出课程（共 ${rows.length} 条，跳过 $skipped 条），'
          '请检查字段映射或改用 Excel 导入。',
        );
      }
      return courses;
    } on AcademicImportException {
      rethrow;
    } catch (_) {
      throw const AcademicImportException(
        AcademicErrorKind.parse,
        '解析教务系统课表失败，请检查字段映射或改用 Excel 导入。',
      );
    }
  }

  Object? _decodeBody(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      throw const AcademicImportException(
        AcademicErrorKind.parse,
        '教务系统返回的课表数据不是合法 JSON，请检查接口地址或改用 Excel 导入。',
      );
    }
  }

  Map<String, Object?> _decodePayload(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // 统一在下方抛出中文异常。
    }
    throw const AcademicImportException(
      AcademicErrorKind.parse,
      '教务系统响应格式异常，无法读取请求结果，请稍后重试或改用 Excel 导入。',
    );
  }

  /// 按 listPath（如 data.list）定位课程数组。
  List<Object?>? _resolveRows(Object? root) {
    final String listPath = (_config.fieldMap['listPath'] ?? '').trim();
    Object? current = root;

    if (listPath.isNotEmpty) {
      for (final String rawSegment in listPath.split('.')) {
        final String segment = rawSegment.trim();
        if (segment.isEmpty) {
          continue;
        }
        if (current is Map) {
          current = current[segment];
        } else if (current is List) {
          final int? index = int.tryParse(segment);
          current = index == null || index < 0 || index >= current.length
              ? null
              : current[index];
        } else {
          current = null;
        }
        if (current == null) {
          break;
        }
      }
    }

    if (current is List) {
      return current.cast<Object?>();
    }
    if (current is Map) {
      // 未配置 listPath 时，对常见的列表字段做一次容错。
      for (final String key in <String>[
        'list',
        'rows',
        'items',
        'courses',
        'data',
      ]) {
        final Object? value = current[key];
        if (value is List) {
          return value.cast<Object?>();
        }
      }
    }
    return null;
  }

  /// 优先使用 fieldMap 中的键，未配置时回退到同名的常见字段。
  String _readMapped(
    Map<dynamic, dynamic> row,
    String field,
    String fallbackKey,
  ) {
    final String mapped = (_config.fieldMap[field] ?? '').trim();
    return _readKey(row, mapped.isEmpty ? fallbackKey : mapped);
  }

  String _readKey(Map<dynamic, dynamic> row, String key) {
    if (key.isEmpty) {
      return '';
    }
    final Object? direct = row[key];
    if (direct != null) {
      return direct.toString();
    }
    for (final Object? itemKey in row.keys) {
      if (itemKey != null &&
          itemKey.toString().toLowerCase() == key.toLowerCase()) {
        final Object? value = row[itemKey];
        return value?.toString() ?? '';
      }
    }
    return '';
  }

  Set<Weekday> _parseWeekdays(String raw) {
    final Set<Weekday> result = <Weekday>{};
    final String text = raw.trim();
    if (text.isEmpty) {
      return result;
    }
    final List<String> tokens = text.split(RegExp(r'[,，、;；/\s]+'));
    for (final String token in tokens) {
      final Weekday? day = _weekdayOf(token.trim());
      if (day != null) {
        result.add(day);
      }
    }
    return result;
  }

  Weekday? _weekdayOf(String raw) {
    final String value = raw.replaceAll(RegExp(r'\s+'), '');
    if (value.isEmpty) {
      return null;
    }
    final int? numeric = int.tryParse(value);
    if (numeric != null) {
      if (numeric >= 1 && numeric <= 7) {
        return Weekday.fromIsoIndex(numeric);
      }
      return null;
    }

    const Map<String, Weekday> names = <String, Weekday>{
      '周一': Weekday.monday,
      '星期一': Weekday.monday,
      '礼拜一': Weekday.monday,
      '一': Weekday.monday,
      'monday': Weekday.monday,
      'mon': Weekday.monday,
      '周二': Weekday.tuesday,
      '星期二': Weekday.tuesday,
      '礼拜二': Weekday.tuesday,
      '二': Weekday.tuesday,
      'tuesday': Weekday.tuesday,
      'tue': Weekday.tuesday,
      'tues': Weekday.tuesday,
      '周三': Weekday.wednesday,
      '星期三': Weekday.wednesday,
      '礼拜三': Weekday.wednesday,
      '三': Weekday.wednesday,
      'wednesday': Weekday.wednesday,
      'wed': Weekday.wednesday,
      '周四': Weekday.thursday,
      '星期四': Weekday.thursday,
      '礼拜四': Weekday.thursday,
      '四': Weekday.thursday,
      'thursday': Weekday.thursday,
      'thu': Weekday.thursday,
      'thur': Weekday.thursday,
      'thurs': Weekday.thursday,
      '周五': Weekday.friday,
      '星期五': Weekday.friday,
      '礼拜五': Weekday.friday,
      '五': Weekday.friday,
      'friday': Weekday.friday,
      'fri': Weekday.friday,
      '周六': Weekday.saturday,
      '星期六': Weekday.saturday,
      '礼拜六': Weekday.saturday,
      '六': Weekday.saturday,
      'saturday': Weekday.saturday,
      'sat': Weekday.saturday,
      '周日': Weekday.sunday,
      '周天': Weekday.sunday,
      '星期日': Weekday.sunday,
      '星期天': Weekday.sunday,
      '礼拜日': Weekday.sunday,
      '礼拜天': Weekday.sunday,
      '日': Weekday.sunday,
      '天': Weekday.sunday,
      'sunday': Weekday.sunday,
      'sun': Weekday.sunday,
    };

    final String lower = value.toLowerCase();
    final Weekday? exact = names[lower];
    if (exact != null) {
      return exact;
    }

    // 容错：从「第周一」等夹杂文案中提取单个星期字符。
    final Match? match = RegExp(r'([1-7一二三四五六日天])').firstMatch(value);
    if (match != null) {
      final String core = match.group(1)!;
      return names[core] ?? names[core.toLowerCase()];
    }
    return null;
  }

  (int, int)? _parsePeriods(Map<dynamic, dynamic> row) {
    final String periodRaw = _readMapped(row, 'period', 'period').trim();
    if (periodRaw.isNotEmpty) {
      final Match? range =
          RegExp(r'(\d+)\s*[-~－—–至到]\s*(\d+)').firstMatch(periodRaw);
      if (range != null) {
        return _normalizePeriods(
          int.parse(range.group(1)!),
          int.parse(range.group(2)!),
        );
      }
      final int? single = _readInt(periodRaw);
      if (single == null) {
        return null;
      }
      return _normalizePeriods(single, single);
    }

    final int? start = _readInt(_readMapped(row, 'startPeriod', 'startPeriod'));
    final int? end = _readInt(_readMapped(row, 'endPeriod', 'endPeriod'));
    if (start == null && end == null) {
      return null;
    }
    if (start == null || end == null) {
      final int value = start ?? end!;
      return _normalizePeriods(value, value);
    }
    return _normalizePeriods(start, end);
  }

  (int, int) _normalizePeriods(int rawStart, int rawEnd) {
    int start = rawStart < 1 ? 1 : rawStart;
    int end = rawEnd < 1 ? 1 : rawEnd;
    if (start > end) {
      final int temp = start;
      start = end;
      end = temp;
    }
    return (start, end);
  }

  /// 解析周次。
  ///
  /// 支持「1-16周」「1,3,5周」「1-16周(单/双)」以及 startWeek/endWeek。
  /// [Course] 只保存连续区间，离散周次取最小值到最大值。
  WeekRange? _parseWeeks(Map<dynamic, dynamic> row, int totalWeeks) {
    final String raw = _readMapped(row, 'weeks', 'weeks').trim();
    if (raw.isNotEmpty) {
      final bool oddOnly = raw.contains('单') && !raw.contains('双');
      final bool evenOnly = raw.contains('双') && !raw.contains('单');
      final Set<int> values = <int>{};

      for (final Match match
          in RegExp(r'(\d+)\s*[-~－—–至到]\s*(\d+)').allMatches(raw)) {
        final int a = int.parse(match.group(1)!);
        final int b = int.parse(match.group(2)!);
        final int from = a <= b ? a : b;
        final int to = a <= b ? b : a;
        for (int week = from; week <= to; week++) {
          values.add(week);
        }
      }
      for (final Match match in RegExp(r'\d+').allMatches(raw)) {
        values.add(int.parse(match.group(0)!));
      }

      if (oddOnly) {
        values.removeWhere((int week) => week.isEven);
      }
      if (evenOnly) {
        values.removeWhere((int week) => week.isOdd);
      }
      if (values.isEmpty) {
        return null;
      }
      final int start = values.reduce(math.min).clamp(1, totalWeeks).toInt();
      final int end = values.reduce(math.max).clamp(1, totalWeeks).toInt();
      if (start > end) {
        return null;
      }
      return WeekRange(start: start, end: end);
    }

    final int? startWeek = _readInt(_readMapped(row, 'startWeek', 'startWeek'));
    final int? endWeek = _readInt(_readMapped(row, 'endWeek', 'endWeek'));
    if (startWeek == null && endWeek == null) {
      // 完全没有周次信息时按整学期处理。
      return WeekRange(start: 1, end: totalWeeks);
    }
    final int start = (startWeek ?? 1).clamp(1, totalWeeks).toInt();
    final int end = (endWeek ?? totalWeeks).clamp(1, totalWeeks).toInt();
    if (start > end) {
      return null;
    }
    return WeekRange(start: start, end: end);
  }

  int? _readInt(Object? value) {
    if (value == null) {
      return null;
    }
    final Match? match = RegExp(r'\d+').firstMatch(value.toString());
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0)!);
  }

  String _asString(Object? value) => value?.toString() ?? '';

  // ---------------------------------------------------------------- 退出

  @override
  Future<void> logout() async {
    final WebViewController? webView = _webView;
    _webView = null;
    if (webView == null) {
      return;
    }
    try {
      // 停止当前加载并清空页面内容。
      await webView.loadRequest(Uri.parse('about:blank'));
    } catch (_) {
      // 控制器已失效时无需再处理，状态已清空。
    }
  }
}

/// 全屏登录页：用户在原生 WebView 中完成登录后点击「已完成登录」。
class _AcademicLoginPage extends StatefulWidget {
  const _AcademicLoginPage({
    required this.config,
    required this.controller,
    required this.initialUrl,
  });

  final AcademicSchoolConfig config;
  final WebViewController controller;
  final Uri initialUrl;

  @override
  State<_AcademicLoginPage> createState() => _AcademicLoginPageState();
}

class _AcademicLoginPageState extends State<_AcademicLoginPage> {
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int progress) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = progress);
        },
        onPageStarted: (String url) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = 0);
        },
      ),
    );
    widget.controller.loadRequest(widget.initialUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('登录教务系统'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('已完成登录'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_progress > 0 && _progress < 100)
              LinearProgressIndicator(value: _progress / 100),
            Expanded(child: WebViewWidget(controller: widget.controller)),
          ],
        ),
      ),
    );
  }
}
