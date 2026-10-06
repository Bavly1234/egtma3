import 'package:flutter/material.dart';

/// Calm, church-appropriate palette with high contrast for older users.
abstract final class AppColors {
  static const primary = Color(0xFF1F3A5F); // deep navy
  static const primaryLight = Color(0xFFE6EDF5);
  static const gold = Color(0xFF9A6B12); // warm liturgical gold (AA on white)
  static const goldLight = Color(0xFFF7EEDB);
  static const background = Color(0xFFFAF7F2); // warm ivory
  static const surface = Colors.white;
  static const text = Color(0xFF1B1B1B);
  static const textMuted = Color(0xFF4A4A4A);
  static const present = Color(0xFF1B6E30);
  static const presentLight = Color(0xFFE3F2E6);
  static const absent = Color(0xFFB3261E);
  static const absentLight = Color(0xFFFBE7E5);
  static const warning = Color(0xFF8A5300);
  static const warningLight = Color(0xFFFFF1D6);
  static const home = Color(0xFF6A1B9A);
  static const homeLight = Color(0xFFF1E6F7);
  static const border = Color(0xFFD9D2C5);
}

abstract final class AppSizes {
  static const touch = 56.0; // minimum touch target for primary actions
  static const radius = 16.0;
  static const gap = 16.0;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.gold,
    surface: AppColors.surface,
    error: AppColors.absent,
  );

  const base = TextTheme(
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 18, height: 1.5),
    bodyMedium: TextStyle(fontSize: 17, height: 1.5),
    bodySmall: TextStyle(fontSize: 15, height: 1.4),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
  );

  final shape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radius));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.apply(
        bodyColor: AppColors.text, displayColor: AppColors.text),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, AppSizes.touch),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, AppSizes.touch),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: const TextStyle(fontSize: 18),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primaryLight,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 15,
            fontWeight:
                s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: AppColors.primary,
          )),
      iconTheme: WidgetStateProperty.all(
          const IconThemeData(size: 28, color: AppColors.primary)),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 12,
      titleTextStyle: TextStyle(
          fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text),
      subtitleTextStyle: TextStyle(fontSize: 16, color: AppColors.textMuted),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: TextStyle(fontSize: 18, color: Colors.white),
    ),
    chipTheme: const ChipThemeData(
      labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    dialogTheme: const DialogThemeData(
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text),
      contentTextStyle: TextStyle(fontSize: 18, color: AppColors.text),
    ),
  );
}
