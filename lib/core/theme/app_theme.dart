import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material 3 Expressive Design System for CloudBeat
/// Supporting dynamic color on Android 12+ and exact Green Medium Contrast fallback.
class AppTheme {
  // Light Scheme Fallback (Green Medium Contrast)
  static const Color lightPrimary = Color(0xFF12512E);
  static const Color lightOnPrimary = Color(0xFFFEFFFE);
  static const Color lightPrimaryContainer = Color(0xFFB1F1C5);
  static const Color lightOnPrimaryContainer = Color(0xFF00391C);
  static const Color lightSecondary = Color(0xFF3A4B3F);
  static const Color lightSecondaryContainer = Color(0xFFD3E8D8);
  static const Color lightOnSecondaryContainer = Color(0xFF243429);
  static const Color lightTertiaryContainer = Color(0xFFBBEBF2);
  static const Color lightOnTertiaryContainer = Color(0xFF0B363B);
  static const Color lightSurface = Color(0xFFF5FBF6);
  static const Color lightSurfaceContainerLow = Color(0xFFEFF5F1);
  static const Color lightSurfaceContainer = Color(0xFFEAEFEB);
  static const Color lightSurfaceContainerHigh = Color(0xFFE4EAE5);
  static const Color lightSurfaceContainerHighest = Color(0xFFDEE4E0);
  static const Color lightOnSurface = Color(0xFF181C1A);
  static const Color lightOnSurfaceVariant = Color(0xFF333E36);
  static const Color lightOutline = Color(0xFF566159);
  static const Color lightOutlineVariant = Color(0xFF94A198);
  static const Color lightInverseSurface = Color(0xFF2D312E);
  static const Color lightInverseOnSurface = Color(0xFFECF2EE);
  static const Color lightInversePrimary = Color(0xFF96D5A9);
  static const Color lightError = Color(0xFFB3261E);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightErrorContainer = Color(0xFFF9DEDC);
  static const Color lightOnErrorContainer = Color(0xFF410E0B);

  // Dark Scheme Fallback (Green Medium Contrast)
  static const Color darkPrimary = Color(0xFFA3E3B7);
  static const Color darkOnPrimary = Color(0xFF00391C);
  static const Color darkPrimaryContainer = Color(0xFF12512E);
  static const Color darkOnPrimaryContainer = Color(0xFFC6FED6);
  static const Color darkSecondary = Color(0xFFC5D9CB);
  static const Color darkSecondaryContainer = Color(0xFF3A4B3F);
  static const Color darkOnSecondaryContainer = Color(0xFFE1F6E7);
  static const Color darkTertiaryContainer = Color(0xFF1E4D54);
  static const Color darkOnTertiaryContainer = Color(0xFFCEF8FF);
  static const Color darkSurface = Color(0xFF101411);
  static const Color darkSurfaceContainerLow = Color(0xFF181C1A);
  static const Color darkSurfaceContainer = Color(0xFF1C211E);
  static const Color darkSurfaceContainerHigh = Color(0xFF272B28);
  static const Color darkSurfaceContainerHighest = Color(0xFF313633);
  static const Color darkOnSurface = Color(0xFFDEE4E0);
  static const Color darkOnSurfaceVariant = Color(0xFFCBD8CE);
  static const Color darkOutline = Color(0xFFA2AEA5);
  static const Color darkOutlineVariant = Color(0xFF6E7A71);
  static const Color darkInverseSurface = Color(0xFFDEE4E0);
  static const Color darkInverseOnSurface = Color(0xFF2D312E);
  static const Color darkInversePrimary = Color(0xFF2E6A45);
  static const Color darkError = Color(0xFFF2B8B5);
  static const Color darkOnError = Color(0xFF601410);
  static const Color darkErrorContainer = Color(0xFF8C1D18);
  static const Color darkOnErrorContainer = Color(0xFFF9DEDC);

  // Backward compatibility static aliases mapped to Dark Scheme default
  static const Color primary = darkPrimary;
  static const Color secondary = darkSecondary;
  static const Color background = darkSurface;
  static const Color surface = darkSurface;
  static const Color surfaceLight = darkSurfaceContainerLow;
  static const Color card = darkSurfaceContainer;
  static const Color textPrimary = darkOnSurface;
  static const Color textSecondary = darkOnSurfaceVariant;
  static const Color textMuted = darkOutline;
  static const Color accentGradientStart = darkPrimary;
  static const Color accentGradientEnd = Color(0xFF12512E);

  static ColorScheme get fallbackLightScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: lightPrimary,
        onPrimary: lightOnPrimary,
        primaryContainer: lightPrimaryContainer,
        onPrimaryContainer: lightOnPrimaryContainer,
        secondary: lightSecondary,
        onSecondary: lightOnPrimary,
        secondaryContainer: lightSecondaryContainer,
        onSecondaryContainer: lightOnSecondaryContainer,
        tertiary: Color(0xFF006874),
        onTertiary: Colors.white,
        tertiaryContainer: lightTertiaryContainer,
        onTertiaryContainer: lightOnTertiaryContainer,
        error: lightError,
        onError: lightOnError,
        errorContainer: lightErrorContainer,
        onErrorContainer: lightOnErrorContainer,
        surface: lightSurface,
        onSurface: lightOnSurface,
        onSurfaceVariant: lightOnSurfaceVariant,
        outline: lightOutline,
        outlineVariant: lightOutlineVariant,
        inverseSurface: lightInverseSurface,
        onInverseSurface: lightInverseOnSurface,
        inversePrimary: lightInversePrimary,
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: lightSurfaceContainerLow,
        surfaceContainer: lightSurfaceContainer,
        surfaceContainerHigh: lightSurfaceContainerHigh,
        surfaceContainerHighest: lightSurfaceContainerHighest,
      );

  static ColorScheme get fallbackDarkScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: darkPrimary,
        onPrimary: darkOnPrimary,
        primaryContainer: darkPrimaryContainer,
        onPrimaryContainer: darkOnPrimaryContainer,
        secondary: darkSecondary,
        onSecondary: darkOnPrimary,
        secondaryContainer: darkSecondaryContainer,
        onSecondaryContainer: darkOnSecondaryContainer,
        tertiary: Color(0xFF80D5E3),
        onTertiary: Color(0xFF00363D),
        tertiaryContainer: darkTertiaryContainer,
        onTertiaryContainer: darkOnTertiaryContainer,
        error: darkError,
        onError: darkOnError,
        errorContainer: darkErrorContainer,
        onErrorContainer: darkOnErrorContainer,
        surface: darkSurface,
        onSurface: darkOnSurface,
        onSurfaceVariant: darkOnSurfaceVariant,
        outline: darkOutline,
        outlineVariant: darkOutlineVariant,
        inverseSurface: darkInverseSurface,
        onInverseSurface: darkInverseOnSurface,
        inversePrimary: darkInversePrimary,
        surfaceContainerLowest: Color(0xFF0B0F0C),
        surfaceContainerLow: darkSurfaceContainerLow,
        surfaceContainer: darkSurfaceContainer,
        surfaceContainerHigh: darkSurfaceContainerHigh,
        surfaceContainerHighest: darkSurfaceContainerHighest,
      );

  static TextTheme _buildRobotoSerifTextTheme(TextTheme base, Color onSurface, Color onSurfaceVariant) {
    return GoogleFonts.robotoSerifTextTheme(base).copyWith(
      displayLarge: GoogleFonts.robotoSerif(
        fontSize: 57,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.25,
      ),
      displayMedium: GoogleFonts.robotoSerif(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      headlineLarge: GoogleFonts.robotoSerif(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: onSurface,
      ),
      headlineMedium: GoogleFonts.robotoSerif(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      headlineSmall: GoogleFonts.robotoSerif(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleLarge: GoogleFonts.robotoSerif(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleMedium: GoogleFonts.robotoSerif(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleSmall: GoogleFonts.robotoSerif(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyLarge: GoogleFonts.robotoSerif(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodyMedium: GoogleFonts.robotoSerif(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
      ),
      bodySmall: GoogleFonts.robotoSerif(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.robotoSerif(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      labelMedium: GoogleFonts.robotoSerif(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.robotoSerif(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: onSurfaceVariant,
      ),
    );
  }

  static ThemeData buildTheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final textTheme = _buildRobotoSerifTextTheme(baseTextTheme, scheme.onSurface, scheme.onSurfaceVariant);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            );
          }
          return textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.secondaryContainer,
        labelStyle: textTheme.labelMedium,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.all(scheme.outline),
      ),
    );
  }

  static ThemeData get lightTheme => buildTheme(fallbackLightScheme);
  static ThemeData get darkTheme => buildTheme(fallbackDarkScheme);
}
