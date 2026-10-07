import 'package:intl/intl.dart';

import '../constants/business_rules.dart';
import 'arabic_text.dart';

abstract final class Dates {
  static final _id = DateFormat('yyyy-MM-dd');
  static final _display = DateFormat('dd/MM/yyyy');

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Stable day id, e.g. `2026-10-07`. Used as meeting id.
  static String dayId(DateTime d) => _id.format(d);
  static DateTime parseDayId(String id) => _id.parse(id);

  static String display(DateTime? d) => d == null ? '—' : _display.format(d);
  static String displayDateTime(DateTime? d) =>
      d == null ? '—' : DateFormat('dd/MM/yyyy  hh:mm a', 'ar').format(d);

  static String weekdayAr(DateTime d) => DateFormat('EEEE', 'ar').format(d);

  /// Today if it is the meeting day, otherwise the most recent meeting day.
  static DateTime currentOrLastMeeting(DateTime now) {
    final today = dateOnly(now);
    final diff = (today.weekday - BusinessRules.meetingWeekday + 7) % 7;
    return today.subtract(Duration(days: diff));
  }

  /// Today if it is the meeting day, otherwise the next meeting day.
  static DateTime nextMeeting(DateTime now) {
    final today = dateOnly(now);
    final diff = (BusinessRules.meetingWeekday - today.weekday + 7) % 7;
    return today.add(Duration(days: diff));
  }

  static bool isMeetingDay(DateTime d) =>
      d.weekday == BusinessRules.meetingWeekday;

  /// Wednesday 9pm cutoff: after this moment, unmarked women of that
  /// meeting count as absent (auto-filled by the app).
  static const cutoffHour = 21;

  static DateTime meetingCutoff(DateTime meetingDay) {
    final d = dateOnly(meetingDay);
    return DateTime(d.year, d.month, d.day, cutoffHour);
  }

  static bool cutoffPassed(DateTime meetingDay, DateTime now) =>
      !now.isBefore(meetingCutoff(meetingDay));

  /// Parses user/Excel dates: dd/MM/yyyy, d-M-yy, yyyy-MM-dd, Excel serials.
  static DateTime? parseFlexible(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return dateOnly(value);
    if (value is num) return _fromExcelSerial(value);
    final s = ArabicText.toLatinDigits(value.toString().trim());
    if (s.isEmpty) return null;
    final serial = num.tryParse(s);
    if (serial != null) return _fromExcelSerial(serial);

    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
    if (iso != null) {
      return _safe(
          int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    }
    final dmy =
        RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(s);
    if (dmy != null) {
      var y = int.parse(dmy[3]!);
      if (y < 100) y += y > 30 ? 1900 : 2000;
      return _safe(y, int.parse(dmy[2]!), int.parse(dmy[1]!));
    }
    return null;
  }

  static DateTime? _fromExcelSerial(num serial) {
    if (serial < 1000 || serial > 80000) return null;
    return dateOnly(
        DateTime(1899, 12, 30).add(Duration(days: serial.floor())));
  }

  static DateTime? _safe(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.month != m || dt.day != d) return null; // e.g. 31/02
    return dt;
  }

  /// Valid birth date: not in the future and not older than 120 years.
  static bool isPlausibleBirthDate(DateTime d, DateTime now) =>
      !d.isAfter(now) && now.year - d.year <= 120;

  static int ageOn(DateTime dob, DateTime on) {
    var age = on.year - dob.year;
    if (on.month < dob.month || (on.month == dob.month && on.day < dob.day)) {
      age--;
    }
    return age;
  }
}
