/// Central place for every Firestore collection name.
/// Never hard-code collection strings elsewhere.
abstract final class FsPaths {
  static const users = 'users';
  static const women = 'women';
  static const streets = 'streets';
  static const meetings = 'meetings';
  static const attendance = 'attendance';
  static const followUps = 'follow_ups';
  static const suggestions = 'follow_up_suggestions';
  static const conferences = 'conferences';
  static const conferenceDays = 'days';
  static const conferenceAttendance = 'conference_attendance';
  static const notifications = 'notifications';
  static const dailyVerses = 'daily_verses';
  static const versePool = 'verse_pool';
  static const settings = 'settings';
  static const settingsAppDoc = 'app';
  static const auditLogs = 'audit_logs';
}

/// Cloud Functions callable names.
abstract final class FnNames {
  static const createServant = 'createServant';
  static const setUserActive = 'setUserActive';
  static const setUserRole = 'setUserRole';
  static const bootstrapFather = 'bootstrapFather';
  static const seedDemoData = 'seedDemoData';
  static const removeDemoData = 'removeDemoData';
  static const recomputeWoman = 'recomputeWoman';
}

const kFunctionsRegion = 'europe-west1';
