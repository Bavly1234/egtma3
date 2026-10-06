import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../conferences/data/conference_repository.dart';
import '../../followups/data/follow_up_repository.dart';
import '../../statistics/data/stats_repository.dart';
import '../../statistics/domain/stats_models.dart';
import '../../statistics/presentation/stats_filter_bar.dart';
import '../../users/data/users_repository.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import '../../women/domain/women_filter.dart';
import '../../women/presentation/women_list_controller.dart';
import '../data/excel_export_service.dart';

/// Excel export. "Filtered women" uses exactly the filters currently applied
/// on the women list.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  RangePreset _preset = RangePreset.quarter;
  late DateRange _range = _preset.resolve(DateTime.now());
  bool _busy = false;

  static const _womenHeaders = [
    'الاسم', 'الشارع', 'العنوان', 'التليفون', 'تاريخ الميلاد', 'الخادمة',
    'نشطة', 'غياب متتالي', 'مرات الحضور', 'مرات الغياب', 'مكالمات', 'زيارات', 'ملاحظات',
  ];

  List<Object?> _womanRow(Woman w) => [
        w.fullName, w.streetName, w.address, w.phone, w.dateOfBirth,
        w.assignedServantName ?? '', w.active, w.consecutiveAbsences,
        w.totalPresent, w.totalAbsent, w.phoneCalls, w.homeVisits, w.notes,
      ];

  Future<void> _run(Future<String> Function() job) async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final path = await job();
      if (mounted) AppToast.success(context, 'تم حفظ الملف ✅\n$path');
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<String> _exportWomen(WomenFilter filter, String name) async {
    final user = ref.read(requireUserProvider);
    final women = await ref.read(womenRepositoryProvider).all(user, filter);
    return ref.read(excelExportServiceProvider)
        .save(name, 'السيدات', _womenHeaders, women.map(_womanRow).toList());
  }

  Future<String> _exportAttendance() async {
    final user = ref.read(requireUserProvider);
    final records = await ref.read(attendanceRepositoryProvider)
        .forMeetings(_range.fromId, _range.toIdInclusive, user);
    final women = {for (final w in await ref.read(womenRepositoryProvider)
        .all(user, WomenFilter.empty)) w.id: w};
    records.sort((a, b) => a.meetingId.compareTo(b.meetingId));
    return ref.read(excelExportServiceProvider).save('attendance', 'الحضور',
        ['التاريخ', 'الاسم', 'الشارع', 'الحالة'], [
      for (final r in records)
        [Dates.display(Dates.parseDayId(r.meetingId)), women[r.womanId]?.fullName ?? r.womanId,
          women[r.womanId]?.streetName ?? '', r.status.label],
    ]);
  }

  Future<String> _exportFollowUps() async {
    final user = ref.read(requireUserProvider);
    final list = await ref.read(followUpRepositoryProvider)
        .inRange(user, from: _range.from, to: _range.to);
    return ref.read(excelExportServiceProvider).save('followups', 'الافتقاد',
        ['التاريخ', 'الوقت', 'السيدة', 'الخادمة', 'النوع', 'النتيجة', 'ملاحظات'], [
      for (final f in list)
        [Dates.display(f.occurredAt),
          '${f.occurredAt.hour.toString().padLeft(2, '0')}:${f.occurredAt.minute.toString().padLeft(2, '0')}',
          f.womanName, f.servantName, f.type.label, f.result.label, f.notes],
    ]);
  }

  Future<String> _exportConference() async {
    final user = ref.read(requireUserProvider);
    final confs = await ref.read(conferencesProvider.future);
    if (confs.isEmpty) throw const AppFailure('لا توجد مؤتمرات');
    if (!mounted) return '';
    final c = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اختاري المؤتمر'),
        children: [
          for (final c in confs)
            SimpleDialogOption(
              padding: const EdgeInsets.all(16),
              onPressed: () => Navigator.pop(ctx, c.id),
              child: Text(c.name, style: const TextStyle(fontSize: 18)),
            ),
        ],
      ),
    );
    if (c == null) return 'تم الإلغاء';
    final conf = confs.firstWhere((x) => x.id == c);
    final records = await ref.read(conferenceRepositoryProvider).allAttendance(c, user);
    final women = {for (final w in await ref.read(womenRepositoryProvider)
        .all(user, WomenFilter.empty)) w.id: w};
    final byWoman = <String, Map<String, AttendanceStatus>>{};
    for (final r in records) {
      (byWoman[r.womanId] ??= {})[r.conferenceDayId] = r.status;
    }
    return ref.read(excelExportServiceProvider).save('conference', 'حضور المؤتمر', [
      'الاسم', 'الشارع',
      for (final d in conf.days) '${d.label} ${Dates.display(d.date)}',
      'عدد أيام الحضور',
    ], [
      for (final e in byWoman.entries)
        [
          women[e.key]?.fullName ?? e.key,
          women[e.key]?.streetName ?? '',
          for (final d in conf.days) e.value[d.id]?.label ?? '',
          e.value.values.where((s) => s == AttendanceStatus.present).length,
        ],
    ]);
  }

  Future<String> _exportStats() async {
    final users = await ref.read(allUsersProvider.future);
    final repo = ref.read(statsRepositoryProvider);
    final f = StatsFilter(range: _range);
    final now = DateTime.now();
    final stats = await Future.wait(users
        .where((u) => u.isServant && u.active)
        .map((s) => repo.servantStats(s, f, now)));
    return ref.read(excelExportServiceProvider).save('statistics', 'إحصائيات الخادمات', [
      'الخادمة', 'السيدات', 'نسبة الحضور %', 'مرات الغياب', 'غياب متتالي',
      'مكالمات', 'افتقاد تليفوني تم', 'زيارات', 'افتقاد منزلي تم', 'لم يتم', 'متأخر',
    ], [
      for (final s in stats)
        [s.servantName, s.assignedWomen, (s.attendanceRate * 100).round(), s.meetingAbsent,
          s.withConsecutiveAbsences, s.followUps.calls, s.followUps.phoneCompleted,
          s.followUps.visits, s.followUps.homeCompleted, s.followUps.pending, s.followUps.overdue],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(womenFilterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تصدير إلى Excel')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_busy) const LinearProgressIndicator(minHeight: 6),
          const SectionTitle('السيدات'),
          MenuTile(
            icon: Icons.groups,
            title: 'كل السيدات',
            onTap: () => _run(() => _exportWomen(WomenFilter.empty, 'women_all')),
          ),
          MenuTile(
            icon: Icons.filter_alt,
            title: 'السيدات حسب الفلاتر الحالية',
            subtitle: filter.isEmpty
                ? 'لا توجد فلاتر — اختاري الفلاتر من شاشة السيدات'
                : '${filter.activeCount} فلتر مطبق',
            onTap: () => _run(() => _exportWomen(filter, 'women_filtered')),
          ),
          const SectionTitle('حسب الفترة'),
          RangeSelector(
            preset: _preset,
            range: _range,
            onChanged: (p, r) => setState(() {
              _preset = p;
              _range = r;
            }),
          ),
          const SizedBox(height: 12),
          MenuTile(icon: Icons.how_to_reg, title: 'الحضور', onTap: () => _run(_exportAttendance)),
          MenuTile(
              icon: Icons.volunteer_activism,
              title: 'الافتقاد (المكالمات والزيارات)',
              onTap: () => _run(_exportFollowUps)),
          MenuTile(icon: Icons.bar_chart, title: 'إحصائيات الخادمات', onTap: () => _run(_exportStats)),
          const SectionTitle('المؤتمرات'),
          MenuTile(
              icon: Icons.event,
              title: 'حضور مؤتمر',
              color: AppColors.gold,
              onTap: () => _run(_exportConference)),
        ]),
      ),
    );
  }
}
