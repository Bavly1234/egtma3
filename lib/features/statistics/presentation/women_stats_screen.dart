import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/data/auth_repository.dart';
import '../../followups/data/follow_up_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import 'charts.dart';

class _WomenStats {
  const _WomenStats({
    required this.total,
    required this.active,
    required this.meetings,
    required this.mostRegular,
    required this.mostAbsent,
  });
  final int total;
  final int active;
  final List<MeetingSummary> meetings;
  final List<Woman> mostRegular;
  final List<Woman> mostAbsent;

  double get averageRate {
    final withData = meetings.where((m) => m.total > 0).toList();
    if (withData.isEmpty) return 0;
    return withData.map((m) => m.rate).reduce((a, b) => a + b) / withData.length;
  }

  double get averageAttendees {
    if (meetings.isEmpty) return 0;
    return meetings.map((m) => m.present).reduce((a, b) => a + b) / meetings.length;
  }
}

final _womenStatsProvider = FutureProvider.autoDispose<_WomenStats>((ref) async {
  final user = ref.watch(requireUserProvider);
  final women = ref.watch(womenRepositoryProvider);
  final r = await Future.wait<Object>([
    women.count(user),
    women.count(user, active: true),
    ref.watch(attendanceRepositoryProvider).summaries(limit: 16),
    women.topBy(user, 'totalPresent'),
    women.topBy(user, 'consecutiveAbsences'),
  ]);
  return _WomenStats(
    total: r[0] as int,
    active: r[1] as int,
    meetings: r[2] as List<MeetingSummary>,
    mostRegular: (r[3] as List<Woman>).where((w) => w.totalPresent > 0).toList(),
    mostAbsent: (r[4] as List<Woman>).where((w) => w.consecutiveAbsences > 0).toList(),
  );
});

/// إحصائيات السيدات.
class WomenStatsScreen extends ConsumerStatefulWidget {
  const WomenStatsScreen({super.key});

  @override
  ConsumerState<WomenStatsScreen> createState() => _WomenStatsScreenState();
}

class _WomenStatsScreenState extends ConsumerState<WomenStatsScreen> {
  bool _streetsByRate = true;

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(suggestionsProvider(
            const SuggestionQuery(type: SuggestionType.phone)))
        .value
        ?.length;
    final home = ref.watch(suggestionsProvider(
            const SuggestionQuery(type: SuggestionType.homeVisit)))
        .value
        ?.length;
    final streets = ref.watch(streetsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('إحصائيات السيدات')),
      body: AsyncBody(
        value: ref.watch(_womenStatsProvider),
        onRetry: () => ref.invalidate(_womenStatsProvider),
        builder: (s) {
          final latest = s.meetings.isEmpty ? null : s.meetings.first;
          final streetRows = [
            for (final st in streets)
              if (latest?.byStreet[st.id] case final c?)
                (st.name, c.present + c.absent == 0 ? 0.0 : c.present / (c.present + c.absent),
                    '(${c.present}/${c.present + c.absent})'),
          ]..sort((a, b) => _streetsByRate ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));

          return ListView(padding: const EdgeInsets.all(16), children: [
            StatCard(icon: Icons.groups, title: 'إجمالي السيدات', value: '${s.total}'),
            const SizedBox(height: 10),
            StatCard(icon: Icons.check, title: 'النشطات', value: '${s.active}'),
            const SizedBox(height: 10),
            StatCard(icon: Icons.percent, title: 'متوسط نسبة الحضور',
                subtitle: 'متوسط عدد الحاضرات ${s.averageAttendees.toStringAsFixed(1)}',
                value: percent(s.averageRate),
                color: AppColors.present, background: AppColors.presentLight),
            const SizedBox(height: 10),
            StatCard(icon: Icons.phone_in_talk, title: 'يحتجن افتقاد تليفوني',
                value: '${phone ?? '—'}',
                color: AppColors.warning, background: AppColors.warningLight,
                onTap: () => context.go(Routes.followUps)),
            const SizedBox(height: 10),
            StatCard(icon: Icons.home, title: 'يحتجن افتقاد منزلي',
                value: '${home ?? '—'}',
                color: AppColors.home, background: AppColors.homeLight,
                onTap: () => context.go(Routes.followUps)),
            const SectionTitle('الحضور حسب الأربعاء'),
            AttendanceTrendChart(meetings: s.meetings),
            SectionTitle(
              latest == null
                  ? 'الحضور حسب الشارع'
                  : 'الحضور حسب الشارع (${Dates.display(Dates.parseDayId(latest.meetingId))})',
              trailing: TextButton(
                onPressed: () => setState(() => _streetsByRate = !_streetsByRate),
                child: Text(_streetsByRate ? 'ترتيب أبجدي' : 'ترتيب بالنسبة'),
              ),
            ),
            if (streetRows.isEmpty)
              const Text('لا توجد بيانات بعد', style: TextStyle(fontSize: 17))
            else
              RateBars(rows: streetRows),
            const SectionTitle('الأكثر انتظاماً'),
            _WomenList(women: s.mostRegular, trailing: (w) => '${w.totalPresent} مرة'),
            const SectionTitle('غياب متكرر'),
            _WomenList(
                women: s.mostAbsent,
                trailing: (w) => '${w.consecutiveAbsences} متتالية',
                color: AppColors.absent),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }
}

class _WomenList extends StatelessWidget {
  const _WomenList({required this.women, required this.trailing, this.color = AppColors.present});
  final List<Woman> women;
  final String Function(Woman) trailing;
  final Color color;

  @override
  Widget build(BuildContext context) => women.isEmpty
      ? const Text('لا يوجد', style: TextStyle(fontSize: 17))
      : Card(
          child: Column(children: [
            for (final w in women)
              ListTile(
                title: Text(w.fullName),
                subtitle: Text(w.streetName),
                trailing: Text(trailing(w),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
                onTap: () => context.push(Routes.woman(w.id)),
              ),
          ]),
        );
}
