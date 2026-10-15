import '../../../core/utils/phone.dart';

/// Field validators shared by the woman form and the Excel importer.
/// Each returns an Arabic error message or null when valid.
abstract final class WomanValidator {
  static String? name(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'الاسم مطلوب';
    if (s.length < 3) return 'الاسم قصير جداً';
    if (RegExp(r'^[0-9\s]+$').hasMatch(s)) return 'الاسم غير صحيح';
    return null;
  }

  static String? street(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'الشارع مطلوب' : null;

  static String? address(String? v) =>
      (v?.trim().isEmpty ?? true) ? 'العنوان مطلوب' : null;

  /// Phone is optional, but when present must be valid.
  static String? phone(String? v) {
    final raw = v?.trim() ?? '';
    if (raw.isEmpty) return null;
    return PhoneUtils.isValid(PhoneUtils.normalize(raw))
        ? null
        : 'رقم التليفون غير صحيح';
  }
}
