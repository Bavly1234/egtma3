import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';
import '../../women/domain/woman.dart';
import '../domain/attendance_record.dart';

class AttendanceRepository {
  AttendanceRepository(this._db, this._audit);
  final FirebaseFirestore _db;
  final AuditRepository _audit;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.attendance);

  /// Live statuses for one meeting, keyed by womanId. Servants only see the
  /// records of their own assigned women.
  Stream<Map<String, AttendanceStatus>> watchMeeting(
      String meetingId, AppUser user) {
    var q = _col.where('meetingId', isEqualTo: meetingId);
    if (!user.isFather) q = q.where('servantId', isEqualTo: user.id);
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
  }) async {
    final list = women.where((w) => previous[w.id] != status).toList();
    for (var i = 0; i < list.length; i += 150) {
      final batch = _db.batch();
      final top = <String, int>{};
      final byStreet = <String, Map<String, int>>{};
      final byServant = <String, Map<String, int>>{};
      void add(AttendanceStatus s, int sign, Woman w) {
        top.update(s.wire, (v) => v + sign, ifAbsent: () => sign);
        (byStreet[w.streetId.isEmpty ? 'unknown' : w.streetId] ??= {})
            .update(s.wire, (v) => v + sign, ifAbsent: () => sign);
        (byServant[w.assignedServantId ?? 'unassigned'] ??= {})
            .update(s.wire, (v) => v + sign, ifAbsent: () => sign);
      }

      for (final w in list.skip(i).take(150)) {
        batch.set(_col.doc(AttendanceRecord.docId(meetingId, w.id)), {
          'meetingId': meetingId,
          'womanId': w.id,
          'servantId': w.assignedServantId,
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

  /// Removes a mark and its contribution to the meeting counters.
  Future<void> clear(String meetingId, Woman w, AttendanceStatus previous) async {
    final batch = _db.batch();
    batch.delete(_col.doc(AttendanceRecord.docId(meetingId, w.id)));
    final dec = FieldValue.increment(-1);
    batch.set(
      _db.collection(FsPaths.meetings).doc(meetingId),
      {
        previous.wire: dec,
        'byStreet': {(w.streetId.isEmpty ? 'unknown' : w.streetId): {previous.wire: dec}},
        'byServant': {(w.assignedServantId ?? 'unassigned'): {previous.wire: dec}},
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
      if (!user.isFather) q = q.where('servantId', isEqualTo: user.id);
      final snap =
          await q.orderBy('meetingId', descending: true).limit(limit).get();
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
      final snap = await q
          .orderBy(FieldPath.documentId, descending: true)
          .limit(limit)
          .get();
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
      if (!user.isFather) q = q.where('servantId', isEqualTo: user.id);
      final snap = await q.get();
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
