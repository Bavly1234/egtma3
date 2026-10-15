import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/business_rules.dart';
import '../../../core/constants/enums.dart';
import '../../../core/services/sync_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/simple_charts.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../users/data/users_repository.dart';
import '../data/servant_attendance_repository.dart';

/// أبونا takes the servants' attendance for a Wednesday.
class ServantAttendanceScreen extends ConsumerStatefulWidget {
  const ServantAttendanceScreen({super.key});

  @override
  ConsumerState<ServantAttendanceScreen> createState() => _State();
}

class _State extends ConsumerState<ServantAttendanceScreen> {
  DateTime _date = Dates.currentOrLastMeeting(DateTime.now());

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: Dates.nextMeeting(now),
      selectableDayPredicate: (d) => d.weekday == BusinessRules.meetingWeekday,
      helpText: 'اختار يوم الأربعاء',
    );
    if (d != null) setState(() => _date = d);
  }

  void _mark(AppUser servant, AttendanceStatus? current, AttendanceStatus status) {
    final repo = ref.read(servantAttendanceRepositoryProvider);
    final meetingId = Dates.dayId(_date);
    final write = current == status
        ? repo.clear(meetingId, servant.id) // tap again = undo
        : repo.mark(meetingId, servant, status, ref.read(requireUserProvider));
    ref.read(syncControllerProvider.notifier).track(write);
  }

  @override
  Widget build(BuildContext context) {
    final servants = ref.watch(activeServantsProvider);
    final statuses = ref.watch(servantMeetingProvider(Dates.dayId(_date))).value ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('حضور الخادمات'),
        actions: const [SyncStatusChip()],
      ),
      body: AsyncBody(
        value: servants,
        builder: (list) {
          final present = list.where((s) => statuses[s.id] == AttendanceStatus.present).length;
          final absent = list.where((s) => statuses[s.id] == AttendanceStatus.absent).length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('${Dates.weekdayAr(_date)}  ${Dates.display(_date)}'),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AttendanceDonut(present: present, absent: absent,
                    title: 'من ${list.length} خادمة'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('اضغط "حاضرة" أو "غائبة" — والضغط تاني على نفس الزرار يلغيه.',
                style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const EmptyState(icon: Icons.badge, title: 'لا توجد خادمات بعد'),
            for (final s in list)
              _ServantRow(
                servant: s,
                status: statuses[s.id],
                onMark: (st) => _mark(s, statuses[s.id], st),
              ),
          ]);
        },
      ),
    );
  }
}

class _ServantRow extends StatelessWidget {
  const _ServantRow({required this.servant, required this.status, required this.onMark});
  final AppUser servant;
  final AttendanceStatus? status;
  final ValueChanged<AttendanceStatus> onMark;

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, AttendanceStatus s, Color c) {
      final on = status == s;
      return SizedBox(
        width: 96,
        height: 56,
        child: on
            ? FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c, padding: EdgeInsets.zero),
                onPressed: () => onMark(s),
                child: Text(label))
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: c,
                    side: BorderSide(color: c, width: 2),
                    padding: EdgeInsets.zero),
                onPressed: () => onMark(s),
                child: Text(label)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        color: switch (status) {
          AttendanceStatus.present => AppColors.presentLight,
          AttendanceStatus.absent => AppColors.absentLight,
          null => null,
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.badge, color: AppColors.primary, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(servant.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            btn('حاضرة', AttendanceStatus.present, AppColors.present),
            const SizedBox(width: 8),
            btn('غائبة', AttendanceStatus.absent, AppColors.absent),
          ]),
        ),
      ),
    );
  }
}
