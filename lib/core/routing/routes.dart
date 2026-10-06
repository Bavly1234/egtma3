/// Route paths. Use these constants — never inline path strings.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const setup = '/setup';
  static const blocked = '/blocked';

  // Tabs
  static const home = '/home';
  static const women = '/women';
  static const attendance = '/attendance';
  static const followUps = '/followups';
  static const stats = '/stats';
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
  static const statsWomen = '/stats/women';

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
  static const assign = '/assign';
  static const settings = '/settings';
  static const audit = '/audit';

  /// Paths only the father may open (also enforced by security rules).
  static const fatherOnly = [
    stats,
    womanNew,
    streets,
    conferenceNew,
    import,
    export,
    users,
    assign,
    audit,
  ];

  /// Servants may open their own statistics page.
  static bool isFatherOnly(String location) =>
      location != statsServants &&
      fatherOnly.any((p) => location == p || location.startsWith('$p/')) ||
      location.endsWith('/edit') ||
      (location.startsWith('/conferences/') && location.endsWith('/stats'));
}
