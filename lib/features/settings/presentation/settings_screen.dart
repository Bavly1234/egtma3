import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../notifications/data/reminder_service.dart';
import '../data/demo_seeder.dart';
import '../data/settings_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(requireUserProvider);
    final auth = ref.read(authRepositoryProvider);

    Widget pref(String key, String title, bool value) => SwitchListTile(
          title: Text(title),
          value: value,
          onChanged: (v) => runGuarded(context, () async {
            await auth.updatePrefs(user.id, user.prefs.copyWith(key, v));
            final updated = ref.read(currentUserProvider).value;
            if (updated != null) {
              await ref.read(reminderServiceProvider).refresh(updated);
            }
          }),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionTitle('حجم الخط'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 1.0, label: Text('عادي')),
                ButtonSegment(value: 1.15, label: Text('كبير')),
                ButtonSegment(value: 1.3, label: Text('أكبر')),
                ButtonSegment(value: 1.5, label: Text('كبير جداً')),
              ],
              selected: {user.textScale},
              onSelectionChanged: (s) =>
                  runGuarded(context, () => auth.updateTextScale(user.id, s.first)),
            ),
          ),
        ),
        const SectionTitle('الإشعارات'),
        Card(
          child: Column(children: [
            pref('meetingReminder', 'تذكير قبل اجتماع الأربعاء', user.prefs.meetingReminder),
            pref('attendanceReminder', 'تذكير بتسجيل الحضور', user.prefs.attendanceReminder),
            pref('followUp', 'الافتقاد المطلوب', user.prefs.followUp),
            pref('birthday', 'أعياد الميلاد', user.prefs.birthday),
            pref('conference', 'المؤتمرات', user.prefs.conference),
            pref('dailyVerse', 'آية اليوم', user.prefs.dailyVerse),
          ]),
        ),
        if (user.isFather) _ChurchSettings(user: user),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await confirmAction(context,
                title: 'تسجيل الخروج', message: 'هل تريدين تسجيل الخروج؟');
            if (!ok) return;
            await ref.read(reminderServiceProvider).stop();
            await auth.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }
}

class _ChurchSettings extends ConsumerWidget {
  const _ChurchSettings({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider).value ?? const AppSettings();
    final repo = ref.read(settingsRepositoryProvider);
    final audit = ref.read(auditRepositoryProvider);

    Future<void> save(AppSettings n) => runGuarded(context, () async {
          await repo.save(n);
          await ref.read(reminderServiceProvider).refresh(user);
          audit.log(
              actor: user,
              action: AuditAction.settingsChanged,
              entityType: 'settings',
              entityId: 'app');
        });

    Widget hour(String title, int value, AppSettings Function(int) update) => ListTile(
          title: Text(title),
          trailing: DropdownButton<int>(
            value: value,
            items: [
              for (var h = 6; h <= 22; h++)
                DropdownMenuItem(value: h, child: Text('${h > 12 ? h - 12 : h} ${h >= 12 ? 'م' : 'ص'}')),
            ],
            onChanged: (v) => v == null ? null : save(update(v)),
          ),
        );

    AppSettings copy({int? m, int? a, int? f, bool? b, bool? v}) => AppSettings(
          meetingReminderHour: m ?? s.meetingReminderHour,
          attendanceReminderHour: a ?? s.attendanceReminderHour,
          followUpReminderHour: f ?? s.followUpReminderHour,
          notifyFatherBirthdays: b ?? s.notifyFatherBirthdays,
          verseNotifications: v ?? s.verseNotifications,
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('إعدادات الكنيسة'),
      Card(
        child: Column(children: [
          hour('موعد تذكير الثلاثاء', s.meetingReminderHour, (h) => copy(m: h)),
          hour('موعد تذكير تسجيل الحضور (الأربعاء)', s.attendanceReminderHour,
              (h) => copy(a: h)),
          hour('موعد تذكير الافتقاد اليومي', s.followUpReminderHour, (h) => copy(f: h)),
          SwitchListTile(
            title: const Text('إشعاري بأعياد ميلاد كل السيدات'),
            value: s.notifyFatherBirthdays,
            onChanged: (v) => save(copy(b: v)),
          ),
          SwitchListTile(
            title: const Text('إرسال آية اليوم للجميع'),
            value: s.verseNotifications,
            onChanged: (v) => save(copy(v: v)),
          ),
        ]),
      ),
      const SectionTitle('بيانات تجريبية'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
                'للتجربة فقط. كل البيانات التجريبية مُعلّمة (تجريبي) '
                'ويمكن حذفها بالكامل قبل الاستخدام الفعلي.',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => runGuarded(context, () async {
                final r = await ref.read(demoSeederProvider).seed(user);
                if (context.mounted) AppToast.success(context, r);
              }),
              icon: const Icon(Icons.science),
              label: const Text('إضافة بيانات تجريبية'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await confirmAction(context,
                    title: 'حذف البيانات التجريبية',
                    message: 'سيتم حذف كل البيانات المعلّمة كتجريبية فقط.',
                    destructive: true,
                    confirmLabel: 'حذف');
                if (!ok || !context.mounted) return;
                await runGuarded(context, () async {
                  final r = await ref.read(demoSeederProvider).remove();
                  if (context.mounted) AppToast.success(context, r);
                });
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('حذف البيانات التجريبية'),
            ),
          ]),
        ),
      ),
    ]);
  }
}
