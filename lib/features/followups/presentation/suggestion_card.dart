import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import '../data/follow_up_repository.dart';
import '../domain/follow_up.dart';
import 'record_follow_up_sheet.dart';

/// One افتقاد task with its large action buttons.
class SuggestionCard extends ConsumerWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    this.woman,
    this.compact = false,
  });
  final FollowUpSuggestion suggestion;
  final Woman? woman;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = suggestion;
    final w = woman ?? ref.watch(womanProvider(s.womanId)).value;
    final user = ref.watch(requireUserProvider);
    final isHome = s.type == SuggestionType.homeVisit;
    final color = isHome ? AppColors.home : AppColors.warning;
    final bg = isHome ? AppColors.homeLight : AppColors.warningLight;
    final overdue = s.isOverdue(DateTime.now());
    final phone = w?.phone ?? s.phone ?? '';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(s.type.icon, color: color, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: compact ? null : () => context.push(Routes.woman(s.womanId)),
                  child: Text(s.womanName,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                Text(s.type.label,
                    style: TextStyle(
                        color: color, fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(s.status.label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              if (overdue)
                const Text('متأخر',
                    style: TextStyle(
                        color: AppColors.absent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
            ]),
          ]),
          const SizedBox(height: 10),
          Text(s.reason, style: const TextStyle(fontSize: 17)),
          if (!compact) ...[
            const SizedBox(height: 6),
            if (isHome && (w?.address ?? s.address ?? '').isNotEmpty)
              _line(Icons.location_on, w?.address ?? s.address!),
            if ((w?.streetName ?? s.streetName ?? '').isNotEmpty)
              _line(Icons.signpost, w?.streetName ?? s.streetName!),
            if (phone.isNotEmpty) _line(Icons.phone, phone),
            _line(Icons.badge, 'الخادمة: ${s.assignedServantName ?? 'غير معينة'}'),
            if (w != null)
              _line(
                isHome ? Icons.home : Icons.phone_callback,
                isHome
                    ? 'زيارات سابقة: ${w.homeVisits} — آخر زيارة ${Dates.display(w.lastVisitAt)}'
                    : 'مكالمات سابقة: ${w.phoneCalls} — آخر مكالمة ${Dates.display(w.lastCallAt)}',
              ),
            _line(Icons.calendar_today, 'منذ ${Dates.display(s.createdAt)}'),
          ],
          if (s.status.isActive) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.present),
              onPressed: w == null
                  ? null
                  : () => showRecordFollowUpSheet(
                        context,
                        woman: w,
                        type: isHome ? FollowUpType.homeVisit : FollowUpType.phoneCall,
                        completes: s,
                      ),
              icon: Icon(isHome ? Icons.home : Icons.check_circle),
              label: Text(isHome ? 'تم الافتقاد المنزلي' : 'تم الافتقاد'),
            ),
            const SizedBox(height: 10),
            if (phone.isNotEmpty) ContactButtons(phone: phone),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: w == null
                      ? null
                      : () => showRecordFollowUpSheet(context,
                          woman: w, type: FollowUpType.note),
                  icon: const Icon(Icons.note_add),
                  label: const Text('إضافة ملاحظة'),
                ),
              ),
              if (user.isFather) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirmAction(context,
                          title: 'تجاهل الاقتراح',
                          message: 'سيُحفظ الاقتراح في السجل كـ "تم التجاهل".');
                      if (!ok || !context.mounted) return;
                      await runGuarded(
                        context,
                        () => ref.read(followUpRepositoryProvider).setSuggestionStatus(
                            s, SuggestionStatus.dismissed, user),
                        successMessage: 'تم',
                      );
                    },
                    icon: const Icon(Icons.do_not_disturb_on),
                    label: const Text('تجاهل'),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ]),
      );
}
