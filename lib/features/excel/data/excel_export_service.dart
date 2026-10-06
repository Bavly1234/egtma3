import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/utils/dates.dart';

/// Builds .xlsx files (RTL sheets) and hands them to the platform saver.
class ExcelExportService {
  /// Pure: builds the workbook bytes. Separated for testing.
  static Uint8List build(String sheetName, List<String> headers,
      List<List<Object?>> rows) {
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    final sheet = book[sheetName];
    if (defaultSheet != null && defaultSheet != sheetName) {
      book.delete(defaultSheet);
    }
    sheet.isRTL = true;
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (final r in rows) {
      sheet.appendRow([for (final v in r) _cell(v)]);
    }
    final bytes = book.save();
    if (bytes == null) throw const AppFailure('تعذر إنشاء ملف Excel.');
    return Uint8List.fromList(bytes);
  }

  static CellValue? _cell(Object? v) => switch (v) {
        null => null,
        int i => IntCellValue(i),
        double d => DoubleCellValue(d),
        DateTime d => TextCellValue(Dates.display(d)),
        bool b => TextCellValue(b ? 'نعم' : 'لا'),
        _ => TextCellValue(v.toString()),
      };

  Future<String> save(
    String fileBaseName,
    String sheetName,
    List<String> headers,
    List<List<Object?>> rows,
  ) async {
    try {
      final bytes = build(sheetName, headers, rows);
      final name = '${fileBaseName}_${Dates.dayId(DateTime.now())}';
      return await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final excelExportServiceProvider = Provider((ref) => ExcelExportService());
