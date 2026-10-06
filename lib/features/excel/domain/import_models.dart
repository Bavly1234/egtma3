import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/phone.dart';
import '../../women/domain/woman.dart';
import '../../women/domain/woman_validator.dart';

enum ImportField { name, street, address, phone, dateOfBirth }

/// Header aliases (English + Arabic). Compared after Arabic normalisation.
const Map<ImportField, List<String>> kImportAliases = {
  ImportField.name: ['name', 'full name', 'الاسم', 'اسم', 'الاسم بالكامل'],
  ImportField.street: ['street', 'street name', 'الشارع', 'شارع', 'اسم الشارع'],
  ImportField.address: ['address', 'full address', 'العنوان', 'عنوان'],
  ImportField.phone: [
    'phone', 'phone number', 'mobile', 'التليفون', 'التلفون', 'الهاتف',
    'الموبايل', 'رقم التليفون', 'رقم الهاتف', 'تليفون'
  ],
  ImportField.dateOfBirth: [
    'date of birth', 'dob', 'birth date', 'birthdate', 'تاريخ الميلاد',
    'الميلاد', 'تاريخ الميلاد'
  ],
};

class ColumnDetection {
  const ColumnDetection(this.indexes, this.missing);
  final Map<ImportField, int> indexes;
  final List<ImportField> missing;
  bool get isValid => missing.isEmpty;

  static const fieldLabels = {
    ImportField.name: 'الاسم',
    ImportField.street: 'الشارع',
    ImportField.address: 'العنوان',
    ImportField.phone: 'التليفون',
    ImportField.dateOfBirth: 'تاريخ الميلاد',
  };

  static ColumnDetection detect(List<Object?> headerRow) {
    final normalized = headerRow
        .map((h) => ArabicText.normalize(h?.toString() ?? '').replaceAll('_', ' '))
        .toList();
    final indexes = <ImportField, int>{};
    for (final entry in kImportAliases.entries) {
      final aliases = entry.value.map(ArabicText.normalize).toSet();
      final i = normalized.indexWhere(aliases.contains);
      if (i >= 0) indexes[entry.key] = i;
    }
    final missing =
        ImportField.values.where((f) => !indexes.containsKey(f)).toList();
    return ColumnDetection(indexes, missing);
  }
}

enum RowCategory { valid, duplicate, invalid }

class ImportRow {
  ImportRow({
    required this.rowNumber,
    required this.rawName,
    required this.draft,
    required this.errors,
  });

  /// 1-based row number as the user sees it in Excel.
  final int rowNumber;
  final String rawName;
  final WomanDraft? draft;
  final List<String> errors;

  RowCategory category = RowCategory.valid;
  String? duplicateReason;

  bool get isValid => errors.isEmpty && draft != null;
}

/// Parses spreadsheet rows into validated drafts. Does not touch Firestore.
abstract final class ImportParser {
  static List<ImportRow> parse(
    List<List<Object?>> rows,
    ColumnDetection cols, {
    DateTime? now,
  }) {
    final out = <ImportRow>[];
    String cell(List<Object?> r, ImportField f) {
      final i = cols.indexes[f]!;
      return i < r.length ? (r[i]?.toString().trim() ?? '') : '';
    }

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.every((c) => (c?.toString().trim() ?? '').isEmpty)) continue;
      final name = cell(r, ImportField.name);
      final street = cell(r, ImportField.street);
      final address = cell(r, ImportField.address);
      final phoneRaw = cell(r, ImportField.phone);
      final dobIdx = cols.indexes[ImportField.dateOfBirth]!;
      final dobRaw = dobIdx < r.length ? r[dobIdx] : null;
      final dob = Dates.parseFlexible(dobRaw);

      final errors = <String>[
        ?WomanValidator.name(name),
        ?WomanValidator.street(street),
        ?WomanValidator.address(address),
        ?WomanValidator.phone(phoneRaw),
        if (dobRaw != null && dobRaw.toString().trim().isNotEmpty && dob == null)
          'تاريخ الميلاد غير مفهوم'
        else
          ?WomanValidator.dateOfBirth(dob, now: now),
      ];

      out.add(ImportRow(
        rowNumber: i + 1,
        rawName: name,
        errors: errors,
        draft: errors.isNotEmpty
            ? null
            : WomanDraft(
                fullName: name,
                streetName: street,
                address: address,
                phone: PhoneUtils.normalize(phoneRaw),
                dateOfBirth: dob,
              ),
      ));
    }
    return out;
  }
}
