import 'package:flutter/material.dart';

/// Web 端教务系统导入占位页。
///
/// WebView 插件不支持 Web 平台，且教务系统存在跨域与登录会话限制，
/// 因此 Web 端不提供「在线探测导入」，仅引导用户改用 Excel / JSON 导入。
class FjlzyProbePage extends StatelessWidget {
  const FjlzyProbePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('从教务系统导入')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.language_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  '网页版暂不支持教务系统导入',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '教务系统需要在内置浏览器中登录并抓取课表，'
                  '网页端受跨域与登录会话限制无法完成。\n\n'
                  '请改用「从 Excel 导入课表」：在教务系统把课表另存为 '
                  'Excel，再回这里选择文件即可。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回设置'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
