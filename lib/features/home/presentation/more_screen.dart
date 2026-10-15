import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/permissions.dart';
import '../../notifications/data/notification_repository.dart';

/// Short, grouped menu. Daily things first; rarely used tools at the end.
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
        MenuTile(
            icon: Icons.notifications,
            title: 'الإشعارات',
            subtitle: unread > 0 ? 'فيه $unread جديد' : null,
            onTap: () => go(Routes.notifications)),
        MenuTile(
            icon: Icons.cake,
            title: 'أعياد الميلاد',
            color: AppColors.gold,
            onTap: () => go(Routes.birthdays)),
        MenuTile(
            icon: Icons.event,
            title: 'المؤتمرات',
            onTap: () => go(Routes.conferences)),
        MenuTile(
            icon: Icons.history,
            title: 'الاجتماعات اللي فاتت',
            onTap: () => go(Routes.attendanceHistory)),
        if (!user.isFather)
          MenuTile(
              icon: Icons.insights,
              title: 'إحصائياتي',
              color: AppColors.present,
              onTap: () => go(Routes.statsServants)),
        if (user.isFather) ...[
          const SectionTitle('إدارة'),
          MenuTile(
              icon: Icons.signpost,
              title: 'الشوارع وتوزيع الخادمات',
              onTap: () => go(Routes.streets)),
          if (Permissions.canManageUsers(user))
            MenuTile(
                icon: Icons.manage_accounts,
                title: 'حسابات الخادمات',
                onTap: () => go(Routes.users)),
          MenuTile(
              icon: Icons.insights,
              title: 'إحصائيات خادمة معيّنة',
              onTap: () => go(Routes.statsServants)),
        ],
        const SectionTitle('أدوات'),
        MenuTile(
            icon: Icons.calendar_month,
            title: 'التقرير الشهري',
            onTap: () => go(Routes.monthlyReport)),
        if (Permissions.canImportExport(user)) ...[
          MenuTile(
              icon: Icons.upload_file,
              title: 'إضافة سيدات من ملف Excel',
              onTap: () => go(Routes.import)),
          MenuTile(
              icon: Icons.file_download,
              title: 'حفظ البيانات في ملف Excel',
              onTap: () => go(Routes.export)),
        ],
        if (Permissions.canViewAudit(user))
          MenuTile(
              icon: Icons.history_edu,
              title: 'سجل التغييرات',
              onTap: () => go(Routes.audit)),
        MenuTile(
            icon: Icons.settings,
            title: 'الإعدادات (حجم الخط والإشعارات)',
            onTap: () => go(Routes.settings)),
      ]),
    );
  }
}
