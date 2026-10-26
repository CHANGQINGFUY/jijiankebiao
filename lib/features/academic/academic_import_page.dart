import 'package:flutter/material.dart';
import 'package:schedule_app/features/import_excel/excel_import_page.dart';

import '../../data/academic/academic_adapter.dart';
import '../../data/academic/academic_school_registry.dart';
import '../../data/academic/webview_academic_adapter.dart';
import '../../models/course.dart';
import '../../services/academic_credential_store.dart';
import '../../state/schedule_controller.dart';
import '../../state/schedule_scope.dart';

/// 教务系统导入页：选择学校、填写（可选）账号密码，登录后拉取课表。
class AcademicImportPage extends StatefulWidget {
  const AcademicImportPage({super.key});

  @override
  State<AcademicImportPage> createState() => _AcademicImportPageState();
}

class _AcademicImportPageState extends State<AcademicImportPage> {
  final AcademicSchoolRegistry _registry = AcademicSchoolRegistry();
  final AcademicCredentialStore _credentialStore = AcademicCredentialStore();

  List<AcademicSchoolConfig> _schools = <AcademicSchoolConfig>[];
  bool _loading = true;

  /// 正在导入的学校 id；为空表示空闲。
  String? _importingSchoolId;

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  Future<void> _loadSchools() async {
    final List<AcademicSchoolConfig> schools = await _registry.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _schools = schools;
      _loading = false;
    });
  }

  Future<void> _addSchool() async {
    final AcademicSchoolConfig? config = await showDialog<AcademicSchoolConfig>(
      context: context,
      builder: (BuildContext dialogContext) => const _AddSchoolDialog(),
    );
    if (config == null) {
      return;
    }
    try {
      await _registry.save(config);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showMessage('保存学校配置失败：$error', title: '保存失败');
      return;
    }
    await _loadSchools();
  }

  Future<void> _startImport(AcademicSchoolConfig config) async {
    final ScheduleController controller = ScheduleScope.of(context);
    final String semesterId = controller.currentSemesterId;
    final String semesterName = controller.config.name;
    final int totalWeeks = controller.totalWeeks;
    final int colorSeedBase = controller.nextColorSeed;

    setState(() => _importingSchoolId = config.id);

    final AcademicAdapter adapter = WebViewAcademicAdapter(config);
    try {
      final AcademicLoginResult loginResult = await adapter.login(context);
      if (!mounted) {
        return;
      }
      if (!loginResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loginResult.message ?? '已取消登录')),
        );
        return;
      }

      final List<Course> courses = await adapter.fetchTimetable(
        semesterId: semesterId,
        semesterName: semesterName,
        totalWeeks: totalWeeks,
        colorSeedBase: colorSeedBase,
      );
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext pageContext) => CourseImportPreviewPage(
            drafts: courses,
            warnings: const <String>[],
            sourceLabel: '教务系统',
          ),
        ),
      );
    } on AcademicImportException catch (error) {
      if (!mounted) {
        return;
      }
      await _showMessage(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showMessage('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() => _importingSchoolId = null);
      }
    }
  }

  Future<void> _showMessage(String message, {String title = '导入失败'}) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教务系统导入'),
        actions: <Widget>[
          TextButton(
            onPressed: _loading ? null : _addSchool,
            child: const Text('添加学校'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_schools.isEmpty) {
      final ThemeData theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.school_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('暂无学校配置', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '点击右上角「添加学校」，填写教务首页与课表接口后即可登录导入。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _schools.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) {
        final AcademicSchoolConfig config = _schools[index];
        return _SchoolCard(
          key: ValueKey<String>(config.id),
          config: config,
          credentialStore: _credentialStore,
          importing: _importingSchoolId == config.id,
          onImport: () => _startImport(config),
        );
      },
    );
  }
}

/// 单所学校的卡片：展示配置状态、账号密码与导入按钮。
class _SchoolCard extends StatefulWidget {
  const _SchoolCard({
    super.key,
    required this.config,
    required this.credentialStore,
    required this.importing,
    required this.onImport,
  });

  final AcademicSchoolConfig config;
  final AcademicCredentialStore credentialStore;
  final bool importing;
  final Future<void> Function() onImport;

  @override
  State<_SchoolCard> createState() => _SchoolCardState();
}

class _SchoolCardState extends State<_SchoolCard> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _remember = false;
  bool _hasSavedAccount = false;
  bool _hasSavedPassword = false;
  bool _loadingCredentials = true;
  bool _saving = false;

  bool get _busy => widget.importing || _saving;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    ({String account, String password})? saved;
    try {
      saved = await widget.credentialStore.read(widget.config.id);
    } catch (_) {
      saved = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingCredentials = false;
      if (saved != null) {
        _accountController.text = saved.account;
        _hasSavedAccount = saved.account.isNotEmpty;
        _hasSavedPassword = saved.password.isNotEmpty;
        _remember = _hasSavedAccount || _hasSavedPassword;
      }
    });
  }

  Future<void> _handleImport() async {
    if (_busy) {
      return;
    }
    setState(() => _saving = true);

    String? validationMessage;
    try {
      final String account = _accountController.text.trim();
      final String password = _passwordController.text;
      if (_remember) {
        if (account.isEmpty) {
          validationMessage = '请填写学号后再记住账号。';
        } else {
          String effectivePassword = password;
          if (effectivePassword.isEmpty && _hasSavedPassword) {
            final ({String account, String password})? saved =
                await widget.credentialStore.read(widget.config.id);
            effectivePassword = saved == null ? '' : saved.password;
          }
          if (effectivePassword.isEmpty) {
            validationMessage = '请填写密码后再记住账号。';
          } else {
            await widget.credentialStore.save(
              widget.config.id,
              account,
              effectivePassword,
            );
            _hasSavedAccount = true;
            _hasSavedPassword = true;
            _passwordController.clear();
          }
        }
      } else if (_hasSavedAccount || _hasSavedPassword) {
        await widget.credentialStore.clear(widget.config.id);
        _hasSavedAccount = false;
        _hasSavedPassword = false;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      await _showLocalMessage('保存账号密码失败：$error');
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (validationMessage != null) {
      await _showLocalMessage(validationMessage);
      return;
    }
    await widget.onImport();
  }

  Future<void> _showLocalMessage(String message) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('提示'),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool disabled = _busy || _loadingCredentials;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.config.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                _ConfigBadge(configured: widget.config.isConfigured),
              ],
            ),
            if (widget.config.note.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(widget.config.note, style: theme.textTheme.bodySmall),
            ],
            if (widget.config.homeUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '教务首页：${widget.config.homeUrl}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const Divider(height: 24),
            Text('账号密码（可选，仅存本机）', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _accountController,
              enabled: !disabled,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '学号',
                hintText: '请输入学号',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              enabled: !disabled,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: _hasSavedPassword ? '已保存' : '请输入密码',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('记住账号密码'),
              subtitle: const Text('仅保存到本机系统安全存储'),
              value: _remember,
              onChanged: disabled
                  ? null
                  : (bool value) => setState(() => _remember = value),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '登录后可在预览页选择要导入的课程。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _handleImport,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 18),
                  label: Text(_busy ? '正在导入…' : '登录并导入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 配置状态标签。
class _ConfigBadge extends StatelessWidget {
  const _ConfigBadge({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: configured
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        configured ? '已配置接口' : '未配置接口',
        style: theme.textTheme.labelSmall?.copyWith(
          color:
              configured ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 添加学校对话框：只收集配置，保存由页面完成。
class _AddSchoolDialog extends StatefulWidget {
  const _AddSchoolDialog();

  @override
  State<_AddSchoolDialog> createState() => _AddSchoolDialogState();
}

class _AddSchoolDialogState extends State<_AddSchoolDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _homeUrlController = TextEditingController();
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _fieldMapController = TextEditingController();

  String _httpMethod = 'GET';
  String _responseFormat = 'json';

  @override
  void dispose() {
    _nameController.dispose();
    _homeUrlController.dispose();
    _apiUrlController.dispose();
    _fieldMapController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(text);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '请输入 http:// 或 https:// 开头的地址';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    final AcademicSchoolConfig config = AcademicSchoolConfig(
      id: 'school-${DateTime.now().microsecondsSinceEpoch}',
      name: _nameController.text.trim(),
      homeUrl: _homeUrlController.text.trim(),
      apiUrl: _apiUrlController.text.trim(),
      httpMethod: _httpMethod,
      responseFormat: _responseFormat,
      fieldMap: _parseFieldMap(_fieldMapController.text),
    );
    Navigator.of(context).pop(config);
  }

  Map<String, String> _parseFieldMap(String raw) {
    final Map<String, String> result = <String, String>{};
    for (final String line in raw.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final int index = trimmed.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final String key = trimmed.substring(0, index).trim();
      final String value = trimmed.substring(index + 1).trim();
      if (key.isEmpty) {
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加学校'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '学校名称',
                    hintText: '例如：某某大学',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (String? value) =>
                      (value?.trim() ?? '').isEmpty ? '请填写学校名称' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _homeUrlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '教务首页地址',
                    hintText: 'https://jw.example.edu.cn',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: _validateUrl,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiUrlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '课表接口地址',
                    hintText: 'https://jw.example.edu.cn/api/schedule',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: _validateUrl,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _httpMethod,
                  decoration: const InputDecoration(
                    labelText: '请求方式',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'GET', child: Text('GET')),
                    DropdownMenuItem<String>(
                        value: 'POST', child: Text('POST')),
                  ],
                  onChanged: (String? value) {
                    setState(() => _httpMethod = value ?? 'GET');
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _responseFormat,
                  decoration: const InputDecoration(
                    labelText: '返回格式',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                        value: 'json', child: Text('JSON')),
                    DropdownMenuItem<String>(
                        value: 'html', child: Text('HTML')),
                  ],
                  onChanged: (String? value) {
                    setState(() => _responseFormat = value ?? 'json');
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fieldMapController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '字段映射',
                    hintText: 'listPath=data.list\nname=courseName\n'
                        'teacher=teacherName\nroom=roomName\n'
                        'weekday=weekday\nperiod=period\nweeks=weeks',
                    helperText: '每行一条 key=value；键：listPath、name、teacher、'
                        'room、weekday、period、startPeriod、endPeriod、weeks、'
                        'startWeek、endWeek、semesterId',
                    helperMaxLines: 4,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
