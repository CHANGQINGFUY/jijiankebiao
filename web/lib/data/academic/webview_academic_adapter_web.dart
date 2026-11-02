import 'package:flutter/widgets.dart';

import '../../models/course.dart';
import 'academic_adapter.dart';

/// Web 端教务适配器存根。
///
/// WebView 插件不支持 Web 平台，且教务系统存在跨域与登录会话限制，
/// 因此 Web 端不提供在线导入，所有操作都返回明确的「不支持」提示。
class WebViewAcademicAdapter implements AcademicAdapter {
  WebViewAcademicAdapter(this._config);

  final AcademicSchoolConfig _config;

  @override
  String get schoolId => _config.id;

  @override
  AcademicSchoolConfig get config => _config;

  @override
  Future<AcademicLoginResult> login(BuildContext context) async {
    return const AcademicLoginResult(
      success: false,
      message: '网页版暂不支持教务系统导入，请改用「从 Excel 导入课表」。',
    );
  }

  @override
  Future<List<Course>> fetchTimetable({
    required String semesterId,
    required String semesterName,
    required int totalWeeks,
    required int colorSeedBase,
  }) async {
    throw const AcademicImportException(
      AcademicErrorKind.notConfigured,
      '网页版暂不支持教务系统导入，请改用「从 Excel 导入课表」。',
    );
  }

  @override
  Future<void> logout() async {}
}
