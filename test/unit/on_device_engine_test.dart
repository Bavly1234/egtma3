import 'package:egtma3/core/constants/enums.dart';
import 'package:egtma3/core/constants/firestore_paths.dart';
import 'package:egtma3/features/attendance/data/attendance_repository.dart';
import 'package:egtma3/features/audit/data/audit_repository.dart';
import 'package:egtma3/features/auth/domain/app_user.dart';
import 'package:egtma3/features/conferences/domain/conference.dart';
import 'package:egtma3/features/followups/data/absence_processor.dart';
import 'package:egtma3/features/notifications/data/notification_writer.dart';
import 'package:egtma3/features/notifications/domain/reminder_plan.dart';
import 'package:egtma3/features/settings/data/settings_repository.dart';
import 'package:egtma3/features/verse/data/fallback_verses.dart';
import 'package:egtma3/features/women/domain/woman.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const father = AppUser(id: 'f', name: 'أبونا', email: '', phone: '', role: UserRole.father, active: true);
const servant = AppUser(id: 's1', name: 'خادمة', email: '', phone: '', role: UserRole.servant, active: true);

Woman woman(String id, {DateTime? dob}) => Woman(
      id: id,
      fullName: 'مريم أحمد',
      streetId: 's',
      streetName: 'شارع',
      address: '',
      phone: '01012345678',
      dateOfBirth: dob,
      active: true,
    );

void main() {
  group('on-device absence processing (replaces the server trigger)', () {
    late FakeFirebaseFirestore db;
    late AttendanceRepository attendance;
    late AbsenceProcessor processor;
    final w = woman('w1');
    const weeks = ['2026-09-02', '2026-09-09', '2026-09-16', '2026-09-23', '2026-09-30', '2026-10-07'];

    setUp(() async {
      db = FakeFirebaseFirestore();
      attendance = AttendanceRepository(db, AuditRepository(db));
      processor = AbsenceProcessor(db, NotificationWriter(db));
      await db.collection(FsPaths.women).doc(w.id).set({'fullName': w.fullName});
      await db.collection(FsPaths.settings).doc(FsPaths.settingsAppDoc).set({'fatherIds': ['f']});
      // Servant accounts so suggestion notifications reach every servant.
      await db.collection(FsPaths.users).doc('s1').set({'active': true, 'role': 'servant'});
      // Street 's' is served by s1 (assignment is by street only).
      await db.collection(FsPaths.streets).doc('s').set({'name': 'شارع', 'servantId': 's1', 'servantName': 'خادمة'});
    });

    Future<void> mark(int week, AttendanceStatus s) async {
      await attendance.mark(weeks[week], w, s, servant);
      await processor.process(w, servant);
      await Future<void>.delayed(Duration.zero); // let un-awaited commits land
    }

    Future<List<Map<String, dynamic>>> suggestions() async =>
        (await db.collection(FsPaths.suggestions).get()).docs.map((d) => d.data()).toList();

    test('spec scenario: P, A, A → phone; A, A → home visit; P resets', () async {
      await mark(0, AttendanceStatus.present);
      await mark(1, AttendanceStatus.absent);
      expect(await suggestions(), isEmpty);

      await mark(2, AttendanceStatus.absent);
      var s = await suggestions();
      expect(s.single['type'], 'phone');
      expect(s.single['status'], 'pending');
      var womanDoc = (await db.collection(FsPaths.women).doc(w.id).get()).data()!;
      expect(womanDoc['consecutiveAbsences'], 2);
      expect(womanDoc['activeSuggestionType'], 'phone');

      await mark(3, AttendanceStatus.absent); // 3rd: no duplicate (Rule D)
      expect((await suggestions()).length, 1);

      await mark(4, AttendanceStatus.absent); // 4th: home visit (Rule B)
      s = await suggestions();
      expect(s.length, 2);
      expect(s.firstWhere((x) => x['type'] == 'phone')['status'], 'cancelled');
      expect(s.firstWhere((x) => x['type'] == 'home_visit')['status'], 'pending');

      await mark(5, AttendanceStatus.present); // Rule C
      womanDoc = (await db.collection(FsPaths.women).doc(w.id).get()).data()!;
      expect(womanDoc['consecutiveAbsences'], 0);
      expect(womanDoc['totalPresent'], 2);
      expect(womanDoc['totalAbsent'], 4);
      expect(womanDoc['activeSuggestionType'], 'none');
    });

    test('processing twice (two phones) never duplicates suggestions or notifications', () async {
      await mark(0, AttendanceStatus.absent);
      await mark(1, AttendanceStatus.absent);
      await processor.process(w, servant);
      await processor.process(w, father);
      await Future<void>.delayed(Duration.zero);
      expect((await suggestions()).length, 1);
      final notes = await db.collection(FsPaths.notifications).get();
      // Every servant is notified of every افتقاد (no global assignment).
      expect(notes.docs.where((d) => d.get('recipientId') == 's1').length, 1);
    });

    test('home visit also notifies the father', () async {
      for (var i = 0; i < 4; i++) {
        await mark(i, AttendanceStatus.absent);
      }
      final recipients = (await db.collection(FsPaths.notifications).get())
          .docs
          .map((d) => d.get('recipientId'))
          .toSet();
      expect(recipients, {'s1', 'f'});
    });
  });

  group('local reminder planning', () {
    final now = DateTime(2026, 10, 6, 12); // Tuesday noon
    List<PlannedReminder> plan({
      AppUser user = servant,
      List<Woman> women = const [],
      List<Conference> conferences = const [],
      int pending = 0,
    }) =>
        ReminderPlanner.plan(
          now: now,
          user: user,
          settings: const AppSettings(),
          women: women,
          conferences: conferences,
          pendingFollowUps: pending,
          verseFor: fallbackVerseFor,
        );

    test('weekly meeting and attendance reminders at configured hours', () {
      final p = plan();
      final meeting = p.firstWhere((r) => r.id == ReminderIds.meeting);
      expect(meeting.at, DateTime(2026, 10, 6, 18)); // today 6pm (Tuesday)
      expect(meeting.repeat, ReminderRepeat.weekly);
      final att = p.firstWhere((r) => r.id == ReminderIds.attendance);
      expect(att.at, DateTime(2026, 10, 7, 20)); // Wednesday 8pm, before the 9pm auto-absence
    });

    test('birthday scheduled on the day, within horizon only', () {
      final p = plan(women: [
        woman('a', dob: DateTime(1970, 10, 9)),
        woman('b', dob: DateTime(1970, 3, 1)), // too far
      ]);
      final b = p.where((r) => r.id >= ReminderIds.birthdayBase && r.id < ReminderIds.conferenceBase).toList();
      expect(b.single.at, DateTime(2026, 10, 9, 8));
      expect(b.single.payload, 'woman:a');
    });

    test('conference: eve + day reminders for future days only', () {
      final c = Conference(id: 'c', name: 'مؤتمر', days: [
        ConferenceDay(id: 'day1', index: 0, date: DateTime(2026, 10, 6)), // today: eve passed, day passed (8am)
        ConferenceDay(id: 'day2', index: 1, date: DateTime(2026, 10, 9)),
        ConferenceDay(id: 'day3', index: 2, date: DateTime(2026, 10, 16)),
      ]);
      final p = plan(conferences: [c]).where((r) => r.id >= ReminderIds.conferenceBase).toList();
      expect(p.length, 4);
      expect(p.map((r) => r.payload).toSet(), {'conference:c'});
    });

    test('follow-up reminder only when something is pending; verse for 14 days', () {
      expect(plan().any((r) => r.id == ReminderIds.followUp), isFalse);
      expect(plan(pending: 3).firstWhere((r) => r.id == ReminderIds.followUp).body, contains('3'));
      final verses = plan().where((r) => r.id >= ReminderIds.verseBase && r.id < 200);
      expect(verses.length, 14);
      expect(verses.map((r) => r.id).toSet().length, 14);
    });

    test('preferences switch reminders off', () {
      const quiet = AppUser(
          id: 'q', name: '', email: '', phone: '', role: UserRole.servant, active: true,
          prefs: NotificationPrefs(
              meetingReminder: false, attendanceReminder: false, followUp: false,
              birthday: false, conference: false, dailyVerse: false));
      expect(plan(user: quiet, pending: 5, women: [woman('a', dob: DateTime(1970, 10, 9))]), isEmpty);
    });

    test('ids never collide', () {
      final p = plan(pending: 1, women: [
        for (var i = 0; i < 50; i++) woman('w$i', dob: DateTime(1970, 10, 7 + i % 20)),
      ]);
      expect(p.map((r) => r.id).toSet().length, p.length);
    });
  });
}
