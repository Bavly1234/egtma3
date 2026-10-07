import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/services/sync_status.dart';
import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/dates.dart';
import '../../auth/data/auth_repository.dart';
import '../../followups/data/absence_processor.dart';
import '../../streets/data/street_repository.dart';
import '../../streets/domain/street.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import '../../women/domain/women_filter.dart';
import '../data/attendance_repository.dart';

class AttendanceFilter {
  const AttendanceFilter({this.streetId, this.servantId, this.query = ''});
  final String? streetId;
  final String? servantId;
  final String query;

  AttendanceFilter copyWith({
    String? Function()? streetId,
    String? Function()? servantId,
    String? query,
  }) =>
      AttendanceFilter(
        streetId: streetId != null ? streetId() : this.streetId,
        servantId: servantId != null ? servantId() : this.servantId,
        query: query ?? this.query,
      );
}

/// Selected meeting date (defaults to today if Wednesday, else last Wednesday).
class MeetingDateController extends Notifier<DateTime> {
  @override
  DateTime build() => Dates.currentOrLastMeeting(ref.read(clockProvider)());
  void set(DateTime d) => state = Dates.dateOnly(d);
}

final meetingDateProvider =
    NotifierProvider<MeetingDateController, DateTime>(MeetingDateController.new);

class AttendanceFilterController extends Notifier<AttendanceFilter> {
  @override
  AttendanceFilter build() => const AttendanceFilter();
  void set(AttendanceFilter f) => state = f;
}

final attendanceFilterProvider =
    NotifierProvider<AttendanceFilterController, AttendanceFilter>(
        AttendanceFilterController.new);

/// Servant responsible for a woman = her street's servant (the ONLY
/// assignment). Unassigned streets count as 'unassigned'.
String streetServantKey(Woman w, Map<String, Street> streets) =>
    streets[w.streetId]?.servantId ?? 'unassigned';

/// Active women in scope for the selected street. The servant filter is
/// applied in memory against the street assignment (no other assignment).
/// Search is applied in memory too so typing never triggers reads.
final attendanceWomenProvider =
    FutureProvider.autoDispose<List<Woman>>((ref) async {
  final f = ref.watch(attendanceFilterProvider.select(
      (f) => (f.streetId, f.servantId)));
  final user = ref.watch(requireUserProvider);
  final list = await ref.watch(womenRepositoryProvider).all(
        user,
        WomenFilter(active: true, streetId: f.$1),
      );
  final servantId = f.$2;
  final streets = ref.watch(streetMapProvider);
  final filtered = servantId == null
      ? list
      : list
          .where((w) => streets[w.streetId]?.servantId == servantId)
          .toList();
  filtered.sort((a, b) => ArabicText.normalizeName(a.fullName)
      .compareTo(ArabicText.normalizeName(b.fullName)));
  return filtered;
});

final visibleAttendanceWomenProvider =
    Provider.autoDispose<AsyncValue<List<Woman>>>((ref) {
  final q = ArabicText.normalize(ref.watch(attendanceFilterProvider).query);
  final absentOnly = ref.watch(absentOnlyProvider);
  final statuses = ref.watch(meetingStatusesProvider).value ?? const {};
  return ref.watch(attendanceWomenProvider).whenData((list) {
    var out = q.isEmpty
        ? list
        : list
            .where((w) => ArabicText.normalize(
                    '${w.fullName} ${w.phone} ${w.streetName}')
                .contains(q))
            .toList();
    if (absentOnly) {
      out = out
          .where((w) => statuses[w.id] == AttendanceStatus.absent)
          .toList();
    }
    return out;
  });
});

final meetingStatusesProvider =
    StreamProvider.autoDispose<Map<String, AttendanceStatus>>((ref) {
  final date = ref.watch(meetingDateProvider);
  final user = ref.watch(requireUserProvider);
  return ref
      .watch(attendanceRepositoryProvider)
      .watchMeeting(Dates.dayId(date), user);
});

/// When true, the attendance list shows only the absent women of the
/// selected meeting (used by the dashboard "absent" card).
class AbsentOnlyController extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final absentOnlyProvider =
    NotifierProvider.autoDispose<AbsentOnlyController, bool>(
        AbsentOnlyController.new);

/// Writes go straight to Firestore's offline cache (instant UI update via the
/// statuses stream) and are tracked for the sync indicator. After each write
/// the on-device [AbsenceProcessor] applies the follow-up rules.
class AttendanceActions {
  AttendanceActions(this.ref);
  final Ref ref;

  Map<String, AttendanceStatus> get _current =>
      ref.read(meetingStatusesProvider).value ?? const {};

  void mark(Woman w, AttendanceStatus status) => markAll([w], status);

  void clear(Woman w) {
    final prev = _current[w.id];
    if (prev == null) return;
    final meetingId = Dates.dayId(ref.read(meetingDateProvider));
    final streets = ref.read(streetMapProvider);
    _track(
        ref.read(attendanceRepositoryProvider).clear(meetingId, w, prev,
            meetingServantId: streets[w.streetId]?.servantId),
        [w]);
  }

  void markAll(List<Woman> women, AttendanceStatus status) {
    final meetingId = Dates.dayId(ref.read(meetingDateProvider));
    final user = ref.read(requireUserProvider);
    final previous = Map.of(_current);
    final changed = women.where((w) => previous[w.id] != status).toList();
    if (changed.isEmpty) return;
    final streets = ref.read(streetMapProvider);
    _track(
      ref.read(attendanceRepositoryProvider).markMany(meetingId, changed,
          status, user,
          previous: previous,
          meetingServants: {
            for (final w in changed) w.id: streets[w.streetId]?.servantId
          }),
      changed,
    );
  }

  void _track(Future<void> write, List<Woman> affected) {
    final sync = ref.read(syncControllerProvider.notifier);
    final processor = ref.read(absenceProcessorProvider);
    final user = ref.read(requireUserProvider);
    // The batch is applied to the local cache as soon as commit() is called,
    // so the rules can run immediately — even offline — without waiting for
    // the server acknowledgement (which never comes while offline).
    sync.track(write);
    sync.track(Future(() async {
      for (final w in affected) {
        await processor.process(w, user);
      }
    }));
  }
}

final attendanceActionsProvider = Provider((ref) => AttendanceActions(ref));
