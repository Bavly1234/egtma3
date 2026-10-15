import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/widgets/simple_charts.dart';
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
              const SectionTitle('الحضور في كل يوم'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(children: [
                    for (final d in c.days)
                      CountBar(
                        label: '${d.label} (${Dates.display(d.date)})',
                        count: s.presentPerDay[d.id] ?? 0,
                        total: s.markedPerDay[d.id] ?? 0,
                      ),
                  ]),
                ),
              ),
              const SectionTitle('السيدات'),
              TileRow(
                NumberTile(
                    icon: Icons.groups,
                    label: 'حضرن المؤتمر',
                    value: '${s.uniqueAttendees}',
                    color: AppColors.present,
                    background: AppColors.presentLight),
                NumberTile(
                    icon: Icons.star,
                    label: 'حضرن الـ 3 أيام',
                    value: '${s.attendedAll}',
                    color: AppColors.gold,
                    background: AppColors.goldLight),
              ),
              TileRow(
                NumberTile(
                    icon: Icons.remove_circle_outline,
                    label: 'غابت يوم واحد',
                    value: '${s.missedOne}',
                    color: AppColors.warning,
                    background: AppColors.warningLight),
                NumberTile(
                    icon: Icons.cancel,
                    label: 'غابت أكتر من يوم',
                    value: '${s.missedMultiple}',
                    color: AppColors.absent,
                    background: AppColors.absentLight),
              ),
            ]);
          },
        ),
      );
}
