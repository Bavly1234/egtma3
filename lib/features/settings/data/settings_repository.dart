import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/firebase_providers.dart';

/// Church-wide settings read by Cloud Functions (`settings/app`).
class AppSettings {
  const AppSettings({
    this.meetingReminderHour = 18,
    this.attendanceReminderHour = 20,
    this.followUpReminderHour = 10,
    this.notifyFatherBirthdays = true,
    this.verseNotifications = true,
  });

  /// Hour (Cairo time) on Tuesday for "غداً اجتماع السيدات".
  final int meetingReminderHour;

  /// Hour on Wednesday to remind servants who haven't recorded attendance.
  final int attendanceReminderHour;
  final int followUpReminderHour;
  final bool notifyFatherBirthdays;
  final bool verseNotifications;

  factory AppSettings.fromMap(Map<String, dynamic>? m) => AppSettings(
        meetingReminderHour: (m?['meetingReminderHour'] as num?)?.toInt() ?? 18,
        attendanceReminderHour:
            (m?['attendanceReminderHour'] as num?)?.toInt() ?? 20,
        followUpReminderHour: (m?['followUpReminderHour'] as num?)?.toInt() ?? 10,
        notifyFatherBirthdays: (m?['notifyFatherBirthdays'] as bool?) ?? true,
        verseNotifications: (m?['verseNotifications'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'meetingReminderHour': meetingReminderHour,
        'attendanceReminderHour': attendanceReminderHour,
        'followUpReminderHour': followUpReminderHour,
        'notifyFatherBirthdays': notifyFatherBirthdays,
        'verseNotifications': verseNotifications,
      };
}

class SettingsRepository {
  SettingsRepository(this._db);
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection(FsPaths.settings).doc(FsPaths.settingsAppDoc);

  Stream<AppSettings> watch() =>
      _doc.snapshots().map((s) => AppSettings.fromMap(s.data()));

  Future<void> save(AppSettings s) async {
    try {
      await _doc.set({...s.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    } catch (e, st) {
      throw AppFailure.from(e, st);
    }
  }
}

final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(ref.watch(firestoreProvider)));

final appSettingsProvider = StreamProvider<AppSettings>(
    (ref) => ref.watch(settingsRepositoryProvider).watch());
