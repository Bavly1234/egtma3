import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/notifications/domain/reminder_plan.dart';
import '../utils/app_logger.dart';

/// Notifications shown by the phone itself — no server and no Blaze plan.
/// Scheduled ones fire even when the app is closed (Android alarms survive
/// reboots via the plugin's boot receiver).
class LocalNotifications {
  LocalNotifications._();
  static final instance = LocalNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  bool _ready = false;

  /// Payloads of notifications the user tapped (e.g. `woman:<id>`).
  Stream<String> get taps => _taps.stream;
  String? launchPayload;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'egtma3_default',
      'اجتماع السيدات',
      channelDescription: 'الافتقاد، أعياد الميلاد، التذكيرات، آية اليوم',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    ),
    iOS: DarwinNotificationDetails(),
  );

  bool get supported => !kIsWeb;

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(
            (await FlutterTimezone.getLocalTimezone()).identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null) _taps.add(r.payload!);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchPayload = launch!.notificationResponse?.payload;
      }
      _ready = true;
    } catch (e, st) {
      AppLog.e('Local notifications init failed', e, st);
    }
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  int _nextShowId = 900000;

  Future<void> showNow(String title, String body, {String? payload}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextShowId++,
        title: title,
        body: body,
        notificationDetails: _details,
        payload: payload,
      );
    } catch (e) {
      AppLog.w('showNow failed', e);
    }
  }

  /// Replaces all scheduled reminders with [plan].
  Future<void> apply(List<PlannedReminder> plan) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      for (final r in plan) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: r.repeat == ReminderRepeat.weekly
              ? DateTimeComponents.dayOfWeekAndTime
              : null,
          payload: r.payload,
        );
      }
      AppLog.d('Scheduled ${plan.length} local reminders');
    } catch (e, st) {
      AppLog.e('Scheduling reminders failed', e, st);
    }
  }

  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }
}
