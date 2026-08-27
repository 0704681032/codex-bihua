import 'package:flutter/material.dart';

class AppPalette {
  static const Color pageBg = Color(0xFFF8F2F2);
  static const Color surfacePink = Color(0xFFF3DEDE);
  static const Color primaryBrown = Color(0xFF9F4A3C);
  static const Color primaryBrownDark = Color(0xFF7E3228);
  static const Color textMain = Color(0xFF3A2626);
  static const Color guideRed = Color(0xFFFF4B5C);
  static const Color strokeBlack = Color(0xFF24242A);
  // 「幽灵墨」图层色：仅透明度参与合成（saveLayer 只取其 alpha ≈ 16.5%），
  // 图层内容用不透明 strokeBlack 绘制；整层叠在画布底色上合成 ≈ #CFD0D3，
  // 与旧实心灰 #CFCFD4 观感一致。取证与约束见 AGENTS.md 2026-08-25 待办。
  static const Color strokeGhost = Color(0x2B24242A);
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
    // 随包中文字体（见 pubspec fonts 段），避免运行时 CDN 字体缺失。
    fontFamily: 'NotoSansSC',
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
