import 'package:egtma3/core/constants/enums.dart';
import 'package:egtma3/features/attendance/domain/absence_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const p = AttendanceStatus.present;
const a = AttendanceStatus.absent;
const w = ['2026-09-02', '2026-09-09', '2026-09-16', '2026-09-23', '2026-09-30'];

List<AttendanceMark> marks(List<AttendanceStatus> s) =>
    [for (var i = 0; i < s.length; i++) AttendanceMark(w[i], s[i])];

ExistingSuggestion sug(String id, SuggestionType t, SuggestionStatus s, String? start) =>
    ExistingSuggestion(id: id, type: t, status: s, streakStartMeetingId: start);

void main() {
  group('consecutive absence calculation', () {
    test('Present, Absent, Absent => streak 2 starting week 2', () {
      final s = AbsenceRules.computeStreak(marks([p, a, a]));
      expect(s.count, 2);
      expect(s.startMeetingId, w[1]);
    });

    test('Rule C: attendance resets the counter', () {
      final s = AbsenceRules.computeStreak(marks([a, a, a, p, a]));
      expect(s.count, 1);
    });

    test('no records => no streak', () {
      expect(AbsenceRules.computeStreak(const []).count, 0);
    });

    test('order independent', () {
      final s = AbsenceRules.computeStreak(marks([p, a, a]).reversed);
      expect(s.count, 2);
    });
  });

  group('suggestion generation', () {
    test('Rule A: 2 absences => phone', () {
      final d = AbsenceRules.decide(const AbsenceStreak(2, '2026-09-09'), const []);
      expect(d.create, SuggestionType.phone);
    });

    test('1 absence => nothing', () {
      expect(AbsenceRules.decide(const AbsenceStreak(1, 'x'), const []).isNoop, isTrue);
    });

    test('Rule B: 4+ absences => home visit and cancels active phone', () {
      final d = AbsenceRules.decide(const AbsenceStreak(4, 's'), [
        sug('ph', SuggestionType.phone, SuggestionStatus.pending, 's'),
      ]);
      expect(d.create, SuggestionType.homeVisit);
      expect(d.cancelIds, ['ph']);
    });

    test('Rule D: no duplicate active suggestion in following weeks', () {
      final d = AbsenceRules.decide(const AbsenceStreak(3, 's'), [
        sug('ph', SuggestionType.phone, SuggestionStatus.assigned, 's'),
      ]);
      expect(d.create, isNull);
    });

    test('Rule D: 5th absence does not create a second home visit', () {
      final d = AbsenceRules.decide(const AbsenceStreak(5, 's'), [
        sug('h', SuggestionType.homeVisit, SuggestionStatus.pending, 's'),
      ]);
      expect(d.create, isNull);
    });

    test('Rule E: completed stays in history and is not re-created', () {
      final d = AbsenceRules.decide(const AbsenceStreak(3, 's'), [
        sug('ph', SuggestionType.phone, SuggestionStatus.completed, 's'),
      ]);
      expect(d.create, isNull);
      expect(d.cancelIds, isEmpty);
    });

    test('new streak after attending => new suggestion', () {
      final d = AbsenceRules.decide(const AbsenceStreak(2, 'new'), [
        sug('ph', SuggestionType.phone, SuggestionStatus.completed, 'old'),
      ]);
      expect(d.create, SuggestionType.phone);
    });

    test('attending cancels pending but keeps in-progress and completed', () {
      final d = AbsenceRules.decide(AbsenceStreak.none, [
        sug('1', SuggestionType.phone, SuggestionStatus.pending, 's'),
        sug('2', SuggestionType.homeVisit, SuggestionStatus.inProgress, 's'),
        sug('3', SuggestionType.phone, SuggestionStatus.completed, 's'),
      ]);
      expect(d.cancelIds, ['1']);
    });

    test('full scenario from the specification', () {
      // Week1 P, W2 A, W3 A => phone; W4 A, W5 A => home visit.
      final s3 = AbsenceRules.computeStreak(marks([p, a, a]));
      final d3 = AbsenceRules.decide(s3, const []);
      expect(d3.create, SuggestionType.phone);
      final existing = [sug('ph', SuggestionType.phone, SuggestionStatus.pending, s3.startMeetingId)];
      final s5 = AbsenceRules.computeStreak(marks([p, a, a, a, a]));
      final d5 = AbsenceRules.decide(s5, existing);
      expect(s5.count, 4);
      expect(d5.create, SuggestionType.homeVisit);
      expect(d5.cancelIds, ['ph']);
    });
  });
}
