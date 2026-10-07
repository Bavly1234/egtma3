/// Business thresholds. Mirrored in functions/src/shared/rules.ts.
abstract final class BusinessRules {
  /// Consecutive Wednesday absences that trigger a phone follow-up suggestion.
  static const phoneThreshold = 2;

  /// Consecutive Wednesday absences that trigger a home-visit suggestion.
  static const homeVisitThreshold = 4;

  /// Intermittent absences: 3+ absences in the last 5 meetings → phone
  /// suggestion, even without consecutive absences (Rule I).
  static const intermittentPhoneWindow = 5;
  static const intermittentPhoneMin = 3;

  /// 5+ absences in the last 8 meetings → home-visit suggestion (Rule J).
  static const intermittentHomeWindow = 8;
  static const intermittentHomeMin = 5;

  /// A suggestion of the same type created within this window blocks a new
  /// intermittent suggestion (no duplicates piling up every week).
  static const intermittentCooldownDays = 21;

  /// Pending suggestions older than this are considered overdue.
  static const overdueDays = 7;

  /// The weekly meeting day (DateTime.wednesday).
  static const meetingWeekday = DateTime.wednesday;

  static const pageSize = 30;
  static const conferenceDayCount = 3;
}
