/// Central place for every Firestore collection name.
/// Never hard-code collection strings elsewhere.
abstract final class FsPaths {
  static const users = 'users';
  static const women = 'women';
  static const streets = 'streets';
  static const meetings = 'meetings';
  static const attendance = 'attendance';
  static const meetingAssignments = 'meeting_assignments';
  static const followUps = 'follow_ups';
  static const suggestions = 'follow_up_suggestions';
  static const conferences = 'conferences';
  static const conferenceAttendance = 'conference_attendance';
  static const conferenceAssignments = 'conference_assignments';
  static const notifications = 'notifications';
  static const dailyVerses = 'daily_verses';
  static const versePool = 'verse_pool';
  static const settings = 'settings';
  static const settingsAppDoc = 'app';
  static const auditLogs = 'audit_logs';
}
