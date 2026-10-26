import 'package:flutter/material.dart';

import '../models/user_role.dart';

/// 首页顶部信息卡：问候语 + 当前身份，点右侧按钮可在学生端/老师端之间切换。
class RoleBanner extends StatelessWidget {
  const RoleBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.role,
    required this.onSwitchRole,
  });

  final String title;
  final String subtitle;
  final UserRole role;
  final VoidCallback onSwitchRole;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isStudent = role == UserRole.student;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ActionChip(
              avatar: Icon(
                isStudent ? Icons.school_outlined : Icons.co_present_outlined,
                size: 18,
              ),
              label: Text(isStudent ? '切换到老师端' : '切换到学生端'),
              onPressed: onSwitchRole,
            ),
          ],
        ),
      ),
    );
  }
}
