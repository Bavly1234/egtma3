import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';

/// A special event with exactly three (possibly non-consecutive) days.
/// Its attendance is stored in `conference_attendance`, never in `attendance`.
class Conference {
  const Conference({
    required this.id,
    required this.name,
    required this.days,
    this.createdAt,
  });

  final String id;
  final String name;
  final List<ConferenceDay> days;
  final DateTime? createdAt;

  DateTime? get firstDate => days.isEmpty ? null : days.first.date;
  DateTime? get lastDate => days.isEmpty ? null : days.last.date;

  factory Conference.fromMap(String id, Map<String, dynamic> m) {
    final raw = (m['days'] as List?) ?? const [];
    final days = <ConferenceDay>[];
    for (final d in raw) {
      if (d is Map) {
        final date = tsToDate(d['date']);
        if (date != null) {
          days.add(ConferenceDay(
            id: d['id'] as String,
            index: (d['index'] as num).toInt(),
            date: date,
          ));
        }
      }
    }
    days.sort((a, b) => a.index.compareTo(b.index));
    return Conference(
      id: id,
      name: (m['name'] as String?) ?? '',
      days: days,
      createdAt: tsToDate(m['createdAt']),
    );
  }
}

class ConferenceDay {
  const ConferenceDay({required this.id, required this.index, required this.date});
  final String id; // day1, day2, day3
  final int index; // 0..2
  final DateTime date;

  static const labels = ['اليوم الأول', 'اليوم الثاني', 'اليوم الثالث'];
  String get label => labels[index];
}

class ConferenceAttendance {
  const ConferenceAttendance({
    required this.conferenceId,
    required this.conferenceDayId,
    required this.womanId,
    required this.status,
    this.timestamp,
  });

  final String conferenceId;
  final String conferenceDayId;
  final String womanId;
  final AttendanceStatus status;
  final DateTime? timestamp;

  static String docId(String conferenceId, String dayId, String womanId) =>
      '${conferenceId}_${dayId}_$womanId';

  static ConferenceAttendance? fromMap(Map<String, dynamic> m) {
    final s = AttendanceStatus.fromWire(m['attendanceStatus'] as String?);
    if (s == null) return null;
    return ConferenceAttendance(
      conferenceId: m['conferenceId'] as String,
      conferenceDayId: m['conferenceDayId'] as String,
      womanId: m['womanId'] as String,
      status: s,
      timestamp: tsToDate(m['timestamp']),
    );
  }
}
