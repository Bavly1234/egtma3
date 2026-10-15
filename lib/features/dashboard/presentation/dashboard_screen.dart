import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/simple_charts.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/presentation/attendance_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../followups/data/follow_up_repository.dart';
import '../../notifications/data/notification_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../users/data/users_repository.dart';
import '../../verse/presentation/verse_card.dart';
import 'dashboard_providers.dart';

/// Home page. Kept deliberately short for older users: the meeting result
/// as a picture, a few big numbers, and big buttons for what to do next.
/// The father sees everyone; a servant sees only her own streets.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(requireUserProvider);
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('اجتماع السيدات'),
        actions: [
          const SyncStatusChip(),
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => context.push(Routes.notifications),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications, size: 30),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(overviewProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Greeting(user: user),
            const SizedBox(height: 16),
            if (user.isFather) _FatherBody(user: user) else _ServantBody(user: user),
            const SizedBox(height: 16),
            const VerseCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(user.isFather ? 'أهلاً يا أبونا ${user.name}' : 'أهلاً ${user.name}',
          style: Theme.of(context).textTheme.headlineSmall),
      Text('${Dates.weekdayAr(now)} ${Dates.display(now)}',
          style: const TextStyle(fontSize: 18, color: AppColors.textMuted)),
    ]);
  }
}

/// The meeting card: picture of who came + one big button.
class _MeetingCard extends ConsumerWidget {
  const _MeetingCard({required this.present, required this.absent, required this.meetingId});
  final int present;
  final int absent;
  final String meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = Dates.parseDayId(meetingId);
    final isToday = Dates.dayId(DateTime.now()) == meetingId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isToday ? 'اجتماع النهارده' : 'آخر اجتماع — ${Dates.display(date)}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          AttendanceDonut(present: present, absent: absent),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              ref.read(absentOnlyProvider.notifier).set(false);
              context.go(Routes.attendance);
            },
            icon: const Icon(Icons.how_to_reg),
            label: const Text('تسجيل الحضور'),
          ),
          if (absent > 0) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.absent,
                  side: const BorderSide(color: AppColors.absent, width: 1.5)),
              onPressed: () {
                ref.read(meetingDateProvider.notifier).set(date);
                ref.read(absentOnlyProvider.notifier).set(true);
                context.go(Routes.attendance);
              },
              icon: const Icon(Icons.person_off),
              label: Text('مين اللي غاب؟ ($absent)'),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ServantBody extends ConsumerWidget {
  const _ServantBody({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(overviewProvider).value;
    final summary = o == null ? null : ref.watch(meetingSummaryProvider(o.meetingId)).value;
    final mine = summary?.byServant[user.id];
    final streets = (ref.watch(streetsProvider).value ?? const [])
        .where((s) => s.servantId == user.id)
        .toList();
    final myWomen = streets.fold<int>(0, (a, s) => a + s.womenCount);
    final myTasks = (ref.watch(suggestionsProvider(const SuggestionQuery())).value ?? const [])
        .where((s) => s.assignedServantId == user.id)
        .length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (o != null)
        _MeetingCard(
            present: mine?.present ?? 0,
            absent: mine?.absent ?? 0,
            meetingId: o.meetingId),
      const SizedBox(height: 12),
      TileRow(
        NumberTile(
          icon: Icons.volunteer_activism,
          label: 'افتقاد مطلوب منكِ',
          value: '$myTasks',
          color: myTasks > 0 ? AppColors.warning : AppColors.present,
          background: myTasks > 0 ? AppColors.warningLight : AppColors.presentLight,
          onTap: () => context.go(Routes.followUps),
        ),
        NumberTile(
          icon: Icons.cake,
          label: 'أعياد ميلاد النهارده',
          value: '${o?.birthdaysToday ?? 0}',
          color: AppColors.gold,
          background: AppColors.goldLight,
          onTap: () => context.push(Routes.birthdays),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('شوارعك ($myWomen سيدة)',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (streets.isEmpty)
              const Text('لم يحدد أبونا شوارع لكِ بعد.',
                  style: TextStyle(fontSize: 18, color: AppColors.textMuted))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in streets)
                  Chip(
                    avatar: const Icon(Icons.signpost, size: 20),
                    label: Text('${s.name} (${s.womenCount})',
                        style: const TextStyle(fontSize: 17)),
                  ),
              ]),
          ]),
        ),
      ),
    ]);
  }
}

class _FatherBody extends ConsumerWidget {
  const _FatherBody({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(overviewProvider).value;
    final summary = o == null ? null : ref.watch(meetingSummaryProvider(o.meetingId)).value;
    final tasks = ref.watch(suggestionsProvider(const SuggestionQuery())).value ?? const [];
    final servants = (ref.watch(allUsersProvider).value ?? const [])
        .where((u) => u.isServant && u.active)
        .toList();
    final streets = ref.watch(streetsProvider).value ?? const [];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (o != null)
        _MeetingCard(
            present: summary?.present ?? o.meetingPresent,
            absent: summary?.absent ?? o.meetingAbsent,
            meetingId: o.meetingId),
      const SizedBox(height: 12),
      TileRow(
        NumberTile(
          icon: Icons.volunteer_activism,
          label: 'افتقاد لسه ما اتعملش',
          value: '${tasks.length}',
          color: tasks.isNotEmpty ? AppColors.warning : AppColors.present,
          background: tasks.isNotEmpty ? AppColors.warningLight : AppColors.presentLight,
          onTap: () => context.go(Routes.followUps),
        ),
        NumberTile(
          icon: Icons.cake,
          label: 'أعياد ميلاد النهارده',
          value: '${o?.birthdaysToday ?? 0}',
          color: AppColors.gold,
          background: AppColors.goldLight,
          onTap: () => context.push(Routes.birthdays),
        ),
      ),
      TileRow(
        NumberTile(
          icon: Icons.groups,
          label: 'كل السيدات',
          value: '${o?.activeWomen ?? 0}',
          onTap: () => context.go(Routes.women),
        ),
        NumberTile(
          icon: Icons.badge,
          label: 'الخادمات',
          value: '${servants.length}',
          onTap: () => context.push(Routes.streets),
        ),
      ),
      // Each servant = her streets (the only assignment).
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('كل خادمة في آخر اجتماع',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Text('(حسب الشوارع اللي معاها)',
                style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
            if (servants.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('لا توجد خادمات بعد', style: TextStyle(fontSize: 18)),
              ),
            for (final s in servants)
              Builder(builder: (_) {
                final c = summary?.byServant[s.id];
                final hasStreets = streets.any((st) => st.servantId == s.id);
                final left = tasks.where((t) => t.assignedServantId == s.id).length;
                return CountBar(
                  label: s.name,
                  count: c?.present ?? 0,
                  total: (c?.present ?? 0) + (c?.absent ?? 0),
                  extra: hasStreets
                      ? 'افتقاد لسه: $left'
                      : 'لم تُحدد لها شوارع بعد',
                );
              }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.streets),
              icon: const Icon(Icons.signpost),
              label: const Text('توزيع الشوارع على الخادمات'),
            ),
          ]),
        ),
      ),
    ]);
  }
}
