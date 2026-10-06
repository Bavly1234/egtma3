import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/services/local_notifications.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/domain/app_user.dart';
import '../../birthdays/domain/birthday_rules.dart';
import '../../conferences/domain/conference.dart';
import '../../settings/data/settings_repository.dart';
import '../../verse/data/fallback_verses.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import '../domain/app_notification.dart';
import '../domain/reminder_plan.dart';
import 'notification_writer.dart';

/// Device-side notification engine (replaces the server scheduler):
///  * schedules reminders on the phone (work with the app closed);
///  * writes today's birthday entries into the in-app notification center;
///  * pops a phone notification for new in-app notifications (e.g. a
///    follow-up created from another phone) while the app is running.
class ReminderService {
  ReminderService(this._db, this._women, this._writer, this._local);
  final FirebaseFirestore _db;
  final WomenRepository _women;
  final NotificationWriter _writer;
  final LocalNotifications _local;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incoming;

  Future<void> start(AppUser user) async {
    await _local.init();
    await _local.requestPermission();
    await refresh(user);
    _listenIncoming(user);
  }

  Future<void> stop() async {
    await _incoming?.cancel();
    _incoming = null;
    await _local.cancelAll();
  }

  /// Re-plans everything. Call on start, on resume, and after settings change.
  Future<void> refresh(AppUser user) async {
    try {
      final now = DateTime.now();
      final settingsDoc =
          await _db.collection(FsPaths.settings).doc(FsPaths.settingsAppDoc).get();
      final settings = AppSettings.fromMap(settingsDoc.data());
      final women = await _upcomingBirthdayWomen(user, now);
      final conferences = (await _db
              .collection(FsPaths.conferences)
              .where('startDate',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(
                      now.subtract(const Duration(days: 30))))
              .get())
          .docs
          .map((d) => Conference.fromMap(d.id, d.data()))
          .toList();
      var pending = _db
          .collection(FsPaths.suggestions)
          .where('status', whereIn: SuggestionStatus.activeWires);
      if (!user.isFather) {
        pending = pending.where('assignedServantId', isEqualTo: user.id);
      }
      final pendingCount = (await pending.count().get()).count ?? 0;

      await _local.apply(ReminderPlanner.plan(
        now: now,
        user: user,
        settings: settings,
        women: (user.isFather && !settings.notifyFatherBirthdays)
            ? const []
            : women,
        conferences: conferences,
        pendingFollowUps: pendingCount,
        verseFor: fallbackVerseFor,
      ));
      await _todayBirthdaysInApp(user, women, now);
    } catch (e, st) {
      AppLog.e('Reminder refresh failed', e, st);
    }
  }

  Future<List<Woman>> _upcomingBirthdayWomen(AppUser user, DateTime now) async {
    final months = {for (var i = 0; i < 3; i++) DateTime(now.year, now.month + i).month};
    final lists = await Future.wait(months.map((m) => _women.birthdays(user, m)));
    return {for (final l in lists) for (final w in l) w.id: w}.values.toList();
  }

  /// Rule G: one in-app birthday notification per woman, recipient, year.
  Future<void> _todayBirthdaysInApp(
      AppUser user, List<Woman> women, DateTime now) async {
    if (!user.prefs.birthday) return;
    for (final w in women) {
      if (w.dateOfBirth == null || !BirthdayRules.isBirthdayOn(w.dateOfBirth!, now)) {
        continue;
      }
      await _writer.createOnce(
        id: BirthdayRules.notificationKey(w.id, user.id, now.year),
        recipientId: user.id,
        title: '🎂 اليوم عيد ميلاد السيدة ${w.fullName}',
        message: 'لا تنسي تهنئتها اليوم.',
        type: NotificationType.birthday,
        relatedEntityId: w.id,
        relatedEntityType: 'woman',
      );
    }
  }

  void _listenIncoming(AppUser user) {
    _incoming?.cancel();
    var first = true;
    _incoming = _db
        .collection(FsPaths.notifications)
        .where('recipientId', isEqualTo: user.id)
        .where('readAt', isNull: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      if (first) {
        first = false;
        // Catch-up after the app was closed: one summary notification.
        final recent = snap.docs.where((d) {
          final n = AppNotification.fromMap(d.id, d.data());
          return DateTime.now().difference(n.createdAt).inHours < 72 &&
              n.type != NotificationType.birthday;
        }).length;
        if (recent > 0) {
          _local.showNow('لديك $recent إشعارات جديدة', 'افتحي مركز الإشعارات للتفاصيل.',
              payload: 'route:/notifications');
        }
        return;
      }
      for (final c in snap.docChanges) {
        if (c.type != DocumentChangeType.added || c.doc.metadata.hasPendingWrites) {
          continue;
        }
        final n = AppNotification.fromMap(c.doc.id, c.doc.data()!);
        _local.showNow(n.title, n.message,
            payload: n.relatedEntityType == 'woman' && n.relatedEntityId != null
                ? 'woman:${n.relatedEntityId}'
                : 'route:/notifications');
      }
    }, onError: (Object e) => AppLog.w('Notification listener error', e));
  }
}

final reminderServiceProvider = Provider((ref) => ReminderService(
      ref.watch(firestoreProvider),
      ref.watch(womenRepositoryProvider),
      ref.watch(notificationWriterProvider),
      LocalNotifications.instance,
    ));
