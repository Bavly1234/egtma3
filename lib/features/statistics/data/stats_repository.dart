import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/dates.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/domain/app_user.dart';
import '../../streets/domain/street.dart';
import '../domain/stats_models.dart';

/// Statistics built from Firestore `count()` aggregations and the
/// function-maintained `meetings/{id}` counters — no full collection scans.
class StatsRepository {
  StatsRepository(this._db);
  final FirebaseFirestore _db;

  Future<int> _count(Query<Map<String, dynamic>> q) async =>
      (await q.count().get()).count ?? 0;

  CollectionReference<Map<String, dynamic>> get _women =>
      _db.collection(FsPaths.women);
  CollectionReference<Map<String, dynamic>> get _followUps =>
      _db.collection(FsPaths.followUps);
  CollectionReference<Map<String, dynamic>> get _sugg =>
      _db.collection(FsPaths.suggestions);

  Future<MeetingSummary?> meeting(String id) async {
    final s = await _db.collection(FsPaths.meetings).doc(id).get();
    return s.exists ? MeetingSummary.fromMap(s.id, s.data()!) : null;
  }

  Future<FollowUpCounts> followUpCounts({
    required DateRange range,
    String? servantId,
    String? streetId,
    FollowUpType? type,
    required DateTime now,
  }) async {
    Query<Map<String, dynamic>> fu = _followUps
        .where('occurredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(range.from))
        .where('occurredAt', isLessThan: Timestamp.fromDate(range.to));
    Query<Map<String, dynamic>> sg = _sugg
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(range.from))
        .where('createdAt', isLessThan: Timestamp.fromDate(range.to));
    Query<Map<String, dynamic>> pending =
        _sugg.where('status', whereIn: SuggestionStatus.activeWires);
    if (servantId != null) {
      fu = fu.where('servantId', isEqualTo: servantId);
      sg = sg.where('assignedServantId', isEqualTo: servantId);
      pending = pending.where('assignedServantId', isEqualTo: servantId);
    }
    if (streetId != null) {
      fu = fu.where('streetId', isEqualTo: streetId);
      sg = sg.where('streetId', isEqualTo: streetId);
      pending = pending.where('streetId', isEqualTo: streetId);
    }
    final wantCalls = type == null || type == FollowUpType.phoneCall;
    final wantVisits = type == null || type == FollowUpType.homeVisit;
    final overdueBefore = Timestamp.fromDate(
        now.subtract(const Duration(days: BusinessRules.overdueDays)));

    final r = await Future.wait([
      wantCalls
          ? _count(fu.where('type', isEqualTo: FollowUpType.phoneCall.wire))
          : Future.value(0),
      wantVisits
          ? _count(fu.where('type', isEqualTo: FollowUpType.homeVisit.wire))
          : Future.value(0),
      _count(sg.where('type', isEqualTo: SuggestionType.phone.wire)),
      _count(sg.where('type', isEqualTo: SuggestionType.homeVisit.wire)),
      _count(sg
          .where('type', isEqualTo: SuggestionType.phone.wire)
          .where('status', isEqualTo: SuggestionStatus.completed.wire)),
      _count(sg
          .where('type', isEqualTo: SuggestionType.homeVisit.wire)
          .where('status', isEqualTo: SuggestionStatus.completed.wire)),
      _count(pending),
      _count(pending.where('createdAt', isLessThan: overdueBefore)),
    ]);
    return FollowUpCounts(
      calls: r[0],
      visits: r[1],
      phoneSuggestions: r[2],
      homeSuggestions: r[3],
      phoneCompleted: r[4],
      homeCompleted: r[5],
      pending: r[6],
      overdue: r[7],
    );
  }

  Future<OverviewStats> overview(AppUser user, DateTime now,
      {required DateRange range, int servants = 0}) async {
    try {
      final meetingId = Dates.dayId(Dates.currentOrLastMeeting(now));
      final scoped = _women;
      final results = await Future.wait<Object?>([
        _count(scoped),
        _count(scoped.where('active', isEqualTo: true)),
        meeting(meetingId),
        followUpCounts(
            range: range,
            now: now),
        _count(scoped
            .where('active', isEqualTo: true)
            .where('birthMonth', isEqualTo: now.month)
            .where('birthDay', isEqualTo: now.day)),
      ]);
      final m = results[2] as MeetingSummary?;
      return OverviewStats(
        totalWomen: results[0] as int,
        activeWomen: results[1] as int,
        totalServants: servants,
        meetingId: meetingId,
        meetingPresent: m?.present ?? 0,
        meetingAbsent: m?.absent ?? 0,
        followUps: results[3] as FollowUpCounts,
        birthdaysToday: results[4] as int,
      );
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// Per-servant statistics. Meeting attendance is aggregated over meetings
  /// in [StatsFilter.range] using the per-servant counters.
  Future<ServantStats> servantStats(
      AppUser servant, StatsFilter f, DateTime now) async {
    try {
      final meetings = await _db
          .collection(FsPaths.meetings)
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: f.range.fromId)
          .where(FieldPath.documentId,
              isLessThanOrEqualTo: f.range.toIdInclusive)
          .get();
      var present = 0, absent = 0;
      for (final d in meetings.docs) {
        final c = MeetingSummary.fromMap(d.id, d.data()).byServant[servant.id];
        present += c?.present ?? 0;
        absent += c?.absent ?? 0;
      }
      final mine = _women.where('assignedServantId', isEqualTo: servant.id);
      final r = await Future.wait<Object>([
        _count(mine.where('active', isEqualTo: true)),
        followUpCounts(
            range: f.range,
            servantId: servant.id,
            streetId: f.streetId,
            type: f.followUpType,
            now: now),
        _count(mine.where('consecutiveAbsences',
            isGreaterThanOrEqualTo: BusinessRules.phoneThreshold)),
      ]);
      return ServantStats(
        servantId: servant.id,
        servantName: servant.name,
        assignedWomen: r[0] as int,
        followUps: r[1] as FollowUpCounts,
        meetingPresent: present,
        meetingAbsent: absent,
        withConsecutiveAbsences: r[2] as int,
      );
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<List<StreetStats>> streetStats(
      List<Street> streets, String meetingId) async {
    try {
      final m = await meeting(meetingId);
      final active = await Future.wait(streets.map((s) => _count(_sugg
          .where('streetId', isEqualTo: s.id)
          .where('status', whereIn: SuggestionStatus.activeWires))));
      return [
        for (var i = 0; i < streets.length; i++)
          StreetStats(
            streetId: streets[i].id,
            name: streets[i].name,
            women: streets[i].womenCount,
            present: m?.byStreet[streets[i].id]?.present ?? 0,
            absent: m?.byStreet[streets[i].id]?.absent ?? 0,
            activeSuggestions: active[i],
          ),
      ];
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final statsRepositoryProvider =
    Provider((ref) => StatsRepository(ref.watch(firestoreProvider)));
