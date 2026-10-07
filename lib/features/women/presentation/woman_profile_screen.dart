import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/permissions.dart';
import '../../followups/presentation/record_follow_up_sheet.dart';
import '../../followups/presentation/suggestion_card.dart';
import '../data/women_repository.dart';
import '../domain/woman.dart';
import 'woman_providers.dart';

class WomanProfileScreen extends ConsumerWidget {
  const WomanProfileScreen({super.key, required this.womanId});
  final String womanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final woman = ref.watch(womanProvider(womanId));
    final user = ref.watch(requireUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('بيانات السيدة'),
        actions: [
          // Full women CRUD for every active servant (not father-only).
          if (woman.value != null && Permissions.canManageWomen(user))
            _WomanMenu(woman: woman.value!, user: user),
        ],
      ),
      body: AsyncBody(
        value: woman,
        builder: (w) => w == null
            ? const EmptyState(
                icon: Icons.person_off, title: 'لم يتم العثور على السيدة')
            : _ProfileBody(woman: w, user: user),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.woman, required this.user});
  final Woman woman;
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = woman;
    final canAct = Permissions.canActOnWoman(user);
    final now = DateTime.now();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(w.fullName, style: Theme.of(context).textTheme.headlineMedium),
      if (!w.active)
        const Text('غير نشطة',
            style: TextStyle(color: AppColors.absent, fontSize: 18)),
      const SizedBox(height: 16),
      if (w.hasPhone) ContactButtons(phone: w.phone, whatsApp: w.hasWhatsApp),
      if (canAct) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.home),
              onPressed: () => showRecordFollowUpSheet(context,
                  woman: w, type: FollowUpType.homeVisit),
              icon: const Icon(Icons.home),
              label: const Text('زيارة منزلية'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showRecordFollowUpSheet(context,
                  woman: w, type: FollowUpType.note),
              icon: const Icon(Icons.note_add),
              label: const Text('إضافة ملاحظة'),
            ),
          ),
        ]),
        if (w.hasPhone) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showRecordFollowUpSheet(context,
                woman: w, type: FollowUpType.phoneCall),
            icon: const Icon(Icons.phone_callback),
            label: const Text('تسجيل مكالمة'),
          ),
        ],
      ],
      const SectionTitle('البيانات الشخصية'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            InfoRow(icon: Icons.phone, label: 'التليفون', value: w.phone),
            InfoRow(icon: Icons.signpost, label: 'الشارع', value: w.streetName),
            InfoRow(icon: Icons.location_on, label: 'العنوان', value: w.address),
            InfoRow(
              icon: Icons.cake,
              label: 'تاريخ الميلاد',
              value: w.dateOfBirth == null
                  ? ''
                  : '${Dates.display(w.dateOfBirth)}  (${Dates.ageOn(w.dateOfBirth!, now)} سنة)',
            ),
            if (w.notes.isNotEmpty)
              InfoRow(icon: Icons.notes, label: 'ملاحظات', value: w.notes),
          ]),
        ),
      ),
      _SuggestionsSection(woman: w),
      const SectionTitle('الافتقاد'),
      Row(children: [
        Expanded(
          child: StatCard(
              icon: Icons.phone, title: 'مكالمات', value: '${w.phoneCalls}',
              subtitle: 'آخر: ${Dates.display(w.lastCallAt)}'),
        ),
      ]),
      const SizedBox(height: 10),
      StatCard(
          icon: Icons.home,
          title: 'زيارات',
          value: '${w.homeVisits}',
          subtitle: 'آخر: ${Dates.display(w.lastVisitAt)}',
          color: AppColors.home,
          background: AppColors.homeLight),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => context.push(Routes.womanFollowUps(w.id)),
        icon: const Icon(Icons.history),
        label: const Text('سجل الافتقاد الكامل'),
      ),
      _AttendanceSection(woman: w),
      const SizedBox(height: 32),
    ]);
  }
}

class _SuggestionsSection extends ConsumerWidget {
  const _SuggestionsSection({required this.woman});
  final Woman woman;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(womanSuggestionsProvider(woman.id)).value ?? const [];
    final active = list.where((s) => s.status.isActive).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('الاقتراح الحالي'),
      for (final s in active) ...[
        SuggestionCard(suggestion: s, woman: woman, compact: true),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _AttendanceSection extends ConsumerWidget {
  const _AttendanceSection({required this.woman});
  final Woman woman;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(womanAttendanceProvider(woman.id));
    final rate = woman.attendanceRate;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('الحضور',
          trailing: rate == null
              ? null
              : Text('نسبة الحضور ${percent(rate)}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700))),
      AsyncBody(
        value: history,
        builder: (records) => records.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('لا يوجد حضور مسجل بعد',
                    style: TextStyle(fontSize: 18)))
            : Card(
                child: Column(children: [
                  for (final r in records)
                    ListTile(
                      title: Text(
                          '${Dates.weekdayAr(Dates.parseDayId(r.meetingId))}  ${Dates.display(Dates.parseDayId(r.meetingId))}'),
                      trailing: StatusPill(r.status),
                    ),
                ]),
              ),
      ),
    ]);
  }
}

/// Edit / activate / delete — every active servant (full women CRUD).
/// Assignment is by street only (managed from the Streets screen).
class _WomanMenu extends ConsumerWidget {
  const _WomanMenu({required this.woman, required this.user});
  final Woman woman;
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(womenRepositoryProvider);
    return PopupMenuButton<String>(
      tooltip: 'خيارات',
      icon: const Icon(Icons.more_vert, size: 30),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            context.push(Routes.womanEdit(woman.id));
          case 'toggle':
            final ok = await confirmAction(context,
                title: woman.active ? 'إيقاف السيدة' : 'تفعيل السيدة',
                message: woman.active
                    ? 'لن تظهر في كشوف الحضور. يمكن إعادة تفعيلها لاحقاً.'
                    : 'ستظهر مرة أخرى في كشوف الحضور.');
            if (ok && context.mounted) {
              await runGuarded(
                  context, () => repo.setActive(woman.id, !woman.active, user),
                  successMessage: 'تم الحفظ');
            }
          case 'delete':
            final ok = await confirmAction(context,
                title: 'حذف نهائي',
                message:
                    'هل أنت متأكد من حذف "${woman.fullName}"؟ يُفضل الإيقاف بدلاً من الحذف.',
                confirmLabel: 'حذف',
                destructive: true);
            if (ok && context.mounted) {
              final done = await runGuarded(context,
                  () => repo.delete(woman.id, woman.fullName, user),
                  successMessage: 'تم الحذف');
              if (done && context.mounted) context.pop();
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
        PopupMenuItem(
            value: 'toggle',
            child: Text(woman.active ? 'إيقاف (غير نشطة)' : 'تفعيل')),
        const PopupMenuItem(
            value: 'delete',
            child: Text('حذف نهائي', style: TextStyle(color: AppColors.absent))),
      ],
    );
  }
}
