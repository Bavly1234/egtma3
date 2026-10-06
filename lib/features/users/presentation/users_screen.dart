import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../data/users_repository.dart';

/// إدارة المستخدمين (father only).
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(requireUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون')),
      body: AsyncBody(
        value: ref.watch(allUsersProvider),
        builder: (users) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.assign),
              icon: const Icon(Icons.assignment_ind),
              label: const Text('تعيين السيدات وتوزيع العمل'),
            ),
            const SizedBox(height: 12),
            const Text(
                'الخادمات ينشئن حساباتهن بأنفسهن من شاشة الدخول باستخدام كود الانضمام. '
                'يمكنك هنا إيقاف أي حساب أو تغيير صلاحيته.',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            for (final u in users) _UserCard(user: u, isMe: u.id == me.id, me: me),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user, required this.isMe, required this.me});
  final AppUser user;
  final bool isMe;
  final AppUser me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(usersRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(user.isFather ? Icons.church : Icons.badge,
                  size: 32, color: user.active ? AppColors.primary : Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('${user.role.label} • ${user.email}',
                      style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
                  if (!user.active)
                    const Text('موقوف',
                        style: TextStyle(color: AppColors.absent, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            if (!isMe) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmAction(context,
                        title: user.active ? 'إيقاف الحساب' : 'تفعيل الحساب',
                        message: user.active
                            ? 'لن تتمكن "${user.name}" من الدخول حتى يتم التفعيل.'
                            : 'ستتمكن "${user.name}" من الدخول مرة أخرى.',
                        destructive: user.active);
                    if (ok && context.mounted) {
                      await runGuarded(context, () => repo.setActive(user, !user.active, me),
                          successMessage: 'تم');
                    }
                  },
                  icon: Icon(user.active ? Icons.block : Icons.check_circle),
                  label: Text(user.active ? 'إيقاف' : 'تفعيل'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmAction(context,
                        title: 'إعادة تعيين الدخول',
                        message: 'إرسال رابط لتغيير كلمة المرور إلى ${user.email}؟');
                    if (ok && context.mounted) {
                      await runGuarded(context, () => repo.sendAccessReset(user.email),
                          successMessage: 'تم إرسال الرابط');
                    }
                  },
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('إعادة تعيين الدخول'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final newRole =
                        user.isFather ? UserRole.servant : UserRole.father;
                    final ok = await confirmAction(context,
                        title: 'تغيير الصلاحية',
                        message: 'تغيير صلاحية "${user.name}" إلى "${newRole.label}"؟',
                        destructive: newRole == UserRole.father);
                    if (ok && context.mounted) {
                      await runGuarded(context, () => repo.setRole(user, newRole, me),
                          successMessage: 'تم');
                    }
                  },
                  icon: const Icon(Icons.admin_panel_settings),
                  label: Text(user.isFather ? 'جعلها خادمة' : 'منح صلاحية كاملة'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
