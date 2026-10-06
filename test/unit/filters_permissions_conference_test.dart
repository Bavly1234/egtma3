import 'package:egtma3/core/constants/enums.dart';
import 'package:egtma3/core/routing/app_router.dart';
import 'package:egtma3/core/routing/routes.dart';
import 'package:egtma3/features/auth/domain/app_user.dart';
import 'package:egtma3/features/auth/domain/permissions.dart';
import 'package:egtma3/features/conferences/domain/conference.dart';
import 'package:egtma3/features/conferences/domain/conference_stats.dart';
import 'package:egtma3/features/women/domain/woman.dart';
import 'package:egtma3/features/women/domain/women_filter.dart';
import 'package:flutter_test/flutter_test.dart';

Woman woman({
  String name = 'مريم أحمد',
  int absences = 0,
  int present = 0,
  int absent = 0,
  String? last,
}) =>
    Woman(
      id: 'w',
      fullName: name,
      streetId: 's1',
      streetName: 'شارع مار جرجس',
      address: '10 شارع',
      phone: '01012345678',
      dateOfBirth: DateTime(1970),
      active: true,
      consecutiveAbsences: absences,
      totalPresent: present,
      totalAbsent: absent,
      lastAttendanceDate: last,
    );

const father = AppUser(id: 'f', name: 'أبونا', email: '', phone: '', role: UserRole.father, active: true);
const servant = AppUser(id: 's', name: 'خادمة', email: '', phone: '', role: UserRole.servant, active: true);
const disabled = AppUser(id: 'd', name: 'x', email: '', phone: '', role: UserRole.father, active: false);

void main() {
  group('filtering', () {
    test('Arabic-tolerant multi-token search across fields', () {
      const f = WomenFilter(query: 'مريم جرجس');
      expect(f.matchesClientSide(woman()), isTrue);
      expect(const WomenFilter(query: 'امريكا').matchesClientSide(woman()), isFalse);
      expect(const WomenFilter(query: '0101234').matchesClientSide(woman()), isTrue);
    });

    test('consecutive absences and attendance rate combine', () {
      const f = WomenFilter(minConsecutiveAbsences: 2, maxAttendanceRate: .5);
      expect(f.matchesClientSide(woman(absences: 3, present: 1, absent: 3)), isTrue);
      expect(f.matchesClientSide(woman(absences: 1, present: 1, absent: 3)), isFalse);
      expect(f.matchesClientSide(woman(absences: 3, present: 9, absent: 3)), isFalse);
    });

    test('last attendance filter', () {
      const present = WomenFilter(lastAttendance: LastAttendanceFilter.present);
      expect(present.matchesClientSide(woman(last: '2026-09-30')), isTrue);
      expect(present.matchesClientSide(woman(absences: 1, last: '2026-09-30')), isFalse);
    });

    test('active count and clear', () {
      const f = WomenFilter(streetId: 's', active: true, followUp: FollowUpFilter.phone);
      expect(f.activeCount, 3);
      expect(f.hasServerFilters, isTrue);
      expect(WomenFilter.empty.isEmpty, isTrue);
      expect(f.copyWith(streetId: () => null).streetId, isNull);
    });
  });

  group('role permissions', () {
    test('father manages, servants act on all women', () {
      expect(Permissions.canManageWomen(father), isTrue);
      expect(Permissions.canManageWomen(servant), isFalse);
      expect(Permissions.canImportExport(servant), isFalse);
      expect(Permissions.canActOnWoman(servant, 's'), isTrue);
      // Assignment is optional: every active servant can act on every woman.
      expect(Permissions.canActOnWoman(servant, 'other'), isTrue);
      expect(Permissions.canActOnWoman(servant, null), isTrue);
      expect(Permissions.canActOnWoman(father, 'other'), isTrue);
    });

    test('disabled accounts have no permissions', () {
      expect(Permissions.canManageWomen(disabled), isFalse);
      expect(Permissions.canTakeAttendance(disabled), isFalse);
    });

    test('router guards father-only routes', () {
      String? go(String loc, AppUser? u) => authRedirect(
          location: loc, authLoading: false, signedIn: true, profileLoading: false, user: u);
      expect(go(Routes.users, servant), Routes.home);
      expect(go(Routes.import, servant), Routes.home);
      expect(go(Routes.womanEdit('x'), servant), Routes.home);
      expect(go(Routes.statsServants, servant), isNull);
      expect(go(Routes.users, father), isNull);
      expect(go(Routes.home, disabled), Routes.blocked);
      expect(authRedirect(location: Routes.home, authLoading: false, signedIn: false,
          profileLoading: false, user: null), Routes.login);
    });
  });

  group('Rule F: conference attendance is independent', () {
    final conf = Conference(id: 'c1', name: 'مؤتمر', days: [
      ConferenceDay(id: 'day1', index: 0, date: DateTime(2026, 11, 6)),
      ConferenceDay(id: 'day2', index: 1, date: DateTime(2026, 11, 7)),
      ConferenceDay(id: 'day3', index: 2, date: DateTime(2026, 11, 13)),
    ]);
    ConferenceAttendance r(String w, String d, AttendanceStatus s, [String c = 'c1']) =>
        ConferenceAttendance(conferenceId: c, conferenceDayId: d, womanId: w, status: s);
    const P = AttendanceStatus.present, A = AttendanceStatus.absent;

    test('statistics per day and per woman', () {
      final s = ConferenceStats.compute(conf, [
        r('a', 'day1', P), r('a', 'day2', P), r('a', 'day3', P), // all 3
        r('b', 'day1', P), r('b', 'day2', P), r('b', 'day3', A), // missed one
        r('c', 'day1', P), r('c', 'day2', A), // missed two (day3 unmarked)
        r('x', 'day1', P, 'other-conference'), // ignored
      ]);
      expect(s.presentPerDay, {'day1': 3, 'day2': 2, 'day3': 1});
      expect(s.attendedAll, 1);
      expect(s.missedOne, 1);
      expect(s.missedMultiple, 1);
      expect(s.uniqueAttendees, 3);
      expect(s.dayRate('day1'), 1.0);
    });

    test('document ids never collide with Wednesday attendance ids', () {
      final id = ConferenceAttendance.docId('c1', 'day1', 'w1');
      expect(id, 'c1_day1_w1');
      expect(id.startsWith(RegExp(r'\d{4}-')), isFalse);
    });
  });
}
