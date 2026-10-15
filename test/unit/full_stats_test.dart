import 'package:egtma3/core/constants/enums.dart';
import 'package:egtma3/core/constants/firestore_paths.dart';
import 'package:egtma3/core/services/firebase_providers.dart';
import 'package:egtma3/features/auth/data/auth_repository.dart';
import 'package:egtma3/features/auth/domain/app_user.dart';
import 'package:egtma3/features/statistics/domain/stats_models.dart';
import 'package:egtma3/features/statistics/presentation/full_stats_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const father = AppUser(id: 'f', name: 'أبونا', email: '', phone: '', role: UserRole.father, active: true);
const sv1 = AppUser(id: 'sv1', name: 'مارينا', email: '', phone: '', role: UserRole.servant, active: true);
const sv2 = AppUser(id: 'sv2', name: 'ماري', email: '', phone: '', role: UserRole.servant, active: true);

class _MockAuth extends Mock implements FirebaseAuth {}

void main() {
  late FakeFirebaseFirestore db;
  late ProviderContainer c;
  final october = DateRange(DateTime(2026, 10, 1), DateTime(2026, 11, 1));

  setUp(() async {
    db = FakeFirebaseFirestore();
    Future<void> woman(String id, String name, String street) =>
        db.collection(FsPaths.women).doc(id).set({
          'fullName': name, 'nameNormalized': name, 'streetId': street,
          'streetName': street, 'active': true,
        });
    await woman('a', 'مريم', 's1');
    await woman('b', 'سعاد', 's1');
    await woman('c', 'منى', 's2');
    await db.collection(FsPaths.streets).doc('s1').set({'name': 'ش1', 'nameNormalized': 'ش1'});
    await db.collection(FsPaths.streets).doc('s2').set({'name': 'ش2', 'nameNormalized': 'ش2'});
    Future<void> mark(String day, String w, String street, String sv, bool present) =>
        db.collection(FsPaths.attendance).doc('${day}_$w').set({
          'meetingId': day, 'womanId': w, 'streetId': street, 'servantId': sv,
          'status': present ? 'present' : 'absent',
        });
    for (final d in ['2026-10-07', '2026-10-14', '2026-10-21']) {
      await mark(d, 'a', 's1', 'sv1', true); // مريم: 3/3
      await mark(d, 'c', 's2', 'sv2', false); // منى: 0/3
    }
    await mark('2026-10-07', 'b', 's1', 'sv1', true); // سعاد: 1/2
    await mark('2026-10-14', 'b', 's1', 'sv1', false);
    await mark('2026-09-30', 'c', 's2', 'sv2', true); // outside October
    // Servants' own attendance.
    Future<void> own(String day, String sv, bool present) =>
        db.collection(FsPaths.servantAttendance).doc('${day}_$sv').set({
          'meetingId': day, 'servantId': sv, 'servantName': sv,
          'status': present ? 'present' : 'absent',
        });
    await own('2026-10-07', 'sv1', true);
    await own('2026-10-14', 'sv1', true);
    await own('2026-10-07', 'sv2', false);

    for (final u in [father, sv1, sv2]) {
      await db.collection(FsPaths.users).doc(u.id).set({
        'name': u.name, 'role': u.role.wire, 'active': true,
      });
    }
    c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      requireUserProvider.overrideWithValue(father),
      // Real users repository on the in-memory database (auth isn't used here).
      firebaseAuthProvider.overrideWithValue(_MockAuth()),
    ]);
  });
  tearDown(() => c.dispose());

  /// Keep the provider alive while it loads, exactly like the screen does.
  Future<FullStats> load(StatsQuery q) {
    c.listen(fullStatsProvider(q), (_, _) {});
    return c.read(fullStatsProvider(q).future);
  }

  test('month: totals, most present / most absent, streets, servants', () async {
    final s = await load(StatsQuery(range: october, kind: PeriodKind.month));
    expect(s.weeks.length, 3);
    expect((s.present, s.absent), (4, 4));
    expect(s.mostPresent.first.woman.fullName, 'مريم');
    expect((s.mostPresent.first.present, s.mostPresent.first.total), (3, 3));
    expect(s.mostAbsent.first.woman.fullName, 'منى');
    expect(s.mostAbsent.first.absent, 3);
    expect(s.streets.map((r) => (r.name, r.count, r.total)),
        containsAll([('ش1', 4, 5), ('ش2', 0, 3)]));
    expect(s.servants.firstWhere((r) => r.name == 'مارينا').count, 4);
    // The servants' own attendance.
    final own = {for (final r in s.servantAttendance) r.name: (r.count, r.total)};
    expect(own['مارينا'], (2, 2));
    expect(own['ماري'], (0, 1));
  });

  test('street filter only counts that street', () async {
    final s = await load(
        StatsQuery(range: october, kind: PeriodKind.month, streetId: 's2'));
    expect((s.present, s.absent), (0, 3));
    expect(s.mostPresent, isEmpty);
    expect(s.streets, isEmpty); // no per-street list when one street is chosen
  });

  test('one Wednesday', () async {
    final day = DateRange(DateTime(2026, 10, 14), DateTime(2026, 10, 15));
    final s = await load(StatsQuery(range: day, kind: PeriodKind.day));
    expect(s.weeks.single.meetingId, '2026-10-14');
    expect((s.present, s.absent), (1, 2));
  });
}
