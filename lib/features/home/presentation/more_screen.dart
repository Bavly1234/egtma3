import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/permissions.dart';
import '../../notifications/data/notification_repository.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(requireUserProvider);
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    void go(String r) => context.push(r);

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MenuTile(icon: Icons.notifications, title: 'الإشعارات',
            subtitle: unread > 0 ? '$unread غير مقروءة' : null,
            onTap: () => go(Routes.notifications)),
        MenuTile(icon: Icons.menu_book, title: 'آية اليوم',
            color: AppColors.gold, onTap: () => go(Routes.verse)),
        MenuTile(icon: Icons.cake, title: 'أعياد الميلاد',
            color: AppColors.gold, onTap: () => go(Routes.birthdays)),
        MenuTile(icon: Icons.event, title: 'المؤتمرات', onTap: () => go(Routes.conferences)),
        MenuTile(icon: Icons.history, title: 'سجل الاجتماعات',
            onTap: () => go(Routes.attendanceHistory)),
        MenuTile(icon: Icons.insights,
            title: user.isFather ? 'إحصائيات الخادمات' : 'إحصائياتي',
            onTap: () => go(Routes.statsServants)),
        if (Permissions.canManageStreets(user))
          MenuTile(icon: Icons.signpost, title: 'الشوارع', onTap: () => go(Routes.streets)),
        if (Permissions.canManageUsers(user)) ...[
          MenuTile(icon: Icons.manage_accounts, title: 'المستخدمون (الخادمات)',
              onTap: () => go(Routes.users)),
          MenuTile(icon: Icons.assignment_ind, title: 'تعيين السيدات للخادمات',
              onTap: () => go(Routes.assign)),
        ],
        if (Permissions.canImportExport(user)) ...[
          MenuTile(icon: Icons.upload_file, title: 'استيراد من Excel',
              onTap: () => go(Routes.import)),
          MenuTile(icon: Icons.file_download, title: 'تصدير إلى Excel',
              onTap: () => go(Routes.export)),
        ],
        if (Permissions.canViewAudit(user))
          MenuTile(icon: Icons.history_edu, title: 'سجل التغييرات',
              onTap: () => go(Routes.audit)),
        MenuTile(icon: Icons.settings, title: 'الإعدادات', onTap: () => go(Routes.settings)),
      ]),
    );
  }
}
