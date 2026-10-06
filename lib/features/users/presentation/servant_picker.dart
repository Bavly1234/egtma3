import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/app_user.dart';
import '../data/users_repository.dart';

/// Wrapper so "no servant" (unassign) differs from "cancelled" (null).
class ServantChoice {
  const ServantChoice(this.value);
  final AppUser? value;
}

Future<ServantChoice?> pickServant(
  BuildContext context,
  WidgetRef ref, {
  bool allowNone = false,
  String title = 'اختاري الخادمة',
}) async {
  final servants = await ref.read(allUsersProvider.future);
  final active = servants.where((u) => u.isServant && u.active).toList();
  if (!context.mounted) return null;
  return showModalBottomSheet<ServantChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Text(title, style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد خادمات نشطات. أضيفي خادمة من إدارة المستخدمين.',
                  style: TextStyle(fontSize: 18)),
            ),
          for (final s in active)
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge, size: 30),
                title: Text(s.name),
                subtitle: Text(s.phone.isEmpty ? s.email : s.phone),
                onTap: () => Navigator.pop(ctx, ServantChoice(s)),
              ),
            ),
          if (allowNone)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_remove, size: 30),
                title: const Text('بدون خادمة (إلغاء التعيين)'),
                onTap: () => Navigator.pop(ctx, const ServantChoice(null)),
              ),
            ),
        ],
      ),
    ),
  );
}
