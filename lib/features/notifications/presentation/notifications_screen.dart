import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _State();
}

class _State extends ConsumerState<NotificationsScreen> {
  NotificationType? _type;

  void _open(AppNotification n) {
    if (!n.isRead) ref.read(notificationRepositoryProvider).markRead(n.id);
    final id = n.relatedEntityId;
    switch (n.relatedEntityType) {
      case 'woman' when id != null:
        context.push(Routes.woman(id));
      case 'suggestion':
        context.go(Routes.followUps);
      case 'conference' when id != null:
        context.push(Routes.conference(id));
      case 'meeting':
        context.go(Routes.attendance);
      case 'verse':
        context.push(Routes.verse);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(requireUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => runGuarded(context,
                () => ref.read(notificationRepositoryProvider).markAllRead(user.id),
                successMessage: 'تم'),
            child: const Text('قراءة الكل'),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                    label: const Text('الكل'),
                    selected: _type == null,
                    onSelected: (_) => setState(() => _type = null)),
              ),
              for (final t in NotificationType.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                      avatar: Icon(t.icon, size: 20),
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t)),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody(
            value: ref.watch(myNotificationsProvider),
            builder: (all) {
              final list = _type == null ? all : all.where((n) => n.type == _type).toList();
              if (list.isEmpty) {
                return const EmptyState(
                    icon: Icons.notifications_none, title: 'لا توجد إشعارات');
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final n = list[i];
                  return Card(
                    color: n.isRead ? null : AppColors.primaryLight,
                    child: ListTile(
                      leading: Icon(n.type.icon, size: 32, color: AppColors.primary),
                      title: Text(n.title,
                          style: TextStyle(
                              fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800)),
                      subtitle: Text('${n.message}\n${Dates.displayDateTime(n.createdAt)}'),
                      isThreeLine: true,
                      trailing: n.isRead
                          ? null
                          : IconButton(
                              tooltip: 'تمت القراءة',
                              icon: const Icon(Icons.mark_email_read),
                              onPressed: () => ref
                                  .read(notificationRepositoryProvider)
                                  .markRead(n.id),
                            ),
                      onTap: () => _open(n),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
