import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/data/auth_repository.dart';
import '../../conferences/data/conference_repository.dart';
import '../../users/data/users_repository.dart';
import '../data/stats_repository.dart';
import '../domain/stats_models.dart';
import 'charts.dart';
import 'stats_filter_bar.dart';

final _fatherStatsProvider = FutureProvider.autoDispose
    .family<(OverviewStats, List<MeetingSummary>), DateRange>((ref, range) async {
  final user = ref.watch(requireUserProvider);
  final users = await ref.watch(allUsersProvider.future);
  final servants = users.where((u) => u.isServant && u.active).length;
  final overview = await ref.watch(statsRepositoryProvider).overview(
      user, DateTime.now(), range: range, servants: servants);
  final meetings = await ref.watch(attendanceRepositoryProvider).summaries(
      limit: 60, fromId: range.fromId, toId: range.toIdInclusive);
  return (overview, meetings);
});

/// The father's full statistics dashboard.
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
    final conferences = ref.watch(conferencesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات')),
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
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
