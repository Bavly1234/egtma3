import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';

/// A historical follow-up action (call, home visit or note). Never aggregated
/// away: statistics are computed from these records.
class FollowUp {
  const FollowUp({
    required this.id,
    required this.womanId,
    required this.womanName,
    required this.servantId,
    required this.servantName,
    required this.type,
    required this.result,
    required this.notes,
    required this.occurredAt,
    this.suggestionId,
    this.streetId,
  });

  final String id;
  final String womanId;
  final String womanName;
  final String servantId;
  final String servantName;
  final FollowUpType type;
  final FollowUpResult result;
  final String notes;
  final DateTime occurredAt;
  final String? suggestionId;
  final String? streetId;

  factory FollowUp.fromMap(String id, Map<String, dynamic> m) => FollowUp(
        id: id,
        womanId: (m['womanId'] as String?) ?? '',
        womanName: (m['womanName'] as String?) ?? '',
        servantId: (m['servantId'] as String?) ?? '',
        servantName: (m['servantName'] as String?) ?? '',
        type: FollowUpType.fromWire(m['type'] as String?),
        result: FollowUpResult.fromWire(m['result'] as String?),
        notes: (m['notes'] as String?) ?? '',
        occurredAt: tsToDate(m['occurredAt']) ?? DateTime.now(),
        suggestionId: m['suggestionId'] as String?,
        streetId: m['streetId'] as String?,
      );
}

/// An automatically (or manually) generated follow-up task.
class FollowUpSuggestion {
  const FollowUpSuggestion({
    required this.id,
    required this.womanId,
    required this.womanName,
    required this.type,
    required this.status,
    required this.consecutiveAbsences,
    required this.reason,
    required this.createdAt,
    this.assignedServantId,
    this.assignedServantName,
    this.streetId,
    this.streetName,
    this.phone,
    this.address,
    this.streakStartMeetingId,
    this.completedAt,
    this.completedBy,
  });

  final String id;
  final String womanId;
  final String womanName;
  final SuggestionType type;
  final SuggestionStatus status;
  final int consecutiveAbsences;
  final String reason;
  final DateTime createdAt;
  final String? assignedServantId;
  final String? assignedServantName;
  final String? streetId;
  final String? streetName;
  final String? phone;
  final String? address;
  final String? streakStartMeetingId;
  final DateTime? completedAt;
  final String? completedBy;

  bool isOverdue(DateTime now) =>
      status.isActive &&
      now.difference(createdAt).inDays >= BusinessRules.overdueDays;

  factory FollowUpSuggestion.fromMap(String id, Map<String, dynamic> m) =>
      FollowUpSuggestion(
        id: id,
        womanId: (m['womanId'] as String?) ?? '',
        womanName: (m['womanName'] as String?) ?? '',
        type: SuggestionType.fromWire(m['type'] as String?) ??
            SuggestionType.phone,
        status: SuggestionStatus.fromWire(m['status'] as String?),
        consecutiveAbsences: (m['consecutiveAbsences'] as num?)?.toInt() ?? 0,
        reason: (m['reason'] as String?) ?? '',
        createdAt: tsToDate(m['createdAt']) ?? DateTime.now(),
        assignedServantId: m['assignedServantId'] as String?,
        assignedServantName: m['assignedServantName'] as String?,
        streetId: m['streetId'] as String?,
        streetName: m['streetName'] as String?,
        phone: m['phone'] as String?,
        address: m['address'] as String?,
        streakStartMeetingId: m['streakStartMeetingId'] as String?,
        completedAt: tsToDate(m['completedAt']),
        completedBy: m['completedBy'] as String?,
      );
}
