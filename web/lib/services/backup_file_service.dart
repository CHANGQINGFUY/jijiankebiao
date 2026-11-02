/// 跨平台备份服务入口，按编译平台自动选择实现：
/// - Web：触发浏览器下载（见 backup_file_service_web.dart）。
/// - iOS / Android：写入应用沙盒或公共下载目录（见 backup_file_service_io.dart）。
library;

export 'backup_file_service_io.dart'
    if (dart.library.html) 'backup_file_service_web.dart';
