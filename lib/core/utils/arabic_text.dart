/// Arabic-tolerant text normalisation used for search and duplicate detection.
abstract final class ArabicText {
  static final _diacritics = RegExp('[ً-ٰٟـ]');
  static final _spaces = RegExp(r'\s+');
  static final _punct = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static const _honorifics = {'السيدة', 'السيده', 'ست', 'مدام', 'الست', 'ت', 'تاسوني', 'طنط'};

  /// Removes diacritics/tatweel, unifies alef/yaa/taa-marbuta forms,
  /// converts Arabic-Indic digits, lower-cases latin and collapses spaces.
  static String normalize(String input) {
    var s = input.trim().toLowerCase();
    s = s.replaceAll(_diacritics, '');
    s = s
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    s = toLatinDigits(s);
    s = s.replaceAll(_punct, ' ');
    return s.replaceAll(_spaces, ' ').trim();
  }

  /// Normalised name without honorific prefixes ("السيدة", "مدام", ...).
  static String normalizeName(String input) {
    final words =
        normalize(input).split(' ').where((w) => w.isNotEmpty).toList();
    final normalizedHonorifics = _honorifics.map(normalize).toSet();
    while (words.length > 1 && normalizedHonorifics.contains(words.first)) {
      words.removeAt(0);
    }
    return words.join(' ');
  }

  static String toLatinDigits(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final ai = arabic.indexOf(c);
      final pi = persian.indexOf(c);
      b.write(ai >= 0 ? '$ai' : (pi >= 0 ? '$pi' : c));
    }
    return b.toString();
  }

  /// Prefix keywords so Firestore `array-contains` can do prefix search.
  /// Each word contributes prefixes of length 2..15.
  static List<String> searchKeywords(Iterable<String> fields) {
    final out = <String>{};
    for (final f in fields) {
      for (final w in normalize(f).split(' ')) {
        if (w.length < 2) continue;
        for (var i = 2; i <= w.length && i <= 15; i++) {
          out.add(w.substring(0, i));
        }
      }
    }
    return out.toList()..sort();
  }
}
