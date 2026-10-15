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
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../../core/services/sync_status.dart';
import '../../women/domain/woman.dart';
import '../data/auto_absence_service.dart';
import 'attendance_controller.dart';

/// Wednesday attendance: only the present are marked. After the Wednesday
/// 9pm cutoff, every still-unmarked woman is auto-marked absent once.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  final _autoFilled = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFill());
  }

  /// Fills unmarked women as absent once the 9pm cutoff has passed, then runs
  /// the افتقاد rules for the newly-absent women. Idempotent: only missing
  /// records are created, never overwritten.
  void _maybeAutoFill() {
    final date = ref.read(meetingDateProvider);
    final meetingId = Dates.dayId(date);
    if (_autoFilled.contains(meetingId)) return;
    if (!Dates.cutoffPassed(date, DateTime.now())) return;
    _autoFilled.add(meetingId);
    ref.read(syncControllerProvider.notifier).track(ref
        .read(autoAbsenceServiceProvider)
        .runIfDue(ref.read(requireUserProvider), meeting: date));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(meetingDateProvider, (_, _) => _maybeAutoFill());
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
    final absentOnly = ref.watch(absentOnlyProvider);
    final streets = ref.watch(streetsProvider).value ?? const [];
    final me = ref.watch(requireUserProvider);
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
          if (absentOnly) ...[
            const SizedBox(height: 8),
            FilterChip(
              avatar: const Icon(Icons.person_off, size: 20),
              label: const Text('الغائبات فقط — عرض الكل'),
              selected: true,
              onSelected: (_) =>
                  ref.read(absentOnlyProvider.notifier).set(false),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            onChanged: (q) => notifier.set(filter.copyWith(query: q)),
            decoration: const InputDecoration(
              hintText: 'اكتبي اسم السيدة',
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
                    labelText: 'اختاري الشارع',
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
          ]),
          if (!me.isFather) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChip(
                avatar: const Icon(Icons.signpost, size: 20),
                label: const Text('شوارعي بس'),
                selected: filter.servantId == me.id,
                onSelected: (on) => notifier.set(
                    filter.copyWith(servantId: () => on ? me.id : null)),
              ),
            ),
          ],
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

    Future<void> bulkPresent() async {
      final targets = women.where((w) => statuses[w.id] == null).toList();
      final all = targets.isEmpty;
      final list = all ? women : targets;
      final ok = await confirmAction(
        context,
        title: 'تسجيل الكل حاضر',
        message: all
            ? 'سيتم تغيير حالة كل السيدات المعروضات (${list.length}) إلى حاضر.'
            : 'سيتم تسجيل ${list.length} سيدة لم تُسجل بعد كحاضر.',
      );
      if (ok) actions.markAll(list, AttendanceStatus.present);
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: bulkPresent,
              icon: const Icon(Icons.done_all, color: AppColors.present),
              label: const Text('الكل حاضر'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
              'علّمي الحاضرات فقط — الغياب يُسجل تلقائياً الأربعاء 9م. الحفظ تلقائي حتى بدون إنترنت',
              textAlign: TextAlign.center,
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
    final servantName =
        ref.watch(streetMapProvider)[woman.streetId]?.servantName;
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(children: [
          Row(children: [
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
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.badge, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'الخادمة (حسب الشارع): ${servantName ?? 'غير معينة'}',
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textMuted),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            _StatusButton(
              label: 'حاضر',
              selected: status == AttendanceStatus.present,
              color: AppColors.present,
              onTap: () => actions.mark(woman, AttendanceStatus.present),
            ),
          ]),
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
