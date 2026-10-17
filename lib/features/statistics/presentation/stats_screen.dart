import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/business_rules.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/simple_charts.dart';
import '../../../core/widgets/states.dart';
import '../../streets/data/street_repository.dart';
import '../domain/stats_models.dart';
import 'full_stats_providers.dart';
import 'simple_stats_providers.dart';

/// Full statistics of all the women — the same page for أبونا and the
/// servants. Filters: a month, a date range or one Wednesday, and a street.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  PeriodKind _kind = PeriodKind.month;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateRange? _range;
  DateTime _day = Dates.currentOrLastMeeting(DateTime.now());
  String? _streetId;

  StatsQuery get _query => StatsQuery(
        kind: _kind,
        streetId: _streetId,
        range: switch (_kind) {
          PeriodKind.month => monthRange(_month),
          PeriodKind.range => _range ??
              DateRange(DateTime(DateTime.now().year, 1, 1),
                  Dates.dateOnly(DateTime.now()).add(const Duration(days: 1))),
          PeriodKind.day => DateRange(_day, _day.add(const Duration(days: 1))),
        },
      );

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'من يوم … لحد يوم',
      initialDateRange: _range == null
          ? DateTimeRange(start: DateTime(now.year, 1, 1), end: Dates.dateOnly(now))
          : DateTimeRange(
              start: _range!.from, end: _range!.to.subtract(const Duration(days: 1))),
    );
    if (r != null) {
      setState(() => _range = DateRange(r.start, r.end.add(const Duration(days: 1))));
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      selectableDayPredicate: (d) => d.weekday == BusinessRules.meetingWeekday,
      helpText: 'اختار يوم الأربعاء',
    );
    if (d != null) setState(() => _day = d);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query;
    final data = ref.watch(fullStatsProvider(q));
    final streets = ref.watch(streetsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('إحصائيات السيدات')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(fullStatsProvider(q).future),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // ---------- filters ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<PeriodKind>(
                  segments: const [
                    ButtonSegment(value: PeriodKind.month, label: Text('شهر')),
                    ButtonSegment(value: PeriodKind.range, label: Text('من … لحد')),
                    ButtonSegment(value: PeriodKind.day, label: Text('يوم أربعاء')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
                const SizedBox(height: 10),
                switch (_kind) {
                  PeriodKind.month => MonthPicker(
                      month: _month, onChanged: (m) => setState(() => _month = m)),
                  PeriodKind.range => OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range),
                      label: Text(q.range.label)),
                  PeriodKind.day => OutlinedButton.icon(
                      onPressed: _pickDay,
                      icon: const Icon(Icons.calendar_month),
                      label: Text('${Dates.weekdayAr(_day)}  ${Dates.display(_day)}')),
                },
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _streetId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'الشارع', prefixIcon: Icon(Icons.signpost)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل الشوارع')),
                    for (final s in streets)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _streetId = v),
                ),
              ]),
            ),
          ),
          AsyncBody(
            value: data,
            onRetry: () => ref.invalidate(fullStatsProvider(q)),
            builder: (s) => _Body(stats: s, query: q),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats, required this.query});
  final FullStats stats;
  final StatsQuery query;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final single = query.kind == PeriodKind.day;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      TileRow(
        NumberTile(
            icon: Icons.how_to_reg,
            label: 'مرات الحضور',
            value: '${s.present}',
            color: AppColors.present,
            background: AppColors.presentLight),
        NumberTile(
            icon: Icons.person_off,
            label: 'مرات الغياب',
            value: '${s.absent}',
            color: AppColors.absent,
            background: AppColors.absentLight),
      ),
      TileRow(
        NumberTile(icon: Icons.event, label: 'عدد الاجتماعات', value: '${s.weeks.length}'),
        NumberTile(icon: Icons.groups, label: 'السيدات', value: '${s.activeWomen}'),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            AttendanceDonut(present: s.present, absent: s.absent),
            if (!single && s.weeks.length > 1) ...[
              const SizedBox(height: 16),
              WeeklyBars(items: [
                for (final w in s.weeks.length > 12 ? s.weeks.sublist(s.weeks.length - 12) : s.weeks)
                  (shortDay(w.meetingId), w.present),
              ]),
            ],
          ]),
        ),
      ),

      const SectionTitle('⭐ أكتر السيدات حضوراً'),
      _WomenList(
        rows: s.mostPresent,
        line: (c) => 'حضرت ${c.present} من ${c.total}',
        color: AppColors.present,
        empty: 'لا يوجد حضور في الفترة دي',
      ),
      const SectionTitle('أكتر السيدات غياباً'),
      _WomenList(
        rows: s.mostAbsent,
        line: (c) => 'غابت ${c.absent} من ${c.total}',
        color: AppColors.absent,
        empty: 'مفيش غياب 👍',
      ),

      if (s.streets.isNotEmpty) ...[
        const SectionTitle('الشوارع'),
        Text('عدد الأربعاءات: ${s.weeks.length} — النسبة = الحضور من كل التسجيلات، '
            'والرقم = متوسط كل أربعاء',
            style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
        _Bars(rows: s.streets, weeks: s.weeks.length),
      ],
      if (query.streetId == null && s.servants.any((r) => r.total > 0)) ...[
        const SectionTitle('حضور سيدات كل خادمة'),
        const Text('(حسب الشوارع اللي مع كل خادمة)',
            style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
        _Bars(rows: s.servants, weeks: s.weeks.length),
      ],
      if (s.servantAttendance.any((r) => r.total > 0)) ...[
        const SectionTitle('حضور الخادمات نفسهم'),
        _Bars(rows: s.servantAttendance, word: 'حضرت'),
      ],

      const SectionTitle('الافتقاد'),
      TileRow(
        NumberTile(
            icon: Icons.task_alt,
            label: 'افتقاد اتعمل',
            value: '${s.followUps.completed}',
            color: AppColors.present,
            background: AppColors.presentLight),
        NumberTile(
            icon: Icons.hourglass_bottom,
            label: 'افتقاد لسه',
            value: '${s.followUps.pending}',
            color: AppColors.warning,
            background: AppColors.warningLight,
            onTap: () => context.go(Routes.followUps)),
      ),
      TileRow(
        NumberTile(icon: Icons.phone, label: 'مكالمات', value: '${s.followUps.calls}'),
        NumberTile(
            icon: Icons.home,
            label: 'زيارات',
            value: '${s.followUps.visits}',
            color: AppColors.home,
            background: AppColors.homeLight),
      ),
      const SectionTitle('تقارير'),
      MenuTile(
          icon: Icons.calendar_month,
          title: 'التقرير الشهري (Excel)',
          color: AppColors.present,
          onTap: () => context.push(Routes.monthlyReport)),
      MenuTile(
          icon: Icons.event,
          title: 'المؤتمرات وإحصائياتها',
          onTap: () => context.push(Routes.conferences)),
    ]);
  }
}

class _WomenList extends StatefulWidget {
  const _WomenList(
      {required this.rows, required this.line, required this.color, required this.empty});
  final List<WomanCount> rows;
  final String Function(WomanCount) line;
  final Color color;
  final String empty;

  @override
  State<_WomenList> createState() => _WomenListState();
}

/// Ranked list; shows the first N (10 by default, any number typed, or all).
class _WomenListState extends State<_WomenList> {
  final _count = TextEditingController(text: '10');
  int _n = 10;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  void _set(int n) => setState(() {
        _n = n;
        _count.text = '$n';
      });

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final color = widget.color;
    final shown = rows.take(_n).toList();
    return Card(
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.empty, style: const TextStyle(fontSize: 18)))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  const Text('اعرض أول', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                          isDense: true, contentPadding: EdgeInsets.all(10)),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n > 0) setState(() => _n = n);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('من ${rows.length}', style: const TextStyle(fontSize: 18)),
                  const Spacer(),
                  TextButton(
                      onPressed: () => _set(rows.length),
                      child: const Text('الكل', style: TextStyle(fontSize: 18))),
                ]),
              ),
              for (final (i, c) in shown.indexed)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: .15),
                    child: Text('${i + 1}',
                        style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(c.woman.fullName),
                  subtitle: Text(c.woman.streetName),
                  trailing: Text(widget.line(c),
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w800, fontSize: 17)),
                  onTap: () => context.push(Routes.woman(c.woman.id)),
                ),
            ]),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.rows, this.word = 'حضر', this.weeks});
  final List<NamedCount> rows;
  final String word;

  /// When set (more than one Wednesday), each row shows the attendance rate
  /// and the average per Wednesday instead of the raw sum over the period
  /// ("حضر 2 من 2" meant 2 marks, not 2 women).
  final int? weeks;

  String? _text(NamedCount r) {
    final n = weeks;
    if (n == null || n <= 1 || r.total == 0) return null;
    String avg(int v) {
      final a = v / n;
      return a == a.roundToDouble() ? '${a.round()}' : a.toStringAsFixed(1);
    }
    return '${(r.count * 100 / r.total).round()}% — '
        'في المتوسط ${avg(r.count)} من ${avg(r.total)} كل أربعاء';
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: [
            for (final r in rows)
              CountBar(
                  label: r.name,
                  count: r.count,
                  total: r.total,
                  countWord: word,
                  valueText: _text(r)),
          ]),
        ),
      );
}
