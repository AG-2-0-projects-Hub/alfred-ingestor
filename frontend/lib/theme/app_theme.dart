import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Alfred Design System — Dark Edition
///
/// Primary : Electric Indigo #6366F1
/// Accent  : Soft Mint       #10B981
/// Base    : Void Slate      #0D0D12
class AppTheme {
  AppTheme._();

  // ── Primary — Electric Indigo ─────────────────────────────────────────────
  static const Color primary            = Color(0xFF6366F1);
  static const Color primaryHover       = Color(0xFF818CF8);
  static const Color primaryDark        = Color(0xFF4338CA);
  static const Color primaryContainer   = Color(0xFF1E1B4B);
  static const Color onPrimaryContainer = Color(0xFFC7D2FE);

  // ── Accent — Soft Mint ────────────────────────────────────────────────────
  static const Color accent             = Color(0xFF10B981);
  static const Color accentContainer   = Color(0xFF064E3B);
  static const Color onAccentContainer = Color(0xFF6EE7B7);

  // ── Neutrals — Void Slate scale ───────────────────────────────────────────
  static const Color background    = Color(0xFF0D0D12);
  static const Color surface       = Color(0xFF16161F);
  static const Color surfaceAlt    = Color(0xFF1E1E2A);
  static const Color border        = Color(0xFF2D2D3F);
  static const Color borderStrong  = Color(0xFF3D3D55);
  static const Color textPrimary   = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted     = Color(0xFF64748B);

  // ── Status ────────────────────────────────────────────────────────────────
  static const Color success           = Color(0xFF10B981);
  static const Color successContainer  = Color(0xFF064E3B);
  static const Color warning           = Color(0xFFF59E0B);
  static const Color warningContainer  = Color(0xFF451A03);
  static const Color danger            = Color(0xFFEF4444);
  static const Color dangerContainer   = Color(0xFF450A0A);

  // ── Glass — tuned for dark background ─────────────────────────────────────
  static const Color glassTint         = Color(0x18FFFFFF); // white @ 9.4%
  static const Color glassTintStrong   = Color(0x28FFFFFF); // white @ 15.7%
  static const Color glassTintHeavy    = Color(0x40FFFFFF); // white @ 25%
  static const Color glassBorder       = Color(0x22FFFFFF); // white @ 13%
  static const Color glassBorderStrong = Color(0x44FFFFFF); // white @ 26%
  static const LinearGradient glassInnerHighlight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x30FFFFFF), Color(0x00FFFFFF)],
  );
  static const double glassBlurSigma      = 18.0;
  static const double glassBlurSigmaHeavy = 28.0;

  // ── Aurora — dark palette blobs ───────────────────────────────────────────
  static const Color auroraTeal     = Color(0xFF6366F1); // indigo
  static const Color auroraSky      = Color(0xFF10B981); // mint
  static const Color auroraLavender = Color(0xFF7C3AED); // violet
  static const Color auroraPeach    = Color(0xFFF59E0B); // amber

  // ── Elevation ─────────────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get cardShadowHover => [
    BoxShadow(
      color: primary.withValues(alpha: 0.22),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get drawerShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 40,
      offset: const Offset(-4, 0),
    ),
  ];

  // ── Theme ─────────────────────────────────────────────────────────────────
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: accent,
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: accentContainer,
        onSecondaryContainer: onAccentContainer,
        tertiary: Color(0xFF7C3AED),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFF2D1B69),
        onTertiaryContainer: Color(0xFFDDD6FE),
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: surfaceAlt,
        onSurfaceVariant: textSecondary,
        error: danger,
        onError: Color(0xFFFFFFFF),
        errorContainer: dangerContainer,
        onErrorContainer: Color(0xFFFECACA),
        outline: border,
        outlineVariant: borderStrong,
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: textPrimary,
        onInverseSurface: Color(0xFF0D0D12),
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
        shadowColor: const Color(0x30000000),
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
        fillColor: surfaceAlt,
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
      tabBarTheme: TabBarThemeData(
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
      dialogTheme: DialogThemeData(
        elevation: 8,
        shadowColor: const Color(0x40000000),
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
        backgroundColor: surfaceAlt,
        contentTextStyle: GoogleFonts.inter(color: textPrimary, fontSize: 14),
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
        titleTextStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500, fontSize: 14, color: textPrimary),
        subtitleTextStyle:
            GoogleFonts.inter(fontSize: 12, color: textSecondary),
      ),
      splashColor: primary.withValues(alpha: 0.10),
      highlightColor: primary.withValues(alpha: 0.08),
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
