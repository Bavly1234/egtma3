import 'app_user.dart';

/// UI-level permission checks. The same rules are enforced server-side in
/// firestore.rules and Cloud Functions; this only decides what to show.
abstract final class Permissions {
  /// Full women CRUD (create / read / update / delete / activate) is open
  /// to every active servant — not father-only.
  static bool canManageWomen(AppUser u) => u.active;
  static bool canManageUsers(AppUser u) => u.active && u.isFather;
  static bool canManageConferences(AppUser u) => u.active;
  static bool canImportExport(AppUser u) => u.active;
  static bool canViewAudit(AppUser u) => u.active && u.isFather;
  static bool canViewAllStatistics(AppUser u) => u.active && u.isFather;
  static bool canManageStreets(AppUser u) => u.active && u.isFather;

  /// Every active servant may act on every woman (no global assignment).
  static bool canActOnWoman(AppUser u) => u.active;

  static bool canTakeAttendance(AppUser u) => u.active;
  static bool canEditWomanNotes(AppUser u) => canActOnWoman(u);
}
