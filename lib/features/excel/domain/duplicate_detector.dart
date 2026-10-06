import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/dates.dart';
import 'import_models.dart';

/// Identity of an existing (or already-accepted) woman for duplicate checks.
class PersonIdentity {
  const PersonIdentity({
    required this.name,
    required this.phone,
    required this.address,
    required this.dateOfBirth,
  });

  final String name;
  final String phone; // normalised
  final String address;
  final DateTime? dateOfBirth;

  String get nameKey => ArabicText.normalizeName(name);
  String get addressKey => ArabicText.normalize(address);
  String? get dobKey => dateOfBirth == null ? null : Dates.dayId(dateOfBirth!);
}

/// Multi-field duplicate detection (Rule H).
///
/// Two people are the same when:
///  * same normalised phone AND (same name OR same date of birth), or
///  * same name AND same date of birth, or
///  * same name AND same address.
/// A shared phone alone is NOT a duplicate (family members often share one).
abstract final class DuplicateDetector {
  static String? matchReason(PersonIdentity a, PersonIdentity b) {
    final sameName = a.nameKey.isNotEmpty && a.nameKey == b.nameKey;
    final samePhone = a.phone.isNotEmpty && a.phone == b.phone;
    final sameDob = a.dobKey != null && a.dobKey == b.dobKey;
    final sameAddress = a.addressKey.isNotEmpty && a.addressKey == b.addressKey;

    if (samePhone && (sameName || sameDob)) return 'نفس رقم التليفون';
    if (sameName && sameDob) return 'نفس الاسم وتاريخ الميلاد';
    if (sameName && sameAddress) return 'نفس الاسم والعنوان';
    return null;
  }

  /// Marks every row as valid / duplicate / invalid. Duplicates are checked
  /// against existing records AND earlier rows in the same file.
  static void classify(List<ImportRow> rows, List<PersonIdentity> existing) {
    final accepted = <PersonIdentity>[];
    for (final row in rows) {
      if (!row.isValid) {
        row.category = RowCategory.invalid;
        continue;
      }
      final d = row.draft!;
      final me = PersonIdentity(
        name: d.fullName,
        phone: d.phone,
        address: d.address,
        dateOfBirth: d.dateOfBirth,
      );
      String? reason;
      for (final e in existing) {
        final r = matchReason(me, e);
        if (r != null) {
          reason = '$r — موجودة بالفعل: ${e.name}';
          break;
        }
      }
      if (reason == null) {
        for (final e in accepted) {
          final r = matchReason(me, e);
          if (r != null) {
            reason = '$r — مكررة داخل الملف';
            break;
          }
        }
      }
      if (reason != null) {
        row.category = RowCategory.duplicate;
        row.duplicateReason = reason;
      } else {
        row.category = RowCategory.valid;
        accepted.add(me);
      }
    }
  }
}
