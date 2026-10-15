import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/simple_charts.dart';
import '../../../core/widgets/states.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../../core/utils/dates.dart';
import '../../streets/data/street_repository.dart';
import 'simple_stats_providers.dart';

/// أبونا's statistics: one month at a time, pictures with real counts.
/// 1) attendance each Wednesday, 2) each servant (her streets),
/// 3) each street, 4) follow-ups done / still to do.
class FatherStatsScreen extends ConsumerStatefulWidget {
  const FatherStatsScreen({super.key});

  @override
  ConsumerState<FatherStatsScreen> createState() => _FatherStatsScreenState();
}

class _FatherStatsScreenState extends ConsumerState<FatherStatsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final meetings = ref.watch(monthMeetingsProvider(_month));
    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(monthMeetingsProvider(_month));
          ref.invalidate(allServantsMonthProvider(_month));
          ref.invalidate(churchFollowUpsProvider(_month));
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          MonthPicker(month: _month, onChanged: (m) => setState(() => _month = m)),
          AsyncBody(
            value: meetings,
            onRetry: () => ref.invalidate(monthMeetingsProvider(_month)),
            builder: (ms) => _MeetingsSection(meetings: ms),
          ),
          _ServantsSection(month: _month),
          AsyncBody(
            value: meetings,
            builder: (ms) => _StreetsSection(meetings: ms),
          ),
          _FollowUpsSection(month: _month),
          const SectionTitle('تقارير'),
          MenuTile(
              icon: Icons.calendar_month,
              title: 'التقرير الشهري (Excel)',
              color: AppColors.present,
              onTap: () => context.push(Routes.monthlyReport)),
          MenuTile(
              icon: Icons.event,
              title: 'المؤتمرات',
              onTap: () => context.push(Routes.conferences)),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _MeetingsSection extends StatelessWidget {
  const _MeetingsSection({required this.meetings});
  final List<MeetingSummary> meetings;

  @override
  Widget build(BuildContext context) {
    var present = 0, absent = 0;
    for (final m in meetings) {
      present += m.present;
      absent += m.absent;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('الحضور في كل أربعاء'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: WeeklyBars(items: [
            for (final m in meetings)
              (_short(m.meetingId), m.present),
          ]),
        ),
      ),
      if (meetings.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AttendanceDonut(
                present: present,
                absent: absent,
                title: 'مجموع الشهر (${meetings.length} اجتماع)'),
          ),
        ),
      ],
    ]);
  }

  static String _short(String id) {
    final d = Dates.parseDayId(id);
    return '${d.day}/${d.month}';
  }
}

class _ServantsSection extends ConsumerWidget {
  const _ServantsSection({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('الخادمات'),
        const Text('حضور سيدات شوارع كل خادمة في الشهر',
            style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
        AsyncBody(
          value: ref.watch(allServantsMonthProvider(month)),
          onRetry: () => ref.invalidate(allServantsMonthProvider(month)),
          builder: (list) => Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('لا توجد خادمات', style: TextStyle(fontSize: 18)),
                    )
                  : Column(children: [
                      for (final s in list)
                        CountBar(
                          label: '${s.servantName} (${s.assignedWomen} سيدة)',
                          count: s.meetingPresent,
                          total: s.meetingPresent + s.meetingAbsent,
                          extra: 'اتصلت ${s.followUps.calls} • زارت ${s.followUps.visits}'
                              ' • افتقاد لسه ${s.followUps.pending}',
                        ),
                    ]),
            ),
          ),
        ),
      ]);
}

class _StreetsSection extends ConsumerWidget {
  const _StreetsSection({required this.meetings});
  final List<MeetingSummary> meetings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streets = ref.watch(streetsProvider).value ?? const [];
    final rows = <(String, int, int)>[];
    for (final s in streets) {
      var p = 0, a = 0;
      for (final m in meetings) {
        p += m.byStreet[s.id]?.present ?? 0;
        a += m.byStreet[s.id]?.absent ?? 0;
      }
      if (p + a > 0) rows.add((s.name, p, p + a));
    }
    rows.sort((x, y) => (y.$2 / y.$3).compareTo(x.$2 / x.$3));
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('الشوارع'),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: [
            for (final (name, p, t) in rows) CountBar(label: name, count: p, total: t),
          ]),
        ),
      ),
    ]);
  }
}

class _FollowUpsSection extends ConsumerWidget {
  const _FollowUpsSection({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('الافتقاد'),
        AsyncBody(
          value: ref.watch(churchFollowUpsProvider(month)),
          onRetry: () => ref.invalidate(churchFollowUpsProvider(month)),
          builder: (f) => Column(children: [
            TileRow(
              NumberTile(
                  icon: Icons.task_alt,
                  label: 'افتقاد اتعمل',
                  value: '${f.completed}',
                  color: AppColors.present,
                  background: AppColors.presentLight),
              NumberTile(
                  icon: Icons.hourglass_bottom,
                  label: 'افتقاد لسه',
                  value: '${f.pending}',
                  color: AppColors.warning,
                  background: AppColors.warningLight,
                  onTap: () => context.go(Routes.followUps)),
            ),
            TileRow(
              NumberTile(icon: Icons.phone, label: 'مكالمات', value: '${f.calls}'),
              NumberTile(
                  icon: Icons.home,
                  label: 'زيارات',
                  value: '${f.visits}',
                  color: AppColors.home,
                  background: AppColors.homeLight),
            ),
          ]),
        ),
      ]);
}
