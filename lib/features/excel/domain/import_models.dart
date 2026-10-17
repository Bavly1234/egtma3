import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/birth_date.dart';
import '../../../core/utils/phone.dart';
import '../../women/domain/woman.dart';
import '../../women/domain/woman_validator.dart';

enum ImportField { name, street, address, phone, dateOfBirth, landline, servant }

/// Columns that must exist in the header row. The landline column is
/// optional (landlines are usually written inside the phone cell).
const kRequiredImportFields = [
  ImportField.name,
  ImportField.street,
  ImportField.address,
  ImportField.phone,
  ImportField.dateOfBirth,
];

/// Street used when the sheet leaves it empty, so the father can fix it.
const kNoStreetName = 'بدون شارع';

/// Header aliases (English + Arabic). Compared after Arabic normalisation.
/// Matches the official template exactly:
/// A الاسم كامل | B رقم التليفون | C الشارع | D العنوان بالكامل | E تاريخ الميلاد
const Map<ImportField, List<String>> kImportAliases = {
  ImportField.name: [
    'name', 'full name', 'الاسم', 'اسم', 'الاسم بالكامل', 'الاسم كامل', 'اسم كامل'
  ],
  ImportField.street: ['street', 'street name', 'الشارع', 'شارع', 'اسم الشارع'],
  ImportField.address: [
    'address', 'full address', 'العنوان', 'عنوان', 'العنوان بالكامل', 'عنوان بالكامل'
  ],
  ImportField.phone: [
    'phone', 'phone number', 'mobile', 'التليفون', 'التلفون', 'الهاتف',
    'الموبايل', 'رقم التليفون', 'رقم الهاتف', 'تليفون', 'رقم التلفون'
  ],
  ImportField.dateOfBirth: [
    'date of birth', 'dob', 'birth date', 'birthdate', 'تاريخ الميلاد',
    'الميلاد', 'تاريخ الميلاد', 'عيد الميلاد'
  ],
  ImportField.servant: ['servant', 'خادمة', 'خادمه', 'خادم', 'الخدمة', 'الخدمه', 'خادمة؟'],
  ImportField.landline: [
    'landline', 'home phone', 'التليفون الارضي', 'تليفون ارضي', 'الارضي',
    'رقم الارضي', 'التليفون الأرضي', 'تليفون أرضي'
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
    ImportField.landline: 'التليفون الأرضي',
    ImportField.servant: 'خادمة',
  };

  static ColumnDetection detect(List<Object?> headerRow) {
    final normalized = headerRow
        .map((h) => ArabicText.normalize(h?.toString() ?? '').replaceAll('_', ' '))
        .toList();
    final indexes = <ImportField, int>{};
    // Landline first, so "التليفون الأرضي" isn't taken as the mobile column.
    final order = [
      ImportField.landline,
      ...ImportField.values.where((f) => f != ImportField.landline),
    ];
    for (final f in order) {
      final aliases = kImportAliases[f]!.map(ArabicText.normalize).toSet();
      for (var j = 0; j < normalized.length; j++) {
        if (aliases.contains(normalized[j]) && !indexes.containsValue(j)) {
          indexes[f] = j;
          break;
        }
      }
    }
    final missing =
        kRequiredImportFields.where((f) => !indexes.containsKey(f)).toList();
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
    Object? raw(List<Object?> r, ImportField f) {
      final i = cols.indexes[f];
      return i == null || i >= r.length ? null : r[i];
    }

    String text(List<Object?> r, ImportField f) =>
        (raw(r, f)?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.every((c) => (c?.toString().trim() ?? '').isEmpty)) continue;
      final name = text(r, ImportField.name);
      final street = text(r, ImportField.street);
      final address = text(r, ImportField.address);

      // Phones: "01222545908/5916219" → mobile + landline; extra numbers
      // and words ("إيناس بنتها") go to the notes so nothing is lost.
      final split = PhoneUtils.split(raw(r, ImportField.phone));
      final landSplit = PhoneUtils.split(raw(r, ImportField.landline));
      final mobile = split.mobile ?? landSplit.mobile ?? '';
      final landline = landSplit.landline ?? split.landline ?? '';
      final notes = [split.noteText, landSplit.noteText]
          .where((t) => t.isNotEmpty)
          .join(' — ');

      // Optional "خادمة" column: نعم / yes / 1 / ✓ means she serves.
      final servantRaw = text(r, ImportField.servant);
      final isServant = const {'✓', '✔', '√', '☑'}.contains(servantRaw) ||
          const {'نعم', 'ايوه', 'اه', 'yes', 'y', '1', 'true', 'x', 'خادمه', 'خادم'}
              .contains(ArabicText.normalize(servantRaw)) ||
          looksLikeServantName(text(r, ImportField.name));

      final dobRaw = raw(r, ImportField.dateOfBirth);
      final birth = BirthDate.parse(dobRaw, now: now);

      final errors = <String>[
        ?WomanValidator.name(name),
        if (birth == null) 'تاريخ الميلاد غير مفهوم: "${dobRaw.toString().trim()}"',
      ];

      out.add(ImportRow(
        rowNumber: i + 1,
        rawName: name,
        errors: errors,
        draft: errors.isNotEmpty
            ? null
            : WomanDraft(
                fullName: name,
                streetName: street.isEmpty ? kNoStreetName : street,
                address: address,
                phone: mobile,
                landline: landline,
                birth: birth!,
                notes: notes,
                isServant: isServant,
              ),
      ));
    }
    return out;
  }
}

/// The church sheet writes servants' names as "ت/ مارينا ...".
bool looksLikeServantName(String name) =>
    RegExp(r'^\s*ت\s*/').hasMatch(name);
