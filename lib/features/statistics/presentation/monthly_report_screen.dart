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
import '../../../core/widgets/simple_charts.dart';

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
          MonthPicker(month: _month, onChanged: (m) => setState(() => _month = m)),
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
              final f = d.followUps;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionTitle('اجتماعات الأربعاء'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          AttendanceDonut(
                              present: present,
                              absent: absent,
                              title: '${d.meetings.length} اجتماع في الشهر'),
                          const SizedBox(height: 16),
                          WeeklyBars(items: [
                            for (final m in d.meetings.reversed)
                              (
                                '${Dates.parseDayId(m.meetingId).day}/${Dates.parseDayId(m.meetingId).month}',
                                m.present
                              ),
                          ]),
                        ]),
                      ),
                    ),
                    const SectionTitle('الافتقاد'),
                    TileRow(
                      NumberTile(
                          icon: Icons.task_alt,
                          label: 'افتقاد اتعمل',
                          value: '${f.completed}',
                          color: AppColors.present,
                          background: AppColors.presentLight),
                      NumberTile(
                          icon: Icons.hourglass_bottom,
                          label: 'افتقاد لسه',
                          value: '${f.pending}',
                          color: AppColors.warning,
                          background: AppColors.warningLight),
                    ),
                    const SectionTitle('الخادمات'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: d.servants.isEmpty
                            ? const Text('لا توجد خادمات',
                                style: TextStyle(fontSize: 18))
                            : Column(children: [
                                for (final s in d.servants)
                                  CountBar(
                                    label:
                                        '${s.servantName} (${s.assignedWomen} سيدة)',
                                    count: s.meetingPresent,
                                    total: s.meetingPresent + s.meetingAbsent,
                                    extra:
                                        'اتصلت ${s.followUps.calls} • زارت ${s.followUps.visits}',
                                  ),
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
                                  'متأخر أكثر من أسبوع'
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
