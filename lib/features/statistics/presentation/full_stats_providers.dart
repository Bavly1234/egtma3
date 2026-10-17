import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/dates.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/data/servant_attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/domain/app_user.dart';
import '../../streets/domain/street.dart';
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../users/data/users_repository.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import '../../women/domain/women_filter.dart';
import '../data/stats_repository.dart';
import '../domain/stats_models.dart';

enum PeriodKind { month, range, day }

/// What the statistics page is showing: a period and (optionally) a street.
class StatsQuery {
  const StatsQuery({required this.range, required this.kind, this.streetId});
  final DateRange range;
  final PeriodKind kind;
  final String? streetId;

  @override
  bool operator ==(Object other) =>
      other is StatsQuery &&
      other.range == range &&
      other.kind == kind &&
      other.streetId == streetId;
  @override
  int get hashCode => Object.hash(range, kind, streetId);
}

class WomanCount {
  const WomanCount(this.woman, this.present, this.absent);
  final Woman woman;
  final int present;
  final int absent;
  int get total => present + absent;
}

class WeekCount {
  const WeekCount(this.meetingId, this.present, this.absent);
  final String meetingId;
  final int present;
  final int absent;
}

class NamedCount {
  const NamedCount(this.name, this.count, this.total, {this.extra});
  final String name;
  final int count;
  final int total;
  final String? extra;
}

class FullStats {
  const FullStats({
    required this.weeks,
    required this.mostPresent,
    required this.mostAbsent,
    required this.streets,
    required this.servants,
    required this.servantAttendance,
    required this.followUps,
    required this.activeWomen,
  });

  final List<WeekCount> weeks; // oldest first
  final List<WomanCount> mostPresent;
  final List<WomanCount> mostAbsent;
  final List<NamedCount> streets; // empty when a street is selected
  final List<NamedCount> servants; // women attendance of each servant's streets
  final List<NamedCount> servantAttendance; // the servants' own attendance
  final FollowUpCounts followUps;
  final int activeWomen;

  int get present => weeks.fold(0, (a, w) => a + w.present);
  int get absent => weeks.fold(0, (a, w) => a + w.absent);
}

/// Everything on the statistics page, computed from the real records of the
/// period (and street). Shared by أبونا and the servants.
final fullStatsProvider =
    FutureProvider.autoDispose.family<FullStats, StatsQuery>((ref, q) async {
  final user = ref.watch(requireUserProvider);
  final fromId = q.range.fromId;
  final toId = q.range.toIdInclusive;

  final results = await Future.wait<Object>([
    ref.watch(attendanceRepositoryProvider).forMeetings(fromId, toId, user),
    ref.watch(womenRepositoryProvider).all(user, WomenFilter(streetId: q.streetId)),
    AppFailure.guard(ref.watch(streetsProvider.future)),
    AppFailure.guard(ref.watch(allUsersProvider.future)),
    ref.watch(servantAttendanceRepositoryProvider).inRange(fromId, toId),
    ref.watch(statsRepositoryProvider)
        .followUpCounts(range: q.range, streetId: q.streetId, now: DateTime.now()),
  ]);
  final records = results[0] as List<AttendanceRecord>;
  final women = results[1] as List<Woman>;
  final streets = results[2] as List<Street>;
  final users = results[3] as List<AppUser>;
  final servantMarks = results[4] as List<ServantMark>;
  final followUps = results[5] as FollowUpCounts;

  final byId = {for (final w in women) w.id: w};
  final weeks = <String, (int, int)>{};
  final perWoman = <String, (int, int)>{};
  final perStreet = <String, (int, int)>{};
  final perServant = <String, (int, int)>{};

  (int, int) add((int, int)? old, bool present) =>
      ((old?.$1 ?? 0) + (present ? 1 : 0), (old?.$2 ?? 0) + (present ? 0 : 1));

  for (final r in records) {
    if (q.streetId != null && r.streetId != q.streetId) continue;
    final present = r.status == AttendanceStatus.present;
    weeks[r.meetingId] = add(weeks[r.meetingId], present);
    if (byId.containsKey(r.womanId)) {
      perWoman[r.womanId] = add(perWoman[r.womanId], present);
    }
    final st = r.streetId;
    if (st != null && st.isNotEmpty) perStreet[st] = add(perStreet[st], present);
    final sv = r.servantId;
    if (sv != null) perServant[sv] = add(perServant[sv], present);
  }

  final counts = [
    for (final e in perWoman.entries) WomanCount(byId[e.key]!, e.value.$1, e.value.$2),
  ];
  final mostPresent = counts.where((c) => c.present > 0).toList()
    ..sort((a, b) => b.present != a.present
        ? b.present.compareTo(a.present)
        : a.absent.compareTo(b.absent));
  final mostAbsent = counts.where((c) => c.absent > 0).toList()
    ..sort((a, b) => b.absent != a.absent
        ? b.absent.compareTo(a.absent)
        : a.present.compareTo(b.present));

  final streetNames = {for (final s in streets) s.id: s.name};
  final streetRows = q.streetId != null
      ? <NamedCount>[]
      : ([
          for (final e in perStreet.entries)
            NamedCount(streetNames[e.key] ?? 'بدون شارع', e.value.$1, e.value.$1 + e.value.$2),
        ]..sort((a, b) => (b.count / b.total).compareTo(a.count / a.total)));

  final servantUsers = [for (final u in users) if (u.isServant && u.active) u];
  final servantRows = [
    for (final s in servantUsers)
      NamedCount(s.name, perServant[s.id]?.$1 ?? 0,
          (perServant[s.id]?.$1 ?? 0) + (perServant[s.id]?.$2 ?? 0)),
  ]..sort((a, b) => b.count.compareTo(a.count));

  final ownPresent = <String, int>{};
  final ownTotal = <String, int>{};
  for (final m in servantMarks) {
    ownTotal[m.servantId] = (ownTotal[m.servantId] ?? 0) + 1;
    if (m.status == AttendanceStatus.present) {
      ownPresent[m.servantId] = (ownPresent[m.servantId] ?? 0) + 1;
    }
  }
  // The servants' own attendance: women marked خادمة, taken by أبونا.
  final ownNames = {for (final m in servantMarks) m.servantId: m.servantName};
  final ownRows = [
    for (final e in ownNames.entries)
      NamedCount(e.value, ownPresent[e.key] ?? 0, ownTotal[e.key] ?? 0),
  ]..sort((a, b) => b.count.compareTo(a.count));

  return FullStats(
    weeks: [
      for (final id in weeks.keys.toList()..sort())
        WeekCount(id, weeks[id]!.$1, weeks[id]!.$2),
    ],
    mostPresent: mostPresent, // all, in order — the screen shows the top N
    mostAbsent: mostAbsent,
    streets: streetRows,
    servants: servantRows,
    servantAttendance: ownRows,
    followUps: followUps,
    activeWomen: women.where((w) => w.active && !w.isServant).length,
  );
});

/// "7/10" label for a Wednesday.
String shortDay(String meetingId) {
  final d = Dates.parseDayId(meetingId);
  return '${d.day}/${d.month}';
}
