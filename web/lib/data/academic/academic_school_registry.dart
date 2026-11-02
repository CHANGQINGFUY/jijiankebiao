import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'academic_adapter.dart';

/// 教务学校注册表。
///
/// 默认学校来自 asset，用户自定义学校保存在 shared_preferences；
/// 两者按 id 合并，自定义配置覆盖同 id 的内置配置。
/// 所有读取失败都退化为空列表，避免把解析异常抛到界面。
class AcademicSchoolRegistry {
  static const String assetPath = 'assets/academic_schools.json';
  static const String prefsKey = 'academic_schools_v1';

  /// 读取合并后的学校列表。
  Future<List<AcademicSchoolConfig>> load() async {
    final List<AcademicSchoolConfig> merged = <AcademicSchoolConfig>[];
    final Map<String, int> indexById = <String, int>{};

    void merge(List<AcademicSchoolConfig> items) {
      for (final AcademicSchoolConfig config in items) {
        if (config.id.isEmpty || config.name.isEmpty) {
          continue;
        }
        final int? existingIndex = indexById[config.id];
        if (existingIndex == null) {
          indexById[config.id] = merged.length;
          merged.add(config);
        } else {
          merged[existingIndex] = config;
        }
      }
    }

    merge(await _loadAssetSchools());
    merge(await _loadSavedSchools());
    return merged;
  }

  /// 保存（新增或覆盖）一所学校。
  Future<void> save(AcademicSchoolConfig config) async {
    if (config.id.isEmpty) {
      return;
    }
    final List<AcademicSchoolConfig> saved = await _loadSavedSchools();
    final int index =
        saved.indexWhere((AcademicSchoolConfig item) => item.id == config.id);
    if (index >= 0) {
      saved[index] = config;
    } else {
      saved.add(config);
    }
    await _writeSavedSchools(saved);
  }

  /// 删除一所用户自定义学校；内置学校会重新从 asset 载入。
  Future<void> remove(String id) async {
    final List<AcademicSchoolConfig> saved = await _loadSavedSchools();
    final List<AcademicSchoolConfig> remaining = saved
        .where((AcademicSchoolConfig item) => item.id != id)
        .toList(growable: false);
    if (remaining.length == saved.length) {
      return;
    }
    await _writeSavedSchools(remaining);
  }

  Future<List<AcademicSchoolConfig>> _loadAssetSchools() async {
    try {
      final String raw = await rootBundle.loadString(assetPath);
      return _decodeSchools(raw);
    } catch (_) {
      // asset 缺失、未注册或格式错误时按空列表处理。
      return <AcademicSchoolConfig>[];
    }
  }

  Future<List<AcademicSchoolConfig>> _loadSavedSchools() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefsKey);
      if (raw == null || raw.trim().isEmpty) {
        return <AcademicSchoolConfig>[];
      }
      return _decodeSchools(raw);
    } catch (_) {
      return <AcademicSchoolConfig>[];
    }
  }

  Future<void> _writeSavedSchools(List<AcademicSchoolConfig> schools) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode(<String, Object?>{
        'schools': <Object?>[
          for (final AcademicSchoolConfig config in schools) config.toJson(),
        ],
      }),
    );
  }

  /// 同时兼容 `{"schools":[...]}` 与裸数组两种结构。
  List<AcademicSchoolConfig> _decodeSchools(String raw) {
    final Object? decoded = jsonDecode(raw);
    final Object? rawSchools = decoded is Map ? decoded['schools'] : decoded;
    if (rawSchools is! List) {
      return <AcademicSchoolConfig>[];
    }
    final List<AcademicSchoolConfig> result = <AcademicSchoolConfig>[];
    for (final Object? item in rawSchools) {
      if (item is! Map) {
        continue;
      }
      try {
        final AcademicSchoolConfig config =
            AcademicSchoolConfig.fromJson(Map<String, Object?>.from(item));
        if (config.id.isNotEmpty && config.name.isNotEmpty) {
          result.add(config);
        }
      } catch (_) {
        // 单条配置损坏时跳过，不影响其他学校。
      }
    }
    return result;
  }
}
