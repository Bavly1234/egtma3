import 'package:flutter/material.dart';

import '../../../core/utils/dates.dart';
import '../domain/stats_models.dart';

enum RangePreset {
  today('اليوم'),
  week('هذا الأسبوع'),
  month('هذا الشهر'),
  quarter('آخر 3 شهور'),
  year('آخر سنة'),
  custom('فترة مخصصة');

  const RangePreset(this.label);
  final String label;

  DateRange resolve(DateTime now) => switch (this) {
        today => DateRange.today(now),
        week => DateRange.thisWeek(now),
        month => DateRange.thisMonth(now),
        quarter => DateRange.lastDays(now, 90),
        year => DateRange.lastDays(now, 365),
        custom => DateRange.thisMonth(now),
      };
}

/// Date-range chips + custom range picker.
class RangeSelector extends StatelessWidget {
  const RangeSelector({
    super.key,
    required this.preset,
    required this.range,
    required this.onChanged,
  });
  final RangePreset preset;
  final DateRange range;
  final void Function(RangePreset, DateRange) onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in RangePreset.values)
          ChoiceChip(
            label: Text(p.label),
            selected: preset == p,
            onSelected: (_) async {
              if (p != RangePreset.custom) {
                onChanged(p, p.resolve(now));
                return;
              }
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 5),
                lastDate: now,
                initialDateRange:
                    DateTimeRange(start: range.from, end: Dates.dateOnly(now)),
              );
              if (r != null) {
                onChanged(p, DateRange(r.start, r.end.add(const Duration(days: 1))));
              }
            },
          ),
      ]),
      const SizedBox(height: 6),
      Text('الفترة: ${range.label}', style: const TextStyle(fontSize: 16)),
    ]);
  }
}
