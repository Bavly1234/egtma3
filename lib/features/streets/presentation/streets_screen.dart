import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/arabic_text.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../statistics/data/stats_repository.dart';
import '../../statistics/domain/stats_models.dart';
import '../../users/presentation/servant_picker.dart';
import '../../women/domain/women_filter.dart';
import '../../women/presentation/women_list_controller.dart';
import '../data/street_repository.dart';

final _streetStatsProvider = FutureProvider.autoDispose<List<StreetStats>>((ref) async {
  final streets = await ref.watch(streetsProvider.future);
  final meetingId = Dates.dayId(Dates.currentOrLastMeeting(DateTime.now()));
  return ref.watch(statsRepositoryProvider).streetStats(streets, meetingId);
});

/// الشوارع: list, search, per-street statistics and bulk assignment.
class StreetsScreen extends ConsumerStatefulWidget {
  const StreetsScreen({super.key});

  @override
  ConsumerState<StreetsScreen> createState() => _StreetsScreenState();
}

class _StreetsScreenState extends ConsumerState<StreetsScreen> {
  String _q = '';
  bool _byName = true;

  Future<void> _addOrRename({String? id, String? current}) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(id == null ? 'إضافة شارع' : 'تعديل اسم الشارع'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'اسم الشارع')),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final repo = ref.read(streetRepositoryProvider);
    await runGuarded(
        context, () => id == null ? repo.add(name) : repo.rename(id, name),
        successMessage: 'تم الحفظ');
    ref.invalidate(_streetStatsProvider);
  }

  Future<void> _assign(StreetStats s) async {
    final streets = ref.read(streetMapProvider);
    final current = streets[s.streetId];
    final choice = await pickServant(context, ref,
        allowNone: true,
        title: 'الخادمة المسؤولة عن ${s.name}'
        '${current?.servantName == null ? '' : ' (الحالية: ${current!.servantName})'}');
    if (choice == null || !mounted) return;
    await runGuarded(
      context,
      () => ref.read(streetRepositoryProvider).setServant(
          s.streetId, choice.value, ref.read(requireUserProvider)),
      successMessage: choice.value == null
          ? 'تم إلغاء مسؤولة الشارع'
          : 'أصبحت ${choice.value!.name} مسؤولة عن ${s.name}',
    );
    ref.invalidate(_streetStatsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(_streetStatsProvider);
    final streetMap = ref.watch(streetMapProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الشوارع')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrRename(),
        icon: const Icon(Icons.add_road),
        label: const Text('إضافة شارع', style: TextStyle(fontSize: 18)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _q = ArabicText.normalize(v)),
                decoration: const InputDecoration(
                    hintText: 'بحث عن شارع', prefixIcon: Icon(Icons.search)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() => _byName = !_byName),
              child: Text(_byName ? 'ترتيب بالحضور' : 'ترتيب أبجدي'),
            ),
          ]),
        ),
        Expanded(
          child: AsyncBody(
            value: stats,
            onRetry: () => ref.invalidate(_streetStatsProvider),
            builder: (list) {
              final rows = list
                  .where((s) => _q.isEmpty || ArabicText.normalize(s.name).contains(_q))
                  .toList()
                ..sort((a, b) => _byName ? a.name.compareTo(b.name) : b.rate.compareTo(a.rate));
              if (rows.isEmpty) {
                return const EmptyState(icon: Icons.signpost, title: 'لا توجد شوارع');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _StreetCard(
                  s: rows[i],
                  servantName: streetMap[rows[i].streetId]?.servantName,
                  onOpen: () {
                    ref.read(womenFilterProvider.notifier)
                        .set(WomenFilter(streetId: rows[i].streetId));
                    context.go(Routes.women);
                  },
                  onRename: () => _addOrRename(id: rows[i].streetId, current: rows[i].name),
                  onAssign: () => _assign(rows[i]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _StreetCard extends StatelessWidget {
  const _StreetCard({
    required this.s,
    required this.servantName,
    required this.onOpen,
    required this.onRename,
    required this.onAssign,
  });
  final StreetStats s;
  final String? servantName;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.signpost, color: AppColors.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(s.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                PopupMenuButton<int>(
                  tooltip: 'خيارات',
                  onSelected: (v) => v == 0 ? onRename() : onAssign(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 0, child: Text('تعديل الاسم')),
                    PopupMenuItem(value: 1, child: Text('تعيين خادمة مسؤولة')),
                  ],
                ),
              ]),
              const SizedBox(height: 4),
              Text('الخادمة المسؤولة: ${servantName ?? 'غير معينة'}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: servantName == null
                          ? AppColors.absent
                          : AppColors.primary)),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 6, children: [
                Text('السيدات: ${s.women}', style: const TextStyle(fontSize: 17)),
                Text('الحضور: ${percent(s.rate)}',
                    style: const TextStyle(fontSize: 17, color: AppColors.present)),
                Text('الغائبات: ${s.missing}',
                    style: const TextStyle(fontSize: 17, color: AppColors.absent)),
                Text('افتقاد مطلوب: ${s.activeSuggestions}',
                    style: const TextStyle(fontSize: 17, color: AppColors.warning)),
              ]),
            ]),
          ),
        ),
      );
}
