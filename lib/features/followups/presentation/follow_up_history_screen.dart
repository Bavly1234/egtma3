import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/states.dart';
import '../../women/data/women_repository.dart';
import '../../women/presentation/woman_providers.dart';

/// Full call / visit / note history of one woman.
class FollowUpHistoryScreen extends ConsumerWidget {
  const FollowUpHistoryScreen({super.key, required this.womanId});
  final String womanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final woman = ref.watch(womanProvider(womanId)).value;
    return Scaffold(
      appBar: AppBar(title: Text('سجل الافتقاد — ${woman?.fullName ?? ''}')),
      body: AsyncBody(
        value: ref.watch(womanFollowUpsProvider(womanId)),
        builder: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.history, title: 'لا يوجد افتقاد مسجل بعد')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final f = items[i];
                  final color = switch (f.type) {
                    FollowUpType.phoneCall => AppColors.primary,
                    FollowUpType.homeVisit => AppColors.home,
                    FollowUpType.note => AppColors.gold,
                  };
                  return Card(
                    child: ListTile(
                      leading: Icon(f.type.icon, color: color, size: 32),
                      title: Text(
                          '${f.type.label}${f.type == FollowUpType.note ? '' : ' — ${f.result.label}'}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${Dates.displayDateTime(f.occurredAt)} • ${f.servantName}'),
                          if (f.notes.isNotEmpty)
                            Text(f.notes,
                                style: const TextStyle(
                                    fontSize: 17, color: AppColors.text)),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
