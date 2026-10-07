import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/attendance/presentation/attendance_history_screen.dart';
import '../../features/attendance/presentation/attendance_screen.dart';
import '../../features/audit/presentation/audit_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/blocked_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/birthdays/presentation/birthdays_screen.dart';
import '../../features/conferences/presentation/conference_attendance_screen.dart';
import '../../features/conferences/presentation/conference_stats_screen.dart';
import '../../features/conferences/presentation/conferences_screen.dart';
import '../../features/conferences/presentation/create_conference_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/excel/presentation/export_screen.dart';
import '../../features/excel/presentation/import_screen.dart';
import '../../features/followups/presentation/follow_up_history_screen.dart';
import '../../features/followups/presentation/followups_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/home/presentation/more_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/statistics/presentation/father_stats_screen.dart';
import '../../features/statistics/presentation/servants_stats_screen.dart';
import '../../features/statistics/presentation/women_stats_screen.dart';
import '../../features/statistics/presentation/monthly_report_screen.dart';
import '../../features/streets/presentation/streets_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../../features/verse/presentation/verse_screen.dart';
import '../../features/women/presentation/woman_form_screen.dart';
import '../../features/women/presentation/woman_profile_screen.dart';
import '../../features/women/presentation/women_list_screen.dart';
import 'routes.dart';

/// Bridges Riverpod auth state to go_router's refreshListenable.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(currentUserProvider, (_, _) => notifyListeners());
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}

/// Pure redirect logic (unit-tested).
String? authRedirect({
  required String location,
  required bool authLoading,
  required bool signedIn,
  required bool profileLoading,
  required AppUser? user,
}) {
  final public = location == Routes.login;
  if (authLoading || (signedIn && profileLoading)) {
    return location == Routes.splash ? null : Routes.splash;
  }
  if (!signedIn) return public ? null : Routes.login;
  if (user == null || !user.active) {
    // Signed in but no profile (e.g. wrong join code) or disabled.
    return location == Routes.blocked ? null : Routes.blocked;
  }
  if (public || location == Routes.splash || location == Routes.blocked) {
    return Routes.home;
  }
  if (!user.isFather && Routes.isFatherOnly(location)) return Routes.home;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  GoRoute r(String path, Widget Function(GoRouterState s) b) =>
      GoRoute(path: path, builder: (_, s) => b(s));

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final profile = ref.read(currentUserProvider);
      return authRedirect(
        location: state.matchedLocation,
        authLoading: auth.isLoading,
        signedIn: auth.value != null,
        profileLoading: profile.isLoading,
        user: profile.value,
      );
    },
    routes: [
      r(Routes.splash, (_) => const SplashScreen()),
      r(Routes.login, (_) => const LoginScreen()),
      r(Routes.blocked, (_) => const BlockedScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [r(Routes.home, (_) => const DashboardScreen())]),
          StatefulShellBranch(routes: [r(Routes.women, (_) => const WomenListScreen())]),
          StatefulShellBranch(
              routes: [r(Routes.attendance, (_) => const AttendanceScreen())]),
          StatefulShellBranch(
              routes: [r(Routes.followUps, (_) => const FollowUpsScreen())]),
          StatefulShellBranch(routes: [r(Routes.stats, (_) => const FatherStatsScreen())]),
          StatefulShellBranch(routes: [r(Routes.more, (_) => const MoreScreen())]),
        ],
      ),
      r(Routes.womanNew, (_) => const WomanFormScreen()),
      r('/women/:id', (s) => WomanProfileScreen(womanId: s.pathParameters['id']!)),
      r('/women/:id/edit', (s) => WomanFormScreen(womanId: s.pathParameters['id'])),
      r('/women/:id/followups',
          (s) => FollowUpHistoryScreen(womanId: s.pathParameters['id']!)),
      r(Routes.attendanceHistory, (_) => const AttendanceHistoryScreen()),
      r(Routes.statsServants, (_) => const ServantsStatsScreen()),
      r(Routes.statsWomen, (_) => const WomenStatsScreen()),
      r(Routes.streets, (_) => const StreetsScreen()),
      r(Routes.conferences, (_) => const ConferencesScreen()),
      r(Routes.conferenceNew, (_) => const CreateConferenceScreen()),
      r('/conferences/:id',
          (s) => ConferenceAttendanceScreen(conferenceId: s.pathParameters['id']!)),
      r('/conferences/:id/stats',
          (s) => ConferenceStatsScreen(conferenceId: s.pathParameters['id']!)),
      r(Routes.birthdays, (_) => const BirthdaysScreen()),
      r(Routes.notifications, (_) => const NotificationsScreen()),
      r(Routes.verse, (_) => const VerseScreen()),
      r(Routes.import, (_) => const ImportScreen()),
      r(Routes.export, (_) => const ExportScreen()),
      r(Routes.users, (_) => const UsersScreen()),
      r(Routes.monthlyReport, (_) => const MonthlyReportScreen()),
      r(Routes.settings, (_) => const SettingsScreen()),
      r(Routes.audit, (_) => const AuditScreen()),
    ],
  );
});
