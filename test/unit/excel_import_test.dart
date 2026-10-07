import 'package:egtma3/features/excel/data/excel_export_service.dart';
import 'package:egtma3/features/excel/data/excel_import_service.dart';
import 'package:egtma3/features/excel/domain/duplicate_detector.dart';
import 'package:egtma3/features/excel/domain/import_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 6);

  group('column detection', () {
    test('English headers', () {
      final c = ColumnDetection.detect(['name', 'street', 'address', 'phone', 'date of birth']);
      expect(c.isValid, isTrue);
    });

    test('Arabic headers in any order', () {
      final c = ColumnDetection.detect(['التليفون', 'الاسم', 'تاريخ الميلاد', 'العنوان', 'الشارع']);
      expect(c.isValid, isTrue);
      expect(c.indexes[ImportField.name], 1);
    });

    test('church template headers (A–E) exactly as in the Excel sheet', () {
      final rows = [
        ['الاسم كامل', 'رقم التليفون', 'الشارع', 'العنوان بالكامل', 'تاريخ الميلاد'],
        ['مريم أحمد', '01012345678', 'شارع مار جرجس', '10 شارع مار جرجس', '15/03/1970'],
      ];
      final c = ColumnDetection.detect(rows.first);
      expect(c.isValid, isTrue);
      expect(c.indexes, {
        ImportField.name: 0,
        ImportField.phone: 1,
        ImportField.street: 2,
        ImportField.address: 3,
        ImportField.dateOfBirth: 4,
      });
      final parsed = ImportParser.parse(rows, c, now: now).single;
      expect(parsed.isValid, isTrue);
      expect(parsed.draft!.fullName, 'مريم أحمد');
      expect(parsed.draft!.phone, '01012345678');
      expect(parsed.draft!.streetName, 'شارع مار جرجس');
      expect(parsed.draft!.address, '10 شارع مار جرجس');
      expect(parsed.draft!.dateOfBirth, DateTime(1970, 3, 15));
    });

    test('template headers survive a real .xlsx round trip', () {
      final bytes = ExcelExportService.build('Sheet',
          ['الاسم كامل', 'رقم التليفون', 'الشارع', 'العنوان بالكامل', 'تاريخ الميلاد'], [
        ['سعاد جرجس', '01112223334', 'شارع النصر', '5 شارع النصر', '01/01/1960'],
      ]);
      final rows = ExcelImportService.readRows(bytes);
      final parsed =
          ImportParser.parse(rows, ColumnDetection.detect(rows.first), now: now).single;
      expect(parsed.isValid, isTrue);
      expect(parsed.draft!.phone, '01112223334');
      expect(parsed.draft!.streetName, 'شارع النصر');
    });

    test('missing columns reported', () {
      final c = ColumnDetection.detect(['name', 'phone']);
      expect(c.isValid, isFalse);
      expect(c.missing, containsAll([ImportField.street, ImportField.address, ImportField.dateOfBirth]));
    });
  });

  group('row validation', () {
    final header = ['name', 'street', 'address', 'phone', 'date of birth'];
    final cols = ColumnDetection.detect(header);

    test('valid row produces a normalised draft', () {
      final rows = ImportParser.parse([
        header,
        ['مريم أحمد', 'شارع مار جرجس', '10 شارع مار جرجس', '+201012345678', '15/03/1970'],
      ], cols, now: now);
      expect(rows.single.isValid, isTrue);
      expect(rows.single.draft!.phone, '01012345678');
      expect(rows.single.draft!.dateOfBirth, DateTime(1970, 3, 15));
      expect(rows.single.rowNumber, 2);
    });

    test('invalid rows collect Arabic errors', () {
      final rows = ImportParser.parse([
        header,
        ['', 'ش', 'ع', '123', '31/02/1970'],
        ['سعاد', '', '', '01012345678', '2090-01-01'],
      ], cols, now: now);
      expect(rows[0].isValid, isFalse);
      expect(rows[0].errors, contains('الاسم مطلوب'));
      expect(rows[0].errors, contains('رقم التليفون غير صحيح'));
      expect(rows[0].errors, contains('تاريخ الميلاد غير مفهوم'));
      expect(rows[1].errors, contains('الشارع مطلوب'));
      expect(rows[1].errors, contains('تاريخ الميلاد غير منطقي'));
    });

    test('blank rows are skipped', () {
      final rows = ImportParser.parse([header, [null, '', ' ', null, null]], cols, now: now);
      expect(rows, isEmpty);
    });
  });

  group('Rule H: duplicate detection', () {
    final header = ['name', 'street', 'address', 'phone', 'date of birth'];
    final cols = ColumnDetection.detect(header);
    List<ImportRow> parse(List<List<Object?>> r) => ImportParser.parse([header, ...r], cols, now: now);

    final existing = [
      PersonIdentity(
          name: 'السيدة مريم أحمد',
          phone: '01012345678',
          address: '10 شارع مار جرجس',
          dateOfBirth: DateTime(1970, 3, 15)),
    ];

    test('same person with differently formatted phone is a duplicate', () {
      final rows = parse([
        ['مريم احمد', 'شارع', 'عنوان آخر', '+201012345678', '01/01/1980'],
      ]);
      DuplicateDetector.classify(rows, existing);
      expect(rows.single.category, RowCategory.duplicate);
    });

    test('same name + date of birth is a duplicate', () {
      final rows = parse([['مريم أحمد', 'شارع', 'عنوان', '', '15/03/1970']]);
      DuplicateDetector.classify(rows, existing);
      expect(rows.single.category, RowCategory.duplicate);
    });

    test('shared family phone alone is not a duplicate', () {
      final rows = parse([['سارة أحمد', 'شارع', 'عنوان', '01012345678', '01/01/2000']]);
      DuplicateDetector.classify(rows, existing);
      expect(rows.single.category, RowCategory.valid);
    });

    test('duplicates within the same file are detected', () {
      final rows = parse([
        ['منى فؤاد', 'شارع', 'عنوان', '01111111111', '01/01/1960'],
        ['منى فؤاد', 'شارع', 'عنوان', '01111111111', '01/01/1960'],
      ]);
      DuplicateDetector.classify(rows, const []);
      expect(rows[0].category, RowCategory.valid);
      expect(rows[1].category, RowCategory.duplicate);
      expect(rows[1].duplicateReason, contains('داخل الملف'));
    });

    test('preview counts', () {
      final rows = parse([
        ['منى فؤاد', 'شارع', 'عنوان', '01111111111', '01/01/1960'],
        ['مريم أحمد', 'شارع', 'عنوان', '01012345678', '15/03/1970'],
        ['', '', '', '', ''],
        ['x', '', '', '', 'bad'],
      ]);
      DuplicateDetector.classify(rows, existing);
      final p = ImportPreview(rows);
      expect(p.valid.length, 1);
      expect(p.duplicates.length, 1);
      expect(p.invalid.length, 1);
    });
  });

  test('export → import round trip through a real xlsx', () {
    final bytes = ExcelExportService.build('Sheet', ['الاسم', 'الشارع', 'العنوان', 'التليفون', 'تاريخ الميلاد'], [
      ['مريم أحمد', 'شارع مار جرجس', '10 شارع', '01012345678', '15/03/1970'],
    ]);
    final rows = ExcelImportService.readRows(bytes);
    final parsed = ImportParser.parse(rows, ColumnDetection.detect(rows.first), now: now);
    expect(parsed.single.isValid, isTrue);
    expect(parsed.single.draft!.fullName, 'مريم أحمد');
  });
}
