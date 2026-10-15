import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/simple_charts.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../users/data/users_repository.dart';
import 'simple_stats_providers.dart';

/// "إحصائياتي": a servant's own month (her streets only).
/// The father can open any servant's page from the list at the top.
class ServantsStatsScreen extends ConsumerStatefulWidget {
  const ServantsStatsScreen({super.key});

  @override
  ConsumerState<ServantsStatsScreen> createState() => _State();
}

class _State extends ConsumerState<ServantsStatsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AppUser? _picked;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(requireUserProvider);
    final servants = me.isFather
        ? (ref.watch(allUsersProvider).value ?? const [])
            .where((u) => u.isServant && u.active)
            .toList()
        : const <AppUser>[];
    final who = me.isFather ? (_picked ?? servants.firstOrNull) : me;

    return Scaffold(
      appBar: AppBar(title: Text(me.isFather ? 'إحصائيات خادمة' : 'إحصائياتي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (me.isFather) ...[
          DropdownButtonFormField<String>(
            initialValue: who?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'اختار الخادمة'),
            items: [
              for (final s in servants)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (id) => setState(
                () => _picked = servants.firstWhere((s) => s.id == id)),
          ),
          const SizedBox(height: 12),
        ],
        MonthPicker(month: _month, onChanged: (m) => setState(() => _month = m)),
        if (who == null)
          const EmptyState(icon: Icons.badge, title: 'لا توجد خادمات بعد')
        else
          _ServantMonth(servant: who, month: _month),
      ]),
    );
  }
}

class _ServantMonth extends ConsumerWidget {
  const _ServantMonth({required this.servant, required this.month});
  final AppUser servant;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(servantMonthProvider((servant, month)));
    final meetings = ref.watch(monthMeetingsProvider(month)).value ?? const [];
    return AsyncBody(
      value: stats,
      onRetry: () => ref.invalidate(servantMonthProvider((servant, month))),
      builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('سيدات شوارعك: ${s.assignedWomen}'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AttendanceDonut(
                present: s.meetingPresent,
                absent: s.meetingAbsent,
                title: 'الحضور في الشهر كله'),
          ),
        ),
        const SectionTitle('الحضور في كل أربعاء'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: WeeklyBars(items: [
              for (final m in meetings)
                (
                  '${Dates.parseDayId(m.meetingId).day}/${Dates.parseDayId(m.meetingId).month}',
                  m.byServant[servant.id]?.present ?? 0,
                ),
            ]),
          ),
        ),
        const SectionTitle('الافتقاد'),
        TileRow(
          NumberTile(
              icon: Icons.task_alt,
              label: 'افتقاد اتعمل',
              value: '${s.followUps.completed}',
              color: AppColors.present,
              background: AppColors.presentLight),
          NumberTile(
              icon: Icons.hourglass_bottom,
              label: 'افتقاد لسه',
              value: '${s.followUps.pending}',
              color: AppColors.warning,
              background: AppColors.warningLight,
              onTap: () => context.go(Routes.followUps)),
        ),
        TileRow(
          NumberTile(icon: Icons.phone, label: 'مكالمات', value: '${s.followUps.calls}'),
          NumberTile(
              icon: Icons.home,
              label: 'زيارات',
              value: '${s.followUps.visits}',
              color: AppColors.home,
              background: AppColors.homeLight),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
