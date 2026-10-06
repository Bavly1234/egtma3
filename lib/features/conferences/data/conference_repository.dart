import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/dates.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';
import '../../women/domain/woman.dart';
import '../domain/conference.dart';

class ConferenceRepository {
  ConferenceRepository(this._db, this._audit);
  final FirebaseFirestore _db;
  final AuditRepository _audit;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsPaths.conferences);
  CollectionReference<Map<String, dynamic>> get _att =>
      _db.collection(FsPaths.conferenceAttendance);

  Stream<List<Conference>> watchAll() => _col
      .orderBy('startDate', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => Conference.fromMap(d.id, d.data())).toList());

  Stream<Conference?> watch(String id) => _col.doc(id).snapshots().map(
      (s) => s.exists ? Conference.fromMap(s.id, s.data()!) : null);

  /// Exactly three user-chosen dates (may be non-consecutive). Days are
  /// embedded in the conference document: there are always three, so a
  /// subcollection would only add reads.
  Future<String> create(
      String name, List<DateTime> dates, AppUser actor) async {
    if (name.trim().isEmpty) throw const AppFailure('اسم المؤتمر مطلوب');
    if (dates.length != BusinessRules.conferenceDayCount) {
      throw const AppFailure('يجب اختيار 3 أيام للمؤتمر');
    }
    final sorted = dates.map(Dates.dateOnly).toList()..sort();
    if (sorted.toSet().length != sorted.length) {
      throw const AppFailure('لا يمكن تكرار نفس اليوم');
    }
    try {
      final ref = _col.doc();
      final batch = _db.batch();
      batch.set(ref, {
        'name': name.trim(),
        'startDate': Timestamp.fromDate(sorted.first),
        'dayIds': [for (var i = 0; i < 3; i++) Dates.dayId(sorted[i])],
        'days': [
          for (var i = 0; i < 3; i++)
            {
              'id': 'day${i + 1}',
              'index': i,
              'date': Timestamp.fromDate(sorted[i]),
            }
        ],
        'createdBy': actor.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.conferenceCreated,
          entityType: 'conference',
          entityId: ref.id,
          summary: name);
      await batch.commit();
      return ref.id;
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<void> delete(Conference c, AppUser actor) async {
    try {
      final batch = _db.batch();
      batch.delete(_col.doc(c.id));
      _audit.addToBatch(batch,
          actor: actor,
          action: AuditAction.conferenceDeleted,
          entityType: 'conference',
          entityId: c.id,
          summary: c.name);
      await batch.commit();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Stream<Map<String, AttendanceStatus>> watchDay(
      String conferenceId, String dayId, AppUser user) {
    var q = _att
        .where('conferenceId', isEqualTo: conferenceId)
        .where('conferenceDayId', isEqualTo: dayId);
    return q.snapshots().map((s) => {
          for (final d in s.docs)
            if (ConferenceAttendance.fromMap(d.data()) case final r?)
              r.womanId: r.status,
        });
  }

  Future<void> mark(String conferenceId, String dayId, Woman w,
          AttendanceStatus status, AppUser actor) =>
      _att.doc(ConferenceAttendance.docId(conferenceId, dayId, w.id)).set({
        'conferenceId': conferenceId,
        'conferenceDayId': dayId,
        'womanId': w.id,
        'servantId': w.assignedServantId,
        'attendanceStatus': status.wire,
        'markedBy': actor.id,
        'timestamp': FieldValue.serverTimestamp(),
      });

  Future<List<ConferenceAttendance>> allAttendance(
      String conferenceId, AppUser user) async {
    try {
      var q = _att.where('conferenceId', isEqualTo: conferenceId);
        final snap = await q.get();
      return snap.docs
          .map((d) => ConferenceAttendance.fromMap(d.data()))
          .whereType<ConferenceAttendance>()
          .toList();
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final conferenceRepositoryProvider = Provider((ref) => ConferenceRepository(
    ref.watch(firestoreProvider), ref.watch(auditRepositoryProvider)));

final conferencesProvider = StreamProvider<List<Conference>>(
    (ref) => ref.watch(conferenceRepositoryProvider).watchAll());

final conferenceProvider = StreamProvider.family<Conference?, String>(
    (ref, id) => ref.watch(conferenceRepositoryProvider).watch(id));
