import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 网页端文件选择的结果。
class PickedWebFile {
  const PickedWebFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 网页端文件选择器。
///
/// 不复用 file_picker 的 Web 实现：它把 `<input type="file">` 设为
/// `display: none`，并且用 window 的 `focus` 事件判断「用户取消」。
/// Safari（尤其 iOS）对隐藏的 input 不会弹出选择框，`focus` 也可能
/// 在选择框刚打开时就触发，导致看起来点了没反应。
///
/// 这里改成：透明的 input 固定在视口内，选择结束前一直保留在 DOM 中，
/// 只监听 `change` / `cancel`，不提前按窗口焦点判断取消。
class WebFilePicker {
  const WebFilePicker._();

  static Future<PickedWebFile?> pick({
    required List<String> extensions,
    String? accept,
  }) {
    final String acceptValue =
        accept ?? extensions.map((String e) => '.$e').join(',');

    final web.HTMLInputElement input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = acceptValue
      ..multiple = false;

    // 不能用 display: none —— Safari 会忽略隐藏 input 的 click。
    // opacity: 0 且位于视口内，既不可见又能正常弹出选择框。
    input.style
      ..position = 'fixed'
      ..top = '0'
      ..left = '0'
      ..width = '1px'
      ..height = '1px'
      ..opacity = '0';

    final Completer<PickedWebFile?> completer = Completer<PickedWebFile?>();
    bool finished = false;

    void finish(web.File? file) {
      if (finished) {
        return;
      }
      finished = true;
      input.remove();
      if (file == null) {
        completer.complete(null);
        return;
      }
      Future<void>(() async {
        try {
          final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
          if (!completer.isCompleted) {
            completer.complete(
              PickedWebFile(
                name: file.name,
                bytes: buffer.toDart.asUint8List(),
              ),
            );
          }
        } catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      });
    }

    input.addEventListener(
      'change',
      ((web.Event event) {
        final web.FileList? files = input.files;
        finish(files == null || files.length == 0 ? null : files.item(0));
      }).toJS,
    );
    // Safari 16.4+ / Chrome 113+ 支持 cancel。旧浏览器取消时只是这一次的
    // Future 不会完成，不影响再次点击导入。
    input.addEventListener(
      'cancel',
      ((web.Event event) => finish(null)).toJS,
    );

    web.document.body?.append(input);
    input.click();
    return completer.future;
  }
}
