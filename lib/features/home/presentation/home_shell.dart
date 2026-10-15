import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/local_notifications.dart';
import '../../../core/services/update_checker.dart';
import '../../attendance/data/auto_absence_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../notifications/data/reminder_service.dart';

class _Tab {
  const _Tab(this.branch, this.icon, this.label);
  final int branch;
  final IconData icon;
  final String label;
}

/// Bottom navigation. Servants get 5 tabs; the father also gets statistics.
/// Also owns the device notification engine for the signed-in user.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _taps;
  String? _startedFor;

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
    WidgetsBinding.instance.addObserver(this);
    final local = LocalNotifications.instance;
    _taps = local.taps.listen(_open);
    final launch = local.launchPayload;
    if (launch != null) {
      local.launchPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(launch));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-plan reminders when the app comes back (new birthdays, counts...).
    final user = ref.read(currentUserProvider).value;
    if (state == AppLifecycleState.resumed && user != null) {
      ref.read(reminderServiceProvider).refresh(user);
      ref.read(autoAbsenceServiceProvider).runIfDue(user);
    }
  }

  void _open(String payload) {
    if (!mounted) return;
    final i = payload.indexOf(':');
    if (i < 0) return;
    final kind = payload.substring(0, i);
    final value = payload.substring(i + 1);
    switch (kind) {
      case 'woman':
        context.push(Routes.woman(value));
      case 'conference':
        context.push(Routes.conference(value));
      case 'route':
        value == Routes.attendance || value == Routes.followUps
            ? context.go(value)
            : context.push(value);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    if (user != null && _startedFor != user.id) {
      _startedFor = user.id;
      ref.read(reminderServiceProvider).start(user);
      // Wednesday 9pm: mark everyone not marked present as absent.
      ref.read(autoAbsenceServiceProvider).runIfDue(user);
      // New APK published? Offer it (Android only, once per launch).
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? UpdateChecker.checkOnce(context) : null);
    }
    final tabs = (user?.isFather ?? false) ? _fatherTabs : _servantTabs;
    final current =
        tabs.indexWhere((t) => t.branch == widget.shell.currentIndex);

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
