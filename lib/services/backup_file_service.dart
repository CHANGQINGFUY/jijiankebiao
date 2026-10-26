import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 跨平台备份文件读写（无原生 Channel，两端行为一致）：
/// - 导出：iOS 写入应用文档目录（沙盒）；Android 优先公共「下载」目录，
///   分区存储（Android 10+）不允许直接写入时退回应用专属外部目录。
/// - 导入：通过系统文件选择器读取 JSON 内容，用户取消时返回 null。
class BackupFileService {
  const BackupFileService._();

  /// 导出 JSON，返回文件实际保存的绝对路径。
  static Future<String> exportJson({
    required String json,
    required String fileName,
  }) async {
    final String name =
        fileName.endsWith('.json') ? fileName : '$fileName.json';

    final List<Directory> candidates = <Directory>[];
    if (Platform.isAndroid) {
      final Directory? downloads = await getDownloadsDirectory();
      if (downloads != null) {
        candidates.add(downloads);
      }
      final Directory? external = await getExternalStorageDirectory();
      if (external != null) {
        candidates.add(external);
      }
    }
    candidates.add(await getApplicationDocumentsDirectory());

    Object? lastError;
    for (final Directory dir in candidates) {
      try {
        final File file = File('${dir.path}${Platform.pathSeparator}$name');
        await file.writeAsString(json);
        return file.path;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('导出失败：$lastError');
  }

  /// 打开系统文件选择器选择 JSON，返回文件内容；用户取消时返回 null。
  static Future<String?> pickJson() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: '选择课表备份 JSON',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (files.isEmpty) {
      return null;
    }
    final List<int> bytes = await files.first.readAsBytes();
    return utf8.decode(bytes);
  }
}
