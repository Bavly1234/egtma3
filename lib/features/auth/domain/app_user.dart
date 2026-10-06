import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';

class NotificationPrefs {
  const NotificationPrefs({
    this.meetingReminder = true,
    this.attendanceReminder = true,
    this.followUp = true,
    this.birthday = true,
    this.conference = true,
    this.dailyVerse = true,
  });

  final bool meetingReminder;
  final bool attendanceReminder;
  final bool followUp;
  final bool birthday;
  final bool conference;
  final bool dailyVerse;

  factory NotificationPrefs.fromMap(Map<String, dynamic>? m) {
    bool b(String k) => (m?[k] as bool?) ?? true;
    return NotificationPrefs(
      meetingReminder: b('meetingReminder'),
      attendanceReminder: b('attendanceReminder'),
      followUp: b('followUp'),
      birthday: b('birthday'),
      conference: b('conference'),
      dailyVerse: b('dailyVerse'),
    );
  }

  Map<String, dynamic> toMap() => {
        'meetingReminder': meetingReminder,
        'attendanceReminder': attendanceReminder,
        'followUp': followUp,
        'birthday': birthday,
        'conference': conference,
        'dailyVerse': dailyVerse,
      };

  NotificationPrefs copyWith(String key, bool value) {
    final m = toMap()..[key] = value;
    return NotificationPrefs.fromMap(m);
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.active,
    this.prefs = const NotificationPrefs(),
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final bool active;
  final NotificationPrefs prefs;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isFather => role == UserRole.father;
  bool get isServant => role == UserRole.servant;

  factory AppUser.fromMap(String id, Map<String, dynamic> m) => AppUser(
        id: id,
        name: (m['name'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        role: UserRole.fromWire(m['role'] as String?),
        active: (m['active'] as bool?) ?? false,
        prefs: NotificationPrefs.fromMap(
            (m['notificationPrefs'] as Map?)?.cast<String, dynamic>()),
        createdAt: tsToDate(m['createdAt']),
        updatedAt: tsToDate(m['updatedAt']),
      );
}
