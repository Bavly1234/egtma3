import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/services/sync_status.dart';
import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/dates.dart';
import '../../auth/data/auth_repository.dart';
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

/// Active women in scope for the selected street/servant. Search is applied
/// in memory so typing never triggers reads.
final attendanceWomenProvider =
    FutureProvider.autoDispose<List<Woman>>((ref) async {
  final f = ref.watch(attendanceFilterProvider.select(
      (f) => (f.streetId, f.servantId)));
  final user = ref.watch(requireUserProvider);
  final list = await ref.watch(womenRepositoryProvider).all(
        user,
        WomenFilter(active: true, streetId: f.$1, servantId: f.$2),
      );
  list.sort((a, b) => ArabicText.normalizeName(a.fullName)
      .compareTo(ArabicText.normalizeName(b.fullName)));
  return list;
});

final visibleAttendanceWomenProvider =
    Provider.autoDispose<AsyncValue<List<Woman>>>((ref) {
  final q = ArabicText.normalize(ref.watch(attendanceFilterProvider).query);
  return ref.watch(attendanceWomenProvider).whenData((list) => q.isEmpty
      ? list
      : list
          .where((w) => ArabicText.normalize(
                  '${w.fullName} ${w.phone} ${w.streetName}')
              .contains(q))
          .toList());
});

final meetingStatusesProvider =
    StreamProvider.autoDispose<Map<String, AttendanceStatus>>((ref) {
  final date = ref.watch(meetingDateProvider);
  final user = ref.watch(requireUserProvider);
  return ref
      .watch(attendanceRepositoryProvider)
      .watchMeeting(Dates.dayId(date), user);
});

/// Writes go straight to Firestore's offline cache (instant UI update via the
/// statuses stream) and are tracked for the sync indicator.
class AttendanceActions {
  AttendanceActions(this.ref);
  final Ref ref;

  void mark(Woman w, AttendanceStatus status) {
    final meetingId = Dates.dayId(ref.read(meetingDateProvider));
    ref.read(syncControllerProvider.notifier).track(ref
        .read(attendanceRepositoryProvider)
        .mark(meetingId, w, status, ref.read(requireUserProvider)));
  }

  void clear(Woman w) {
    final meetingId = Dates.dayId(ref.read(meetingDateProvider));
    ref
        .read(syncControllerProvider.notifier)
        .track(ref.read(attendanceRepositoryProvider).clear(meetingId, w.id));
  }

  void markAll(List<Woman> women, AttendanceStatus status) {
    final meetingId = Dates.dayId(ref.read(meetingDateProvider));
    ref.read(syncControllerProvider.notifier).track(ref
        .read(attendanceRepositoryProvider)
        .markMany(meetingId, women, status, ref.read(requireUserProvider)));
  }
}

final attendanceActionsProvider = Provider((ref) => AttendanceActions(ref));
