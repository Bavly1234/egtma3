import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/dates.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';
import '../../women/domain/woman.dart';
import '../domain/attendance_record.dart';

class AttendanceRepository {
  /// The security rules check each woman exists, and Firestore allows only
  /// ~20 such checks per batch — a bigger batch is rejected as a whole.
  static const _batchSize = 12;

  AttendanceRepository(this._db, this._audit);
  final FirebaseFirestore _db;
  final AuditRepository _audit;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.attendance);

  /// Live statuses for one meeting, keyed by womanId.
  Stream<Map<String, AttendanceStatus>> watchMeeting(
      String meetingId, AppUser user) {
    var q = _col.where('meetingId', isEqualTo: meetingId);
    return q.snapshots(includeMetadataChanges: true).map((s) {
      final out = <String, AttendanceStatus>{};
      for (final d in s.docs) {
        final r = AttendanceRecord.fromMap(d.data());
        if (r != null) out[r.womanId] = r.status;
      }
      return out;
    });
  }

  /// Writes are not awaited by the UI: Firestore applies them to the local
  /// cache immediately and syncs when online. The deterministic doc id
  /// guarantees no duplicates on re-sync.
  ///
  /// The meeting counters (used by dashboards) are updated in the same batch
  /// with the net change from the [previous] status.
  Future<void> mark(
    String meetingId,
    Woman woman,
    AttendanceStatus status,
    AppUser actor, {
    AttendanceStatus? previous,
  }) =>
      markMany(meetingId, [woman], status, actor,
          previous: {woman.id: ?previous});

  Future<void> markMany(
    String meetingId,
    Iterable<Woman> women,
    AttendanceStatus status,
    AppUser actor, {
    Map<String, AttendanceStatus> previous = const {},
    Map<String, String?> meetingServants = const {},
  }) async {
    final list = women.where((w) => previous[w.id] != status).toList();
    for (var i = 0; i < list.length; i += _batchSize) {
      final batch = _db.batch();
      final top = <String, int>{};
      final byStreet = <String, Map<String, int>>{};
      final byServant = <String, Map<String, int>>{};
      String servantKey(Woman w) =>
          // Only the per-meeting assignment counts; no global assignment.
          meetingServants[w.id] ?? 'unassigned';

      void add(AttendanceStatus s, int sign, Woman w) {
        top.update(s.wire, (v) => v + sign, ifAbsent: () => sign);
        (byStreet[w.streetId.isEmpty ? 'unknown' : w.streetId] ??= {})
            .update(s.wire, (v) => v + sign, ifAbsent: () => sign);
        (byServant[servantKey(w)] ??= {})
            .update(s.wire, (v) => v + sign, ifAbsent: () => sign);
      }

      for (final w in list.skip(i).take(_batchSize)) {
        batch.set(_col.doc(AttendanceRecord.docId(meetingId, w.id)), {
          'meetingId': meetingId,
          'womanId': w.id,
          'servantId': servantKey(w) == 'unassigned' ? null : servantKey(w),
          'streetId': w.streetId,
          'status': status.wire,
          'markedBy': actor.id,
          'markedAt': FieldValue.serverTimestamp(),
          if (w.isDemo) 'isDemo': true,
        });
        final prev = previous[w.id];
        if (prev != null) {
          add(prev, -1, w);
          _audit.addToBatch(batch,
              actor: actor,
              action: AuditAction.attendanceChanged,
              entityType: 'attendance',
              entityId: AttendanceRecord.docId(meetingId, w.id),
              summary: '${w.fullName}: ${prev.label} ← ${status.label}');
        }
        add(status, 1, w);
      }
      Map<String, Object> inc(Map<String, int> m) => {
            for (final e in m.entries)
              if (e.value != 0) e.key: FieldValue.increment(e.value),
          };
      batch.set(
        _db.collection(FsPaths.meetings).doc(meetingId),
        {
          ...inc(top),
          'byStreet': {for (final e in byStreet.entries) e.key: inc(e.value)},
          'byServant': {for (final e in byServant.entries) e.key: inc(e.value)},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    }
  }

  /// Auto-marks every still-unmarked active woman as absent for [meetingId]
  /// (Wednesday 9pm cutoff). Only creates missing records — existing marks
  /// are never touched — so re-running is safe. Sets `autoAbsentDone`.
  /// Returns the ids of the newly-marked women.
  ///
  /// [force] (أبونا's manual button): run even if it already ran, and include
  /// women added after that Wednesday. Still only fills missing records.
  Future<List<String>> autoFillAbsent(String meetingId, AppUser actor,
      {bool force = false}) async {
    // Already done (possibly by another phone): never count absences twice.
    if (!force) {
      final meetingDoc = await AppFailure.guard(
          _db.collection(FsPaths.meetings).doc(meetingId).get());
      if (meetingDoc.data()?['autoAbsentDone'] == true) return const [];
    }
    final attSnap = await AppFailure.guard(
        _col.where('meetingId', isEqualTo: meetingId).get());
    final marked = {
      for (final d in attSnap.docs)
        (d.data()['womanId'] as String?) ?? d.id
    };
    final womenSnap = await AppFailure.guard(_db
        .collection(FsPaths.women)
        .where('active', isEqualTo: true)
        .get());
    // Women added after that Wednesday's cutoff weren't members yet: never
    // mark them absent for it.
    final cutoff = Dates.meetingCutoff(Dates.parseDayId(meetingId));
    final unmarked = womenSnap.docs.where((d) {
      if (marked.contains(d.id)) return false;
      // Servants have their own attendance (taken by أبونا).
      if (d.data()['isServant'] == true) return false;
      if (force) return true;
      final created = tsToDate(d.data()['createdAt']);
      return created == null || !created.isAfter(cutoff);
    }).toList();
    final streetsSnap =
        await AppFailure.guard(_db.collection(FsPaths.streets).get());
    final streetServant = {
      for (final d in streetsSnap.docs)
        d.id: d.data()['servantId'] as String?,
    };
    String servantKey(Map<String, dynamic> w) =>
        streetServant[w['streetId'] as String?] ?? 'unassigned';

    final filledIds = <String>[];
    for (var i = 0; i < unmarked.length; i += _batchSize) {
      final batch = _db.batch();
      final top = <String, int>{};
      final byStreet = <String, Map<String, int>>{};
      final byServant = <String, Map<String, int>>{};
      for (final d in unmarked.skip(i).take(_batchSize)) {
        final w = d.data();
        final streetKey = (w['streetId'] as String?)?.isNotEmpty == true
            ? w['streetId'] as String
            : 'unknown';
        batch.set(_col.doc(AttendanceRecord.docId(meetingId, d.id)), {
          'meetingId': meetingId,
          'womanId': d.id,
          'servantId': streetServant[w['streetId'] as String?],
          'streetId': w['streetId'],
          'status': AttendanceStatus.absent.wire,
          'markedBy': actor.id,
          'markedAt': FieldValue.serverTimestamp(),
          'autoMarked': true,
          if ((w['isDemo'] as bool?) == true) 'isDemo': true,
        });
        top.update('absent', (v) => v + 1, ifAbsent: () => 1);
        (byStreet[streetKey] ??= {})
            .update('absent', (v) => v + 1, ifAbsent: () => 1);
        (byServant[servantKey(w)] ??= {})
            .update('absent', (v) => v + 1, ifAbsent: () => 1);
        filledIds.add(d.id);
      }
      Map<String, Object> inc(Map<String, int> m) => {
            for (final e in m.entries) e.key: FieldValue.increment(e.value),
          };
      batch.set(
        _db.collection(FsPaths.meetings).doc(meetingId),
        {
          ...inc(top),
          'byStreet': {for (final e in byStreet.entries) e.key: inc(e.value)},
          'byServant': {for (final e in byServant.entries) e.key: inc(e.value)},
          'autoAbsentDone': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    }
    if (unmarked.isEmpty) {
      await _db.collection(FsPaths.meetings).doc(meetingId).set(
        {'autoAbsentDone': true, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    return filledIds;
  }

  /// Removes a mark and its contribution to the meeting counters.
  Future<void> clear(String meetingId, Woman w, AttendanceStatus previous,
      {String? meetingServantId}) async {
    final batch = _db.batch();
    batch.delete(_col.doc(AttendanceRecord.docId(meetingId, w.id)));
    final dec = FieldValue.increment(-1);
    final servantKey = meetingServantId ?? 'unassigned';
    batch.set(
      _db.collection(FsPaths.meetings).doc(meetingId),
      {
        previous.wire: dec,
        'byStreet': {(w.streetId.isEmpty ? 'unknown' : w.streetId): {previous.wire: dec}},
        'byServant': {servantKey: {previous.wire: dec}},
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Attendance history of one woman, newest first.
  Future<List<AttendanceRecord>> history(String womanId, AppUser user,
      {int limit = 52}) async {
    try {
      var q = _col.where('womanId', isEqualTo: womanId);
        final snap =
          await AppFailure.guard(q.orderBy('meetingId', descending: true).limit(limit).get());
      return snap.docs
          .map((d) => AttendanceRecord.fromMap(d.data()))
          .whereType<AttendanceRecord>()
          .toList();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Stream<MeetingSummary?> watchSummary(String meetingId) => _db
      .collection(FsPaths.meetings)
      .doc(meetingId)
      .snapshots()
      .map((s) => s.exists ? MeetingSummary.fromMap(s.id, s.data()!) : null);

  /// Most recent meeting summaries (newest first), optionally within a range.
  Future<List<MeetingSummary>> summaries({
    int limit = 12,
    String? fromId,
    String? toId,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db.collection(FsPaths.meetings);
      if (fromId != null) {
        q = q.where(FieldPath.documentId, isGreaterThanOrEqualTo: fromId);
      }
      if (toId != null) {
        q = q.where(FieldPath.documentId, isLessThanOrEqualTo: toId);
      }
      final snap = await AppFailure.guard(q
          .orderBy(FieldPath.documentId, descending: true)
          .limit(limit)
          .get());
      return snap.docs
          .map((d) => MeetingSummary.fromMap(d.id, d.data()))
          .toList();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  /// All attendance records for export.
  Future<List<AttendanceRecord>> forMeetings(
      String fromId, String toId, AppUser user) async {
    try {
      var q = _col
          .where('meetingId', isGreaterThanOrEqualTo: fromId)
          .where('meetingId', isLessThanOrEqualTo: toId);
        final snap = await AppFailure.guard(q.get());
      return snap.docs
          .map((d) => AttendanceRecord.fromMap(d.data()))
          .whereType<AttendanceRecord>()
          .toList();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final attendanceRepositoryProvider =
    Provider((ref) => AttendanceRepository(
        ref.watch(firestoreProvider), ref.watch(auditRepositoryProvider)));

final meetingSummaryProvider = StreamProvider.family<MeetingSummary?, String>(
    (ref, id) => ref.watch(attendanceRepositoryProvider).watchSummary(id));
