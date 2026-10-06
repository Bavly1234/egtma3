import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';

/// One woman's attendance at one Wednesday meeting.
///
/// The document id is deterministic (`{meetingId}_{womanId}`), so marking the
/// same woman twice — even offline on two devices — overwrites rather than
/// duplicating.
class AttendanceRecord {
  const AttendanceRecord({
    required this.meetingId,
    required this.womanId,
    required this.status,
    this.servantId,
    this.streetId,
    this.markedBy,
    this.markedAt,
  });

  final String meetingId; // yyyy-MM-dd
  final String womanId;
  final AttendanceStatus status;
  final String? servantId;
  final String? streetId;
  final String? markedBy;
  final DateTime? markedAt;

  String get id => docId(meetingId, womanId);

  static String docId(String meetingId, String womanId) =>
      '${meetingId}_$womanId';

  static AttendanceRecord? fromMap(Map<String, dynamic> m) {
    final status = AttendanceStatus.fromWire(m['status'] as String?);
    if (status == null) return null;
    return AttendanceRecord(
      meetingId: m['meetingId'] as String,
      womanId: m['womanId'] as String,
      status: status,
      servantId: m['servantId'] as String?,
      streetId: m['streetId'] as String?,
      markedBy: m['markedBy'] as String?,
      markedAt: tsToDate(m['markedAt']),
    );
  }
}

/// Aggregated counters for a meeting (maintained by Cloud Functions).
class MeetingSummary {
  const MeetingSummary({
    required this.meetingId,
    required this.present,
    required this.absent,
    this.byStreet = const {},
    this.byServant = const {},
  });

  final String meetingId;
  final int present;
  final int absent;
  final Map<String, ({int present, int absent})> byStreet;
  final Map<String, ({int present, int absent})> byServant;

  int get total => present + absent;
  double get rate => total == 0 ? 0 : present / total;

  static Map<String, ({int present, int absent})> _counts(Object? raw) {
    final out = <String, ({int present, int absent})>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          out['$k'] = (
            present: (v['present'] as num?)?.toInt() ?? 0,
            absent: (v['absent'] as num?)?.toInt() ?? 0,
          );
        }
      });
    }
    return out;
  }

  factory MeetingSummary.fromMap(String id, Map<String, dynamic> m) =>
      MeetingSummary(
        meetingId: id,
        present: (m['present'] as num?)?.toInt() ?? 0,
        absent: (m['absent'] as num?)?.toInt() ?? 0,
        byStreet: _counts(m['byStreet']),
        byServant: _counts(m['byServant']),
      );
}
