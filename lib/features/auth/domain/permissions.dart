import 'app_user.dart';

/// UI-level permission checks. The same rules are enforced server-side in
/// firestore.rules and Cloud Functions; this only decides what to show.
abstract final class Permissions {
  static bool canManageWomen(AppUser u) => u.active && u.isFather;
  static bool canManageUsers(AppUser u) => u.active && u.isFather;
  static bool canAssign(AppUser u) => u.active && u.isFather;
  static bool canManageConferences(AppUser u) => u.active && u.isFather;
  static bool canImportExport(AppUser u) => u.active && u.isFather;
  static bool canViewAudit(AppUser u) => u.active && u.isFather;
  static bool canViewAllStatistics(AppUser u) => u.active && u.isFather;
  static bool canManageStreets(AppUser u) => u.active && u.isFather;

  /// Servants may only act on women assigned to them.
  static bool canActOnWoman(AppUser u, String? assignedServantId) =>
      u.active && (u.isFather || assignedServantId == u.id);

  static bool canTakeAttendance(AppUser u) => u.active;
  static bool canEditWomanNotes(AppUser u, String? assignedServantId) =>
      canActOnWoman(u, assignedServantId);
}
