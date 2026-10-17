import 'package:egtma3/core/constants/enums.dart';
import 'package:egtma3/core/constants/firestore_paths.dart';
import 'package:egtma3/features/attendance/data/attendance_repository.dart';
import 'package:egtma3/features/attendance/data/servant_attendance_repository.dart';
import 'package:egtma3/features/audit/data/audit_repository.dart';
import 'package:egtma3/features/auth/domain/app_user.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const father = AppUser(id: 'f', name: 'أبونا', email: '', phone: '', role: UserRole.father, active: true);

void main() {
  const meeting = '2026-10-14';
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Future<void> woman(String id, {bool servant = false, bool active = true}) =>
        db.collection(FsPaths.women).doc(id).set({
          'fullName': 'سيدة $id', 'active': active, 'isServant': servant,
          'streetId': 's', 'createdAt': DateTime(2026, 1, 1),
        });
    await woman('sv1', servant: true); // not marked → auto absent
    await woman('sv2', servant: true); // marked present by أبونا
    await woman('sv3', servant: true, active: false); // inactive → ignored
    await woman('w1'); // normal woman
    await db.collection(FsPaths.servantAttendance).doc('${meeting}_sv2').set({
      'meetingId': meeting, 'servantId': 'sv2', 'servantName': 'سيدة sv2',
      'status': 'present', 'markedBy': 'f',
    });
  });

  test('9pm: unmarked servants become absent, real marks stay', () async {
    final n = await ServantAttendanceRepository(db).autoFillAbsent(meeting, father);
    await Future<void>.delayed(Duration.zero);
    expect(n, 1);
    final marks = {
      for (final d in (await db.collection(FsPaths.servantAttendance).get()).docs)
        d.get('servantId'): d.get('status')
    };
    expect(marks, {'sv1': 'absent', 'sv2': 'present'});
  });

  test('servants are never auto-marked in the women attendance', () async {
    final ids = await AttendanceRepository(db, AuditRepository(db)).autoFillAbsent(meeting, father);
    expect(ids, ['w1']);
  });

  test('servant women list and running twice is harmless', () async {
    final repo = ServantAttendanceRepository(db);
    await repo.autoFillAbsent(meeting, father);
    await Future<void>.delayed(Duration.zero);
    final second = await repo.autoFillAbsent(meeting, father);
    expect(second, 0);
    final all = await db.collection(FsPaths.servantAttendance).get();
    expect(all.size, 2);
    expect(all.docs.every((d) => AttendanceStatus.fromWire(d.get('status')) != null), isTrue);
  });
}
