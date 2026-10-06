import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';
import 'conference.dart';

class ConferenceStats {
  const ConferenceStats({
    required this.presentPerDay,
    required this.markedPerDay,
    required this.attendedAll,
    required this.missedOne,
    required this.missedMultiple,
    required this.uniqueAttendees,
  });

  /// dayId -> number present.
  final Map<String, int> presentPerDay;

  /// dayId -> number marked (present + absent).
  final Map<String, int> markedPerDay;
  final int attendedAll;
  final int missedOne;
  final int missedMultiple;
  final int uniqueAttendees;

  int get totalPresent => presentPerDay.values.fold(0, (a, b) => a + b);
  int get totalMarked => markedPerDay.values.fold(0, (a, b) => a + b);
  double get rate => totalMarked == 0 ? 0 : totalPresent / totalMarked;

  double dayRate(String dayId) {
    final m = markedPerDay[dayId] ?? 0;
    return m == 0 ? 0 : (presentPerDay[dayId] ?? 0) / m;
  }

  /// Computes conference statistics from its own attendance only (Rule F).
  /// A woman is counted in missed/attended buckets only if she was marked on
  /// at least one day. Unmarked days count as missed.
  static ConferenceStats compute(
    Conference conf,
    Iterable<ConferenceAttendance> records,
  ) {
    final present = {for (final d in conf.days) d.id: 0};
    final marked = {for (final d in conf.days) d.id: 0};
    final daysPresentByWoman = <String, int>{};
    final seen = <String>{};

    for (final r in records) {
      if (r.conferenceId != conf.id || !present.containsKey(r.conferenceDayId)) {
        continue;
      }
      marked[r.conferenceDayId] = marked[r.conferenceDayId]! + 1;
      seen.add(r.womanId);
      if (r.status == AttendanceStatus.present) {
        present[r.conferenceDayId] = present[r.conferenceDayId]! + 1;
        daysPresentByWoman.update(r.womanId, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    const n = BusinessRules.conferenceDayCount;
    var all = 0, one = 0, multiple = 0;
    for (final w in seen) {
      final missed = n - (daysPresentByWoman[w] ?? 0);
      if (missed == 0) {
        all++;
      } else if (missed == 1) {
        one++;
      } else {
        multiple++;
      }
    }
    return ConferenceStats(
      presentPerDay: present,
      markedPerDay: marked,
      attendedAll: all,
      missedOne: one,
      missedMultiple: multiple,
      uniqueAttendees: daysPresentByWoman.length,
    );
  }
}
