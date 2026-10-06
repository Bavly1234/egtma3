import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../users/data/users_repository.dart';
import '../data/stats_repository.dart';
import '../domain/stats_models.dart';
import 'charts.dart';
import 'stats_filter_bar.dart';

final _servantStatsProvider = FutureProvider.autoDispose
    .family<List<ServantStats>, StatsFilter>((ref, f) async {
  final user = ref.watch(requireUserProvider);
  final repo = ref.watch(statsRepositoryProvider);
  final now = DateTime.now();
  if (!user.isFather) return [await repo.servantStats(user, f, now)];
  final users = await ref.watch(allUsersProvider.future);
  final servants = users
      .where((u) => u.isServant && u.active)
      .where((u) => f.servantId == null || u.id == f.servantId)
      .toList();
  return Future.wait(servants.map((s) => repo.servantStats(s, f, now)));
});

/// إحصائيات الخادمات. Servants see only their own card.
class ServantsStatsScreen extends ConsumerStatefulWidget {
  const ServantsStatsScreen({super.key});

  @override
  ConsumerState<ServantsStatsScreen> createState() => _State();
}

class _State extends ConsumerState<ServantsStatsScreen> {
  RangePreset _preset = RangePreset.month;
  late DateRange _range = _preset.resolve(DateTime.now());
  String? _servantId;
  String? _streetId;
  FollowUpType? _type;

  StatsFilter get _filter => StatsFilter(
      range: _range, servantId: _servantId, streetId: _streetId, followUpType: _type);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(requireUserProvider);
    final stats = ref.watch(_servantStatsProvider(_filter));
    final streets = ref.watch(streetsProvider).value ?? const [];
    final servants =
        user.isFather ? ref.watch(activeServantsProvider).value ?? const [] : const [];

    return Scaffold(
      appBar: AppBar(title: Text(user.isFather ? 'إحصائيات الخادمات' : 'إحصائياتي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        RangeSelector(
          preset: _preset,
          range: _range,
          onChanged: (p, r) => setState(() {
            _preset = p;
            _range = r;
          }),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, children: [
          if (user.isFather)
            DropdownButton<String?>(
              value: _servantId,
              hint: const Text('كل الخادمات'),
              items: [
                const DropdownMenuItem(value: null, child: Text('كل الخادمات')),
                for (final s in servants) DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _servantId = v),
            ),
          DropdownButton<String?>(
            value: _streetId,
            hint: const Text('كل الشوارع'),
            items: [
              const DropdownMenuItem(value: null, child: Text('كل الشوارع')),
              for (final s in streets) DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _streetId = v),
          ),
          DropdownButton<FollowUpType?>(
            value: _type,
            hint: const Text('كل أنواع الافتقاد'),
            items: const [
              DropdownMenuItem(value: null, child: Text('كل أنواع الافتقاد')),
              DropdownMenuItem(value: FollowUpType.phoneCall, child: Text('مكالمات')),
              DropdownMenuItem(value: FollowUpType.homeVisit, child: Text('زيارات')),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
        ]),
        AsyncBody(
          value: stats,
          onRetry: () => ref.invalidate(_servantStatsProvider(_filter)),
          builder: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.badge, title: 'لا توجد خادمات');
            }
            final sorted = [...list]
              ..sort((a, b) => b.attendanceRate.compareTo(a.attendanceRate));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (list.length > 1) ...[
                const SectionTitle('مقارنة نسبة الحضور'),
                RateBars(rows: [
                  for (final s in sorted)
                    (s.servantName, s.attendanceRate, '(${s.assignedWomen} سيدة)'),
                ]),
              ],
              for (final s in sorted) _ServantCard(s),
            ]);
          },
        ),
      ]),
    );
  }
}

class _ServantCard extends StatelessWidget {
  const _ServantCard(this.s);
  final ServantStats s;

  @override
  Widget build(BuildContext context) {
    final f = s.followUps;
    Widget cell(String label, String value, [Color color = AppColors.primary]) =>
        SizedBox(
          width: 150,
          child: Column(children: [
            Text(value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.servantName, style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            Wrap(alignment: WrapAlignment.spaceAround, runSpacing: 16, children: [
              cell('السيدات المسؤولة', '${s.assignedWomen}'),
              cell('نسبة الحضور', percent(s.attendanceRate), AppColors.present),
              cell('مرات الغياب', '${s.meetingAbsent}', AppColors.absent),
              cell('غياب متتالي', '${s.withConsecutiveAbsences}', AppColors.absent),
              cell('المكالمات', '${f.calls}'),
              cell('افتقاد تليفوني تم', '${f.phoneCompleted}', AppColors.present),
              cell('الزيارات', '${f.visits}', AppColors.home),
              cell('افتقاد منزلي تم', '${f.homeCompleted}', AppColors.present),
              cell('لم يتم بعد', '${f.pending}', AppColors.warning),
              cell('متأخر', '${f.overdue}', AppColors.absent),
              cell('اقتراحات تليفوني', '${f.phoneSuggestions}', AppColors.warning),
              cell('اقتراحات منزلي', '${f.homeSuggestions}', AppColors.home),
            ]),
          ]),
        ),
      ),
    );
  }
}
