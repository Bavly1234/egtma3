import '../../../core/utils/dates.dart';

/// Birthday logic. Mirrored by functions/src/birthdays.
abstract final class BirthdayRules {
  /// Feb 29 birthdays are celebrated on Feb 28 in non-leap years.
  static bool isBirthdayOn(DateTime dob, DateTime day) {
    if (dob.month == 2 && dob.day == 29 && !_isLeap(day.year)) {
      return day.month == 2 && day.day == 28;
    }
    return dob.month == day.month && dob.day == day.day;
  }

  /// Next occurrence of the birthday on or after [from].
  static DateTime nextBirthday(DateTime dob, DateTime from) {
    final today = Dates.dateOnly(from);
    DateTime occurrence(int year) {
      if (dob.month == 2 && dob.day == 29 && !_isLeap(year)) {
        return DateTime(year, 2, 28);
      }
      return DateTime(year, dob.month, dob.day);
    }

    final thisYear = occurrence(today.year);
    return thisYear.isBefore(today) ? occurrence(today.year + 1) : thisYear;
  }

  static int daysUntil(DateTime dob, DateTime from) =>
      nextBirthday(dob, from).difference(Dates.dateOnly(from)).inDays;

  /// Rule G: one notification per woman, per recipient, per year. Used as the
  /// notification document id so Firestore rejects duplicates.
  static String notificationKey(String womanId, String recipientId, int year) =>
      'birthday_${womanId}_${recipientId}_$year';

  static bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
}
