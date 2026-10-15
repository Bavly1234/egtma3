import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Very simple visuals for older users: big numbers in words, one colour per
/// meaning (green = حضر, red = غاب), no percentages without the real counts.

/// Donut: green part = present, red = absent, with "حضر X من Y" next to it.
class AttendanceDonut extends StatelessWidget {
  const AttendanceDonut({
    super.key,
    required this.present,
    required this.absent,
    this.title,
  });
  final int present;
  final int absent;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final total = present + absent;
    return Row(children: [
      SizedBox(
        width: 120,
        height: 120,
        child: total == 0
            ? const CircleAvatar(
                radius: 60,
                backgroundColor: Color(0xFFEEEEEE),
                child: Text('لم يُسجل\nبعد',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
              )
            : PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 34,
                startDegreeOffset: -90,
                sections: [
                  PieChartSectionData(
                      value: present.toDouble(),
                      color: AppColors.present,
                      radius: 24,
                      showTitle: false),
                  PieChartSectionData(
                      value: absent.toDouble(),
                      color: AppColors.absent,
                      radius: 24,
                      showTitle: false),
                ],
              )),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Text(title!,
                style:
                    const TextStyle(fontSize: 18, color: AppColors.textMuted)),
          _legend(AppColors.present, 'حضر', present),
          const SizedBox(height: 6),
          _legend(AppColors.absent, 'غاب', absent),
          if (total > 0) ...[
            const SizedBox(height: 6),
            Text('من $total سيدة',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    ]);
  }

  Widget _legend(Color c, String label, int n) => Row(children: [
        Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('$label  ',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        Text('$n',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: c)),
      ]);
}

/// A big square with a number and a short label. Use two per row.
class NumberTile extends StatelessWidget {
  const NumberTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.primary,
    this.background = AppColors.primaryLight,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: '$label $value',
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(height: 6),
                Text(value,
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
}

/// Two [NumberTile]s side by side.
class TileRow extends StatelessWidget {
  const TileRow(this.a, this.b, {super.key});
  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ]),
        ),
      );
}

/// One row: name, then "حضر X من Y" with a coloured bar under it.
class CountBar extends StatelessWidget {
  const CountBar({
    super.key,
    required this.label,
    required this.count,
    required this.total,
    this.countWord = 'حضر',
    this.color = AppColors.present,
    this.extra,
  });
  final String label;
  final int count;
  final int total;
  final String countWord;
  final Color color;

  /// Optional second line, e.g. "افتقاد لسه: 3".
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final v = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800))),
          Text(total == 0 ? 'لا يوجد' : '$countWord $count من $total',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 18,
            color: color,
            backgroundColor: color.withValues(alpha: .15),
          ),
        ),
        if (extra != null) ...[
          const SizedBox(height: 4),
          Text(extra!,
              style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
        ],
      ]),
    );
  }
}

/// Simple bars: how many came each Wednesday (number written on top).
class WeeklyBars extends StatelessWidget {
  const WeeklyBars({super.key, required this.items});

  /// (label e.g. "7/10", present count), oldest first.
  final List<(String, int)> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('لا توجد اجتماعات في هذا الشهر',
            style: TextStyle(fontSize: 18)),
      );
    }
    final maxV = items.map((e) => e.$2).fold<int>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (label, v) in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('$v',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Container(
                    height: 130 * v / maxV + 4,
                    decoration: BoxDecoration(
                      color: AppColors.present,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 16)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

const kMonthNamesAr = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// ◀ أكتوبر 2026 ▶ — the only filter on the statistics pages.
class MonthPicker extends StatelessWidget {
  const MonthPicker({super.key, required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          IconButton(
            iconSize: 36,
            tooltip: 'الشهر اللي فات',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          ),
          Expanded(
            child: Text('${kMonthNamesAr[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            iconSize: 36,
            tooltip: 'الشهر اللي بعده',
            icon: const Icon(Icons.chevron_left),
            onPressed: isCurrent
                ? null
                : () => onChanged(DateTime(month.year, month.month + 1)),
          ),
        ]),
      ),
    );
  }
}
