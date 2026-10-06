import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/enums.dart';
import '../services/contact_launcher.dart';
import '../services/sync_status.dart';
import '../theme/app_theme.dart';
import 'feedback.dart';

/// Big tappable summary card used on dashboards.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.color = AppColors.primary,
    this.background = AppColors.primaryLight,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      label: '$title $value',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: background, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: t.bodyMedium
                              ?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
              Text(value,
                  style: t.headlineSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w800)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left, color: AppColors.textMuted),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Row(children: [
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
          ?trailing,
        ]),
      );
}

/// Labeled info row for profile pages.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.primary, size: 26),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 17, color: AppColors.textMuted)),
          ),
          Expanded(
            child: SelectableText(value.isEmpty ? '—' : value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// Present/absent pill.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final AttendanceStatus? status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      AttendanceStatus.present => ('حاضر', AppColors.present, AppColors.presentLight),
      AttendanceStatus.absent => ('غائب', AppColors.absent, AppColors.absentLight),
      null => ('لم يُسجل', AppColors.textMuted, const Color(0xFFEFEFEF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontWeight: FontWeight.w800, fontSize: 16)),
    );
  }
}

/// Call + WhatsApp buttons (icon AND text, never icon-only).
class ContactButtons extends ConsumerWidget {
  const ContactButtons({super.key, required this.phone, this.whatsApp = true});
  final String phone;
  final bool whatsApp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (phone.isEmpty) {
      return const Text('لا يوجد رقم تليفون',
          style: TextStyle(color: AppColors.textMuted, fontSize: 17));
    }
    final launcher = ref.read(contactLauncherProvider);
    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.present),
          onPressed: () => runGuarded(context, () => launcher.call(phone)),
          icon: const Icon(Icons.phone),
          label: const Text('اتصال'),
        ),
      ),
      if (whatsApp) ...[
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF128C4A)),
            onPressed: () =>
                runGuarded(context, () => launcher.whatsApp(phone)),
            icon: const Icon(Icons.chat),
            label: const Text('واتساب'),
          ),
        ),
      ],
    ]);
  }
}

/// Small header chip showing متصل / غير متصل / جارٍ المزامنة / تمت المزامنة.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final (icon, color) = switch (s) {
      SyncState.online => (Icons.cloud_done, AppColors.present),
      SyncState.offline => (Icons.cloud_off, AppColors.absent),
      SyncState.syncing => (Icons.sync, AppColors.warning),
      SyncState.synced => (Icons.check_circle, AppColors.present),
    };
    return Semantics(
      label: s.label,
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(s.label,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// Big menu tile for the "More" screen.
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.color = AppColors.primary,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Icon(icon, color: color, size: 32),
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle!),
            trailing: const Icon(Icons.chevron_left),
            onTap: onTap,
          ),
        ),
      );
}

String percent(double v) => '${(v * 100).round()}%';
