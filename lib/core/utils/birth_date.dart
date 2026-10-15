import 'arabic_text.dart';

/// A birth date where the year (and even the day) may be unknown — the
/// church's sheets mostly hold "day/month" or just "/month".
class BirthDate {
  const BirthDate({this.day, this.month, this.year});

  final int? day;
  final int? month;
  final int? year;

  static const empty = BirthDate();

  bool get isEmpty => month == null;
  bool get hasDayMonth => day != null && month != null;

  /// The full date, only when the year is known.
  DateTime? get full =>
      year != null && hasDayMonth ? DateTime(year!, month!, day!) : null;

  /// A date usable for "next birthday" maths. Unknown year → 2000 (a leap
  /// year, so 29/2 stays valid).
  DateTime? get anchor =>
      hasDayMonth ? DateTime(year ?? 2000, month!, day!) : null;

  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// "15 أبريل 1970", "15 أبريل", "شهر يونيو" or "".
  String get display {
    if (month == null) return '';
    final m = _monthsAr[month! - 1];
    if (day == null) return 'شهر $m';
    return year == null ? '$day $m' : '$day $m $year';
  }

  /// Stable key for duplicate detection: "15-4-1970", "15-4", "-6".
  String? get key => isEmpty ? null : '${day ?? ''}-$month${year == null ? '' : '-$year'}';

  static bool _validDay(int d, int m) {
    const days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return m >= 1 && m <= 12 && d >= 1 && d <= days[m - 1];
  }

  static BirthDate? _make(int? d, int m, int? y, DateTime now) {
    if (m < 1 || m > 12) return null;
    if (d != null && !_validDay(d, m)) return null;
    if (y != null) {
      if (y < 100) y += y > (now.year % 100) ? 1900 : 2000;
      if (y > now.year || now.year - y > 120) return null;
      if (d != null && DateTime(y, m, d).month != m) return null; // 29/2/1971
    }
    return BirthDate(day: d, month: m, year: y);
  }

  /// Reads whatever the sheet / form holds. Returns:
  ///  * [BirthDate.empty] for an empty cell,
  ///  * null when something is written but can't be understood.
  ///
  /// Understood:
  ///  * "30/4", "30-4", "30.4"            → day 30, month 4, no year
  ///  * "/6", "  /12", "6"                → month only
  ///  * "15/3/1970", "15/3/70"            → full date (day/month/year)
  ///  * "1970-03-15"                      → full date
  ///  * Arabic digits "١٥/٣"
  ///  * real Excel dates: an old year is a real birth date; a recent year
  ///    (e.g. 2026) means Excel turned the typed "day/month" into a US
  ///    month/day date — swapped back to the typed day/month, no year.
  ///  * Excel 1900-01-01 (a stray "1") → empty.
  static BirthDate? parse(Object? v, {DateTime? now}) {
    now ??= DateTime.now();
    if (v == null) return empty;
    if (v is DateTime) return _fromDateTime(v, now);
    if (v is num) {
      final n = v.toInt();
      if (n >= 1 && n <= 12 && v == n) return BirthDate(month: n); // "6"
      if (n > 1000 && n < 80000) {
        // Excel serial number.
        return _fromDateTime(DateTime(1899, 12, 30).add(Duration(days: n)), now);
      }
      return null;
    }
    final s = ArabicText.toLatinDigits(v.toString()).trim();
    if (s.isEmpty) return empty;

    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
    if (iso != null) {
      return _make(int.parse(iso[3]!), int.parse(iso[2]!), int.parse(iso[1]!), now);
    }
    final dmy = RegExp(r'^(\d{1,2})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{2,4})$').firstMatch(s);
    if (dmy != null) {
      return _make(int.parse(dmy[1]!), int.parse(dmy[2]!), int.parse(dmy[3]!), now);
    }
    final dm = RegExp(r'^(\d{1,2})\s*[-/.]\s*(\d{1,2})$').firstMatch(s);
    if (dm != null) return _make(int.parse(dm[1]!), int.parse(dm[2]!), null, now);
    final monthOnly = RegExp(r'^[-/.]?\s*(\d{1,2})$').firstMatch(s);
    if (monthOnly != null) return _make(null, int.parse(monthOnly[1]!), null, now);
    return null;
  }

  static BirthDate? _fromDateTime(DateTime d, DateTime now) {
    // Excel serial 0/1 (a stray "1" typed in the cell) → 1899/1900.
    if (d.year <= 1900) return empty;
    if (d.year >= now.year - 2) {
      // Excel auto-converted a typed "day/month": swap back.
      return _make(d.month, d.day, null, now);
    }
    return _make(d.day, d.month, d.year, now);
  }
}
