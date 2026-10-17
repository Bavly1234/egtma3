import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/dates.dart';
import '../../auth/domain/app_user.dart';
import '../../women/domain/woman.dart';

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

  /// [servant] is a woman marked as خادمة.
  Future<void> mark(String meetingId, Woman servant, AttendanceStatus status,
          AppUser actor) =>
      _col.doc(docId(meetingId, servant.id)).set({
        'meetingId': meetingId,
        'servantId': servant.id,
        'servantName': servant.fullName,
        'status': status.wire,
        'markedBy': actor.id,
        'markedAt': FieldValue.serverTimestamp(),
      });

  /// Wednesday 9pm: every servant not marked yet becomes absent. Only
  /// missing records are created (existing marks are never touched), so
  /// running it again — or on two phones — is harmless.
  Future<int> autoFillAbsent(String meetingId, AppUser actor) async {
    final cutoff = Dates.meetingCutoff(Dates.parseDayId(meetingId));
    final servants = await AppFailure.guard(_db
        .collection(FsPaths.women)
        .where('isServant', isEqualTo: true)
        .where('active', isEqualTo: true)
        .get());
    final marked = await AppFailure.guard(
        _col.where('meetingId', isEqualTo: meetingId).get());
    final done = {for (final d in marked.docs) d.data()['servantId']};
    var n = 0;
    for (final d in servants.docs) {
      if (done.contains(d.id)) continue;
      final created = tsToDate(d.data()['createdAt']);
      if (created != null && created.isAfter(cutoff)) continue; // joined later
      // One write per servant: if someone marked her meanwhile, the rules
      // reject this create and her real mark stays.
      _col.doc(docId(meetingId, d.id)).set({
        'meetingId': meetingId,
        'servantId': d.id,
        'servantName': d.data()['fullName'] ?? '',
        'status': AttendanceStatus.absent.wire,
        'autoMarked': true,
        'markedBy': actor.id,
        'markedAt': FieldValue.serverTimestamp(),
      }).catchError((Object _) {});
      n++;
    }
    return n;
  }

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

/// Women marked as خادمة (active), sorted by name.
final servantWomenProvider = StreamProvider<List<Woman>>((ref) => ref
    .watch(firestoreProvider)
    .collection(FsPaths.women)
    .where('isServant', isEqualTo: true)
    .where('active', isEqualTo: true)
    .snapshots()
    .map((s) => s.docs.map((d) => Woman.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName))));

final servantMeetingProvider =
    StreamProvider.family<Map<String, AttendanceStatus>, String>((ref, meetingId) =>
        ref.watch(servantAttendanceRepositoryProvider).watchMeeting(meetingId));
