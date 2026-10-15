import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

/// One servant's attendance at one Wednesday meeting (taken by the father).
class ServantMark {
  const ServantMark(this.meetingId, this.servantId, this.servantName, this.status);
  final String meetingId;
  final String servantId;
  final String servantName;
  final AttendanceStatus status;
}

/// The servants' own attendance. Kept separate from the women's attendance
/// so it never affects the women's statistics or follow-up rules.
class ServantAttendanceRepository {
  ServantAttendanceRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.servantAttendance);

  static String docId(String meetingId, String servantId) => '${meetingId}_$servantId';

  ServantMark? _fromDoc(Map<String, dynamic> m) {
    final s = AttendanceStatus.fromWire(m['status'] as String?);
    if (s == null) return null;
    return ServantMark(m['meetingId'] as String, m['servantId'] as String,
        (m['servantName'] as String?) ?? '', s);
  }

  /// servantId → status for one Wednesday (live).
  Stream<Map<String, AttendanceStatus>> watchMeeting(String meetingId) => _col
      .where('meetingId', isEqualTo: meetingId)
      .snapshots()
      .map((s) => {
            for (final d in s.docs)
              if (_fromDoc(d.data()) case final r?) r.servantId: r.status,
          });

  Future<void> mark(String meetingId, AppUser servant, AttendanceStatus status,
          AppUser actor) =>
      _col.doc(docId(meetingId, servant.id)).set({
        'meetingId': meetingId,
        'servantId': servant.id,
        'servantName': servant.name,
        'status': status.wire,
        'markedBy': actor.id,
        'markedAt': FieldValue.serverTimestamp(),
      });

  Future<void> clear(String meetingId, String servantId) =>
      _col.doc(docId(meetingId, servantId)).delete();

  /// All marks between two Wednesdays (inclusive), for statistics.
  Future<List<ServantMark>> inRange(String fromId, String toId) async {
    try {
      final snap = await AppFailure.guard(_col
          .where('meetingId', isGreaterThanOrEqualTo: fromId)
          .where('meetingId', isLessThanOrEqualTo: toId)
          .get());
      return snap.docs.map((d) => _fromDoc(d.data())).whereType<ServantMark>().toList();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final servantAttendanceRepositoryProvider =
    Provider((ref) => ServantAttendanceRepository(ref.watch(firestoreProvider)));

final servantMeetingProvider =
    StreamProvider.family<Map<String, AttendanceStatus>, String>((ref, meetingId) =>
        ref.watch(servantAttendanceRepositoryProvider).watchMeeting(meetingId));
