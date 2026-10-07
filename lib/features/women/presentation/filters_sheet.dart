import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../streets/data/street_repository.dart';
import '../domain/women_filter.dart';
import 'women_list_controller.dart';

const kMonthsAr = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

Future<void> showWomenFilters(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _FiltersSheet(),
    );

class _FiltersSheet extends ConsumerStatefulWidget {
  const _FiltersSheet();

  @override
  ConsumerState<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<_FiltersSheet> {
  late WomenFilter _f = ref.read(womenFilterProvider);

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<(T?, String)> items,
    required ValueChanged<T?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<T?>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final (v, l) in items)
              DropdownMenuItem(value: v, child: Text(l)),
          ],
          onChanged: onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final streets = ref.watch(streetsProvider).value ?? const [];

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Text('الفلاتر', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            _dropdown<String>(
              label: 'الشارع',
              value: _f.streetId,
              items: [(null, 'كل الشوارع'), for (final s in streets) (s.id, s.name)],
              onChanged: (v) => setState(() => _f = _f.copyWith(streetId: () => v)),
            ),
            _dropdown<bool>(
              label: 'الحالة',
              value: _f.active,
              items: const [(null, 'الكل'), (true, 'نشطة'), (false, 'غير نشطة')],
              onChanged: (v) => setState(() => _f = _f.copyWith(active: () => v)),
            ),
            _dropdown<int>(
              label: 'شهر عيد الميلاد',
              value: _f.birthMonth,
              items: [
                (null, 'كل الشهور'),
                for (var i = 0; i < 12; i++) (i + 1, kMonthsAr[i]),
              ],
              onChanged: (v) =>
                  setState(() => _f = _f.copyWith(birthMonth: () => v)),
            ),
            _dropdown<FollowUpFilter>(
              label: 'الافتقاد',
              value: _f.followUp,
              items: [for (final v in FollowUpFilter.values) (v, v.label)],
              onChanged: (v) => setState(
                  () => _f = _f.copyWith(followUp: v ?? FollowUpFilter.any)),
            ),
            _dropdown<LastAttendanceFilter>(
              label: 'آخر اجتماع',
              value: _f.lastAttendance,
              items: [for (final v in LastAttendanceFilter.values) (v, v.label)],
              onChanged: (v) => setState(() => _f = _f.copyWith(
                  lastAttendance: v ?? LastAttendanceFilter.any)),
            ),
            _dropdown<int>(
              label: 'الغياب المتتالي',
              value: _f.minConsecutiveAbsences,
              items: const [
                (0, 'الكل'),
                (2, 'غابت مرتين متتاليتين أو أكثر'),
                (4, 'غابت 4 مرات متتالية أو أكثر'),
              ],
              onChanged: (v) => setState(
                  () => _f = _f.copyWith(minConsecutiveAbsences: v ?? 0)),
            ),
            _dropdown<double>(
              label: 'نسبة الحضور',
              value: _f.maxAttendanceRate,
              items: const [
                (null, 'الكل'),
                (0.5, '50% أو أقل'),
                (0.25, '25% أو أقل'),
              ],
              onChanged: (v) =>
                  setState(() => _f = _f.copyWith(maxAttendanceRate: () => v)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                ref.read(womenFilterProvider.notifier).set(_f);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check),
              label: const Text('تطبيق الفلاتر'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                ref.read(womenFilterProvider.notifier).clear();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('مسح كل الفلاتر'),
            ),
          ],
        ),
      ),
    );
  }
}
