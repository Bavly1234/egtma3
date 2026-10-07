import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';

/// A minimal attendance mark used by the absence rules.
class AttendanceMark {
  const AttendanceMark(this.meetingId, this.status);
  final String meetingId; // yyyy-MM-dd — sorts chronologically as a string
  final AttendanceStatus status;
}

/// Current run of consecutive Wednesday absences.
class AbsenceStreak {
  const AbsenceStreak(this.count, this.startMeetingId);
  final int count;

  /// The first meeting of the current streak; identifies the streak so that
  /// one streak produces at most one suggestion of each type.
  final String? startMeetingId;

  static const none = AbsenceStreak(0, null);
}

/// A previously created suggestion, as far as the rules need to know.
class ExistingSuggestion {
  const ExistingSuggestion({
    required this.id,
    required this.type,
    required this.status,
    required this.streakStartMeetingId,
    this.createdAt,
  });
  final String id;
  final SuggestionType type;
  final SuggestionStatus status;
  final String? streakStartMeetingId;
  final DateTime? createdAt;
}

class SuggestionDecision {
  const SuggestionDecision(
      {this.create, this.cancelIds = const [], this.streakStartMeetingId, this.reason});
  final SuggestionType? create;
  final List<String> cancelIds;

  /// Overrides the deterministic streak start (e.g. intermittent windows).
  final String? streakStartMeetingId;

  /// Overrides the display reason for the created suggestion.
  final String? reason;

  bool get isNoop =>
      create == null && cancelIds.isEmpty;
}

/// Pure business logic, applied on the device by AbsenceProcessor.
abstract final class AbsenceRules {
  /// Intermittent suggestions use a streak id prefixed with `int_`.
  static const intermittentPrefix = 'int_';
  static bool isIntermittent(ExistingSuggestion s) =>
      s.streakStartMeetingId?.startsWith(intermittentPrefix) ?? false;

  /// Rule C: counts absences from the most recent meeting backwards and stops
  /// at the first attendance — old absences before a present are ignored.
  static AbsenceStreak computeStreak(Iterable<AttendanceMark> marks) {
    final sorted = marks.toList()
      ..sort((a, b) => b.meetingId.compareTo(a.meetingId));
    var count = 0;
    String? start;
    for (final m in sorted) {
      if (m.status == AttendanceStatus.present) break;
      count++;
      start = m.meetingId;
    }
    return count == 0 ? AbsenceStreak.none : AbsenceStreak(count, start);
  }

  /// Which suggestion (if any) the current streak requires.
  static SuggestionType? requiredType(int consecutiveAbsences) {
    if (consecutiveAbsences >= BusinessRules.homeVisitThreshold) {
      return SuggestionType.homeVisit; // Rule B (higher priority)
    }
    if (consecutiveAbsences >= BusinessRules.phoneThreshold) {
      return SuggestionType.phone; // Rule A
    }
    return null;
  }

  /// Rules A, B, D, E combined, plus intermittent Rules I and J.
  ///
  /// * Never creates a suggestion when an active one of the same type exists.
  /// * Creates at most one suggestion of each type per absence streak, so a
  ///   completed phone follow-up is not re-created next week (Rule E keeps it
  ///   in history; Rule D prevents duplicates).
  /// * Escalating to a home visit cancels any still-active phone suggestion.
  /// * When she attends again (streak 0), suggestions that nobody has started
  ///   yet (pending/assigned) are cancelled; in-progress work is kept.
  /// * Rules I/J (intermittent): alternating absences that never form a long
  ///   consecutive streak still trigger افتقاد — 3+ absences in the last 5
  ///   meetings → phone; 5+ in the last 8 → home visit. A suggestion of the
  ///   same type created within [BusinessRules.intermittentCooldownDays] days
  ///   blocks a new one, so nothing duplicates week after week. Pass [marks]
  ///   (newest first or not — they are sorted inside) and [now] to enable
  ///   Rules I/J; without them only the consecutive rules apply.
  static SuggestionDecision decide(
    AbsenceStreak streak,
    List<ExistingSuggestion> existing, {
    List<AttendanceMark>? marks,
    DateTime? now,
  }) {
    if (streak.count == 0) {
      // Attending ends a consecutive streak, so its not-yet-started tasks are
      // cancelled. Intermittent (alternating) tasks are kept: attending one
      // week is exactly the alternating pattern they were created for.
      final stale = existing
          .where((s) =>
              (s.status == SuggestionStatus.pending ||
                  s.status == SuggestionStatus.assigned) &&
              !isIntermittent(s))
          .map((s) => s.id)
          .toList();
      return SuggestionDecision(cancelIds: stale);
    }

    final type = requiredType(streak.count);
    if (type == null) {
      return _decideIntermittent(streak, existing, marks, now);
    }

    bool activeOf(SuggestionType t) =>
        existing.any((s) => s.type == t && s.status.isActive);
    bool alreadyForStreak(SuggestionType t) => existing.any((s) =>
        s.type == t && s.streakStartMeetingId == streak.startMeetingId);

    final cancel = <String>[];
    if (type == SuggestionType.homeVisit) {
      cancel.addAll(existing
          .where((s) => s.type == SuggestionType.phone && s.status.isActive)
          .map((s) => s.id));
    } else if (activeOf(SuggestionType.homeVisit)) {
      return const SuggestionDecision();
    }

    final shouldCreate = !activeOf(type) && !alreadyForStreak(type);
    if (!shouldCreate) {
      // Consecutive rule is silent (e.g. work already in progress):
      // intermittent rules must not duplicate it.
      if (activeOf(SuggestionType.phone) ||
          activeOf(SuggestionType.homeVisit)) {
        return SuggestionDecision(cancelIds: cancel);
      }
      return _decideIntermittent(streak, existing, marks, now,
          extraCancelIds: cancel);
    }
    return SuggestionDecision(
      create: type,
      cancelIds: cancel,
    );
  }

  /// Rules I/J: intermittent (alternating) absences.
  static SuggestionDecision _decideIntermittent(
    AbsenceStreak streak,
    List<ExistingSuggestion> existing,
    List<AttendanceMark>? marks,
    DateTime? now, {
    List<String> extraCancelIds = const [],
  }) {
    if (marks == null || now == null || marks.isEmpty) {
      return SuggestionDecision(cancelIds: extraCancelIds);
    }
    bool activeOf(SuggestionType t) =>
        existing.any((s) => s.type == t && s.status.isActive);
    // Any active افتقاد in progress blocks a parallel intermittent one —
    // no duplicates, no overlapping tasks for the same woman.
    if (activeOf(SuggestionType.phone) ||
        activeOf(SuggestionType.homeVisit)) {
      return SuggestionDecision(cancelIds: extraCancelIds);
    }
    bool recent(SuggestionType t) => existing.any((s) =>
        s.type == t &&
        (s.status.isActive || s.status == SuggestionStatus.completed) &&
        s.createdAt != null &&
        now.difference(s.createdAt!).inDays <
            BusinessRules.intermittentCooldownDays);

    final sorted = marks.toList()
      ..sort((a, b) => b.meetingId.compareTo(a.meetingId));
    int absentIn(int window) => sorted
        .take(window)
        .where((m) => m.status == AttendanceStatus.absent)
        .length;
    final latestAbsentIds = sorted
        .where((m) => m.status == AttendanceStatus.absent)
        .map((m) => m.meetingId)
        .toList();
    if (latestAbsentIds.isEmpty) {
      return SuggestionDecision(cancelIds: extraCancelIds);
    }
    final latestAbsent = latestAbsentIds.first;
    bool alreadyForStreak(SuggestionType t, String start) => existing.any(
        (s) => s.type == t && s.streakStartMeetingId == start);

    // Rule J first (higher priority, mirrors Rule B escalation).
    final in8 = absentIn(BusinessRules.intermittentHomeWindow);
    if (in8 >= BusinessRules.intermittentHomeMin &&
        !recent(SuggestionType.homeVisit)) {
      final start = '$intermittentPrefix$latestAbsent';
      if (!alreadyForStreak(SuggestionType.homeVisit, start)) {
        return SuggestionDecision(
          create: SuggestionType.homeVisit,
          cancelIds: extraCancelIds,
          streakStartMeetingId: start,
          reason:
              'غابت $in8 مرات من آخر ${BusinessRules.intermittentHomeWindow} اجتماعات (متقطعة).',
        );
      }
      return SuggestionDecision(cancelIds: extraCancelIds);
    }
    // Rule I.
    final in5 = absentIn(BusinessRules.intermittentPhoneWindow);
    if (in5 >= BusinessRules.intermittentPhoneMin &&
        !recent(SuggestionType.phone)) {
      final start = '$intermittentPrefix$latestAbsent';
      if (!alreadyForStreak(SuggestionType.phone, start)) {
        return SuggestionDecision(
          create: SuggestionType.phone,
          cancelIds: extraCancelIds,
          streakStartMeetingId: start,
          reason:
              'غابت $in5 مرات من آخر ${BusinessRules.intermittentPhoneWindow} اجتماعات (متقطعة).',
        );
      }
    }
    return SuggestionDecision(cancelIds: extraCancelIds);
  }
}
