import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ArcBenchTheme {
  ArcBenchTheme._();

  // ── Brand colors ──
  static const Color arcBlue = Color(0xFF4A9EF7);
  static const Color arcBlueDark = Color(0xFF2962FF);
  static const Color arcBlueGlow = Color(0xFF82B1FF);

  // ── Spark accent ──
  static const Color sparkCyan = Color(0xFF00D4FF);
  static const Color sparkCyanDim = Color(0xFF007A99);

  // ── Surfaces ──
  static const Color surface = Color(0xFF0E0E12);
  static const Color surfaceCard = Color(0xFF18181F);
  static const Color surfaceElevated = Color(0xFF24242E);
  static const Color surfaceGlass = Color(0x0DFFFFFF);

  // ── Semantic ──
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFAB40);
  static const Color success = Color(0xFF69F0AE);

  // ── Text ──
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB0B0B8);
  static const Color textMuted = Color(0xFF6B6B78);

  // ── Terminal ──
  static const Color terminalBg = Color(0xFF0A0A0F);
  static const Color terminalText = Color(0xFFD4D4D4);
  static const Color ansiGreen = Color(0xFF4EC9B0);
  static const Color ansiOrange = Color(0xFFCE9178);
  static const Color ansiBlue = Color(0xFF569CD6);
  static const Color ansiRed = Color(0xFFF44747);
  static const Color ansiYellow = Color(0xFFDCDCAA);
  static const Color ansiMagenta = Color(0xFFC586C0);
  static const Color ansiCyan = Color(0xFF9CDCFE);
  static const Color ansiWhite = Color(0xFFD4D4D4);
  static const Color ansiBrightBlack = Color(0xFF808080);

  // ── Glassmorphism helpers ──
  static ImageFilter get glassBlur => ImageFilter.blur(sigmaX: 24, sigmaY: 24);

  static BoxDecoration get glassDecoration => BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withAlpha(18), width: 1),
      );

  // ── Theme Data ──
  static ThemeData get darkTheme {
    final base = ThemeData.dark();

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: arcBlue,
        secondary: arcBlueDark,
        surface: surface,
        error: error,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: textSecondary),
        labelLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceCard,
        indicatorColor: arcBlue.withAlpha(30),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: arcBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: arcBlue,
          minimumSize: const Size(double.infinity, 56),
          side: const BorderSide(color: arcBlue, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: arcBlue, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: GoogleFonts.inter(color: textMuted),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: arcBlue,
        foregroundColor: Colors.white,
        elevation: 6,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: GoogleFonts.inter(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
