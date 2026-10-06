import 'package:flutter/material.dart';

/// Every enum has a stable [wire] value stored in Firestore and an Arabic [label].
enum UserRole {
  father('father', 'الأب الكاهن'),
  servant('servant', 'خادمة');

  const UserRole(this.wire, this.label);
  final String wire;
  final String label;

  static UserRole fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => UserRole.servant);
}

enum AttendanceStatus {
  present('present', 'حاضر'),
  absent('absent', 'غائب');

  const AttendanceStatus(this.wire, this.label);
  final String wire;
  final String label;

  static AttendanceStatus? fromWire(String? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

enum SuggestionType {
  phone('phone', 'افتقاد تليفوني', Icons.phone_in_talk),
  homeVisit('home_visit', 'افتقاد منزلي', Icons.home);

  const SuggestionType(this.wire, this.label, this.icon);
  final String wire;
  final String label;
  final IconData icon;

  static SuggestionType? fromWire(String? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

enum SuggestionStatus {
  pending('pending', 'في الانتظار'),
  assigned('assigned', 'مُسند'),
  inProgress('in_progress', 'جارٍ التنفيذ'),
  completed('completed', 'تم'),
  dismissed('dismissed', 'تم التجاهل'),
  cancelled('cancelled', 'ملغي');

  const SuggestionStatus(this.wire, this.label);
  final String wire;
  final String label;

  bool get isActive => this == pending || this == assigned || this == inProgress;

  static const activeWires = ['pending', 'assigned', 'in_progress'];

  static SuggestionStatus fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => SuggestionStatus.pending);
}

enum FollowUpType {
  phoneCall('phone_call', 'مكالمة', Icons.phone),
  homeVisit('home_visit', 'زيارة منزلية', Icons.home),
  note('note', 'ملاحظة', Icons.note_alt);

  const FollowUpType(this.wire, this.label, this.icon);
  final String wire;
  final String label;
  final IconData icon;

  static FollowUpType fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => FollowUpType.note);
}

enum FollowUpResult {
  reached('reached', 'تم التواصل'),
  noAnswer('no_answer', 'لم ترد'),
  wrongNumber('wrong_number', 'رقم خاطئ'),
  visited('visited', 'تمت الزيارة'),
  notHome('not_home', 'غير موجودة بالمنزل'),
  other('other', 'أخرى');

  const FollowUpResult(this.wire, this.label);
  final String wire;
  final String label;

  static FollowUpResult fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => FollowUpResult.other);

  static List<FollowUpResult> forType(FollowUpType t) => switch (t) {
        FollowUpType.phoneCall => [reached, noAnswer, wrongNumber, other],
        FollowUpType.homeVisit => [visited, notHome, other],
        FollowUpType.note => [other],
      };
}

enum NotificationType {
  attendance('attendance', 'الحضور', Icons.how_to_reg),
  followUp('follow_up', 'الافتقاد', Icons.volunteer_activism),
  birthday('birthday', 'أعياد الميلاد', Icons.cake),
  conference('conference', 'المؤتمرات', Icons.event),
  system('system', 'النظام', Icons.info),
  reminder('reminder', 'تذكير', Icons.alarm),
  verse('verse', 'آية اليوم', Icons.menu_book);

  const NotificationType(this.wire, this.label, this.icon);
  final String wire;
  final String label;
  final IconData icon;

  static NotificationType fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => NotificationType.system);
}
