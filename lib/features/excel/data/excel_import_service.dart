import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/arabic_text.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';
import '../../streets/data/street_repository.dart';
import '../../women/data/women_repository.dart';
import '../domain/duplicate_detector.dart';
import '../domain/import_models.dart';

class ImportPreview {
  const ImportPreview(this.rows);
  final List<ImportRow> rows;

  List<ImportRow> get valid =>
      rows.where((r) => r.category == RowCategory.valid).toList();
  List<ImportRow> get duplicates =>
      rows.where((r) => r.category == RowCategory.duplicate).toList();
  List<ImportRow> get invalid =>
      rows.where((r) => r.category == RowCategory.invalid).toList();
}

/// Excel import pipeline: read → validate columns → validate rows →
/// detect duplicates (file + database) → preview → user confirms → write.
class ExcelImportService {
  ExcelImportService(this._db, this._women, this._streets, this._audit);
  final FirebaseFirestore _db;
  final WomenRepository _women;
  final StreetRepository _streets;
  final AuditRepository _audit;

  /// Reads the first sheet into plain Dart values.
  static List<List<Object?>> readRows(Uint8List bytes) {
    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const AppFailure('الملف ليس ملف Excel صالحاً (.xlsx).');
    }
    if (book.tables.isEmpty) throw const AppFailure('الملف فارغ.');
    final sheet = book.tables.values.first;
    return [
      for (final row in sheet.rows) [for (final c in row) _cellValue(c?.value)]
    ];
  }

  static Object? _cellValue(CellValue? v) => switch (v) {
        null => null,
        TextCellValue t => t.value.toString(),
        IntCellValue i => i.value,
        DoubleCellValue d => d.value,
        DateCellValue d => DateTime(d.year, d.month, d.day),
        DateTimeCellValue d => DateTime(d.year, d.month, d.day),
        BoolCellValue b => b.value.toString(),
        FormulaCellValue f => f.formula,
        TimeCellValue t => t.toString(),
      };

  Future<ImportPreview> preview(List<List<Object?>> rows) async {
    if (rows.isEmpty) throw const AppFailure('الملف فارغ.');
    final cols = ColumnDetection.detect(rows.first);
    if (!cols.isValid) {
      final names =
          cols.missing.map((f) => ColumnDetection.fieldLabels[f]).join('، ');
      throw AppFailure('أعمدة ناقصة في الملف: $names');
    }
    final parsed = ImportParser.parse(rows, cols);
    if (parsed.isEmpty) throw const AppFailure('لا توجد بيانات في الملف.');
    try {
      final drafts = parsed.where((r) => r.isValid).map((r) => r.draft!);
      final existing = await _women.identitiesMatching(
        phones: drafts.map((d) => d.phone),
        normalizedNames: drafts.map((d) => ArabicText.normalizeName(d.fullName)),
      );
      DuplicateDetector.classify(parsed, existing);
      return ImportPreview(parsed);
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Writes only the rows classified as valid. Returns how many were added.
  Future<int> commit(
    ImportPreview preview,
    AppUser actor, {
    AppUser? assignTo,
    void Function(int done, int total)? onProgress,
  }) async {
    final rows = preview.valid;
    try {
      var done = 0;
      for (var i = 0; i < rows.length; i += 200) {
        final batch = _db.batch();
        for (final row in rows.skip(i).take(200)) {
          final d = row.draft!;
          final streetId = _streets.upsertInBatch(batch, d.streetName);
          batch.set(_db.collection(FsPaths.women).doc(), {
            ...d.toFields(streetId),
            'assignedServantId': assignTo?.id,
            'assignedServantName': assignTo?.name,
            'consecutiveAbsences': 0,
            'totalPresent': 0,
            'totalAbsent': 0,
            'phoneCalls': 0,
            'homeVisits': 0,
            'activeSuggestionType': 'none',
            'importedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'createdBy': actor.id,
          });
        }
        await batch.commit();
        done += rows.skip(i).take(200).length;
        onProgress?.call(done, rows.length);
      }
      _audit.log(
        actor: actor,
        action: AuditAction.excelImported,
        entityType: 'import',
        entityId: DateTime.now().toIso8601String(),
        summary: 'تمت إضافة $done — مكرر ${preview.duplicates.length}'
            ' — غير صالح ${preview.invalid.length}',
      );
      return done;
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final excelImportServiceProvider = Provider((ref) => ExcelImportService(
      ref.watch(firestoreProvider),
      ref.watch(womenRepositoryProvider),
      ref.watch(streetRepositoryProvider),
      ref.watch(auditRepositoryProvider),
    ));
