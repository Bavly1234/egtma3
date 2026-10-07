import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/services/sync_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../attendance/presentation/attendance_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../women/domain/woman.dart';
import '../data/conference_repository.dart';
import '../domain/conference.dart';

typedef _DayKey = ({String conferenceId, String dayId});

final _dayStatusesProvider = StreamProvider.autoDispose
    .family<Map<String, AttendanceStatus>, _DayKey>((ref, k) => ref
        .watch(conferenceRepositoryProvider)
        .watchDay(k.conferenceId, k.dayId, ref.watch(requireUserProvider)));

/// Conference attendance — one tab per day, stored separately from
/// Wednesday attendance (Rule F).
class ConferenceAttendanceScreen extends ConsumerWidget {
  const ConferenceAttendanceScreen({super.key, required this.conferenceId});
  final String conferenceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(conferenceProvider(conferenceId)),
      builder: (c) {
        if (c == null) {
          return const Scaffold(
              body: EmptyState(icon: Icons.event_busy, title: 'المؤتمر غير موجود'));
        }
        final today = Dates.dateOnly(DateTime.now());
        final initial = c.days.indexWhere((d) => d.date == today);
        return DefaultTabController(
          length: c.days.length,
          initialIndex: initial < 0 ? 0 : initial,
          child: Scaffold(
            appBar: AppBar(
              title: Text(c.name),
              actions: const [
                SyncStatusChip(),
              ],
              bottom: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                indicatorWeight: 4,
                labelStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                tabs: [
                  for (final d in c.days)
                    Tab(text: '${d.label}\n${Dates.display(d.date)}', height: 64),
                ],
              ),
            ),
            body: TabBarView(children: [
              for (final d in c.days) _DayList(conference: c, day: d),
            ]),
          ),
        );
      },
    );
  }
}

class _DayList extends ConsumerStatefulWidget {
  const _DayList({required this.conference, required this.day});
  final Conference conference;
  final ConferenceDay day;

  @override
  ConsumerState<_DayList> createState() => _DayListState();
}

class _DayListState extends ConsumerState<_DayList>
    with AutomaticKeepAliveClientMixin {
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  void _mark(Woman w, AttendanceStatus s) {
    // The ONLY assignment is by street.
    final streets = ref.read(streetMapProvider);
    ref.read(syncControllerProvider.notifier).track(ref
        .read(conferenceRepositoryProvider)
        .mark(widget.conference.id, widget.day.id, w, s,
            ref.read(requireUserProvider),
            servantId: streets[w.streetId]?.servantId));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final women = ref.watch(attendanceWomenProvider);
    final statuses = ref.watch(_dayStatusesProvider(
                (conferenceId: widget.conference.id, dayId: widget.day.id)))
            .value ??
        const {};
    final streets = ref.watch(streetMapProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => _q = ArabicText.normalize(v)),
          decoration: const InputDecoration(
              hintText: 'بحث بالاسم', prefixIcon: Icon(Icons.search)),
        ),
      ),
      Expanded(
        child: AsyncBody(
          value: women,
          builder: (all) {
            final list = _q.isEmpty
                ? all
                : all.where((w) => ArabicText.normalize(w.fullName).contains(_q)).toList();
            final present =
                statuses.values.where((s) => s == AttendanceStatus.present).length;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: list.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                          'حاضر $present  •  غائب ${statuses.length - present}  •  لم تُسجل ${all.length - statuses.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  );
                }
                final w = list[i - 1];
                final s = statuses[w.id];
                final servantLabel =
                    streets[w.streetId]?.servantName ?? 'غير معينة';
                return Card(
                  color: switch (s) {
                    AttendanceStatus.present => AppColors.presentLight,
                    AttendanceStatus.absent => AppColors.absentLight,
                    null => Colors.white,
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(w.fullName,
                                  style: const TextStyle(
                                      fontSize: 19, fontWeight: FontWeight.w700)),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.badge,
                                    size: 16, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'الخادمة (حسب الشارع): $servantLabel',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textMuted),
                                  ),
                                ),
                              ]),
                            ])),
                        _btn('حاضر', s == AttendanceStatus.present, AppColors.present,
                            () => _mark(w, AttendanceStatus.present)),
                        const SizedBox(width: 8),
                        _btn('غائب', s == AttendanceStatus.absent, AppColors.absent,
                            () => _mark(w, AttendanceStatus.absent)),
                      ]),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _btn(String label, bool selected, Color color, VoidCallback onTap) => SizedBox(
        width: 84,
        height: 56,
        child: selected
            ? FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: color, padding: EdgeInsets.zero),
                onPressed: onTap,
                child: Text(label))
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color, width: 2),
                    padding: EdgeInsets.zero),
                onPressed: onTap,
                child: Text(label)),
      );
}
