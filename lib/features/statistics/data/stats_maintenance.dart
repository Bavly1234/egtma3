import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../excel/domain/import_models.dart';

/// Rebuilds every statistic from the records that really exist.
///
/// Meeting totals are kept as running counters for speed. After deleting
/// women (or the test data) those counters still include them, so the
/// statistics pages showed numbers for people who are gone. This:
///  1. removes records that belong to women who no longer exist
///     (attendance, follow-up tasks, calls/visits, conference attendance);
///  2. recomputes each Wednesday's totals from the remaining attendance
///     (Wednesdays with nothing left are removed);
///  3. recomputes how many women live in each street.
class StatsMaintenance {
  StatsMaintenance(this._db);
  final FirebaseFirestore _db;

  Future<void> _deleteAll(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 400) {
      final b = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        b.delete(r);
      }
      await b.commit();
    }
  }

  /// Marks every woman whose name starts with "ت/" as خادمة.
  /// Returns how many were changed.
  Future<int> markServantsByName() async {
    final women = await AppFailure.guard(_db.collection(FsPaths.women).get(),
        timeout: const Duration(seconds: 60));
    final refs = [
      for (final d in women.docs)
        if (d.data()['isServant'] != true &&
            looksLikeServantName((d.data()['fullName'] as String?) ?? ''))
          d.reference,
    ];
    for (var i = 0; i < refs.length; i += 400) {
      final b = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        b.update(r, {'isServant': true});
      }
      await b.commit();
    }
    return refs.length;
  }

  /// Returns a short Arabic summary.
  Future<String> rebuild() async {
    try {
      final women = await AppFailure.guard(_db.collection(FsPaths.women).get(),
          timeout: const Duration(seconds: 60));
      final womanIds = {for (final d in women.docs) d.id};

      // 1. Orphans.
      var orphans = 0;
      Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> keepLiving(
          String col) async {
        final snap = await AppFailure.guard(_db.collection(col).get(),
            timeout: const Duration(seconds: 60));
        final dead = snap.docs
            .where((d) => !womanIds.contains(d.data()['womanId']))
            .map((d) => d.reference)
            .toList();
        await _deleteAll(dead);
        orphans += dead.length;
        return snap.docs
            .where((d) => womanIds.contains(d.data()['womanId']))
            .toList();
      }

      final attendance = await keepLiving(FsPaths.attendance);
      await keepLiving(FsPaths.suggestions);
      await keepLiving(FsPaths.followUps);
      await keepLiving(FsPaths.conferenceAttendance);

      // 2. Meeting totals from scratch.
      final totals = <String, Map<String, dynamic>>{};
      for (final d in attendance) {
        final a = d.data();
        final status = a['status'];
        if (status != 'present' && status != 'absent') continue;
        final m = totals.putIfAbsent(a['meetingId'] as String, () => {
              'present': 0,
              'absent': 0,
              'byStreet': <String, Map<String, int>>{},
              'byServant': <String, Map<String, int>>{},
            });
        m[status] = (m[status] as int) + 1;
        void bump(String group, String? key) {
          final g = m[group] as Map<String, Map<String, int>>;
          final k = (key == null || key.isEmpty)
              ? (group == 'byStreet' ? 'unknown' : 'unassigned')
              : key;
          final c = g.putIfAbsent(k, () => {'present': 0, 'absent': 0});
          c[status as String] = c[status]! + 1;
        }

        bump('byStreet', a['streetId'] as String?);
        bump('byServant', a['servantId'] as String?);
      }
      final meetings = await AppFailure.guard(_db.collection(FsPaths.meetings).get());
      final batch = <(DocumentReference, Map<String, dynamic>?)>[];
      for (final d in meetings.docs) {
        final t = totals.remove(d.id);
        batch.add((d.reference, t == null
            ? null
            : {
                ...t,
                if (d.data()['autoAbsentDone'] == true) 'autoAbsentDone': true,
                'updatedAt': FieldValue.serverTimestamp(),
              }));
      }
      for (final e in totals.entries) {
        batch.add((
          _db.collection(FsPaths.meetings).doc(e.key),
          {...e.value, 'updatedAt': FieldValue.serverTimestamp()},
        ));
      }
      var removedMeetings = 0;
      for (var i = 0; i < batch.length; i += 400) {
        final b = _db.batch();
        for (final (ref, data) in batch.skip(i).take(400)) {
          if (data == null) {
            b.delete(ref);
            removedMeetings++;
          } else {
            b.set(ref, data); // full overwrite, no stale counters
          }
        }
        await b.commit();
      }

      // 3. Street counts.
      final perStreet = <String, int>{};
      for (final d in women.docs) {
        final s = d.data()['streetId'] as String?;
        if (s != null && s.isNotEmpty) perStreet[s] = (perStreet[s] ?? 0) + 1;
      }
      final streets = await AppFailure.guard(_db.collection(FsPaths.streets).get());
      for (var i = 0; i < streets.docs.length; i += 400) {
        final b = _db.batch();
        for (final d in streets.docs.skip(i).take(400)) {
          b.update(d.reference, {'womenCount': perStreet[d.id] ?? 0});
        }
        await b.commit();
      }

      return 'تم تحديث الإحصائيات ✅ '
          '(اتشال $orphans سجل قديم لسيدات اتمسحوا، و$removedMeetings اجتماع فاضي)';
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final statsMaintenanceProvider =
    Provider((ref) => StatsMaintenance(ref.watch(firestoreProvider)));
