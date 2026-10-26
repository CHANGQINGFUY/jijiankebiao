import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 教务系统账号密码存储。
///
/// 只写入系统安全存储（flutter_secure_storage），不写日志、不打印，
/// 也不参与任何网络上传。
class AcademicCredentialStore {
  AcademicCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _prefix = 'academic_';

  final FlutterSecureStorage _storage;

  String _accountKey(String schoolId) => '$_prefix${schoolId}_account';

  String _passwordKey(String schoolId) => '$_prefix${schoolId}_password';

  /// 保存某个学校的账号密码。
  Future<void> save(String schoolId, String account, String password) async {
    await _storage.write(key: _accountKey(schoolId), value: account);
    await _storage.write(key: _passwordKey(schoolId), value: password);
  }

  /// 读取某个学校已保存的账号密码；不存在时返回 null。
  Future<({String account, String password})?> read(String schoolId) async {
    final String? account = await _storage.read(key: _accountKey(schoolId));
    final String? password = await _storage.read(key: _passwordKey(schoolId));
    if (account == null && password == null) {
      return null;
    }
    return (account: account ?? '', password: password ?? '');
  }

  /// 清除某个学校已保存的账号密码。
  Future<void> clear(String schoolId) async {
    await _storage.delete(key: _accountKey(schoolId));
    await _storage.delete(key: _passwordKey(schoolId));
  }
}
