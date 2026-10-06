import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/auth_repository.dart';

class _Tab {
  const _Tab(this.branch, this.icon, this.label);
  final int branch;
  final IconData icon;
  final String label;
}

/// Bottom navigation. Servants get 5 tabs; the father also gets statistics.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  StreamSubscription<RemoteMessage>? _fg;
  StreamSubscription<RemoteMessage>? _opened;
  String? _registeredUid;

  static const _servantTabs = [
    _Tab(0, Icons.home, 'الرئيسية'),
    _Tab(1, Icons.groups, 'السيدات'),
    _Tab(2, Icons.how_to_reg, 'الحضور'),
    _Tab(3, Icons.volunteer_activism, 'الافتقاد'),
    _Tab(5, Icons.menu, 'المزيد'),
  ];
  static const _fatherTabs = [
    _Tab(0, Icons.home, 'الرئيسية'),
    _Tab(1, Icons.groups, 'السيدات'),
    _Tab(2, Icons.how_to_reg, 'الحضور'),
    _Tab(3, Icons.volunteer_activism, 'الافتقاد'),
    _Tab(4, Icons.bar_chart, 'الإحصائيات'),
    _Tab(5, Icons.menu, 'المزيد'),
  ];

  @override
  void initState() {
    super.initState();
    final messaging = ref.read(messagingServiceProvider);
    _fg = messaging.foregroundMessages.listen((m) {
      final n = m.notification;
      if (n != null && mounted) {
        AppToast.info(context, '${n.title ?? ''}\n${n.body ?? ''}'.trim());
      }
    });
    _opened = messaging.openedMessages.listen(_openFromPush);
  }

  void _openFromPush(RemoteMessage m) {
    if (!mounted) return;
    final type = m.data['relatedEntityType'];
    final id = m.data['relatedEntityId'];
    if (type == 'woman' && id is String) {
      context.push(Routes.woman(id));
    } else if (type == 'suggestion') {
      context.go(Routes.followUps);
    } else if (type == 'conference' && id is String) {
      context.push(Routes.conference(id));
    } else {
      context.push(Routes.notifications);
    }
  }

  @override
  void dispose() {
    _fg?.cancel();
    _opened?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    if (user != null && _registeredUid != user.id) {
      _registeredUid = user.id;
      ref.read(messagingServiceProvider).registerFor(user.id);
    }
    final tabs = (user?.isFather ?? false) ? _fatherTabs : _servantTabs;
    final current = tabs.indexWhere((t) => t.branch == widget.shell.currentIndex);

    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: current < 0 ? 0 : current,
        onDestinationSelected: (i) => widget.shell.goBranch(
          tabs[i].branch,
          initialLocation: tabs[i].branch == widget.shell.currentIndex,
        ),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
