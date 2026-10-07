import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../statistics/presentation/charts.dart';
import '../data/conference_repository.dart';
import '../domain/conference.dart';
import '../domain/conference_stats.dart';

final _statsProvider = FutureProvider.autoDispose
    .family<(Conference, ConferenceStats)?, String>((ref, id) async {
  final conf = await AppFailure.guard(ref.watch(conferenceProvider(id).future));
  if (conf == null) return null;
  final records = await ref
      .watch(conferenceRepositoryProvider)
      .allAttendance(id, ref.watch(requireUserProvider));
  return (conf, ConferenceStats.compute(conf, records));
});

class ConferenceStatsScreen extends ConsumerWidget {
  const ConferenceStatsScreen({super.key, required this.conferenceId});
  final String conferenceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('إحصائيات المؤتمر')),
        body: AsyncBody(
          value: ref.watch(_statsProvider(conferenceId)),
          onRetry: () => ref.invalidate(_statsProvider(conferenceId)),
          builder: (data) {
            if (data == null) {
              return const EmptyState(icon: Icons.event_busy, title: 'المؤتمر غير موجود');
            }
            final (c, s) = data;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
              const SectionTitle('الحضور لكل يوم'),
              RateBars(rows: [
                for (final d in c.days)
                  ('${d.label} (${Dates.display(d.date)})', s.dayRate(d.id),
                      '${s.presentPerDay[d.id]} حاضرة'),
              ]),
              const SectionTitle('الإجمالي'),
              StatCard(icon: Icons.groups, title: 'إجمالي مرات الحضور',
                  value: '${s.totalPresent}'),
              const SizedBox(height: 10),
              StatCard(icon: Icons.person, title: 'عدد السيدات اللاتي حضرن',
                  value: '${s.uniqueAttendees}'),
              const SizedBox(height: 10),
              StatCard(icon: Icons.percent, title: 'نسبة الحضور', value: percent(s.rate),
                  color: AppColors.present, background: AppColors.presentLight),
              const SizedBox(height: 10),
              StatCard(icon: Icons.star, title: 'حضرن الأيام الثلاثة',
                  value: '${s.attendedAll}',
                  color: AppColors.gold, background: AppColors.goldLight),
              const SizedBox(height: 10),
              StatCard(icon: Icons.remove_circle_outline, title: 'غبن يوماً واحداً',
                  value: '${s.missedOne}',
                  color: AppColors.warning, background: AppColors.warningLight),
              const SizedBox(height: 10),
              StatCard(icon: Icons.cancel, title: 'غبن أكثر من يوم',
                  value: '${s.missedMultiple}',
                  color: AppColors.absent, background: AppColors.absentLight),
            ]);
          },
        ),
      );
}
