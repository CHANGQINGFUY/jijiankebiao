/// 福建林业职业技术学院教务系统（正方 zftal-ui-v5-1.0.2 / V-9.0）固定信息。
///
/// 该校接口与页面路径已确认，因此这里直接硬编码，不做通用猜测。
class FjlzySchool {
  const FjlzySchool._();

  static const String name = '福建林业职业技术学院';
  static const String origin = 'https://zfjw.fjlzy.com';
  static const String basePath = '/jwglxt';
  static const String systemName = '正方 V-9.0（zftal-ui-v5-1.0.2）';

  /// 登录页（实测需带 /xtgl/ 前缀，否则返回 404「您访问的页面不存在哦」）。
  static const String loginUrl = '$origin$basePath/xtgl/login_slogin.html';

  /// 课表查询页（2026-10 真机实测地址）。
  static const String timetableUrl =
      '$origin$basePath/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default';

  /// 学校代码，对应登录页 hidden 字段 xxdm。
  static const String schoolCode = '12625';

  /// 登录表单字段名（仅用于说明，实际登录在 WebView 内由用户完成）。
  static const String usernameField = 'yhm';
  static const String passwordField = 'mm';
  static const String csrfField = 'csrftoken';

  static bool isLoginUrl(String url) => url.contains('login_slogin.html');

  static bool isTimetableUrl(String url) =>
      url.contains('/kbcx/') || url.contains('kbcx_') || url.contains('xskbcx');
}
