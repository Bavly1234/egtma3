import 'package:flutter/material.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/woman.dart';

class WomanTile extends StatelessWidget {
  const WomanTile({
    super.key,
    required this.woman,
    this.onTap,
    this.trailing,
    this.servantName,
    this.isMine = false,
  });
  final Woman woman;

  /// Servant of the woman's street (the only assignment).
  final String? servantName;
  final bool isMine;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final w = woman;
    final sub = [
      if (w.streetName.isNotEmpty) w.streetName,
      if (servantName != null) 'الخادمة: $servantName',
    ].join('  •  ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  w.active ? AppColors.primaryLight : const Color(0xFFEEEEEE),
              child: Text(
                w.fullName.isEmpty ? '؟' : w.fullName.characters.first,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.fullName,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w700)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (isMine)
                      const _Badge('✓ شارعك', AppColors.primary,
                          AppColors.primaryLight),
                    if (w.isServant)
                      const _Badge('🎖 خادمة', AppColors.gold, AppColors.goldLight),
                    if (!w.active)
                      const _Badge('غير نشطة', Colors.black54, Color(0xFFEEEEEE)),
                    if (w.consecutiveAbsences >= 2)
                      _Badge('غابت ${w.consecutiveAbsences} مرات متتالية',
                          AppColors.absent, AppColors.absentLight),
                    if (w.activeSuggestionType == SuggestionType.phone)
                      const _Badge('📞 افتقاد تليفوني', AppColors.warning,
                          AppColors.warningLight),
                    if (w.activeSuggestionType == SuggestionType.homeVisit)
                      const _Badge(
                          '🏠 افتقاد منزلي', AppColors.home, AppColors.homeLight),
                  ]),
                ],
              ),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.fg, this.bg);
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
      );
}
