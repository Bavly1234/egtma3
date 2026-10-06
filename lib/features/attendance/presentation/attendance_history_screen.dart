import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_record.dart';
import 'attendance_controller.dart';

final _historyProvider = FutureProvider.autoDispose<List<MeetingSummary>>(
    (ref) => ref.watch(attendanceRepositoryProvider).summaries(limit: 52));

/// Past Wednesday meetings with counts; tap to open that meeting's sheet.
class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(requireUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الاجتماعات')),
      body: AsyncBody(
        value: ref.watch(_historyProvider),
        onRetry: () => ref.invalidate(_historyProvider),
        builder: (items) => items.isEmpty
            ? const EmptyState(icon: Icons.event_busy, title: 'لا توجد اجتماعات مسجلة')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final m = items[i];
                  final mine = user.isFather ? null : m.byServant[user.id];
                  final present = mine?.present ?? m.present;
                  final absent = mine?.absent ?? m.absent;
                  final total = present + absent;
                  final rate = total == 0 ? 0.0 : present / total;
                  final date = Dates.parseDayId(m.meetingId);
                  return Card(
                    child: ListTile(
                      title: Text('${Dates.weekdayAr(date)}  ${Dates.display(date)}'),
                      subtitle: Text('حاضر $present  •  غائب $absent'),
                      trailing: Text(percent(rate),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                      onTap: () {
                        ref.read(meetingDateProvider.notifier).set(date);
                        context.go(Routes.attendance);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
