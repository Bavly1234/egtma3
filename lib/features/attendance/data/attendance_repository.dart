import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../auth/domain/app_user.dart';
import '../../women/domain/woman.dart';
import '../domain/attendance_record.dart';

class AttendanceRepository {
  AttendanceRepository(this._db);
  final FirebaseFirestore _db;

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

  /// Writes are returned un-awaited by the UI: Firestore applies them to the
  /// local cache immediately and syncs when online. The deterministic doc id
  /// guarantees no duplicates on re-sync.
  Future<void> mark(
    String meetingId,
    Woman woman,
    AttendanceStatus status,
    AppUser actor,
  ) =>
      _col.doc(AttendanceRecord.docId(meetingId, woman.id)).set({
        'meetingId': meetingId,
        'womanId': woman.id,
        'servantId': woman.assignedServantId,
        'streetId': woman.streetId,
        'status': status.wire,
        'markedBy': actor.id,
        'markedAt': FieldValue.serverTimestamp(),
      });

  Future<void> markMany(
    String meetingId,
    Iterable<Woman> women,
    AttendanceStatus status,
    AppUser actor,
  ) async {
    final list = women.toList();
    for (var i = 0; i < list.length; i += 400) {
      final batch = _db.batch();
      for (final w in list.skip(i).take(400)) {
        batch.set(_col.doc(AttendanceRecord.docId(meetingId, w.id)), {
          'meetingId': meetingId,
          'womanId': w.id,
          'servantId': w.assignedServantId,
          'streetId': w.streetId,
          'status': status.wire,
          'markedBy': actor.id,
          'markedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> clear(String meetingId, String womanId) =>
      _col.doc(AttendanceRecord.docId(meetingId, womanId)).delete();

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
    Provider((ref) => AttendanceRepository(ref.watch(firestoreProvider)));

final meetingSummaryProvider = StreamProvider.family<MeetingSummary?, String>(
    (ref, id) => ref.watch(attendanceRepositoryProvider).watchSummary(id));
