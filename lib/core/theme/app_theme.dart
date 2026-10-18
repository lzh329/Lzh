import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFFFF8A00);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _seedColor,
    brightness: Brightness.light,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 8,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      labelStyle: const TextStyle(fontSize: 12),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      linearTrackColor: Color(0x1A000000),
      linearMinHeight: 3,
      circularTrackColor: Color(0x1A000000),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    // v2 统一底色：近黑（非纯黑），让卡片有层次
    scaffoldBackgroundColor: const Color(0xFF0F0D0C),
    colorScheme: const ColorScheme.dark(
      surface: Colors.black,
      onSurface: Colors.white,
      primary: Color(0xFFFF8A00),
      onPrimary: Colors.black,
      secondary: Colors.white70,
      onSecondary: Colors.black,
      outline: Colors.white38,
      surfaceContainerHighest: Color(0xFF1B1713),
      primaryContainer: Color(0xFF2A231C),
      onPrimaryContainer: Colors.white,
      secondaryContainer: Color(0xFF2A231C),
      onSecondaryContainer: Colors.white70,
      tertiary: Colors.white54,
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF2A231C),
      onTertiaryContainer: Colors.white,
      onInverseSurface: Colors.black,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Color(0xFF0F0D0C),
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFF1B1713),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 2,
      backgroundColor: Color(0xFFFF8A00),
      foregroundColor: Colors.black,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white38),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.black,
      indicatorColor: const Color(0xFFFF8A00),
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const IconThemeData(color: Colors.black)
              : const IconThemeData(color: Colors.white54)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)
              : const TextStyle(fontSize: 12, color: Colors.white54)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 8,
      backgroundColor: const Color(0xFF1E1E1E),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      labelStyle: const TextStyle(fontSize: 12),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      linearTrackColor: Color(0x1AFFFFFF),
      linearMinHeight: 3,
      circularTrackColor: Color(0x1AFFFFFF),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF23262A),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withAlpha(14),
      thickness: 1,
      space: 1,
    ),
  );

  static const categoryColors = {
    'bodyweight': Color(0xFF38BDF8),
    'gym': Color(0xFFEF5350),
    'cardio': Color(0xFFFF9800),
    'stretch': Color(0xFFFF8A00),
  };

  static const categoryLabels = {
    'bodyweight': '徒手',
    'gym': '器械',
    'cardio': '有氧',
    'stretch': '拉伸',
  };

  static const categoryIcons = {
    'bodyweight': Icons.fitness_center,
    'gym': Icons.monitor_weight,
    'cardio': Icons.directions_run,
    'stretch': Icons.self_improvement,
  };
}
