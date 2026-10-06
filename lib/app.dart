import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';

class Egtma3App extends ConsumerWidget {
  const Egtma3App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final userScale = ref.watch(
        currentUserProvider.select((u) => u.value?.textScale ?? 1.0));

    return MaterialApp.router(
      title: 'اجتماع السيدات',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        // Respect the system font size, multiplied by the in-app preference,
        // but cap it so layouts stay usable.
        final mq = MediaQuery.of(context);
        final system = mq.textScaler.scale(1);
        final scale = (system * userScale).clamp(1.0, 1.8);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        );
      },
    );
  }
}
