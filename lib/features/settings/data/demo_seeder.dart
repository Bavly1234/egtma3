import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/dates.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../followups/data/absence_processor.dart';
import '../../streets/domain/street.dart';
import '../../women/domain/woman.dart';

/// Demo data created from the father's phone (no server needed).
/// Everything is flagged `isDemo: true` and names end with "(تجريبي)",
/// and [remove] deletes all of it plus everything derived from it.
class DemoSeeder {
  DemoSeeder(this._db, this._attendance, this._processor);
  final FirebaseFirestore _db;
  final AttendanceRepository _attendance;
  final AbsenceProcessor _processor;

  static const _streets = ['شارع مار جرجس (تجريبي)', 'شارع الكنيسة (تجريبي)', 'شارع النصر (تجريبي)'];
  static const _first = ['مريم', 'سعاد', 'منى', 'نادية', 'ماجدة', 'عايدة', 'فيفيان', 'إيفون', 'تريزا', 'هدى', 'سامية', 'نبيلة'];
  static const _last = ['أحمد', 'جرجس', 'فؤاد', 'حنا', 'بطرس', 'عزيز', 'شنودة', 'ميخائيل'];

  Future<String> seed(AppUser father) async {
    if (!father.isFather) throw const AppFailure('ليس لديك صلاحية لهذا الإجراء.');
    try {
      final existing =
          await _db.collection(FsPaths.women).where('isDemo', isEqualTo: true).limit(1).get();
      if (existing.docs.isNotEmpty) {
        throw const AppFailure('البيانات التجريبية موجودة بالفعل. احذفيها أولاً.');
      }
      final now = DateTime.now();
      final batch = _db.batch();
      for (final s in _streets) {
        batch.set(_db.collection(FsPaths.streets).doc(Street.idFor(s)),
            {'name': s, 'nameNormalized': ArabicText.normalize(s), 'womenCount': 6, 'isDemo': true},
            SetOptions(merge: true));
      }
      final women = <Woman>[];
      for (var i = 0; i < 18; i++) {
        final name = '${_first[i % _first.length]} ${_last[(i * 3) % _last.length]} (تجريبي)';
        final street = _streets[i % _streets.length];
        // The first demo woman has her birthday today.
        final dob = i == 0
            ? DateTime(1965, now.month, now.day)
            : DateTime(1950 + (i * 3) % 50, 1 + i % 12, 1 + (i * 7) % 28);
        final draft = WomanDraft(
          fullName: name,
          streetName: street,
          address: '${10 + i} $street',
          phone: '01000000${100 + i}',
          dateOfBirth: dob,
          assignedServantId: father.id,
          assignedServantName: father.name,
        );
        final ref = _db.collection(FsPaths.women).doc();
        final streetId = Street.idFor(street);
        batch.set(ref, {
          ...draft.toFields(streetId),
          'consecutiveAbsences': 0,
          'totalPresent': 0,
          'totalAbsent': 0,
          'phoneCalls': 0,
          'homeVisits': 0,
          'activeSuggestionType': 'none',
          'isDemo': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': father.id,
        });
        women.add(Woman(
          id: ref.id,
          fullName: name,
          streetId: streetId,
          streetName: street,
          address: draft.address,
          phone: draft.phone,
          dateOfBirth: dob,
          active: true,
          assignedServantId: father.id,
          assignedServantName: father.name,
          isDemo: true,
        ));
      }
      final confDays = [
        Dates.dateOnly(now).add(const Duration(days: 9)),
        Dates.dateOnly(now).add(const Duration(days: 10)),
        Dates.dateOnly(now).add(const Duration(days: 12)),
      ];
      batch.set(_db.collection(FsPaths.conferences).doc(), {
        'name': 'مؤتمر السيدات (تجريبي)',
        'startDate': Timestamp.fromDate(confDays.first),
        'dayIds': confDays.map(Dates.dayId).toList(),
        'days': [
          for (var i = 0; i < 3; i++)
            {'id': 'day${i + 1}', 'index': i, 'date': Timestamp.fromDate(confDays[i])}
        ],
        'createdBy': father.id,
        'isDemo': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      // Six past Wednesdays. Patterns: regular, last 2 absent (→ phone),
      // last 4 absent (→ home visit), alternating.
      final meeting = Dates.currentOrLastMeeting(now);
      final meetings = [
        for (var i = 0; i < 6; i++) meeting.subtract(Duration(days: 7 * i))
      ].reversed.toList();
      bool absent(int pattern, int idx) => switch (pattern) {
            1 => idx >= 4,
            2 => idx >= 2,
            3 => idx.isOdd,
            _ => false,
          };
      for (final (idx, m) in meetings.indexed) {
        final id = Dates.dayId(m);
        final present = [for (final (i, w) in women.indexed) if (!absent(i % 6, idx)) w];
        final away = [for (final (i, w) in women.indexed) if (absent(i % 6, idx)) w];
        await _attendance.markMany(id, present, AttendanceStatus.present, father);
        await _attendance.markMany(id, away, AttendanceStatus.absent, father);
      }
      for (final w in women) {
        await _processor.process(w, father);
      }
      return 'تمت إضافة ${women.length} سيدة و ${meetings.length} اجتماعات ومؤتمر تجريبي.';
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }

  Future<String> remove() async {
    try {
      var removed = 0;
      Future<void> deleteDocs(List<DocumentReference> refs) async {
        for (var i = 0; i < refs.length; i += 400) {
          final b = _db.batch();
          for (final r in refs.skip(i).take(400)) {
            b.delete(r);
          }
          await b.commit();
        }
        removed += refs.length;
      }

      final demoWomen =
          await _db.collection(FsPaths.women).where('isDemo', isEqualTo: true).get();
      final ids = demoWomen.docs.map((d) => d.id).toList();
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
        for (final (col, field) in [
          (FsPaths.suggestions, 'womanId'),
          (FsPaths.followUps, 'womanId'),
          (FsPaths.attendance, 'womanId'),
          (FsPaths.conferenceAttendance, 'womanId'),
          (FsPaths.notifications, 'relatedEntityId'),
        ]) {
          final snap = await _db.collection(col).where(field, whereIn: chunk).get();
          await deleteDocs(snap.docs.map((d) => d.reference).toList());
        }
      }
      for (final col in [FsPaths.women, FsPaths.conferences, FsPaths.streets]) {
        final snap = await _db.collection(col).where('isDemo', isEqualTo: true).get();
        await deleteDocs(snap.docs.map((d) => d.reference).toList());
      }
      // Meeting counters that only contained demo marks.
      final meetings = await _db.collection(FsPaths.meetings).get();
      for (final m in meetings.docs) {
        final left = await _db
            .collection(FsPaths.attendance)
            .where('meetingId', isEqualTo: m.id)
            .limit(1)
            .get();
        if (left.docs.isEmpty) await deleteDocs([m.reference]);
      }
      return 'تم حذف $removed سجل تجريبي.';
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final demoSeederProvider = Provider((ref) => DemoSeeder(
      ref.watch(firestoreProvider),
      ref.watch(attendanceRepositoryProvider),
      ref.watch(absenceProcessorProvider),
    ));
