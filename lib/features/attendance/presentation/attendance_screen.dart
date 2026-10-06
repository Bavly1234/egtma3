import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../streets/data/street_repository.dart';
import '../../users/data/users_repository.dart';
import '../../women/domain/woman.dart';
import 'attendance_controller.dart';

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final women = ref.watch(visibleAttendanceWomenProvider);
    final statuses = ref.watch(meetingStatusesProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('اجتماع الأربعاء'),
        actions: [
          const SyncStatusChip(),
          IconButton(
            tooltip: 'سجل الاجتماعات',
            icon: const Icon(Icons.history, size: 28),
            onPressed: () => context.push(Routes.attendanceHistory),
          ),
        ],
      ),
      body: Column(children: [
        const _Header(),
        Expanded(
          child: AsyncBody(
            value: women,
            onRetry: () => ref.invalidate(attendanceWomenProvider),
            builder: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.group_off, title: 'لا توجد سيدات للعرض')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => i == 0
                        ? _Summary(women: list, statuses: statuses)
                        : _AttendanceRow(
                            woman: list[i - 1],
                            status: statuses[list[i - 1].id]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final current = ref.read(meetingDateProvider);
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 2),
      lastDate: Dates.nextMeeting(now),
      selectableDayPredicate: (d) => d.weekday == BusinessRules.meetingWeekday,
      helpText: 'اختاري يوم الأربعاء',
    );
    if (d != null) ref.read(meetingDateProvider.notifier).set(d);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(meetingDateProvider);
    final filter = ref.watch(attendanceFilterProvider);
    final streets = ref.watch(streetsProvider).value ?? const [];
    final servants = ref.watch(activeServantsProvider).value ?? const [];
    final notifier = ref.read(attendanceFilterProvider.notifier);

    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(children: [
          OutlinedButton.icon(
            onPressed: () => _pickDate(context, ref),
            icon: const Icon(Icons.calendar_month),
            label: Text('${Dates.weekdayAr(date)}  ${Dates.display(date)}'),
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (q) => notifier.set(filter.copyWith(query: q)),
            decoration: const InputDecoration(
              hintText: 'بحث بالاسم',
              prefixIcon: Icon(Icons.search),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: filter.streetId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'الشارع',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('الكل')),
                  for (final s in streets)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) =>
                    notifier.set(filter.copyWith(streetId: () => v)),
              ),
            ),
            ...[
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: filter.servantId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'الخادمة',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('الكل')),
                    for (final s in servants)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) =>
                      notifier.set(filter.copyWith(servantId: () => v)),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.women, required this.statuses});
  final List<Woman> women;
  final Map<String, AttendanceStatus> statuses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var present = 0, absent = 0;
    for (final w in women) {
      switch (statuses[w.id]) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.absent:
          absent++;
        case null:
          break;
      }
    }
    final unmarked = women.length - present - absent;
    final rate = present + absent == 0 ? 0.0 : present / (present + absent);
    final actions = ref.read(attendanceActionsProvider);

    Future<void> bulk(AttendanceStatus s) async {
      final targets = women.where((w) => statuses[w.id] == null).toList();
      final all = targets.isEmpty;
      final list = all ? women : targets;
      final ok = await confirmAction(
        context,
        title: s == AttendanceStatus.present ? 'تسجيل الكل حاضر' : 'تسجيل الكل غائب',
        message: all
            ? 'سيتم تغيير حالة كل السيدات المعروضات (${list.length}).'
            : 'سيتم تسجيل ${list.length} سيدة لم تُسجل بعد كـ "${s.label}".',
      );
      if (ok) actions.markAll(list, s);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _count('حاضر', present, AppColors.present),
            _count('غائب', absent, AppColors.absent),
            _count('لم تُسجل', unmarked, AppColors.textMuted),
            _count('النسبة', null, AppColors.primary, text: percent(rate)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => bulk(AttendanceStatus.present),
                icon: const Icon(Icons.done_all, color: AppColors.present),
                label: const Text('الكل حاضر'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => bulk(AttendanceStatus.absent),
                icon: const Icon(Icons.remove_done, color: AppColors.absent),
                label: const Text('الكل غائب'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('يتم الحفظ تلقائياً — حتى بدون إنترنت',
              style: TextStyle(fontSize: 15, color: AppColors.textMuted)),
        ]),
      ),
    );
  }

  Widget _count(String label, int? n, Color c, {String? text}) => Column(children: [
        Text(text ?? '$n',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c)),
        Text(label, style: const TextStyle(fontSize: 15)),
      ]);
}

class _AttendanceRow extends ConsumerWidget {
  const _AttendanceRow({required this.woman, required this.status});
  final Woman woman;
  final AttendanceStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(attendanceActionsProvider);
    final bg = switch (status) {
      AttendanceStatus.present => AppColors.presentLight,
      AttendanceStatus.absent => AppColors.absentLight,
      null => Colors.white,
    };
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onLongPress: status == null
                  ? null
                  : () async {
                      final ok = await confirmAction(context,
                          title: 'مسح التسجيل',
                          message: 'مسح تسجيل حضور "${woman.fullName}"؟');
                      if (ok) actions.clear(woman);
                    },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(woman.fullName,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                if (woman.streetName.isNotEmpty)
                  Text(woman.streetName,
                      style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
              ]),
            ),
          ),
          _StatusButton(
            label: 'حاضر',
            selected: status == AttendanceStatus.present,
            color: AppColors.present,
            onTap: () => actions.mark(woman, AttendanceStatus.present),
          ),
          const SizedBox(width: 8),
          _StatusButton(
            label: 'غائب',
            selected: status == AttendanceStatus.absent,
            color: AppColors.absent,
            onTap: () => actions.mark(woman, AttendanceStatus.absent),
          ),
        ]),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: SizedBox(
          width: 84,
          height: 56,
          child: selected
              ? FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: color,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(84, 56)),
                  onPressed: onTap,
                  child: Text(label),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color, width: 2),
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      minimumSize: const Size(84, 56)),
                  onPressed: onTap,
                  child: Text(label),
                ),
        ),
      );
}
