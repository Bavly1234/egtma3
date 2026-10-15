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

  /// The app icon (three women under a Coptic cross), drawn by
  /// tool/make_icon.py.
  @override
  Widget build(BuildContext context) => ClipOval(
        child: Image.asset('assets/icon/app_icon.png',
            width: size, height: size, fit: BoxFit.cover),
      );
}
