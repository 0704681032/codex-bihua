import 'package:flutter/material.dart';

class AppPalette {
  static const Color pageBg = Color(0xFFF8F2F2);
  static const Color surfacePink = Color(0xFFF3DEDE);
  static const Color primaryBrown = Color(0xFF9F4A3C);
  static const Color primaryBrownDark = Color(0xFF7E3228);
  static const Color textMain = Color(0xFF3A2626);
  static const Color guideRed = Color(0xFFFF4B5C);
  static const Color strokeBlack = Color(0xFF24242A);
  static const Color strokeGrey = Color(0xFFCFCFD4);
  static const Color white = Colors.white;
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppPalette.primaryBrown,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppPalette.primaryBrown,
    secondary: AppPalette.guideRed,
    surface: AppPalette.surfacePink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppPalette.pageBg,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppPalette.textMain),
      bodyMedium: TextStyle(color: AppPalette.textMain),
      titleLarge: TextStyle(
        color: AppPalette.textMain,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: AppPalette.textMain,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.pageBg,
      foregroundColor: AppPalette.textMain,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppPalette.textMain,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppPalette.primaryBrown,
      contentTextStyle: TextStyle(color: AppPalette.white),
    ),
  );
}
