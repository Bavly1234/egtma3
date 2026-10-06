import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../streets/data/street_repository.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import '../../women/domain/women_filter.dart';
import '../../women/presentation/women_list_controller.dart';
import '../data/users_repository.dart';
import 'servant_picker.dart';

final _workloadProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final user = ref.watch(requireUserProvider);
  final users = await ref.watch(allUsersProvider.future);
  final repo = ref.watch(womenRepositoryProvider);
  final servants = users.where((u) => u.isServant && u.active).toList();
  final counts = await Future.wait(
      servants.map((s) => repo.count(user, active: true, servantId: s.id)));
  return {for (var i = 0; i < servants.length; i++) servants[i].id: counts[i]};
});

class _AssignFilter extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final _streetProvider = NotifierProvider<_AssignFilter, String?>(_AssignFilter.new);

final _assignWomenProvider = FutureProvider.autoDispose<List<Woman>>((ref) {
  final street = ref.watch(_streetProvider);
  return ref.watch(womenRepositoryProvider).all(
      ref.watch(requireUserProvider), WomenFilter(active: true, streetId: street),
      max: 1000);
});

/// Assignment: workload overview, multi-select assign, assign by street.
class AssignScreen extends ConsumerStatefulWidget {
  const AssignScreen({super.key});

  @override
  ConsumerState<AssignScreen> createState() => _AssignScreenState();
}

class _AssignScreenState extends ConsumerState<AssignScreen> {
  final _selected = <String>{};

  Future<void> _assignSelected() async {
    final c = await pickServant(context, ref, allowNone: true,
        title: 'تعيين ${_selected.length} سيدة');
    if (c == null || !mounted) return;
    final ok = await runGuarded(
      context,
      () => ref.read(womenRepositoryProvider)
          .assign(_selected.toList(), c.value, ref.read(requireUserProvider)),
      successMessage: 'تم التعيين',
    );
    if (ok) {
      setState(_selected.clear);
      ref.invalidate(_assignWomenProvider);
      ref.invalidate(_workloadProvider);
      ref.invalidate(womenListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servants = ref.watch(activeServantsProvider).value ?? const [];
    final workload = ref.watch(_workloadProvider).value ?? const {};
    final streets = ref.watch(streetsProvider).value ?? const [];
    final street = ref.watch(_streetProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تعيين السيدات')),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _assignSelected,
                  icon: const Icon(Icons.assignment_ind),
                  label: Text('تعيين ${_selected.length} سيدة لخادمة'),
                ),
              ),
            ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionTitle('توزيع العمل الحالي'),
        Card(
          child: Column(children: [
            for (final s in servants)
              ListTile(
                leading: const Icon(Icons.badge),
                title: Text(s.name),
                trailing: Text('${workload[s.id] ?? '…'} سيدة',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
        const SectionTitle('اختاري السيدات'),
        DropdownButtonFormField<String?>(
          initialValue: street,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الشارع'),
          items: [
            const DropdownMenuItem(value: null, child: Text('كل الشوارع')),
            for (final s in streets) DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: (v) {
            setState(_selected.clear);
            ref.read(_streetProvider.notifier).set(v);
          },
        ),
        const SizedBox(height: 8),
        AsyncBody(
          value: ref.watch(_assignWomenProvider),
          builder: (women) => Column(children: [
            Row(children: [
              TextButton(
                onPressed: () => setState(() => _selected.addAll(women.map((w) => w.id))),
                child: const Text('تحديد الكل'),
              ),
              TextButton(
                onPressed: () => setState(_selected.clear),
                child: const Text('إلغاء التحديد'),
              ),
            ]),
            for (final w in women)
              CheckboxListTile(
                value: _selected.contains(w.id),
                onChanged: (v) => setState(
                    () => v == true ? _selected.add(w.id) : _selected.remove(w.id)),
                title: Text(w.fullName),
                subtitle: Text(
                  '${w.streetName} • ${w.assignedServantName ?? 'غير معينة'}',
                  style: TextStyle(
                      color: w.assignedServantId == null ? AppColors.absent : null),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
