import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../women/data/women_repository.dart';
import '../../women/domain/woman.dart';
import '../domain/birthday_rules.dart';

/// Today's birthdays + the next 30 days. Uses two indexed month queries
/// (this month and next) rather than scanning all women.
final _birthdaysProvider =
    FutureProvider.autoDispose<(List<Woman>, List<Woman>)>((ref) async {
  final user = ref.watch(requireUserProvider);
  final repo = ref.watch(womenRepositoryProvider);
  final now = DateTime.now();
  final next = DateTime(now.year, now.month + 1);
  final lists = await Future.wait([
    repo.birthdays(user, now.month),
    repo.birthdays(user, next.month),
  ]);
  final all = {for (final w in [...lists[0], ...lists[1]]) w.id: w}.values
      .where((w) => w.dateOfBirth != null)
      .toList();
  final today = all.where((w) => BirthdayRules.isBirthdayOn(w.dateOfBirth!, now)).toList();
  final upcoming = all
      .where((w) {
        final d = BirthdayRules.daysUntil(w.dateOfBirth!, now);
        return d > 0 && d <= 30;
      })
      .toList()
    ..sort((a, b) => BirthdayRules.daysUntil(a.dateOfBirth!, now)
        .compareTo(BirthdayRules.daysUntil(b.dateOfBirth!, now)));
  return (today, upcoming);
});

class BirthdaysScreen extends ConsumerWidget {
  const BirthdaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(requireUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('أعياد الميلاد')),
      body: AsyncBody(
        value: ref.watch(_birthdaysProvider),
        onRetry: () => ref.invalidate(_birthdaysProvider),
        builder: (d) {
          final (today, upcoming) = d;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const SectionTitle('🎂 أعياد الميلاد اليوم'),
            if (today.isEmpty)
              const Text('لا توجد أعياد ميلاد اليوم', style: TextStyle(fontSize: 18))
            else
              for (final w in today) _BirthdayCard(w: w, showServant: user.isFather, today: true),
            const SectionTitle('أعياد الميلاد القادمة (30 يوم)'),
            if (upcoming.isEmpty)
              const Text('لا يوجد', style: TextStyle(fontSize: 18))
            else
              for (final w in upcoming) _BirthdayCard(w: w, showServant: user.isFather),
          ]);
        },
      ),
    );
  }
}

class _BirthdayCard extends StatelessWidget {
  const _BirthdayCard({required this.w, required this.showServant, this.today = false});
  final Woman w;
  final bool showServant;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = BirthdayRules.nextBirthday(w.dateOfBirth!, now);
    final age = Dates.ageOn(w.dateOfBirth!, next);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: today ? AppColors.goldLight : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              onTap: () => context.push(Routes.woman(w.id)),
              child: Text(w.fullName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text(
              today
                  ? 'تتم $age سنة اليوم'
                  : '${Dates.weekdayAr(next)} ${Dates.display(next)} — تتم $age سنة',
              style: const TextStyle(fontSize: 17),
            ),
            Text('تاريخ الميلاد: ${Dates.display(w.dateOfBirth)}  •  ${w.streetName}',
                style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
            if (showServant)
              Text('الخادمة: ${w.assignedServantName ?? 'غير معينة'}',
                  style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
            if (w.hasPhone) ...[
              const SizedBox(height: 10),
              ContactButtons(phone: w.phone, whatsApp: w.hasWhatsApp),
            ],
          ]),
        ),
      ),
    );
  }
}
