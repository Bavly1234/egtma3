import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppLogo(size: 110),
            SizedBox(height: 24),
            Text('اجتماع السيدات',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('Egtma3',
                style: TextStyle(color: AppColors.goldLight, fontSize: 18)),
            SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.white),
          ]),
        ),
      );
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 80});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.goldLight,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.gold, width: 3),
        ),
        child: Icon(Icons.church, size: size * .55, color: AppColors.primary),
      );
}
