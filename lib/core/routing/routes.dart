/// Route paths. Use these constants — never inline path strings.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const blocked = '/blocked';

  // Tabs
  static const home = '/home';
  static const women = '/women';
  static const attendance = '/attendance';
  static const followUps = '/followups';
  static const stats = '/stats';
  static const servantAttendance = '/servants-attendance';
  static const more = '/more';

  // Women
  static const womanNew = '/women/new';
  static String woman(String id) => '/women/$id';
  static String womanEdit(String id) => '/women/$id/edit';
  static String womanFollowUps(String id) => '/women/$id/followups';

  // Attendance
  static const attendanceHistory = '/attendance/history';

  // Statistics
  static const statsServants = '/stats/servants';

  // More
  static const streets = '/streets';
  static const conferences = '/conferences';
  static const conferenceNew = '/conferences/new';
  static String conference(String id) => '/conferences/$id';
  static String conferenceStats(String id) => '/conferences/$id/stats';
  static const birthdays = '/birthdays';
  static const notifications = '/notifications';
  static const verse = '/verse';
  static const import = '/import';
  static const export = '/export';
  static const users = '/users';
  static const settings = '/settings';
  static const audit = '/audit';
  static const monthlyReport = '/report/monthly';

  /// Paths only the father may open (also enforced by security rules).
  /// Open to every active servant: women CRUD, conferences (create + stats),
  /// all statistics screens, monthly report, import/export.
  /// Assignment is by street only (managed on the Streets screen).
  static const fatherOnly = [
    servantAttendance,
    streets,
    users,
    audit,
  ];

  /// Servants share every statistics page with the father.
  static bool isFatherOnly(String location) =>
      location != statsServants &&
      fatherOnly.any((p) => location == p || location.startsWith('$p/'));
}
