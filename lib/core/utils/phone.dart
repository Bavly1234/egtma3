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

  /// Local area code added to 7-digit landlines (the church is in Alexandria).
  static const localAreaCode = '03';

  /// Splits a free-text phone cell such as
  /// "01222545908/5916219", "5918327/01220404928",
  /// "01001564081/5930519-(01001564081) إيناس بنتها" into:
  /// the first mobile, the first landline, every other number, and any words.
  static PhoneSplit split(Object? raw) {
    if (raw == null) return const PhoneSplit();
    var text = raw is num ? raw.toInt().toString() : raw.toString();
    text = ArabicText.toLatinDigits(text);
    final numbers = RegExp(r'\+?\d[\d\s]{5,}\d')
        .allMatches(text)
        .map((m) => m[0]!.replaceAll(' ', ''))
        .toList();
    final words = text
        .replaceAll(RegExp(r'\+?\d[\d\s]{5,}\d'), ' ')
        .replaceAll(RegExp(r'[\-/()،,:+]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    String? mobile;
    String? landline;
    final others = <String>[];
    for (final n in numbers) {
      final norm = normalize(n);
      if (isValidMobile(norm)) {
        if (mobile == null) {
          mobile = norm;
        } else if (norm != mobile) {
          others.add(norm);
        }
        continue;
      }
      final land = _landline(norm);
      if (land != null) {
        if (landline == null) {
          landline = land;
        } else if (land != landline) {
          others.add(land);
        }
        continue;
      }
      others.add(n); // unclear number: kept as written
    }
    return PhoneSplit(
        mobile: mobile, landline: landline, others: others, words: words);
  }

  /// "5916219" → "035916219"; full landlines ("035916219", "0223456789")
  /// are kept. Anything else is not a landline.
  static String? _landline(String digits) {
    if (RegExp(r'^\d{7}$').hasMatch(digits)) return '$localAreaCode$digits';
    if (RegExp(r'^0[2-9]\d{7,8}$').hasMatch(digits)) return digits;
    return null;
  }

  /// International format without '+', as required by wa.me links.
  static String toInternational(String normalized) =>
      normalized.startsWith('0') ? '20${normalized.substring(1)}' : normalized;
}

/// Result of [PhoneUtils.split].
class PhoneSplit {
  const PhoneSplit({this.mobile, this.landline, this.others = const [], this.words = ''});
  final String? mobile;
  final String? landline;

  /// Extra or unclear numbers (kept, never dropped).
  final List<String> others;

  /// Text written next to the numbers, e.g. "إيناس بنتها".
  final String words;

  bool get isEmpty => mobile == null && landline == null && others.isEmpty && words.isEmpty;

  /// What goes into the notes so nothing from the cell is lost.
  String get noteText => [
        if (others.isNotEmpty) 'أرقام أخرى: ${others.join(' - ')}',
        if (words.isNotEmpty) words,
      ].join(' — ');
}
