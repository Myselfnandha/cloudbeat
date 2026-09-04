import 'package:flutter/material.dart';

class AppTheme {
  // OLED Dark Palette
  static const Color background = Color(0xFF07090E);
  static const Color surface = Color(0xFF10141D);
  static const Color surfaceLight = Color(0xFF181F2C);
  static const Color card = Color(0xFF131822);

  // Vibrant Accents
  static const Color primary = Color(0xFF00E5FF);       // Electric Cyan
  static const Color secondary = Color(0xFF00E676);     // Neon Emerald
  static const Color accentGradientStart = Color(0xFF00E5FF);
  static const Color accentGradientEnd = Color(0xFF7C4DFF);

  // Text Colors
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.95),
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 16,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
