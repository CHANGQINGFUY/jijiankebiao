/// 教务系统接入参数（正方 zftal-ui-v5 / V-9.0）。
///
/// 具体学校的域名、学校代码属于本地私有信息，不写入本仓库：
/// 构建时通过 `--dart-define-from-file=academic.local.json`（或逐项 `--dart-define`）注入。
/// 未注入时使用中性占位值，仅用于编译与界面预览，无法真正登录。
class AcademicSchool {
  const AcademicSchool._();

  static const String name = String.fromEnvironment(
    'ACADEMIC_SCHOOL_NAME',
    defaultValue: '示例学院',
  );

  static const String origin = String.fromEnvironment(
    'ACADEMIC_SCHOOL_ORIGIN',
    defaultValue: 'https://jw.example.edu.cn',
  );

  static const String basePath = String.fromEnvironment(
    'ACADEMIC_BASE_PATH',
    defaultValue: '/jwglxt',
  );

  static const String systemName = '正方教务（zftal-ui-v5）';

  /// 登录页（实测需带 /xtgl/ 前缀，否则可能返回「页面不存在」）。
  static const String loginUrl = String.fromEnvironment(
    'ACADEMIC_LOGIN_URL',
    defaultValue: '$origin$basePath/xtgl/login_slogin.html',
  );

  /// 课表查询页。
  static const String timetableUrl = String.fromEnvironment(
    'ACADEMIC_TIMETABLE_URL',
    defaultValue:
        '$origin$basePath/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default',
  );

  /// 学校代码，对应登录页 hidden 字段 xxdm；同时用作本机凭据存储的 key。
  static const String schoolCode = String.fromEnvironment(
    'ACADEMIC_SCHOOL_CODE',
    defaultValue: 'example',
  );

  /// 登录表单字段名（仅在自动填充时使用，实际登录在 WebView 内由用户完成）。
  static const String usernameField = 'yhm';
  static const String passwordField = 'mm';
  static const String csrfField = 'csrftoken';

  static bool isLoginUrl(String url) => url.contains('login_slogin.html');

  static bool isTimetableUrl(String url) =>
      url.contains('/kbcx/') || url.contains('kbcx_') || url.contains('xskbcx');
}
