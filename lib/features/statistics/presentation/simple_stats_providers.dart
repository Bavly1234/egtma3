import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../users/data/users_repository.dart';
import '../data/stats_repository.dart';
import '../domain/stats_models.dart';

DateRange monthRange(DateTime month) =>
    DateRange(DateTime(month.year, month.month), DateTime(month.year, month.month + 1));

/// The Wednesdays of a month, oldest first.
final monthMeetingsProvider = FutureProvider.autoDispose
    .family<List<MeetingSummary>, DateTime>((ref, month) async {
  final r = monthRange(month);
  final list = await ref
      .watch(attendanceRepositoryProvider)
      .summaries(limit: 6, fromId: r.fromId, toId: r.toIdInclusive);
  return list.reversed.toList();
});

/// One servant's month (her streets).
final servantMonthProvider = FutureProvider.autoDispose
    .family<ServantStats, (AppUser, DateTime)>((ref, key) {
  final (servant, month) = key;
  return ref.watch(statsRepositoryProvider).servantStats(
      servant, StatsFilter(range: monthRange(month)), DateTime.now());
});

/// Every active servant's month, best attendance first (father).
final allServantsMonthProvider = FutureProvider.autoDispose
    .family<List<ServantStats>, DateTime>((ref, month) async {
  final users = await AppFailure.guard(ref.watch(allUsersProvider.future));
  final repo = ref.watch(statsRepositoryProvider);
  final now = DateTime.now();
  final list = await Future.wait(users
      .where((u) => u.isServant && u.active)
      .map((s) => repo.servantStats(s, StatsFilter(range: monthRange(month)), now)));
  return list..sort((a, b) => b.attendanceRate.compareTo(a.attendanceRate));
});

/// Follow-ups of the whole church for a month (father).
final churchFollowUpsProvider = FutureProvider.autoDispose
    .family<FollowUpCounts, DateTime>((ref, month) {
  ref.watch(requireUserProvider);
  return ref
      .watch(statsRepositoryProvider)
      .followUpCounts(range: monthRange(month), now: DateTime.now());
});
