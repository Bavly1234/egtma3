import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../auth/data/auth_repository.dart';
import '../../excel/data/excel_export_service.dart';
import '../../statistics/domain/stats_models.dart';
import '../../users/data/users_repository.dart';
import '../data/stats_repository.dart';
import 'charts.dart';

/// Monthly data bundle for the full report.
class MonthlyReportData {
  const MonthlyReportData({
    required this.meetings,
    required this.followUps,
    required this.servants,
    required this.totalWomen,
    required this.activeWomen,
  });
  final List<MeetingSummary> meetings;
  final FollowUpCounts followUps;
  final List<ServantStats> servants;
  final int totalWomen;
  final int activeWomen;
}

final _monthlyReportProvider = FutureProvider.autoDispose
    .family<MonthlyReportData, DateTime>((ref, month) async {
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);
  final range = DateRange(from, to);
  final repo = ref.watch(statsRepositoryProvider);
  final now = DateTime.now();
  final users = await AppFailure.guard(ref.watch(allUsersProvider.future));
  final servants =
      users.where((u) => u.isServant && u.active).toList();
  final meetings = await ref
      .watch(attendanceRepositoryProvider)
      .summaries(limit: 6, fromId: range.fromId, toId: range.toIdInclusive);
  final results = await Future.wait([
    repo.followUpCounts(range: range, now: now),
    Future.wait(servants.map((s) => repo.servantStats(
        s, StatsFilter(range: range), now))),
    repo.overview(ref.watch(requireUserProvider), now,
        range: range, servants: servants.length),
  ]);
  final overview = results[2] as OverviewStats;
  return MonthlyReportData(
    meetings: meetings,
    followUps: results[0] as FollowUpCounts,
    servants: (results[1] as List<ServantStats>)
      ..sort((a, b) => b.attendanceRate.compareTo(a.attendanceRate)),
    totalWomen: overview.totalWomen,
    activeWomen: overview.activeWomen,
  );
});

/// Full monthly report (item 4): meetings, follow-ups, per-servant table,
/// with Excel export. Open to every active servant.
class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  ConsumerState<MonthlyReportScreen> createState() => _State();
}

class _State extends ConsumerState<MonthlyReportScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  void _shift(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
      });

  String get _title => '${_month.month}/${_month.year}';

  Future<void> _export(
      MonthlyReportData d, List<List<Object?>> Function() rowsFor,
      List<String> headers, String suffix) async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final path = await ref.read(excelExportServiceProvider).save(
          'monthly_report_${_month.year}_${_month.month}_$suffix',
          'التقرير الشهري',
          headers,
          rowsFor());
      if (mounted) AppToast.success(context, 'تم حفظ الملف ✅\n$path');
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_monthlyReportProvider(_month));
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير الشهري')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                IconButton(
                  tooltip: 'الشهر السابق',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text('شهر $_title',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'الشهر التالي',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(1),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(minHeight: 6),
          AsyncBody(
            value: data,
            onRetry: () => ref.invalidate(_monthlyReportProvider(_month)),
            builder: (d) {
              var present = 0, absent = 0;
              for (final m in d.meetings) {
                present += m.present;
                absent += m.absent;
              }
              final rate =
                  present + absent == 0 ? 0.0 : present / (present + absent);
              final f = d.followUps;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionTitle('اجتماعات الأربعاء'),
                    StatCard(
                        icon: Icons.percent,
                        title: 'نسبة الحضور',
                        subtitle: '${d.meetings.length} اجتماع',
                        value: percent(rate),
                        color: AppColors.present,
                        background: AppColors.presentLight),
                    const SizedBox(height: 10),
                    AttendanceTrendChart(meetings: d.meetings),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: StatCard(
                              icon: Icons.how_to_reg,
                              title: 'حضور',
                              value: '$present')),
                      const SizedBox(width: 10),
                      Expanded(
                          child: StatCard(
                              icon: Icons.person_off,
                              title: 'غياب',
                              value: '$absent',
                              color: AppColors.absent,
                              background: AppColors.absentLight)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: StatCard(
                              icon: Icons.groups,
                              title: 'السيدات',
                              subtitle: 'النشطات ${d.activeWomen}',
                              value: '${d.totalWomen}')),
                      const SizedBox(width: 10),
                      Expanded(
                          child: StatCard(
                              icon: Icons.volunteer_activism,
                              title: 'الخادمات',
                              value: '${d.servants.length}')),
                    ]),
                    const SectionTitle('الافتقاد'),
                    Row(children: [
                      Expanded(
                          child: StatCard(
                              icon: Icons.phone,
                              title: 'مكالمات',
                              value: '${f.calls}')),
                      const SizedBox(width: 10),
                      Expanded(
                          child: StatCard(
                              icon: Icons.home,
                              title: 'زيارات',
                              value: '${f.visits}',
                              color: AppColors.home,
                              background: AppColors.homeLight)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: StatCard(
                              icon: Icons.task_alt,
                              title: 'افتقاد تم',
                              value: '${f.completed}',
                              color: AppColors.present,
                              background: AppColors.presentLight)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: StatCard(
                              icon: Icons.pending_actions,
                              title: 'لم يتم',
                              subtitle: 'متأخر ${f.overdue}',
                              value: '${f.pending}',
                              color: AppColors.warning,
                              background: AppColors.warningLight)),
                    ]),
                    const SectionTitle('الخادمات'),
                    if (d.servants.isEmpty)
                      const Text('لا توجد خادمات',
                          style: TextStyle(fontSize: 18))
                    else
                      RateBars(rows: [
                        for (final s in d.servants)
                          (s.servantName, s.attendanceRate,
                              '(${s.assignedWomen} سيدة)'),
                      ]),
                    for (final s in d.servants)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.servantName,
                                    style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 6),
                                Wrap(spacing: 16, runSpacing: 4, children: [
                                  Text('السيدات: ${s.assignedWomen}',
                                      style: const TextStyle(fontSize: 16)),
                                  Text('الحضور: ${percent(s.attendanceRate)}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          color: AppColors.present)),
                                  Text('الغياب: ${s.meetingAbsent}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          color: AppColors.absent)),
                                  Text(
                                      'مكالمات: ${s.followUps.calls} — تم ${s.followUps.phoneCompleted}',
                                      style: const TextStyle(fontSize: 16)),
                                  Text(
                                      'زيارات: ${s.followUps.visits} — تم ${s.followUps.homeCompleted}',
                                      style: const TextStyle(fontSize: 16)),
                                  Text('لم يتم: ${s.followUps.pending}',
                                      style: const TextStyle(fontSize: 16)),
                                ]),
                              ]),
                        ),
                      ),
                    const SectionTitle('تصدير'),
                    MenuTile(
                        icon: Icons.file_download,
                        title: 'تصدير اجتماعات الشهر',
                        onTap: () => _export(
                                d,
                                () => [
                                      for (final m in d.meetings)
                                        [
                                          Dates.display(Dates.parseDayId(
                                              m.meetingId)),
                                          m.present,
                                          m.absent,
                                          '${(m.rate * 100).round()}%',
                                        ],
                                    ],
                                ['التاريخ', 'حضور', 'غياب', 'النسبة'],
                                'meetings')),
                    MenuTile(
                        icon: Icons.file_download,
                        title: 'تصدير الخادمات',
                        onTap: () => _export(
                                d,
                                () => [
                                      for (final s in d.servants)
                                        [
                                          s.servantName,
                                          s.assignedWomen,
                                          (s.attendanceRate * 100).round(),
                                          s.meetingAbsent,
                                          s.withConsecutiveAbsences,
                                          s.followUps.calls,
                                          s.followUps.phoneCompleted,
                                          s.followUps.visits,
                                          s.followUps.homeCompleted,
                                          s.followUps.pending,
                                          s.followUps.overdue,
                                        ],
                                    ],
                                [
                                  'الخادمة',
                                  'السيدات',
                                  'نسبة الحضور %',
                                  'مرات الغياب',
                                  'غياب متتالي',
                                  'مكالمات',
                                  'افتقاد تليفوني تم',
                                  'زيارات',
                                  'افتقاد منزلي تم',
                                  'لم يتم',
                                  'متأخر'
                                ],
                                'servants')),
                    const SizedBox(height: 32),
                  ]);
            },
          ),
        ]),
      ),
    );
  }
}
