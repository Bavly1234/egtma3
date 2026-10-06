import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../data/verse_repository.dart';

class VerseCard extends ConsumerWidget {
  const VerseCard({super.key, this.expanded = false});
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verse = ref.watch(todayVerseProvider).value;
    if (verse == null) return const SizedBox.shrink();
    return Card(
      color: AppColors.goldLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        side: const BorderSide(color: AppColors.gold),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        onTap: expanded ? null : () => context.push(Routes.verse),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.menu_book, color: AppColors.gold, size: 28),
                SizedBox(width: 8),
                Text('آية اليوم',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold)),
              ]),
              const SizedBox(height: 12),
              Text(
                verse.text,
                maxLines: expanded ? null : 4,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: expanded ? 26 : 20,
                    height: 1.7,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text('(${verse.reference})',
                    style: const TextStyle(
                        fontSize: 17,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
