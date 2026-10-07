import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/data/auth_repository.dart';
import '../../conferences/data/conference_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../users/data/users_repository.dart';
import '../data/stats_repository.dart';
import '../domain/stats_models.dart';
import 'charts.dart';
import 'stats_filter_bar.dart';

final _fatherStatsProvider = FutureProvider.autoDispose
    .family<(OverviewStats, List<MeetingSummary>), DateRange>((ref, range) async {
  final user = ref.watch(requireUserProvider);
  final users = await AppFailure.guard(ref.watch(allUsersProvider.future));
  final servants = users.where((u) => u.isServant && u.active).length;
  final overview = await ref.watch(statsRepositoryProvider).overview(
      user, DateTime.now(), range: range, servants: servants);
  final meetings = await ref.watch(attendanceRepositoryProvider).summaries(
      limit: 60, fromId: range.fromId, toId: range.toIdInclusive);
  return (overview, meetings);
});

/// All servants' cards for the father's page (range-aware).
final _fatherServantsProvider = FutureProvider.autoDispose
    .family<List<ServantStats>, DateRange>((ref, range) async {
  final users = await AppFailure.guard(ref.watch(allUsersProvider.future));
  final servants = users.where((u) => u.isServant && u.active).toList();
  final repo = ref.watch(statsRepositoryProvider);
  final now = DateTime.now();
  final stats = await Future.wait(servants.map((s) => repo.servantStats(
      s, StatsFilter(range: range), now)));
  stats.sort((a, b) => b.attendanceRate.compareTo(a.attendanceRate));
  return stats;
});

/// Street attendance for the latest meeting in range (father's page).
final _fatherStreetsProvider = FutureProvider.autoDispose
    .family<List<StreetStats>, List<MeetingSummary>>((ref, meetings) async {
  if (meetings.isEmpty) return const [];
  final streets =
      await AppFailure.guard(ref.watch(streetRepositoryProvider).watchAll().first);
  return ref
      .watch(statsRepositoryProvider)
      .streetStats(streets, meetings.first.meetingId);
});

/// The father's exclusive full statistics dashboard: all servants, all
/// women and all streets with charts (servants use their own pages).
class FatherStatsScreen extends ConsumerStatefulWidget {
  const FatherStatsScreen({super.key});

  @override
  ConsumerState<FatherStatsScreen> createState() => _FatherStatsScreenState();
}

class _FatherStatsScreenState extends ConsumerState<FatherStatsScreen> {
  RangePreset _preset = RangePreset.quarter;
  late DateRange _range = _preset.resolve(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_fatherStatsProvider(_range));
    final servantStats = ref.watch(_fatherServantsProvider(_range));
    final conferences = ref.watch(conferencesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('إحصائيات الأب الكاهن')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_fatherStatsProvider(_range).future),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          RangeSelector(
            preset: _preset,
            range: _range,
            onChanged: (p, r) => setState(() {
              _preset = p;
              _range = r;
            }),
          ),
          AsyncBody(
            value: data,
            onRetry: () => ref.invalidate(_fatherStatsProvider(_range)),
            builder: (d) {
              final (o, meetings) = d;
              final ms = meetings;
              var present = 0, absent = 0;
              for (final m in ms) {
                present += m.present;
                absent += m.absent;
              }
              final rate = present + absent == 0 ? 0.0 : present / (present + absent);
              final f = o.followUps;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionTitle('عام'),
                StatCard(icon: Icons.groups, title: 'إجمالي السيدات',
                    subtitle: 'النشطات ${o.activeWomen}', value: '${o.totalWomen}'),
                const SizedBox(height: 10),
                StatCard(icon: Icons.badge, title: 'الخادمات', value: '${o.totalServants}'),
                const SizedBox(height: 10),
                StatCard(icon: Icons.percent, title: 'نسبة الحضور في الفترة',
                    subtitle: '${ms.length} اجتماع', value: percent(rate),
                    color: AppColors.present, background: AppColors.presentLight),
                const SizedBox(height: 10),
                StatCard(icon: Icons.person_off, title: 'إجمالي الغياب', value: '$absent',
                    color: AppColors.absent, background: AppColors.absentLight),
                const SectionTitle('الحضور حسب الأربعاء'),
                AttendanceTrendChart(meetings: meetings),
                const SectionTitle('الافتقاد'),
                StatCard(icon: Icons.phone, title: 'المكالمات', value: '${f.calls}'),
                const SizedBox(height: 10),
                StatCard(icon: Icons.home, title: 'الزيارات المنزلية', value: '${f.visits}',
                    color: AppColors.home, background: AppColors.homeLight),
                const SizedBox(height: 10),
                StatCard(icon: Icons.phone_in_talk, title: 'اقتراحات افتقاد تليفوني',
                    subtitle: 'تم ${f.phoneCompleted}', value: '${f.phoneSuggestions}',
                    color: AppColors.warning, background: AppColors.warningLight),
                const SizedBox(height: 10),
                StatCard(icon: Icons.house, title: 'اقتراحات افتقاد منزلي',
                    subtitle: 'تم ${f.homeCompleted}', value: '${f.homeSuggestions}',
                    color: AppColors.home, background: AppColors.homeLight),
                const SizedBox(height: 10),
                StatCard(icon: Icons.pending_actions, title: 'لم يتم بعد (كل الوقت)',
                    subtitle: 'متأخر ${f.overdue}', value: '${f.pending}',
                    color: AppColors.absent, background: AppColors.absentLight,
                    onTap: () => context.go(Routes.followUps)),
                const SizedBox(height: 10),
                StatCard(icon: Icons.task_alt, title: 'تم الافتقاد',
                    value: '${f.completed}',
                    color: AppColors.present, background: AppColors.presentLight),
              ]);
            },
          ),
          const SectionTitle('الخادمات — مقارنة شاملة'),
          AsyncBody(
            value: servantStats,
            onRetry: () => ref.invalidate(_fatherServantsProvider(_range)),
            builder: (list) => list.isEmpty
                ? const Text('لا توجد خادمات نشطات',
                    style: TextStyle(fontSize: 18))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RateBars(rows: [
                        for (final s in list)
                          (s.servantName, s.attendanceRate,
                              '(${s.assignedWomen} سيدة)'),
                      ]),
                      for (final s in list) _FatherServantCard(s),
                    ],
                  ),
          ),
          _FatherStreetsSection(range: _range),
          const SectionTitle('تقارير تفصيلية'),
          MenuTile(icon: Icons.badge, title: 'إحصائيات الخادمات',
              subtitle: 'مقارنة نشاط الخادمات',
              onTap: () => context.push(Routes.statsServants)),
          MenuTile(icon: Icons.groups, title: 'إحصائيات السيدات',
              subtitle: 'الأكثر انتظاماً والغياب المتكرر',
              onTap: () => context.push(Routes.statsWomen)),
          MenuTile(icon: Icons.signpost, title: 'إحصائيات الشوارع',
              subtitle: 'الحضور والافتقاد حسب الشارع',
              onTap: () => context.push(Routes.streets)),
          MenuTile(icon: Icons.event, title: 'إحصائيات المؤتمرات',
              subtitle: '${conferences.length} مؤتمر',
              onTap: () => context.push(Routes.conferences)),
          MenuTile(icon: Icons.calendar_month, title: 'التقرير الشهري',
              subtitle: 'تقرير كامل لكل شهر مع تصدير',
              color: AppColors.present,
              onTap: () => context.push(Routes.monthlyReport)),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

/// One servant's full card on the father's page.
class _FatherServantCard extends StatelessWidget {
  const _FatherServantCard(this.s);
  final ServantStats s;

  @override
  Widget build(BuildContext context) {
    final f = s.followUps;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.servantName,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 4, children: [
              Text('السيدات: ${s.assignedWomen}',
                  style: const TextStyle(fontSize: 16)),
              Text('الحضور: ${percent(s.attendanceRate)}',
                  style: const TextStyle(
                      fontSize: 16, color: AppColors.present)),
              Text('الغياب: ${s.meetingAbsent}',
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.absent)),
              Text('غياب متتالي: ${s.withConsecutiveAbsences}',
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.absent)),
              Text('مكالمات: ${f.calls} (تم ${f.phoneCompleted})',
                  style: const TextStyle(fontSize: 16)),
              Text('زيارات: ${f.visits} (تم ${f.homeCompleted})',
                  style: const TextStyle(fontSize: 16)),
              Text('لم يتم: ${f.pending} — متأخر ${f.overdue}',
                  style: const TextStyle(fontSize: 16)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Street attendance bars for the latest meeting in range.
class _FatherStreetsSection extends ConsumerWidget {
  const _FatherStreetsSection({required this.range});
  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings =
        ref.watch(_fatherStatsProvider(range)).value?.$2 ?? const [];
    final stats = ref.watch(_fatherStreetsProvider(meetings));
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('الشوارع — آخر اجتماع'),
      AsyncBody(
        value: stats,
        onRetry: () => ref.invalidate(_fatherStreetsProvider(meetings)),
        builder: (list) => list.isEmpty
            ? const Text('لا توجد بيانات', style: TextStyle(fontSize: 18))
            : RateBars(rows: [
                for (final s in list)
                  (s.name, s.rate, '(${s.women} سيدة)'),
              ]),
      ),
    ]);
  }
}
