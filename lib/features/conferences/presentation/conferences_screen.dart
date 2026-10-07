import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conference_repository.dart';

class ConferencesScreen extends ConsumerWidget {
  const ConferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(requireUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('المؤتمرات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.conferenceNew),
        icon: const Icon(Icons.add),
        label: const Text('مؤتمر جديد', style: TextStyle(fontSize: 18)),
      ),
      body: AsyncBody(
        value: ref.watch(conferencesProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.event, title: 'لا توجد مؤتمرات بعد')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final c = list[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          const Icon(Icons.event, color: AppColors.gold, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(c.name,
                                  style: const TextStyle(
                                      fontSize: 21, fontWeight: FontWeight.w800))),
                        ]),
                        const SizedBox(height: 8),
                        for (final d in c.days)
                          Text('${d.label}: ${Dates.weekdayAr(d.date)} ${Dates.display(d.date)}',
                              style: const TextStyle(fontSize: 17)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => context.push(Routes.conference(c.id)),
                              icon: const Icon(Icons.how_to_reg),
                              label: const Text('الحضور'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(Routes.conferenceStats(c.id)),
                              icon: const Icon(Icons.bar_chart),
                              label: const Text('الإحصائيات'),
                            ),
                          ),
                        ]),
                        if (user.isFather)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: AppColors.absent),
                              onPressed: () async {
                                final ok = await confirmAction(context,
                                    title: 'حذف المؤتمر',
                                    message: 'حذف "${c.name}"؟ يبقى سجل الحضور محفوظاً.',
                                    confirmLabel: 'حذف',
                                    destructive: true);
                                if (ok && context.mounted) {
                                  await runGuarded(context,
                                      () => ref.read(conferenceRepositoryProvider).delete(c, user),
                                      successMessage: 'تم الحذف');
                                }
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('حذف'),
                            ),
                          ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
