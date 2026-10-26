import 'package:flutter/material.dart';

/// 课程配色：使用固定调色板，保证同一门课在明暗主题下颜色稳定。
class CourseColors {
  const CourseColors._();

  static const List<Color> _palette = <Color>[
    Color(0xFF3B6EF6),
    Color(0xFF19A974),
    Color(0xFFF2994A),
    Color(0xFF9B51E0),
    Color(0xFFEB5757),
    Color(0xFF2D9CDB),
  ];

  /// 按种子值取色，越界时自动回绕。
  static Color of(int seed) => _palette[seed.abs() % _palette.length];

  /// 完整调色板，供颜色选择器展示。
  static List<Color> get palette => List<Color>.unmodifiable(_palette);
}
