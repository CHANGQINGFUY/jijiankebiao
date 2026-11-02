import 'package:flutter/widgets.dart';

import '../../models/course.dart';

/// 教务导入过程中的固定提示文案。
class AcademicMessages {
  const AcademicMessages._();

  /// 登录态失效、被重定向或返回 HTML 时的统一提示。
  static const String loginRequired = '教务系统可能需要重新登录或不支持自动导入，请改用 Excel 导入';
}

/// 一所学校的教务系统配置。
///
/// 新增学校时只需补充首页地址、课表接口地址与字段映射，
/// 无需为每所学校单独编写页面。
class AcademicSchoolConfig {
  const AcademicSchoolConfig({
    required this.id,
    required this.name,
    this.homeUrl = '',
    this.apiUrl = '',
    this.httpMethod = 'GET',
    this.responseFormat = 'json',
    this.enabled = true,
    this.note = '',
    this.fieldMap = const <String, String>{},
  });

  /// 学校唯一标识，用于关联保存在本机的账号密码。
  final String id;

  /// 学校名称。
  final String name;

  /// 教务系统首页地址，用于 WebView 登录。
  final String homeUrl;

  /// 课表接口地址，在 WebView 内用 fetch 请求。
  final String apiUrl;

  /// 请求方式：GET 或 POST。
  final String httpMethod;

  /// 返回格式：json 或 html。
  final String responseFormat;

  /// 是否启用；关闭后仍保留配置，便于以后恢复。
  final bool enabled;

  /// 备注，例如「需先在教务系统完成评教」。
  final String note;

  /// 字段映射，键为统一字段名，值为接口返回的字段名。
  ///
  /// 支持的键：listPath、name、teacher、room、weekday、period、
  /// startPeriod、endPeriod、weeks、startWeek、endWeek、semesterId。
  final Map<String, String> fieldMap;

  /// 首页与接口地址都已填写时才视为配置完成。
  bool get isConfigured => homeUrl.isNotEmpty && apiUrl.isNotEmpty;

  /// 是否按 JSON 解析。
  bool get isJson => responseFormat.toLowerCase() == 'json';

  /// 规范化后的请求方式，只接受 GET / POST。
  String get normalizedHttpMethod =>
      httpMethod.toUpperCase() == 'POST' ? 'POST' : 'GET';

  factory AcademicSchoolConfig.fromJson(Map<String, Object?> json) {
    final Map<String, String> fieldMap = <String, String>{};
    final Object? rawFieldMap = json['fieldMap'];
    if (rawFieldMap is Map) {
      for (final MapEntry<dynamic, dynamic> entry in rawFieldMap.entries) {
        final Object? key = entry.key;
        final Object? value = entry.value;
        if (key == null || value == null) {
          continue;
        }
        final String normalizedKey = key.toString().trim();
        if (normalizedKey.isEmpty) {
          continue;
        }
        fieldMap[normalizedKey] = value.toString().trim();
      }
    }

    final Object? enabledValue = json['enabled'];
    return AcademicSchoolConfig(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      homeUrl: (json['homeUrl'] as String?)?.trim() ?? '',
      apiUrl: (json['apiUrl'] as String?)?.trim() ?? '',
      httpMethod: (json['httpMethod'] as String?)?.trim() ?? 'GET',
      responseFormat: (json['responseFormat'] as String?)?.trim() ?? 'json',
      enabled: enabledValue is bool ? enabledValue : true,
      note: (json['note'] as String?)?.trim() ?? '',
      fieldMap: fieldMap,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'homeUrl': homeUrl,
        'apiUrl': apiUrl,
        'httpMethod': httpMethod,
        'responseFormat': responseFormat,
        'enabled': enabled,
        'note': note,
        'fieldMap': fieldMap,
      };

  AcademicSchoolConfig copyWith({
    String? id,
    String? name,
    String? homeUrl,
    String? apiUrl,
    String? httpMethod,
    String? responseFormat,
    bool? enabled,
    String? note,
    Map<String, String>? fieldMap,
  }) {
    return AcademicSchoolConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      homeUrl: homeUrl ?? this.homeUrl,
      apiUrl: apiUrl ?? this.apiUrl,
      httpMethod: httpMethod ?? this.httpMethod,
      responseFormat: responseFormat ?? this.responseFormat,
      enabled: enabled ?? this.enabled,
      note: note ?? this.note,
      fieldMap: fieldMap ?? this.fieldMap,
    );
  }
}

/// 导入失败的分类，便于 UI 或后续适配器区分处理。
enum AcademicErrorKind {
  notConfigured,
  loginRequired,
  unsupportedFormat,
  network,
  parse,
  cancelled,
  unknown,
}

/// 教务导入异常：所有对外抛出的错误都应带有明确的中文文案。
class AcademicImportException implements Exception {
  const AcademicImportException(this.kind, this.message);

  final AcademicErrorKind kind;

  /// 可直接展示给用户的中文提示。
  final String message;

  @override
  String toString() => message;
}

/// 登录结果。
class AcademicLoginResult {
  const AcademicLoginResult({required this.success, this.message});

  final bool success;

  /// 失败原因或提示，例如用户取消登录。
  final String? message;
}

/// 教务适配器：每所学校只需实现配置或继承该接口。
abstract class AcademicAdapter {
  /// 学校 id，与 [AcademicSchoolConfig.id] 一致。
  String get schoolId;

  /// 当前学校配置。
  AcademicSchoolConfig get config;

  /// 打开 WebView 让用户完成登录；返回是否已登录。
  Future<AcademicLoginResult> login(BuildContext context);

  /// 拉取并解析课表。
  Future<List<Course>> fetchTimetable({
    required String semesterId,
    required String semesterName,
    required int totalWeeks,
    required int colorSeedBase,
  });

  /// 退出登录并清理 WebView 状态。
  Future<void> logout();
}
