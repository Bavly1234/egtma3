import 'package:egtma3/core/constants/enums.dart';
import 'package:egtma3/core/constants/firestore_paths.dart';
import 'package:egtma3/features/attendance/data/attendance_repository.dart';
import 'package:egtma3/features/audit/data/audit_repository.dart';
import 'package:egtma3/features/auth/domain/app_user.dart';
import 'package:egtma3/features/conferences/data/conference_repository.dart';
import 'package:egtma3/features/followups/data/absence_processor.dart';
import 'package:egtma3/features/followups/data/follow_up_repository.dart';
import 'package:egtma3/features/notifications/data/notification_writer.dart';
import 'package:egtma3/features/followups/domain/follow_up.dart';
import 'package:egtma3/features/notifications/data/notification_repository.dart';
import 'package:egtma3/features/streets/data/street_repository.dart';
import 'package:egtma3/features/women/data/women_repository.dart';
import 'package:egtma3/features/women/domain/woman.dart';
import 'package:egtma3/features/women/domain/women_filter.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const father = AppUser(id: 'f', name: 'أبونا', email: '', phone: '', role: UserRole.father, active: true);
const servant = AppUser(id: 's1', name: 'خادمة 1', email: '', phone: '', role: UserRole.servant, active: true);

void main() {
  late FakeFirebaseFirestore db;
  late WomenRepository women;
  late AuditRepository audit;

  setUp(() {
    db = FakeFirebaseFirestore();
    audit = AuditRepository(db);
    women = WomenRepository(db, StreetRepository(db), audit);
  });

  Future<Woman> addWoman(String name, {String street = 'شارع مار جرجس', String? servantId}) async {
    final id = await women.create(
      WomanDraft(
        fullName: name,
        streetName: street,
        address: '10 $street',
        phone: '01012345678',
        dateOfBirth: DateTime(1970, 3, 15),
        assignedServantId: servantId,
        assignedServantName: servantId == null ? null : 'خادمة',
      ),
      father,
    );
    return Woman.fromMap(id, (await db.collection(FsPaths.women).doc(id).get()).data()!);
  }

  test('women CRUD with street upsert and audit', () async {
    final w = await addWoman('مريم أحمد');
    expect(w.streetId, isNotEmpty);
    expect((await db.collection(FsPaths.streets).get()).size, 1);
    await women.setActive(w.id, false, father);
    expect((await db.collection(FsPaths.women).doc(w.id).get()).get('active'), isFalse);
    await women.delete(w.id, w.fullName, father);
    expect((await db.collection(FsPaths.women).doc(w.id).get()).exists, isFalse);
    expect((await db.collection(FsPaths.auditLogs).get()).size, 3);
  });

  test('servant query is scoped to assigned women; filters apply', () async {
    await addWoman('مريم أحمد', servantId: 's1');
    await addWoman('سعاد جرجس', servantId: 's2', street: 'شارع النصر');
    final mine = await women.page(servant, WomenFilter.empty);
    expect(mine.items.map((w) => w.fullName), ['مريم أحمد']);
    final byStreet = await women.page(father, WomenFilter(streetId: mine.items.first.streetId));
    expect(byStreet.items.length, 1);
    final search = await women.page(father, const WomenFilter(query: 'سعاد'));
    expect(search.items.single.fullName, 'سعاد جرجس');
  });

  test('assign multiple women', () async {
    final a = await addWoman('أ ب ج');
    final b = await addWoman('د هـ و');
    await women.assign([a.id, b.id], servant, father);
    final mine = await women.page(servant, WomenFilter.empty);
    expect(mine.items.length, 2);
  });

  test('attendance: marking twice never duplicates (deterministic id)', () async {
    final w = await addWoman('مريم أحمد', servantId: 's1');
    final repo = AttendanceRepository(db, audit);
    await repo.mark('2026-09-30', w, AttendanceStatus.absent, servant);
    await repo.mark('2026-09-30', w, AttendanceStatus.present, servant,
        previous: AttendanceStatus.absent);
    final docs = await db.collection(FsPaths.attendance).get();
    expect(docs.size, 1);
    expect(docs.docs.single.get('status'), 'present');
    final statuses = await repo.watchMeeting('2026-09-30', servant).first;
    expect(statuses[w.id], AttendanceStatus.present);
    final history = await repo.history(w.id, servant);
    expect(history.single.meetingId, '2026-09-30');
    // Meeting counters reflect only the final status.
    final m = (await db.collection(FsPaths.meetings).doc('2026-09-30').get()).data()!;
    expect(m['present'], 1);
    expect(m['absent'], 0);
  });

  test('Rule F: conference attendance does not touch Wednesday attendance', () async {
    final w = await addWoman('مريم أحمد', servantId: 's1');
    final conf = ConferenceRepository(db, audit);
    final id = await conf.create('مؤتمر السيدات 2026',
        [DateTime(2026, 11, 6), DateTime(2026, 11, 7), DateTime(2026, 11, 13)], father);
    await conf.mark(id, 'day1', w, AttendanceStatus.present, father);
    await conf.mark(id, 'day3', w, AttendanceStatus.absent, father);
    expect((await db.collection(FsPaths.attendance).get()).size, 0);
    expect((await db.collection(FsPaths.conferenceAttendance).get()).size, 2);
    final all = await conf.allAttendance(id, father);
    expect(all.map((a) => a.conferenceDayId).toSet(), {'day1', 'day3'});
  });

  test('conference requires exactly 3 distinct days', () async {
    final conf = ConferenceRepository(db, audit);
    expect(() => conf.create('x', [DateTime(2026)], father), throwsA(anything));
    expect(() => conf.create('x', [DateTime(2026), DateTime(2026), DateTime(2027)], father),
        throwsA(anything));
  });

  test('recording a follow-up keeps history and completes the suggestion atomically', () async {
    final w = await addWoman('مريم أحمد', servantId: 's1');
    await db.collection(FsPaths.suggestions).doc('sg1').set({
      'womanId': w.id,
      'womanName': w.fullName,
      'type': 'phone',
      'status': 'pending',
      'assignedServantId': 's1',
      'createdAt': DateTime(2026, 9, 30),
    });
    final s = FollowUpSuggestion.fromMap(
        'sg1', (await db.collection(FsPaths.suggestions).doc('sg1').get()).data()!);
    final repo = FollowUpRepository(db, audit, AbsenceProcessor(db, NotificationWriter(db)));
    await repo.record(
      woman: w,
      type: FollowUpType.phoneCall,
      result: FollowUpResult.reached,
      notes: 'بخير',
      actor: servant,
      completes: s,
    );
    final fu = await db.collection(FsPaths.followUps).get();
    expect(fu.size, 1);
    expect(fu.docs.single.get('suggestionId'), 'sg1');
    expect((await db.collection(FsPaths.suggestions).doc('sg1').get()).get('status'), 'completed');
    final history = await repo.watchHistory(w.id, servant).first;
    expect(history.single.type, FollowUpType.phoneCall);
    final updated = (await db.collection(FsPaths.women).doc(w.id).get()).data()!;
    expect(updated['phoneCalls'], 1);
    expect(updated['lastCallAt'], isNotNull);
  });

  test('notification center: mark all read', () async {
    final n = db.collection(FsPaths.notifications);
    await n.add({'recipientId': 's1', 'title': 't', 'message': 'm', 'type': 'birthday', 'createdAt': DateTime.now(), 'readAt': null});
    await n.add({'recipientId': 's1', 'title': 't', 'message': 'm', 'type': 'follow_up', 'createdAt': DateTime.now(), 'readAt': null});
    await n.add({'recipientId': 'other', 'title': 't', 'message': 'm', 'type': 'system', 'createdAt': DateTime.now(), 'readAt': null});
    final repo = NotificationRepository(db);
    expect(await repo.watchUnreadCount('s1').first, 2);
    final list = await repo.watch('s1').first;
    expect(list.map((e) => e.type).toSet(), {NotificationType.birthday, NotificationType.followUp});
    await repo.markAllRead('s1');
    expect(await repo.watchUnreadCount('s1').first, 0);
    expect(await repo.watchUnreadCount('other').first, 1);
  });
}
