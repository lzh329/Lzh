import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF66BB6A);

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
    scaffoldBackgroundColor: Colors.black,
    colorScheme: const ColorScheme.dark(
      surface: Colors.black,
      onSurface: Colors.white,
      primary: Colors.white,
      onPrimary: Colors.black,
      secondary: Colors.white70,
      onSecondary: Colors.black,
      outline: Colors.white38,
      surfaceContainerHighest: Color(0xFF1A1A1A),
      primaryContainer: Color(0xFF2A2A2A),
      onPrimaryContainer: Colors.white,
      secondaryContainer: Color(0xFF2A2A2A),
      onSecondaryContainer: Colors.white70,
      tertiary: Colors.white54,
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF2A2A2A),
      onTertiaryContainer: Colors.white,
      onInverseSurface: Colors.black,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 2,
      backgroundColor: Colors.white,
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
  );

  static const categoryColors = {
    'bodyweight': Color(0xFF42A5F5),
    'gym': Color(0xFFEF5350),
    'cardio': Color(0xFFFF9800),
    'stretch': Color(0xFF66BB6A),
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
