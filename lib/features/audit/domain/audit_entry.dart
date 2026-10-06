import '../../../core/errors/app_failure.dart';

enum AuditAction {
  womanCreated('woman_created', 'إضافة سيدة'),
  womanUpdated('woman_updated', 'تعديل بيانات سيدة'),
  womanDisabled('woman_disabled', 'إيقاف سيدة'),
  womanDeleted('woman_deleted', 'حذف سيدة'),
  attendanceChanged('attendance_changed', 'تعديل الحضور'),
  servantAssigned('servant_assigned', 'تعيين خادمة'),
  followUpCompleted('follow_up_completed', 'إتمام افتقاد'),
  followUpRecorded('follow_up_recorded', 'تسجيل افتقاد'),
  excelImported('excel_imported', 'استيراد Excel'),
  conferenceCreated('conference_created', 'إنشاء مؤتمر'),
  conferenceDeleted('conference_deleted', 'حذف مؤتمر'),
  userChanged('user_changed', 'تعديل مستخدم'),
  streetChanged('street_changed', 'تعديل شارع'),
  settingsChanged('settings_changed', 'تعديل الإعدادات');

  const AuditAction(this.wire, this.label);
  final String wire;
  final String label;

  static AuditAction? fromWire(String? v) {
    for (final a in values) {
      if (a.wire == v) return a;
    }
    return null;
  }
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.actionLabel,
    required this.actorId,
    required this.actorName,
    required this.entityType,
    required this.entityId,
    required this.summary,
    required this.createdAt,
  });

  final String id;
  final AuditAction? action;
  final String actionLabel;
  final String actorId;
  final String actorName;
  final String entityType;
  final String entityId;
  final String summary;
  final DateTime createdAt;

  factory AuditEntry.fromMap(String id, Map<String, dynamic> m) {
    final action = AuditAction.fromWire(m['action'] as String?);
    return AuditEntry(
      id: id,
      action: action,
      actionLabel: action?.label ?? (m['action'] as String? ?? ''),
      actorId: (m['actorId'] as String?) ?? '',
      actorName: (m['actorName'] as String?) ?? '',
      entityType: (m['entityType'] as String?) ?? '',
      entityId: (m['entityId'] as String?) ?? '',
      summary: (m['summary'] as String?) ?? '',
      createdAt: tsToDate(m['createdAt']) ?? DateTime.now(),
    );
  }
}
