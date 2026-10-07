import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../attendance/presentation/attendance_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../notifications/data/notification_repository.dart';
import '../../statistics/domain/stats_models.dart';
import '../../verse/presentation/verse_card.dart';
import 'dashboard_providers.dart';

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
            const VerseCard(),
            const SizedBox(height: 16),
            if (user.isFather) const _FatherBody() else const _ServantBody(),
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

/// Cards shared by both roles, in priority order.
List<Widget> _priorityCards(BuildContext context, WidgetRef ref,
    OverviewStats? o) {
  final phone = ref.watch(activePhoneSuggestionsProvider).value?.length;
  final home = ref.watch(activeHomeSuggestionsProvider).value?.length;
  final now = ref.watch(clockProvider)();
  final meeting = Dates.currentOrLastMeeting(now);
  final isToday = Dates.isMeetingDay(now);
  final conf = ref.watch(upcomingConferenceProvider);

  return [
    StatCard(
      icon: Icons.how_to_reg,
      title: 'اجتماع الأربعاء',
      subtitle: isToday
          ? 'اليوم — ${Dates.display(meeting)}'
          : 'آخر اجتماع ${Dates.display(meeting)}',
      value: o == null || o.meetingPresent + o.meetingAbsent == 0
          ? '—'
          : percent(o.attendanceRate),
      onTap: () => context.go(Routes.attendance),
    ),
    const SizedBox(height: 12),
    StatCard(
      icon: Icons.phone_in_talk,
      title: 'افتقاد تليفوني مطلوب',
      subtitle: phone == null ? null : '$phone سيدات يحتجن اتصال',
      value: '${phone ?? '—'}',
      color: AppColors.warning,
      background: AppColors.warningLight,
      onTap: () => context.go(Routes.followUps),
    ),
    const SizedBox(height: 12),
    StatCard(
      icon: Icons.home,
      title: 'افتقاد منزلي',
      subtitle: home == null ? null : '$home سيدة',
      value: '${home ?? '—'}',
      color: AppColors.home,
      background: AppColors.homeLight,
      onTap: () => context.go(Routes.followUps),
    ),
    const SizedBox(height: 12),
    StatCard(
      icon: Icons.cake,
      title: 'أعياد الميلاد اليوم',
      value: '${o?.birthdaysToday ?? '—'}',
      color: AppColors.gold,
      background: AppColors.goldLight,
      onTap: () => context.push(Routes.birthdays),
    ),
    if (conf != null) ...[
      const SizedBox(height: 12),
      StatCard(
        icon: Icons.event,
        title: conf.name,
        subtitle: 'يبدأ ${Dates.display(conf.firstDate)}',
        value: '',
        onTap: () => context.push(Routes.conference(conf.id)),
      ),
    ],
  ];
}

class _ServantBody extends ConsumerWidget {
  const _ServantBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewProvider);
    final o = overview.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (overview.hasError)
        ErrorView(
            error: overview.error!,
            onRetry: () => ref.invalidate(overviewProvider)),
      ..._priorityCards(context, ref, o),
      const SectionTitle('السيدات المسؤولة عنهن'),
      StatCard(
        icon: Icons.groups,
        title: 'عدد السيدات',
        value: '${o?.activeWomen ?? '—'}',
        onTap: () => context.go(Routes.women),
      ),
      const SizedBox(height: 12),
      StatCard(
        icon: Icons.person_off,
        title: 'غائبات في آخر اجتماع',
        value: '${o?.meetingAbsent ?? '—'}',
        color: AppColors.absent,
        background: AppColors.absentLight,
        onTap: () {
          _openAbsent(context, ref, o);
        },
      ),
      const SizedBox(height: 12),
      StatCard(
        icon: Icons.insights,
        title: 'إحصائيات الخادمات',
        value: '',
        onTap: () => context.push(Routes.statsServants),
      ),
    ]);
  }
}

class _FatherBody extends ConsumerWidget {
  const _FatherBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewProvider);
    final o = overview.value;
    String v(int? n) => n == null ? '—' : '$n';
    Widget grid(List<Widget> cards) => LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth > 700 ? 2 : 1;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards)
                SizedBox(
                    width: (c.maxWidth - (cols - 1) * 12) / cols, child: card),
            ],
          );
        });

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (overview.hasError)
        ErrorView(
            error: overview.error!,
            onRetry: () => ref.invalidate(overviewProvider)),
      ..._priorityCards(context, ref, o),
      const SectionTitle('نظرة عامة'),
      grid([
        StatCard(
            icon: Icons.groups,
            title: 'إجمالي السيدات',
            subtitle: o == null ? null : 'النشطات ${o.activeWomen}',
            value: v(o?.totalWomen),
            onTap: () => context.go(Routes.women)),
        StatCard(
            icon: Icons.badge,
            title: 'الخادمات',
            value: v(o?.totalServants),
            onTap: () => context.push(Routes.users)),
        StatCard(
            icon: Icons.check_circle,
            title: 'حضور هذا الأربعاء',
            value: v(o?.meetingPresent),
            color: AppColors.present,
            background: AppColors.presentLight),
        StatCard(
            icon: Icons.person_off,
            title: 'الغائبات',
            value: v(o?.meetingAbsent),
            color: AppColors.absent,
            background: AppColors.absentLight,
            onTap: () {
              _openAbsent(context, ref, o);
            }),
      ]),
      const SectionTitle('الافتقاد (هذا الشهر)'),
      grid([
        StatCard(
            icon: Icons.pending_actions,
            title: 'افتقاد لم يتم',
            subtitle: o == null ? null : 'متأخر ${o.followUps.overdue}',
            value: v(o?.followUps.pending),
            color: AppColors.warning,
            background: AppColors.warningLight,
            onTap: () => context.go(Routes.followUps)),
        StatCard(
            icon: Icons.task_alt,
            title: 'افتقاد تم',
            value: v(o?.followUps.completed),
            color: AppColors.present,
            background: AppColors.presentLight),
        StatCard(
            icon: Icons.phone,
            title: 'إجمالي المكالمات',
            value: v(o?.followUps.calls)),
        StatCard(
            icon: Icons.home,
            title: 'إجمالي الزيارات',
            value: v(o?.followUps.visits),
            color: AppColors.home,
            background: AppColors.homeLight),
      ]),
      const SectionTitle('المزيد'),
      grid([
        StatCard(
            icon: Icons.bar_chart,
            title: 'الإحصائيات الكاملة',
            value: '',
            onTap: () => context.go(Routes.stats)),
        StatCard(
            icon: Icons.signpost,
            title: 'إحصائيات الشوارع',
            value: '',
            onTap: () => context.push(Routes.streets)),
        StatCard(
            icon: Icons.event,
            title: 'المؤتمرات',
            value: '',
            onTap: () => context.push(Routes.conferences)),
      ]),
    ]);
  }
}

/// Opens the attendance sheet of the SAME meeting the card counts, showing
/// only the absent women.
void _openAbsent(BuildContext context, WidgetRef ref, OverviewStats? o) {
  if (o != null) {
    ref.read(meetingDateProvider.notifier).set(Dates.parseDayId(o.meetingId));
  }
  ref.read(absentOnlyProvider.notifier).set(true);
  context.go(Routes.attendance);
}
