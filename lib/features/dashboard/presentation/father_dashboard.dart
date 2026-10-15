import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/routing/routes.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/simple_charts.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/data/servant_attendance_repository.dart';
import '../../attendance/presentation/attendance_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../followups/data/follow_up_repository.dart';
import '../../notifications/data/notification_repository.dart';
import '../../statistics/presentation/full_stats_providers.dart';
import '../../statistics/presentation/simple_stats_providers.dart';
import '../../streets/data/street_repository.dart';
import '../../users/data/users_repository.dart';
import '../../verse/presentation/verse_card.dart';
import 'dashboard_providers.dart';

/// أبونا's control panel: different from the servants' pages — a dark header
/// with the key numbers, big quick actions, then the last meeting (women and
/// servants), each servant, and the most faithful women this month.
class FatherDashboard extends ConsumerWidget {
  const FatherDashboard({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(overviewProvider).value;
    final meetingId = o?.meetingId ?? Dates.dayId(Dates.currentOrLastMeeting(DateTime.now()));
    final summary = ref.watch(meetingSummaryProvider(meetingId)).value;
    final tasks = ref.watch(suggestionsProvider(const SuggestionQuery())).value ?? const [];
    final servants = (ref.watch(allUsersProvider).value ?? const [])
        .where((u) => u.isServant && u.active)
        .toList();
    final servantMarks = ref.watch(servantMeetingProvider(meetingId)).value ?? const {};
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    final now = ref.watch(clockProvider)();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(overviewProvider.future),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: _Header(
              user: user,
              date: now,
              unread: unread,
              women: o?.activeWomen ?? 0,
              servants: servants.length,
              present: summary?.present ?? 0,
              total: (summary?.present ?? 0) + (summary?.absent ?? 0),
              tasks: tasks.length,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: [
              const _SectionLabel('إجراءات سريعة'),
              _QuickActions(onAttendance: () {
                ref.read(absentOnlyProvider.notifier).set(false);
                context.go(Routes.attendance);
              }),
              const _SectionLabel('آخر اجتماع'),
              _Panel(
                title: 'السيدات — ${Dates.display(Dates.parseDayId(meetingId))}',
                child: Column(children: [
                  AttendanceDonut(present: summary?.present ?? 0, absent: summary?.absent ?? 0),
                  if ((summary?.absent ?? 0) > 0) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.absent,
                          side: const BorderSide(color: AppColors.absent, width: 1.5)),
                      onPressed: () {
                        ref.read(meetingDateProvider.notifier).set(Dates.parseDayId(meetingId));
                        ref.read(absentOnlyProvider.notifier).set(true);
                        context.go(Routes.attendance);
                      },
                      icon: const Icon(Icons.person_off),
                      label: Text('مين اللي غاب؟ (${summary!.absent})'),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              _Panel(
                title: 'الخادمات في نفس الاجتماع',
                action: TextButton(
                    onPressed: () => context.go(Routes.servantAttendance),
                    child: const Text('تسجيل')),
                child: _ServantsMeeting(servants: servants, marks: servantMarks),
              ),
              const _SectionLabel('كل خادمة (حسب شوارعها)'),
              _Panel(child: _ServantsWomen(servants: servants, meetingId: meetingId, tasks: tasks)),
              const _SectionLabel('⭐ أكتر السيدات حضوراً الشهر ده'),
              const _TopWomen(),
              const SizedBox(height: 16),
              const VerseCard(),
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.date,
    required this.unread,
    required this.women,
    required this.servants,
    required this.present,
    required this.total,
    required this.tasks,
  });
  final AppUser user;
  final DateTime date;
  final int unread, women, servants, present, total, tasks;

  @override
  Widget build(BuildContext context) {
    Widget kpi(IconData icon, String label, String value, VoidCallback onTap) => Expanded(
          child: Material(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                child: Column(children: [
                  Icon(icon, color: AppColors.goldLight, size: 26),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(value,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                  ),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ]),
              ),
            ),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1F3A5F), Color(0xFF0E1E36)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.dashboard, color: AppColors.goldLight, size: 30),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('لوحة التحكم',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          const SyncStatusChip(),
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => context.push(Routes.notifications),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications, color: Colors.white, size: 30),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('أهلاً يا أبونا ${user.name} — ${Dates.weekdayAr(date)} ${Dates.display(date)}',
            style: const TextStyle(color: Colors.white70, fontSize: 17)),
        const SizedBox(height: 16),
        Row(children: [
          kpi(Icons.groups, 'السيدات', '$women', () => context.go(Routes.women)),
          const SizedBox(width: 8),
          kpi(Icons.badge, 'الخادمات', '$servants', () => context.go(Routes.servantAttendance)),
          const SizedBox(width: 8),
          kpi(Icons.how_to_reg, 'حضور آخر أربعاء', total == 0 ? '—' : '$present/$total',
              () => context.go(Routes.attendance)),
          const SizedBox(width: 8),
          kpi(Icons.volunteer_activism, 'افتقاد لسه', '$tasks', () => context.go(Routes.followUps)),
        ]),
      ]),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onAttendance});
  final VoidCallback onAttendance;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, Color, VoidCallback)>[
      (Icons.how_to_reg, 'حضور السيدات', AppColors.present, onAttendance),
      (Icons.badge, 'حضور الخادمات', AppColors.primary, () => context.go(Routes.servantAttendance)),
      (Icons.volunteer_activism, 'الافتقاد', AppColors.warning, () => context.go(Routes.followUps)),
      (Icons.bar_chart, 'الإحصائيات', const Color(0xFF6A1B9A), () => context.go(Routes.stats)),
      (Icons.signpost, 'الشوارع والخادمات', const Color(0xFF00796B), () => context.push(Routes.streets)),
      (Icons.event, 'المؤتمرات', AppColors.gold, () => context.push(Routes.conferences)),
      (Icons.cake, 'أعياد الميلاد', const Color(0xFFC2185B), () => context.push(Routes.birthdays)),
      (Icons.upload_file, 'إضافة من Excel', const Color(0xFF455A64), () => context.push(Routes.import)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (icon, label, color, onTap) in items)
          SizedBox(
            width: w,
            height: 92,
            child: Material(
              color: color,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    Icon(icon, color: Colors.white, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({this.title, this.action, required this.child});
  final String? title;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Row(children: [
              Expanded(
                child: Text(title!,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              ?action,
            ]),
          if (title != null) const SizedBox(height: 10),
          child,
        ]),
      );
}

class _ServantsMeeting extends StatelessWidget {
  const _ServantsMeeting({required this.servants, required this.marks});
  final List<AppUser> servants;
  final Map<String, AttendanceStatus> marks;

  @override
  Widget build(BuildContext context) {
    if (servants.isEmpty) {
      return const Text('لا توجد خادمات بعد', style: TextStyle(fontSize: 18));
    }
    final present = servants.where((s) => marks[s.id] == AttendanceStatus.present).toList();
    final absent = servants.where((s) => marks[s.id] == AttendanceStatus.absent).toList();
    final notYet = servants.length - present.length - absent.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CountBar(
          label: 'الخادمات',
          count: present.length,
          total: present.length + absent.length,
          countWord: 'حضرت',
          extra: notYet > 0 ? 'لسه ما اتسجلش: $notYet' : null),
      if (absent.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          const Text('غابت: ', style: TextStyle(fontSize: 17, color: AppColors.absent)),
          for (final s in absent)
            Chip(
                label: Text(s.name, style: const TextStyle(fontSize: 16)),
                backgroundColor: AppColors.absentLight),
        ]),
    ]);
  }
}

class _ServantsWomen extends ConsumerWidget {
  const _ServantsWomen({required this.servants, required this.meetingId, required this.tasks});
  final List<AppUser> servants;
  final String meetingId;
  final List tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(meetingSummaryProvider(meetingId)).value;
    final streets = ref.watch(streetsProvider).value ?? const [];
    if (servants.isEmpty) {
      return const Text('لا توجد خادمات بعد', style: TextStyle(fontSize: 18));
    }
    return Column(children: [
      for (final s in servants)
        Builder(builder: (_) {
          final c = summary?.byServant[s.id];
          final hasStreets = streets.any((st) => st.servantId == s.id);
          final left = tasks.where((t) => t.assignedServantId == s.id).length;
          return CountBar(
            label: s.name,
            count: c?.present ?? 0,
            total: (c?.present ?? 0) + (c?.absent ?? 0),
            extra: hasStreets ? 'افتقاد لسه: $left' : 'لم تُحدد لها شوارع بعد',
          );
        }),
    ]);
  }
}

class _TopWomen extends ConsumerWidget {
  const _TopWomen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final q = StatsQuery(
        kind: PeriodKind.month, range: monthRange(DateTime(now.year, now.month)));
    final data = ref.watch(fullStatsProvider(q)).value;
    final top = (data?.mostPresent ?? const <WomanCount>[]).take(5).toList();
    return _Panel(
      action: TextButton(
          onPressed: () => context.go(Routes.stats), child: const Text('كل الإحصائيات')),
      title: top.isEmpty ? 'لسه مفيش حضور الشهر ده' : 'أول ${top.length}',
      child: Column(children: [
        for (final (i, c) in top.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppColors.goldLight,
              child: Text('${i + 1}',
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
            ),
            title: Text(c.woman.fullName),
            trailing: Text('حضرت ${c.present} من ${c.total}',
                style: const TextStyle(
                    color: AppColors.present, fontWeight: FontWeight.w800, fontSize: 16)),
            onTap: () => context.push(Routes.woman(c.woman.id)),
          ),
      ]),
    );
  }
}
