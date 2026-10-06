/// Business thresholds. Mirrored in functions/src/shared/rules.ts.
abstract final class BusinessRules {
  /// Consecutive Wednesday absences that trigger a phone follow-up suggestion.
  static const phoneThreshold = 2;

  /// Consecutive Wednesday absences that trigger a home-visit suggestion.
  static const homeVisitThreshold = 4;

  /// Pending suggestions older than this are considered overdue.
  static const overdueDays = 7;

  /// The weekly meeting day (DateTime.wednesday).
  static const meetingWeekday = DateTime.wednesday;

  static const pageSize = 30;
  static const conferenceDayCount = 3;
}
