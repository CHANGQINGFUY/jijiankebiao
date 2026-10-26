import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/academic/academic_probe_scripts.dart';
import '../../data/academic/academic_school.dart';
import '../../data/academic/academic_timetable_parser.dart';
import '../../services/academic_credential_store.dart';
import '../../services/backup_file_service.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';
import '../import_excel/excel_import_page.dart';

/// 教务系统 WebView 导入页。
///
/// 只做「登录 + 探测」，不做猜测式解析：探测结果先给用户确认，
/// 确认页面结构后再编写解析器。
class AcademicProbePage extends StatefulWidget {
  const AcademicProbePage({super.key});

  @override
  State<AcademicProbePage> createState() => _AcademicProbePageState();
}

class _AcademicProbePageState extends State<AcademicProbePage> {
  late final WebViewController _controller;

  final AcademicCredentialStore _credentialStore = AcademicCredentialStore();
  final List<String> _logs = <String>[];
  Timer? _timeoutTimer;
  Timer? _importTimer;
  Timer? _retryTimer;
  int _retryCount = 0;
  String _currentUrl = AcademicSchool.loginUrl;
  String _pageTitle = AcademicSchool.name;
  bool _loading = true;
  bool _timedOut = false;
  bool _probing = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // 教务系统依赖 JavaScript 与 DOM storage（Android WebView 默认开启 DOM storage）。
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..addJavaScriptChannel(
        'AcademicProbe',
        onMessageReceived: _onChannelMessage,
      )
      ..addJavaScriptChannel(
        'AcademicImport',
        onMessageReceived: _onImportMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            _startLoading(url);
            _installHooks();
          },
          onPageFinished: (String url) async {
            _timeoutTimer?.cancel();
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
              _currentUrl = url;
            });
            _installHooks();
            await _refreshTitle();
            await _checkErrorPage();
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            final bool retriable =
                error.errorType == WebResourceErrorType.failedSslHandshake ||
                    error.errorType == WebResourceErrorType.connect ||
                    error.errorType == WebResourceErrorType.hostLookup ||
                    error.errorType == WebResourceErrorType.timeout ||
                    error.errorType == WebResourceErrorType.io;
            if (retriable && _retryCount < 2) {
              _scheduleRetry('页面加载失败（${error.description}）');
              return;
            }
            _showSnack('页面加载失败：${error.description}');
          },
          onHttpError: (HttpResponseError error) {
            final int? status = error.response?.statusCode;
            if (status != null && status >= 500 && _retryCount < 2) {
              _scheduleRetry('教务系统返回 HTTP $status');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(AcademicSchool.loginUrl));
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _importTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  /// 教务系统偶发返回「系统维护 / 页面不存在」的错误页，自动重试。
  Future<void> _checkErrorPage() async {
    try {
      final Object raw = await _controller.runJavaScriptReturningResult(
        '(document.body && document.body.innerText ? document.body.innerText : "").slice(0, 300)',
      );
      final String text = _decodeJsString(raw);
      final bool bad =
          text.contains('系统维护') || text.contains('页面不存在');
      if (bad && _retryCount < 2) {
        _scheduleRetry('教务系统返回异常页面');
        return;
      }
      _retryCount = 0;
    } catch (_) {}
  }

  void _scheduleRetry(String reason) {
    _retryTimer?.cancel();
    _retryCount++;
    setState(() {
      _loading = true;
      _timedOut = false;
    });
    _showSnack('$reason，正在重试（$_retryCount/2）…');
    _retryTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) {
        return;
      }
      _controller.reload();
    });
  }

  void _startLoading(String url) {
    _timeoutTimer?.cancel();
    setState(() {
      _loading = true;
      _timedOut = false;
      _currentUrl = url;
    });
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || !_loading) {
        return;
      }
      setState(() {
        _loading = false;
        _timedOut = true;
      });
    });
  }

  Future<void> _installHooks() async {
    try {
      await _controller.runJavaScript(AcademicProbeScripts.installHooks);
    } catch (_) {
      // 页面尚未就绪时注入失败可以忽略，onPageFinished 会再注入一次。
    }
  }

  Future<void> _refreshTitle() async {
    try {
      final Object raw =
          await _controller.runJavaScriptReturningResult('document.title');
      final String title = _decodeJsString(raw);
      if (!mounted || title.trim().isEmpty) {
        return;
      }
      setState(() => _pageTitle = title.trim());
    } catch (_) {}
  }

  String _decodeJsString(Object? raw) {
    final String text = raw?.toString() ?? '';
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        final Object? decoded = jsonDecode(text);
        if (decoded is String) {
          return decoded;
        }
      } catch (_) {}
    }
    return text;
  }

  void _onChannelMessage(JavaScriptMessage message) {
    final String raw = message.message;
    if (raw.startsWith('LOG:')) {
      if (_logs.length >= 200) {
        return;
      }
      setState(() => _logs.add(raw.substring(4)));
      return;
    }
    if (raw.startsWith('ERROR:')) {
      _showSnack('探测脚本执行出错：${raw.substring(6)}');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _probing = false);
    Map<String, dynamic>? result;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        result = decoded;
      }
    } catch (error) {
      _showSnack('探测结果解析失败：$error');
      return;
    }
    if (result == null) {
      _showSnack('探测结果格式不正确。');
      return;
    }
    _openResult(result, raw);
  }

  Future<void> _openResult(
    Map<String, dynamic> result,
    String rawJson,
  ) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => AcademicProbeResultPage(
          result: result,
          rawJson: rawJson,
          logs: List<String>.of(_logs),
        ),
      ),
    );
  }

  Future<void> _runProbe() async {
    if (_probing) {
      return;
    }
    if (AcademicSchool.isLoginUrl(_currentUrl)) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('还在登录页'),
          content: const Text(
            '请先在页面中输入学号与密码完成登录，'
            '再点击菜单进入「课表查询」页面，然后回到这里点右上角的探测按钮。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _probing = true);
    _showSnack('正在探测当前页面结构…');
    try {
      await _controller.runJavaScript(AcademicProbeScripts.probe);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _probing = false);
      _showSnack('探测失败：$error');
    }
  }

  /// 在课表结果页执行提取脚本，把结构化条目交给解析器。
  Future<void> _runImport() async {
    if (_importing) {
      return;
    }
    if (AcademicSchool.isLoginUrl(_currentUrl)) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('还在登录页'),
          content: const Text('请先登录并进入「个人课表查询」结果页，再解析导入。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _importing = true);
    _showSnack('正在解析课表结构…');
    _importTimer?.cancel();
    _importTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || !_importing) {
        return;
      }
      setState(() => _importing = false);
      _showSnack('解析超时，请确认页面停留在「个人课表查询」结果页后重试');
    });
    try {
      await _controller.runJavaScript(AcademicTimetableParser.extractScript);
    } catch (error) {
      _importTimer?.cancel();
      if (!mounted) {
        return;
      }
      setState(() => _importing = false);
      _showSnack('解析失败：$error');
    }
  }

  void _onImportMessage(JavaScriptMessage message) {
    final String raw = message.message;
    if (raw.startsWith('ERROR:')) {
      _importTimer?.cancel();
      if (mounted) {
        setState(() => _importing = false);
      }
      _showSnack('解析脚本出错：${raw.substring(6)}');
      return;
    }
    if (!raw.startsWith('COURSE:')) {
      return;
    }
    _importTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _importing = false);

    Map<String, dynamic>? payload;
    try {
      final Object? decoded = jsonDecode(raw.substring(7));
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    } catch (error) {
      _showSnack('解析结果不是合法 JSON：$error');
      return;
    }
    if (payload == null) {
      _showSnack('解析结果格式不正确');
      return;
    }
    _openImportPreview(payload);
  }

  Future<void> _openImportPreview(Map<String, dynamic> payload) async {
    final ScheduleController controller = ScheduleScope.of(context);
    final AcademicParseResult result = AcademicTimetableParser.parse(
      payload,
      semesterId: controller.currentSemesterId,
      academicTerm: controller.config.name,
      totalWeeks: controller.totalWeeks,
      totalPeriods: controller.periods.length,
      colorSeedBase: controller.nextColorSeed,
    );

    if (result.courses.isEmpty) {
      final List<String> messages = result.errors.isEmpty
          ? <String>['未检测到课表数据，请确认已在课表查询结果页面']
          : result.errors.take(8).toList();
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('解析失败'),
          content: SingleChildScrollView(
            child: Text(
              '${messages.join('\n')}\n\n'
              '请确认页面停留在「个人课表查询」结果页，'
              '并在网页上切换到「列表」视图后重试。',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    if (result.errors.isNotEmpty) {
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text('有 ${result.errors.length} 条未能解析'),
          content: SingleChildScrollView(
            child: Text(
              '${result.errors.take(8).join('\n')}\n\n'
              '仍要继续导入已解析的 ${result.courses.length} 条课程吗？',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) {
        return;
      }
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => CourseImportPreviewPage(
          drafts: result.courses,
          warnings: result.warnings,
          sourceLabel: '教务系统 · ${result.term}',
        ),
      ),
    );
  }

  /// 账号密码只写入系统安全存储，界面不回显已保存的密码。
  Future<void> _openCredentials() async {
    ({String account, String password})? saved;
    try {
      saved = await _credentialStore.read(AcademicSchool.schoolCode);
    } catch (_) {
      saved = null;
    }
    if (!mounted) {
      return;
    }
    final ({String account, String password, bool remember})? input =
        await showDialog<({String account, String password, bool remember})>(
      context: context,
      builder: (BuildContext dialogContext) => _CredentialsDialog(
        initialAccount: saved?.account ?? '',
        hasSavedPassword: (saved?.password.isNotEmpty ?? false),
      ),
    );
    if (input == null || !mounted) {
      return;
    }

    final String account = input.account.trim();
    String password = input.password;
    if (password.isEmpty && saved != null) {
      password = saved.password;
    }
    try {
      if (input.remember && account.isNotEmpty && password.isNotEmpty) {
        await _credentialStore.save(
          AcademicSchool.schoolCode,
          account,
          password,
        );
      } else if (!input.remember) {
        await _credentialStore.clear(AcademicSchool.schoolCode);
      }
    } catch (_) {
      // 安全存储不可用时不影响本次填入。
    }
    if (!mounted) {
      return;
    }
    if (account.isEmpty || password.isEmpty) {
      _showSnack('请先填写学号与密码');
      return;
    }

    final bool filled = await _fillLoginForm(account, password);
    if (!mounted) {
      return;
    }
    _showSnack(
      filled ? '已填入学号与密码，请点击网页上的「登录」' : '当前页面没有登录表单，请先「回到登录页」',
    );
  }

  Future<bool> _fillLoginForm(String account, String password) async {
    final String script = '''
(function () {
  var u = document.getElementById('${AcademicSchool.usernameField}');
  var p = document.getElementById('${AcademicSchool.passwordField}');
  if (!u || !p) { return 'not-login'; }
  u.value = ${jsonEncode(account)};
  p.value = ${jsonEncode(password)};
  u.dispatchEvent(new Event('input', { bubbles: true }));
  p.dispatchEvent(new Event('input', { bubbles: true }));
  return 'ok';
})();
''';
    try {
      final Object raw = await _controller.runJavaScriptReturningResult(script);
      return _decodeJsString(raw).contains('ok');
    } catch (_) {
      return false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool onLogin = AcademicSchool.isLoginUrl(_currentUrl);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(AcademicSchool.name, style: theme.textTheme.titleMedium),
            Text(
              _pageTitle.trim().isEmpty ? '教务系统' : _pageTitle,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '直接打开课表查询页',
            onPressed: () => _controller.loadRequest(
              Uri.parse(AcademicSchool.timetableUrl),
            ),
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: '账号密码（只存本机）',
            onPressed: _openCredentials,
            icon: const Icon(Icons.key_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '探测课表页结构',
            onPressed: _probing ? null : _runProbe,
            icon: const Icon(Icons.radar),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_timedOut)
              _TimeoutBanner(
                onRetry: () {
                  setState(() => _timedOut = false);
                  _controller.reload();
                },
              ),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    onLogin
                        ? '请在上方网页登录，登录后点菜单进入「课表查询」，再点右上角探测。'
                        : '已离开登录页。请在网页中进入「课表查询」结果页，再点右上角探测。',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _controller.loadRequest(
                            Uri.parse(AcademicSchool.loginUrl),
                          ),
                          child: const Text('回到登录页'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _probing ? null : _runProbe,
                          icon: const Icon(Icons.radar),
                          label: Text(_probing ? '探测中…' : '探测课表页'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _importing ? null : _runImport,
                      icon: const Icon(Icons.download_done),
                      label: Text(_importing ? '解析中…' : '解析并导入课表'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({
    required this.initialAccount,
    required this.hasSavedPassword,
  });

  final String initialAccount;
  final bool hasSavedPassword;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final TextEditingController _account =
      TextEditingController(text: widget.initialAccount);
  final TextEditingController _password = TextEditingController();
  late bool _remember =
      widget.initialAccount.isNotEmpty || widget.hasSavedPassword;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_remember && _account.text.trim().isEmpty) {
      setState(() => _error = '请填写学号后再记住账号');
      return;
    }
    Navigator.of(context).pop((
      account: _account.text,
      password: _password.text,
      remember: _remember,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('学号与密码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _account,
              decoration: const InputDecoration(
                labelText: '学号',
                hintText: '教务系统用户名（yhm）',
              ),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: widget.hasSavedPassword
                    ? '已保存，留空则沿用上次密码'
                    : '教务系统密码（mm）',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (bool? value) =>
                  setState(() => _remember = value ?? false),
              title: const Text('记住在本机（系统安全存储）'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '只写入本机安全存储，不上传第三方、不写日志、不在界面回显已保存的密码。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('填入登录页'),
        ),
      ],
    );
  }
}

class _TimeoutBanner extends StatelessWidget {
  const _TimeoutBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '教务系统响应超时，请检查网络',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 探测结果展示页：把 WebView 采集到的结构原样呈现，供确认后再写解析器。
class AcademicProbeResultPage extends StatelessWidget {
  const AcademicProbeResultPage({
    super.key,
    required this.result,
    required this.rawJson,
    this.logs = const <String>[],
  });

  final Map<String, dynamic> result;
  final String rawJson;
  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<dynamic> tables = _list('tables');
    final List<dynamic> ajax = _list('ajax');
    final List<dynamic> keywords = _list('keywords');
    final List<dynamic> iframes = _list('iframes');
    final Map<String, dynamic> storage = _map('storage');
    final bool noData = tables.isEmpty && keywords.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('探测结果'),
        actions: <Widget>[
          IconButton(
            tooltip: '保存探测结果到下载目录',
            onPressed: () => _saveToDownloads(context),
            icon: const Icon(Icons.save_alt),
          ),
          IconButton(
            tooltip: '复制完整 JSON',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: rawJson));
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('探测结果已复制，可直接粘贴发送')),
              );
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (noData)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '未检测到课表数据，请确认已在课表查询结果页面。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            _Section(
              title: '页面信息',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _kv(context, 'URL', '${result['url'] ?? ''}'),
                  _kv(context, '标题', '${result['title'] ?? ''}'),
                  _kv(context, '表格数量', '${tables.length}'),
                  _kv(context, 'AJAX 请求', '${ajax.length}'),
                  _kv(context, '关键词命中', '${keywords.length}'),
                  _kv(context, 'iframe', '${iframes.length}'),
                ],
              ),
            ),
            _Section(
              title: '表格结构（${tables.length}）',
              child: tables.isEmpty
                  ? _emptyText(context)
                  : Column(
                      children: <Widget>[
                        for (int index = 0; index < tables.length; index++)
                          _TableCard(
                            index: index,
                            data: tables[index] is Map<String, dynamic>
                                ? tables[index] as Map<String, dynamic>
                                : <String, dynamic>{},
                          ),
                      ],
                    ),
            ),
            _Section(
              title: 'AJAX / fetch 请求（${ajax.length}）',
              child: ajax.isEmpty
                  ? _emptyText(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final dynamic item in ajax)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SelectableText(
                              item is Map
                                  ? '${item['method'] ?? ''} ${item['url'] ?? ''}'
                                  : '$item',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
            ),
            _Section(
              title: '关键词命中的 DOM 元素（${keywords.length}）',
              child: keywords.isEmpty
                  ? _emptyText(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final dynamic item in keywords)
                          if (item is Map)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '${item['keyword']} · ${item['tag']}'
                                '${_idClass(item as Map<String, dynamic>)}'
                                '：${item['text'] ?? ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                      ],
                    ),
            ),
            _Section(
              title: 'localStorage / sessionStorage（${storage.length}）',
              child: storage.isEmpty
                  ? _emptyText(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final MapEntry<String, dynamic> entry
                            in storage.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SelectableText(
                              '${entry.key} = ${entry.value}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
            ),
            if (logs.isNotEmpty)
              _Section(
                title: '控制台日志（${logs.length}）',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final String line in logs.take(40))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: SelectableText(
                          line,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            _Section(
              title: '课表容器 HTML 片段',
              child: SelectableText(
                '${result['containerHtml'] ?? ''}'.isEmpty
                    ? '（未匹配到 #kbtable / [class*=kb] 之类的容器，见下方整页片段）'
                    : '${result['containerHtml']}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            _Section(
              title: '整页 HTML 片段（前 6000 字符）',
              child: SelectableText(
                '${result['bodyHtmlSnippet'] ?? ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            _Section(
              title: '完整 JSON',
              child: SelectableText(
                rawJson,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToDownloads(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final String stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final String path = await BackupFileService.exportJson(
        json: rawJson,
        fileName: 'academic_probe_$stamp.json',
      );
      messenger.showSnackBar(SnackBar(content: Text('已保存到 $path')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  List<dynamic> _list(String key) {
    final Object? value = result[key];
    return value is List ? value : <dynamic>[];
  }

  Map<String, dynamic> _map(String key) {
    final Object? value = result[key];
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  }

  String _idClass(Map<String, dynamic> item) {
    final String id = '${item['id'] ?? ''}';
    final String cls = '${item['cls'] ?? ''}';
    if (id.isEmpty && cls.isEmpty) {
      return '';
    }
    return '（${id.isEmpty ? '' : '#$id'}${cls.isEmpty ? '' : '.$cls'}）';
  }

  Widget _emptyText(BuildContext context) {
    return Text('（无）', style: Theme.of(context).textTheme.bodySmall);
  }

  Widget _kv(BuildContext context, String key, String value) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(key, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.index, required this.data});

  final int index;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<dynamic> rows =
        data['rows'] is List ? data['rows'] as List<dynamic> : <dynamic>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '#$index ${data['source'] ?? ''} '
            'id=${data['id'] ?? ''} class=${data['cls'] ?? ''} '
            '行=${data['rowCount'] ?? 0} 列=${data['colCount'] ?? 0}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SelectableText(
                '第${i + 1}行：'
                '${rows[i] is List ? (rows[i] as List<dynamic>).join(' | ') : rows[i]}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
