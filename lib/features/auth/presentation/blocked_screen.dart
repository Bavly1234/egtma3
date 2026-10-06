import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/states.dart';
import '../data/auth_repository.dart';

/// Shown when the account has no profile or was disabled by the father.
class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('الحساب غير مفعّل')),
        body: EmptyState(
          icon: Icons.lock_person,
          title: 'حسابك غير مفعّل حالياً',
          message: 'تواصلي مع الأب الكاهن لتفعيل الحساب.',
          action: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
            ),
          ]),
        ),
      );
}
