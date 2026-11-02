import '../../models/course.dart';

/// Excel 中某一行解析失败的原因（行号从 1 开始，与 Excel 看到的一致）。
class ExcelRowError {
  const ExcelRowError({required this.rowNumber, required this.reason});

  final int rowNumber;
  final String reason;

  String get label => '第 $rowNumber 行：$reason';
}

/// Excel 解析结果：成功生成的课程草稿、错误行、需要人工确认的提示。
class ExcelParseResult {
  const ExcelParseResult({
    required this.drafts,
    required this.errors,
    required this.warnings,
    required this.totalRows,
    required this.headerRow,
  });

  /// 待导入的课程草稿（已带当前学期与身份）。
  final List<Course> drafts;

  /// 解析失败的行。
  final List<ExcelRowError> errors;

  /// 单双周、周次不连续等需要用户确认的提示。
  final List<String> warnings;

  /// 表头之后的数据行数（不含空行）。
  final int totalRows;

  /// 识别到的表头所在行号（从 1 开始）。
  final int headerRow;

  bool get hasDrafts => drafts.isNotEmpty;
}
