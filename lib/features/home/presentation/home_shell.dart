import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/services/local_notifications.dart';
import '../../attendance/data/auto_absence_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../notifications/data/notification_repository.dart';
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
    _Tab(4, Icons.bar_chart, 'الإحصائيات'),
    _Tab(5, Icons.menu, 'المزيد'),
  ];

  /// أبونا: a control-panel layout, different from the servants'.
  static const _fatherTabs = [
    _Tab(0, Icons.dashboard, 'لوحة التحكم'),
    _Tab(6, Icons.badge, 'حضور الخادمات'),
    _Tab(4, Icons.bar_chart, 'الإحصائيات'),
    _Tab(1, Icons.groups, 'السيدات'),
    _Tab(5, Icons.menu, 'المزيد'),
  ];

  /// On a computer screen أبونا also gets these in the side menu.
  static const _fatherRailExtra = [
    _Tab(2, Icons.how_to_reg, 'حضور السيدات'),
    _Tab(3, Icons.volunteer_activism, 'الافتقاد'),
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
      // Leftover notifications about the deleted test data.
      ref.read(notificationRepositoryProvider)
          .deleteMine(user.id, demoOnly: true)
          .ignore();
    }
    final isFather = user?.isFather ?? false;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    void go(_Tab t) => widget.shell.goBranch(
          t.branch,
          initialLocation: t.branch == widget.shell.currentIndex,
        );

    if (isFather && wide) {
      // Admin-style side menu on a computer.
      final rail = [..._fatherTabs.take(4), ..._fatherRailExtra, _fatherTabs.last];
      final current = rail.indexWhere((t) => t.branch == widget.shell.currentIndex);
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            backgroundColor: const Color(0xFF0E1E36),
            extended: MediaQuery.sizeOf(context).width >= 1200,
            minExtendedWidth: 220,
            selectedIndex: current < 0 ? 0 : current,
            onDestinationSelected: (i) => go(rail[i]),
            labelType: MediaQuery.sizeOf(context).width >= 1200
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            indicatorColor: const Color(0xFFD6A84A),
            selectedIconTheme: const IconThemeData(color: Color(0xFF0E1E36), size: 28),
            unselectedIconTheme: const IconThemeData(color: Colors.white70, size: 28),
            selectedLabelTextStyle: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            unselectedLabelTextStyle:
                const TextStyle(color: Colors.white70, fontSize: 15),
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.church, color: Color(0xFFD6A84A), size: 34),
            ),
            destinations: [
              for (final t in rail)
                NavigationRailDestination(icon: Icon(t.icon), label: Text(t.label)),
            ],
          ),
          Expanded(child: widget.shell),
        ]),
      );
    }

    final tabs = isFather ? _fatherTabs : _servantTabs;
    final current =
        tabs.indexWhere((t) => t.branch == widget.shell.currentIndex);

    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: current < 0 ? 0 : current,
        onDestinationSelected: (i) => go(tabs[i]),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
