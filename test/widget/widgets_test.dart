import 'package:egtma3/core/constants/enums.dart';
import 'package:egtma3/core/theme/app_theme.dart';
import 'package:egtma3/core/widgets/common.dart';
import 'package:egtma3/features/attendance/presentation/attendance_controller.dart';
import 'package:egtma3/features/attendance/presentation/attendance_screen.dart';
import 'package:egtma3/features/auth/data/auth_repository.dart';
import 'package:egtma3/features/auth/domain/app_user.dart';
import 'package:egtma3/features/streets/data/street_repository.dart';
import 'package:egtma3/features/women/domain/woman.dart';
import 'package:egtma3/core/services/firebase_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const servant = AppUser(id: 's1', name: 'خادمة', email: '', phone: '', role: UserRole.servant, active: true);

Woman w(String id, String name) => Woman(
      id: id,
      fullName: name,
      streetId: 's',
      streetName: 'شارع مار جرجس',
      address: '',
      phone: '',
      dateOfBirth: null,
      active: true,
    );

class _RecordingActions extends AttendanceActions {
  _RecordingActions(super.ref);
  final calls = <(String, AttendanceStatus)>[];
  @override
  void mark(Woman w, AttendanceStatus status) => calls.add((w.id, status));
}

Widget wrap(Widget child, List overrides) => ProviderScope(
      overrides: [...overrides],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  testWidgets('StatusPill shows Arabic labels', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Column(children: [
      StatusPill(AttendanceStatus.present),
      StatusPill(AttendanceStatus.absent),
      StatusPill(null),
    ])));
    expect(find.text('حاضر'), findsOneWidget);
    expect(find.text('غائب'), findsOneWidget);
    expect(find.text('لم يُسجل'), findsOneWidget);
  });

  testWidgets('StatCard is a large labelled tap target', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatCard(icon: Icons.cake, title: 'أعياد الميلاد اليوم', value: '2',
                onTap: () => tapped = true))));
    await t.tap(find.text('أعياد الميلاد اليوم'));
    expect(tapped, isTrue);
    expect(t.getSize(find.byType(Card)).height, greaterThanOrEqualTo(56));
  });

  testWidgets('attendance: present-only marking, summary updates', (t) async {
    // A phone-sized screen so both rows are visible below the header.
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late _RecordingActions actions;
    await t.pumpWidget(wrap(const AttendanceScreen(), [
      // In-memory database: the screen's Wednesday-9pm auto-absence step
      // must not touch real Firebase (it runs on any day after the cutoff).
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      requireUserProvider.overrideWithValue(servant),
      currentUserProvider.overrideWith((ref) => Stream.value(servant)),
      streetsProvider.overrideWith((ref) => Stream.value(const [])),
      attendanceWomenProvider.overrideWith((ref) async => [w('a', 'مريم أحمد'), w('b', 'سعاد جرجس')]),
      meetingStatusesProvider.overrideWith(
          (ref) => Stream.value({'a': AttendanceStatus.present})),
      attendanceActionsProvider.overrideWith((ref) => actions = _RecordingActions(ref)),
    ]));
    await t.pumpAndSettle();

    expect(find.text('مريم أحمد'), findsOneWidget);
    expect(find.text('سعاد جرجس'), findsOneWidget);
    // Summary: 1 present, 0 absent, 1 unmarked.
    expect(find.text('100%'), findsOneWidget);

    // Tap "حاضر" on the second row (only present is marked; absence is
    // auto-filled at Wednesday 9pm).
    final presentButtons = find.widgetWithText(OutlinedButton, 'حاضر');
    await t.ensureVisible(presentButtons.last);
    await t.pumpAndSettle();
    await t.tap(presentButtons.last, warnIfMissed: false);
    expect(actions.calls, [('b', AttendanceStatus.present)]);
  });
}
