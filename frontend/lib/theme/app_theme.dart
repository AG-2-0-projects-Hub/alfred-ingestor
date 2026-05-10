import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Alfred Design System
///
/// Primary : Teal  #0F766E — trust, property management, calm authority
/// Accent  : Sky   #0EA5E9 — freedom, openness, the product's core promise
/// Neutrals: Slate scale   — clean, modern, readable
class AppTheme {
  AppTheme._();

  // ── Primary — Teal ────────────────────────────────────────────────────────
  static const Color primary            = Color(0xFF0F766E);
  static const Color primaryHover       = Color(0xFF0D9488);
  static const Color primaryDark        = Color(0xFF0D5E57);
  static const Color primaryContainer   = Color(0xFFCCFBF1);
  static const Color onPrimaryContainer = Color(0xFF134E4A);

  // ── Accent — Sky (freedom flair) ─────────────────────────────────────────
  static const Color accent              = Color(0xFF0EA5E9);
  static const Color accentContainer    = Color(0xFFE0F2FE);
  static const Color onAccentContainer  = Color(0xFF0369A1);

  // ── Neutrals — Slate ─────────────────────────────────────────────────────
  static const Color background    = Color(0xFFF8FAFC);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceAlt    = Color(0xFFF1F5F9);
  static const Color border        = Color(0xFFE2E8F0);
  static const Color borderStrong  = Color(0xFFCBD5E1);
  static const Color textPrimary   = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted     = Color(0xFF94A3B8);

  // ── Status ────────────────────────────────────────────────────────────────
  static const Color success           = Color(0xFF059669);
  static const Color successContainer  = Color(0xFFD1FAE5);
  static const Color warning           = Color(0xFFD97706);
  static const Color warningContainer  = Color(0xFFFEF3C7);
  static const Color danger            = Color(0xFFDC2626);
  static const Color dangerContainer   = Color(0xFFFEE2E2);

  // ── Elevation ─────────────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withOpacity(0.06),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get cardShadowHover => [
    BoxShadow(
      color: primary.withOpacity(0.12),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withOpacity(0.04),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get drawerShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withOpacity(0.18),
      blurRadius: 40,
      offset: const Offset(-4, 0),
    ),
  ];

  // ── Theme ─────────────────────────────────────────────────────────────────
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: primary,
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: accent,
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: accentContainer,
        onSecondaryContainer: onAccentContainer,
        tertiary: Color(0xFF14B8A6),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFCCFBF1),
        onTertiaryContainer: Color(0xFF134E4A),
        surface: surface,
        onSurface: textPrimary,
        surfaceVariant: surfaceAlt,
        onSurfaceVariant: textSecondary,
        // ignore: deprecated_member_use
        background: background,
        // ignore: deprecated_member_use
        onBackground: textPrimary,
        error: danger,
        onError: Color(0xFFFFFFFF),
        errorContainer: dangerContainer,
        onErrorContainer: Color(0xFF7F1D1D),
        outline: border,
        outlineVariant: borderStrong,
        shadow: Color(0xFF0F172A),
        scrim: Color(0xFF0F172A),
        inverseSurface: textPrimary,
        onInverseSurface: surface,
        inversePrimary: primaryContainer,
      ),
      scaffoldBackgroundColor: background,
      textTheme: _buildTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0x10000000),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        iconTheme: const IconThemeData(color: textSecondary),
        actionsIconTheme: const IconThemeData(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
        color: surface,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: const Color(0xFFFFFFFF),
          disabledBackgroundColor: border,
          disabledForegroundColor: textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: border, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 14),
        prefixIconColor: textMuted,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
        labelStyle:
            GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      dialogTheme: DialogTheme(
        elevation: 8,
        shadowColor: const Color(0x20000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: surface,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: GoogleFonts.inter(color: surface, fontSize: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14, color: textPrimary),
        subtitleTextStyle:
            GoogleFonts.inter(fontSize: 12, color: textSecondary),
      ),
      splashColor: primary.withOpacity(0.08),
      highlightColor: primary.withOpacity(0.06),
    );
  }

  static TextTheme _buildTextTheme() {
    final poppins = GoogleFonts.poppinsTextTheme();
    final inter = GoogleFonts.interTextTheme();
    return TextTheme(
      displayLarge:  poppins.displayLarge?.copyWith(fontWeight: FontWeight.w700, color: textPrimary),
      displayMedium: poppins.displayMedium?.copyWith(fontWeight: FontWeight.w700, color: textPrimary),
      displaySmall:  poppins.displaySmall?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      headlineLarge:  poppins.headlineLarge?.copyWith(fontWeight: FontWeight.w700, color: textPrimary),
      headlineMedium: poppins.headlineMedium?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      headlineSmall:  poppins.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      titleLarge:  poppins.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium: poppins.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      titleSmall:  poppins.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge:  inter.bodyLarge?.copyWith(color: textPrimary, height: 1.6),
      bodyMedium: inter.bodyMedium?.copyWith(color: textPrimary, height: 1.6),
      bodySmall:  inter.bodySmall?.copyWith(color: textSecondary, height: 1.5),
      labelLarge:  inter.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      labelMedium: inter.labelMedium?.copyWith(fontWeight: FontWeight.w500, color: textSecondary),
      labelSmall:  inter.labelSmall?.copyWith(color: textMuted),
    );
  }
}
