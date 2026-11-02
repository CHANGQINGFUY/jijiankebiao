import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

/// Web 端备份文件读写：
/// - 导出：通过创建 Blob + 临时 <a download> 触发浏览器下载（Web 无文件系统写入权限）。
/// - 导入：复用 file_picker 的 Web 实现（input[type=file]）读取内容。
class BackupFileService {
  const BackupFileService._();

  /// 导出 JSON。Web 端实际是把内容作为文件触发浏览器下载，
  /// 返回给用户看的「保存位置」就是文件名本身。
  static Future<String> exportJson({
    required String json,
    required String fileName,
  }) async {
    final String name =
        fileName.endsWith('.json') ? fileName : '$fileName.json';
    final Uint8List bytes = utf8.encode(json);
    final web.Blob blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final String url = web.URL.createObjectURL(blob);
    final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return name;
  }

  /// 打开文件选择器选择 JSON，返回文件内容；用户取消时返回 null。
  static Future<String?> pickJson() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: '选择课表备份 JSON',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (files.isEmpty) {
      return null;
    }
    final Uint8List bytes = await files.first.readAsBytes();
    return utf8.decode(bytes);
  }
}
