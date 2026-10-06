import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/domain/attendance_record.dart';

/// Attendance percentage per Wednesday (oldest → newest).
class AttendanceTrendChart extends StatelessWidget {
  const AttendanceTrendChart({super.key, required this.meetings});
  final List<MeetingSummary> meetings;

  @override
  Widget build(BuildContext context) {
    final data = meetings.reversed.toList();
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('لا توجد بيانات حضور بعد', style: TextStyle(fontSize: 18)),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
        child: SizedBox(
          height: 240,
          child: BarChart(BarChartData(
            maxY: 100,
            minY: 0,
            gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 25),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (g, _, r, _) => BarTooltipItem(
                  '${Dates.display(Dates.parseDayId(data[g.x].meetingId))}\n'
                  '${r.toY.round()}% (${data[g.x].present}/${data[g.x].total})',
                  const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: 25,
                  getTitlesWidget: (v, _) =>
                      Text('${v.toInt()}%', style: const TextStyle(fontSize: 13)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= data.length) return const SizedBox();
                    if (data.length > 8 && i % 2 == 1) return const SizedBox();
                    final d = Dates.parseDayId(data[i].meetingId);
                    return Text('${d.day}/${d.month}',
                        style: const TextStyle(fontSize: 12));
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < data.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: data[i].rate * 100,
                    width: data.length > 12 ? 10 : 18,
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ]),
            ],
          )),
        ),
      ),
    );
  }
}

/// Simple, very readable horizontal bars (label, value 0..1, caption).
class RateBars extends StatelessWidget {
  const RateBars({super.key, required this.rows, this.color = AppColors.primary});
  final List<(String label, double value, String caption)> rows;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            for (final (label, value, caption) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(label,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700))),
                      Text('${percent(value)}  $caption',
                          style: const TextStyle(fontSize: 15)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: value.clamp(0, 1),
                        minHeight: 14,
                        color: color,
                        backgroundColor: color.withValues(alpha: .12),
                      ),
                    ),
                  ],
                ),
              ),
          ]),
        ),
      );
}
