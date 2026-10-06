import 'arabic_text.dart';

/// Egyptian phone-number normalisation. Canonical form: `01XXXXXXXXX` (11 digits)
/// for mobiles, otherwise the cleaned digits with a leading zero.
abstract final class PhoneUtils {
  static String normalize(String? raw) {
    if (raw == null) return '';
    var d = ArabicText.toLatinDigits(raw).replaceAll(RegExp(r'[^0-9+]'), '');
    if (d.startsWith('+')) d = d.substring(1);
    if (d.startsWith('0020')) d = d.substring(4);
    if (d.startsWith('20') && d.length >= 11 && d.length <= 12) {
      d = '0${d.substring(2)}';
    }
    // Mobile written without the leading zero (e.g. 1012345678).
    if (d.length == 10 && d.startsWith('1')) d = '0$d';
    return d;
  }

  static bool isValidMobile(String normalized) =>
      RegExp(r'^01[0125][0-9]{8}$').hasMatch(normalized);

  /// Landlines (e.g. 02XXXXXXXX) are accepted but cannot use WhatsApp.
  static bool isValid(String normalized) =>
      isValidMobile(normalized) ||
      RegExp(r'^0[2-9][0-9]{7,9}$').hasMatch(normalized);

  /// International format without '+', as required by wa.me links.
  static String toInternational(String normalized) =>
      normalized.startsWith('0') ? '20${normalized.substring(1)}' : normalized;
}
