import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../attendance/domain/absence_rules.dart';
import '../../auth/domain/app_user.dart';
import '../../notifications/data/notification_writer.dart';
import '../../women/domain/woman.dart';

/// Runs the follow-up business rules on the device right after attendance is
/// saved (this replaces a server trigger so the app works on the free plan).
///
/// Safety against duplicates without a server:
///  * suggestion ids are deterministic — `{womanId}_{type}_{streakStart}` —
///    so two phones processing the same absence streak write the same doc;
///  * the decision itself (Rules A–E) is the pure, tested [AbsenceRules].
class AbsenceProcessor {
  AbsenceProcessor(this._db, this._notifications);
  final FirebaseFirestore _db;
  final NotificationWriter _notifications;

  static String suggestionId(String womanId, SuggestionType t, String streakStart) =>
      '${womanId}_${t.wire}_$streakStart';

  /// Recomputes the woman's attendance summary and syncs her suggestions.
  /// Never throws: failures are logged and retried on the next mark.
  Future<void> process(Woman woman, AppUser actor) async {
    try {
      // 1. History (servants can only read records of their own women).
      var hq = _db.collection(FsPaths.attendance).where('womanId', isEqualTo: woman.id);
      if (!actor.isFather) hq = hq.where('servantId', isEqualTo: actor.id);
      final history = await hq.orderBy('meetingId', descending: true).limit(500).get();
      final marks = <AttendanceMark>[];
      var present = 0, absent = 0;
      for (final d in history.docs) {
        final s = AttendanceStatus.fromWire(d.get('status') as String?);
        if (s == null) continue;
        marks.add(AttendanceMark(d.get('meetingId') as String, s));
        s == AttendanceStatus.present ? present++ : absent++;
      }
      final streak = AbsenceRules.computeStreak(marks);

      // 2. Existing suggestions.
      var sq = _db.collection(FsPaths.suggestions).where('womanId', isEqualTo: woman.id);
      if (!actor.isFather) sq = sq.where('assignedServantId', isEqualTo: actor.id);
      final existingDocs = (await sq.get()).docs;
      final existing = [
        for (final d in existingDocs)
          ExistingSuggestion(
            id: d.id,
            type: SuggestionType.fromWire(d.get('type') as String?) ?? SuggestionType.phone,
            status: SuggestionStatus.fromWire(d.get('status') as String?),
            streakStartMeetingId: d.data()['streakStartMeetingId'] as String?,
          ),
      ];
      final decision = AbsenceRules.decide(streak, existing);

      // 3. Apply atomically.
      final batch = _db.batch();
      final now = FieldValue.serverTimestamp();
      for (final id in decision.cancelIds) {
        batch.update(_db.collection(FsPaths.suggestions).doc(id), {
          'status': SuggestionStatus.cancelled.wire,
          'cancelReason': streak.count == 0 ? 'attended' : 'escalated',
          'updatedAt': now,
        });
      }
      String? createdId;
      final create = decision.create;
      if (create != null && streak.startMeetingId != null) {
        createdId = suggestionId(woman.id, create, streak.startMeetingId!);
        batch.set(_db.collection(FsPaths.suggestions).doc(createdId), {
          'womanId': woman.id,
          'womanName': woman.fullName,
          'type': create.wire,
          'status': SuggestionStatus.pending.wire,
          'consecutiveAbsences': streak.count,
          'streakStartMeetingId': streak.startMeetingId,
          'reason': reasonFor(create, streak.count),
          'assignedServantId': woman.assignedServantId,
          'assignedServantName': woman.assignedServantName,
          'streetId': woman.streetId,
          'streetName': woman.streetName,
          'phone': woman.phone,
          'address': woman.address,
          'isDemo': woman.isDemo,
          'createdBy': actor.id,
          'createdAt': now,
          'updatedAt': now,
        });
      }

      // Active type after this change.
      final activeTypes = <SuggestionType>{
        for (final s in existing)
          if (s.status.isActive && !decision.cancelIds.contains(s.id)) s.type,
        ?create,
      };
      batch.update(_db.collection(FsPaths.women).doc(woman.id), {
        'consecutiveAbsences': streak.count,
        'totalPresent': present,
        'totalAbsent': absent,
        'lastAttendanceDate': marks.isEmpty ? null : marks.first.meetingId,
        'activeSuggestionType': activeTypeWire(activeTypes),
      });
      // Not awaited: offline, commit() only completes after reconnecting,
      // but the change is already in the local cache and will sync.
      batch.commit().catchError((Object e) => AppLog.w('Suggestion sync failed', e));

      // 4. In-app notifications for the new suggestion.
      if (createdId != null) {
        await _notifications.suggestionCreated(
          suggestionId: createdId,
          woman: woman,
          type: create!,
          count: streak.count,
        );
      }
    } catch (e, st) {
      AppLog.e('Absence processing failed', e, st);
    }
  }

  /// Recomputes `women.activeSuggestionType` (e.g. after completing a task).
  Future<void> refreshActiveType(String womanId, AppUser actor) async {
    try {
      var q = _db
          .collection(FsPaths.suggestions)
          .where('womanId', isEqualTo: womanId)
          .where('status', whereIn: SuggestionStatus.activeWires);
      if (!actor.isFather) q = q.where('assignedServantId', isEqualTo: actor.id);
      final types = {
        for (final d in (await q.get()).docs)
          ?SuggestionType.fromWire(d.get('type') as String?),
      };
      _db.collection(FsPaths.women).doc(womanId).update({
        'activeSuggestionType': activeTypeWire(types),
      }).catchError((Object e) => AppLog.w('Active type sync failed', e));
    } catch (e, st) {
      AppLog.e('Active type refresh failed', e, st);
    }
  }

  static String activeTypeWire(Set<SuggestionType> types) =>
      types.contains(SuggestionType.homeVisit)
          ? SuggestionType.homeVisit.wire
          : types.contains(SuggestionType.phone)
              ? SuggestionType.phone.wire
              : 'none';

  static String reasonFor(SuggestionType t, int count) => t == SuggestionType.homeVisit
      ? 'غائبة منذ $count اجتماعات متتالية.'
      : 'غابت $count اجتماعات متتالية.';
}

final absenceProcessorProvider = Provider((ref) => AbsenceProcessor(
      ref.watch(firestoreProvider),
      ref.watch(notificationWriterProvider),
    ));
