/// 使用者的角色，决定首页展示哪一套视图。
enum UserRole {
  student('学生', '我的课程安排'),
  teacher('老师', '我的授课安排');

  const UserRole(this.label, this.description);

  /// 角色显示名，如「学生」。
  final String label;

  /// 该角色在首页的视图说明。
  final String description;
}
