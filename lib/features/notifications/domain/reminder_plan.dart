import '../../../core/utils/dates.dart';
import '../../auth/domain/app_user.dart';
import '../../birthdays/domain/birthday_rules.dart';
import '../../conferences/domain/conference.dart';
import '../../settings/data/settings_repository.dart';
import '../../verse/domain/daily_verse.dart';
import '../../women/domain/woman.dart';

enum ReminderRepeat { none, weekly }

/// A notification scheduled on this phone (works with the app closed).
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    this.repeat = ReminderRepeat.none,
    this.payload,
  });
  final int id;
  final String title;
  final String body;
  final DateTime at;
  final ReminderRepeat repeat;

  /// e.g. `woman:<id>`, `conference:<id>`, `route:/attendance`.
  final String? payload;

  @override
  String toString() => '$id $at $title';
}

/// Id ranges so every kind can be rescheduled independently.
abstract final class ReminderIds {
  static const meeting = 1; // weekly Tuesday
  static const attendance = 2; // weekly Wednesday
  static const followUp = 3; // next follow-up reminder
  static const verseBase = 100; // 100..113  next 14 days
  static const birthdayBase = 1000; // 1000..1499
  static const conferenceBase = 2000; // 2000..2199
  static const maxBirthdays = 500;
  static const maxConferenceItems = 200;
}

/// Pure planning of all local reminders (unit-tested). The service applies
/// the plan by cancelling everything and scheduling the result.
abstract final class ReminderPlanner {
  static const verseHour = 7;
  static const birthdayHour = 8;
  static const conferenceDayHour = 8;
  static const conferenceEveHour = 19;
  static const verseDays = 14;
  static const birthdayHorizonDays = 60;

  static DateTime _nextWeekday(DateTime now, int weekday, int hour) {
    var d = DateTime(now.year, now.month, now.day, hour);
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
      d = DateTime(d.year, d.month, d.day, hour);
    }
    return d;
  }

  static DateTime _nextAt(DateTime now, int hour) {
    final today = DateTime(now.year, now.month, now.day, hour);
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  static List<PlannedReminder> plan({
    required DateTime now,
    required AppUser user,
    required AppSettings settings,
    required List<Woman> women,
    required List<Conference> conferences,
    required int pendingFollowUps,
    required DailyVerse Function(DateTime day) verseFor,
  }) {
    final p = user.prefs;
    final out = <PlannedReminder>[];

    if (p.meetingReminder) {
      out.add(PlannedReminder(
        id: ReminderIds.meeting,
        title: 'غداً اجتماع السيدات',
        body: 'يرجى تسجيل الحضور.',
        at: _nextWeekday(now, DateTime.tuesday, settings.meetingReminderHour),
        repeat: ReminderRepeat.weekly,
        payload: 'route:/attendance',
      ));
    }
    if (p.attendanceReminder) {
      out.add(PlannedReminder(
        id: ReminderIds.attendance,
        title: 'تذكير بتسجيل الحضور',
        body: 'هل سجلتِ حضور اجتماع اليوم؟',
        at: _nextWeekday(now, DateTime.wednesday, settings.attendanceReminderHour),
        repeat: ReminderRepeat.weekly,
        payload: 'route:/attendance',
      ));
    }
    if (p.followUp && pendingFollowUps > 0) {
      out.add(PlannedReminder(
        id: ReminderIds.followUp,
        title: 'افتقاد في انتظارك',
        body: 'لديك $pendingFollowUps افتقاد لم يتم بعد.',
        at: _nextAt(now, settings.followUpReminderHour),
        payload: 'route:/followups',
      ));
    }
    if (p.dailyVerse && settings.verseNotifications) {
      for (var i = 0; i < verseDays; i++) {
        final at = _nextAt(now, verseHour).add(Duration(days: i));
        final v = verseFor(at);
        out.add(PlannedReminder(
          id: ReminderIds.verseBase + i,
          title: '📖 آية اليوم',
          body: '${v.text} (${v.reference})',
          at: at,
          payload: 'route:/verse',
        ));
      }
    }
    if (p.birthday) {
      var n = 0;
      final sorted = women.where((w) => w.active && w.dateOfBirth != null).toList()
        ..sort((a, b) => BirthdayRules.daysUntil(a.dateOfBirth!, now)
            .compareTo(BirthdayRules.daysUntil(b.dateOfBirth!, now)));
      for (final w in sorted) {
        if (n >= ReminderIds.maxBirthdays) break;
        final day = BirthdayRules.nextBirthday(w.dateOfBirth!, now);
        final at = DateTime(day.year, day.month, day.day, birthdayHour);
        if (!at.isAfter(now) ||
            at.difference(now).inDays > birthdayHorizonDays) {
          continue;
        }
        out.add(PlannedReminder(
          id: ReminderIds.birthdayBase + n++,
          title: '🎂 اليوم عيد ميلاد السيدة ${w.fullName}',
          body: 'لا تنسي تهنئتها اليوم.',
          at: at,
          payload: 'woman:${w.id}',
        ));
      }
    }
    if (p.conference) {
      var n = 0;
      for (final c in conferences) {
        for (final d in c.days) {
          if (n + 2 > ReminderIds.maxConferenceItems) break;
          final eve = Dates.dateOnly(d.date)
              .subtract(const Duration(days: 1))
              .add(const Duration(hours: conferenceEveHour));
          final day = Dates.dateOnly(d.date).add(const Duration(hours: conferenceDayHour));
          if (eve.isAfter(now)) {
            out.add(PlannedReminder(
              id: ReminderIds.conferenceBase + n++,
              title: 'غداً ${c.name}',
              body: '${d.label} — ${Dates.display(d.date)}',
              at: eve,
              payload: 'conference:${c.id}',
            ));
          }
          if (day.isAfter(now)) {
            out.add(PlannedReminder(
              id: ReminderIds.conferenceBase + n++,
              title: 'اليوم ${c.name} (${d.label})',
              body: 'لا تنسي تسجيل حضور المؤتمر.',
              at: day,
              payload: 'conference:${c.id}',
            ));
          }
        }
      }
    }
    return out;
  }
}
