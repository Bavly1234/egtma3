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
  });
  final String id;
  final SuggestionType type;
  final SuggestionStatus status;
  final String? streakStartMeetingId;
}

class SuggestionDecision {
  const SuggestionDecision({this.create, this.cancelIds = const []});
  final SuggestionType? create;
  final List<String> cancelIds;

  bool get isNoop => create == null && cancelIds.isEmpty;
}

/// Pure business logic. Mirrored exactly by functions/src/shared/rules.ts,
/// which is the authority that writes suggestions.
abstract final class AbsenceRules {
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

  /// Rules A, B, D, E combined.
  ///
  /// * Never creates a suggestion when an active one of the same type exists.
  /// * Creates at most one suggestion of each type per absence streak, so a
  ///   completed phone follow-up is not re-created next week (Rule E keeps it
  ///   in history; Rule D prevents duplicates).
  /// * Escalating to a home visit cancels any still-active phone suggestion.
  /// * When she attends again (streak 0), suggestions that nobody has started
  ///   yet (pending/assigned) are cancelled; in-progress work is kept.
  static SuggestionDecision decide(
    AbsenceStreak streak,
    List<ExistingSuggestion> existing,
  ) {
    if (streak.count == 0) {
      final stale = existing
          .where((s) =>
              s.status == SuggestionStatus.pending ||
              s.status == SuggestionStatus.assigned)
          .map((s) => s.id)
          .toList();
      return SuggestionDecision(cancelIds: stale);
    }

    final type = requiredType(streak.count);
    if (type == null) return const SuggestionDecision();

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
    return SuggestionDecision(
      create: shouldCreate ? type : null,
      cancelIds: cancel,
    );
  }
}
