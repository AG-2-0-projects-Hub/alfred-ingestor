import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Alfred Design System — Daylight + Midnight
///
/// Theme-varying tokens live on [AppPalette] (ThemeExtension).
/// Access in widgets via `context.palette.xxx`.
/// Non-color constants (blur sigma, inner-highlight gradient) stay on [AppTheme].
class AppPalette extends ThemeExtension<AppPalette> {
  // ── Primary / Accent ────────────────────────────────────────────────────
  final Color primary;
  final Color primaryHover;
  final Color primaryDark;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color accent;
  final Color accentContainer;
  final Color onAccentContainer;

  // ── Neutrals ────────────────────────────────────────────────────────────
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // ── Status ──────────────────────────────────────────────────────────────
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;

  // ── Glass ───────────────────────────────────────────────────────────────
  final Color glassTint;
  final Color glassTintStrong;
  final Color glassTintHeavy;
  final Color glassBorder;
  final Color glassBorderStrong;

  // ── Aurora blobs ────────────────────────────────────────────────────────
  final Color auroraTeal;
  final Color auroraSky;
  final Color auroraLavender;
  final Color auroraPeach;

  // ── Elevation ───────────────────────────────────────────────────────────
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> cardShadowHover;
  final List<BoxShadow> drawerShadow;

  const AppPalette({
    required this.primary,
    required this.primaryHover,
    required this.primaryDark,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.accent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.glassTint,
    required this.glassTintStrong,
    required this.glassTintHeavy,
    required this.glassBorder,
    required this.glassBorderStrong,
    required this.auroraTeal,
    required this.auroraSky,
    required this.auroraLavender,
    required this.auroraPeach,
    required this.cardShadow,
    required this.cardShadowHover,
    required this.drawerShadow,
  });

  @override
  AppPalette copyWith({
    Color? primary,
    Color? primaryHover,
    Color? primaryDark,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? accent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? glassTint,
    Color? glassTintStrong,
    Color? glassTintHeavy,
    Color? glassBorder,
    Color? glassBorderStrong,
    Color? auroraTeal,
    Color? auroraSky,
    Color? auroraLavender,
    Color? auroraPeach,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? cardShadowHover,
    List<BoxShadow>? drawerShadow,
  }) {
    return AppPalette(
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      accent: accent ?? this.accent,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      glassTint: glassTint ?? this.glassTint,
      glassTintStrong: glassTintStrong ?? this.glassTintStrong,
      glassTintHeavy: glassTintHeavy ?? this.glassTintHeavy,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBorderStrong: glassBorderStrong ?? this.glassBorderStrong,
      auroraTeal: auroraTeal ?? this.auroraTeal,
      auroraSky: auroraSky ?? this.auroraSky,
      auroraLavender: auroraLavender ?? this.auroraLavender,
      auroraPeach: auroraPeach ?? this.auroraPeach,
      cardShadow: cardShadow ?? this.cardShadow,
      cardShadowHover: cardShadowHover ?? this.cardShadowHover,
      drawerShadow: drawerShadow ?? this.drawerShadow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      onAccentContainer: Color.lerp(onAccentContainer, other.onAccentContainer, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassTintStrong: Color.lerp(glassTintStrong, other.glassTintStrong, t)!,
      glassTintHeavy: Color.lerp(glassTintHeavy, other.glassTintHeavy, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBorderStrong: Color.lerp(glassBorderStrong, other.glassBorderStrong, t)!,
      auroraTeal: Color.lerp(auroraTeal, other.auroraTeal, t)!,
      auroraSky: Color.lerp(auroraSky, other.auroraSky, t)!,
      auroraLavender: Color.lerp(auroraLavender, other.auroraLavender, t)!,
      auroraPeach: Color.lerp(auroraPeach, other.auroraPeach, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      cardShadowHover: t < 0.5 ? cardShadowHover : other.cardShadowHover,
      drawerShadow: t < 0.5 ? drawerShadow : other.drawerShadow,
    );
  }
}

extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

// ── Daylight palette ────────────────────────────────────────────────────────
// Olive/sage tokens from _Context/Design inspo/Design_inspo_Alfred.json.
final AppPalette _daylightPalette = AppPalette(
  primary: const Color(0xFF778643),
  primaryHover: const Color(0xFF8A9A4D),
  primaryDark: const Color(0xFF5D6A35),
  primaryContainer: const Color(0xFFE4E8D4),
  onPrimaryContainer: const Color(0xFF3A4321),
  accent: const Color(0xFF6B7280),
  accentContainer: const Color(0xFFE5E7EB),
  onAccentContainer: const Color(0xFF374151),
  background: const Color(0xFFFEFCFB),
  surface: const Color(0xFFEFEFEF),
  surfaceAlt: const Color(0xFFE8E8E8),
  border: const Color.fromRGBO(0, 0, 0, 0.08),
  borderStrong: const Color.fromRGBO(0, 0, 0, 0.18),
  textPrimary: const Color(0xFF161E29),
  textSecondary: const Color(0xFF3D4452),
  textMuted: const Color(0xFF8A8F98),
  success: const Color(0xFF059669),
  successContainer: const Color(0xFFD1FAE5),
  warning: const Color(0xFFD97706),
  warningContainer: const Color(0xFFFEF3C7),
  danger: const Color(0xFFDC2626),
  dangerContainer: const Color(0xFFFEE2E2),
  glassTint: const Color.fromRGBO(255, 255, 255, 0.60),
  glassTintStrong: const Color.fromRGBO(255, 255, 255, 0.75),
  glassTintHeavy: const Color.fromRGBO(255, 255, 255, 0.90),
  glassBorder: const Color.fromRGBO(0, 0, 0, 0.08),
  glassBorderStrong: const Color.fromRGBO(0, 0, 0, 0.15),
  auroraTeal: const Color.fromRGBO(119, 134, 67, 0.15),
  auroraSky: const Color.fromRGBO(156, 163, 175, 0.20),
  auroraLavender: const Color.fromRGBO(119, 134, 67, 0.08),
  auroraPeach: const Color.fromRGBO(254, 252, 251, 0.50),
  cardShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 30,
      offset: const Offset(0, 4),
    ),
  ],
  cardShadowHover: [
    BoxShadow(
      color: const Color(0xFF778643).withValues(alpha: 0.20),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ],
  drawerShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.18),
      blurRadius: 40,
      offset: const Offset(-4, 0),
    ),
  ],
);

// ── Midnight palette ────────────────────────────────────────────────────────
// Olive/sage tokens from _Context/Design inspo/Design_inspo_Alfred.json.
final AppPalette _midnightPalette = AppPalette(
  primary: const Color(0xFF778643),
  primaryHover: const Color(0xFF8A9A4D),
  primaryDark: const Color(0xFF5D6A35),
  primaryContainer: const Color.fromRGBO(119, 134, 67, 0.18),
  onPrimaryContainer: const Color(0xFFFEFCFB),
  accent: const Color(0xFF9CA3AF),
  accentContainer: const Color.fromRGBO(156, 163, 175, 0.15),
  onAccentContainer: const Color(0xFFFEFCFB),
  background: const Color(0xFF050506),
  surface: const Color(0xFF0A0A0C),
  surfaceAlt: const Color(0xFF0D0D10),
  border: const Color.fromRGBO(255, 255, 255, 0.08),
  borderStrong: const Color.fromRGBO(255, 255, 255, 0.20),
  textPrimary: const Color(0xFFFEFCFB),
  textSecondary: const Color(0xFFEFEFEF),
  textMuted: const Color(0xFF8A8F98),
  success: const Color(0xFF4ADE80),
  successContainer: const Color.fromRGBO(74, 222, 128, 0.15),
  warning: const Color(0xFFFBBF24),
  warningContainer: const Color.fromRGBO(251, 191, 36, 0.15),
  danger: const Color(0xFFF87171),
  dangerContainer: const Color.fromRGBO(248, 113, 113, 0.15),
  glassTint: const Color.fromRGBO(255, 255, 255, 0.05),
  glassTintStrong: const Color.fromRGBO(255, 255, 255, 0.10),
  glassTintHeavy: const Color.fromRGBO(255, 255, 255, 0.15),
  glassBorder: const Color.fromRGBO(255, 255, 255, 0.08),
  glassBorderStrong: const Color.fromRGBO(255, 255, 255, 0.20),
  auroraTeal: const Color.fromRGBO(119, 134, 67, 0.20),
  auroraSky: const Color.fromRGBO(254, 252, 251, 0.40),
  auroraLavender: const Color.fromRGBO(119, 134, 67, 0.12),
  auroraPeach: const Color.fromRGBO(156, 163, 175, 0.15),
  cardShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.30),
      blurRadius: 30,
      offset: const Offset(0, 4),
    ),
  ],
  cardShadowHover: [
    BoxShadow(
      color: const Color(0xFF778643).withValues(alpha: 0.25),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.30),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ],
  drawerShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.50),
      blurRadius: 40,
      offset: const Offset(-4, 0),
    ),
  ],
);

class AppTheme {
  AppTheme._();

  // ── Non-color constants ───────────────────────────────────────────────────
  static const LinearGradient glassInnerHighlight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x30FFFFFF), Color(0x00FFFFFF)],
  );
  static const double glassBlurSigma = 20.0;
  static const double glassBlurSigmaHeavy = 24.0;

  // Design-token easing: cubic-bezier(0.16, 1, 0.3, 1) — replaces Curves.easeOut/easeInOut.
  static const Cubic standardEasing = Cubic(0.16, 1.0, 0.3, 1.0);

  // Design-token interaction-scale: 0.97 → 1.0 on press.
  static const double pressScale = 0.97;

  // ── Themes ────────────────────────────────────────────────────────────────
  static ThemeData get daylightTheme => _buildTheme(_daylightPalette, Brightness.light);
  static ThemeData get midnightTheme => _buildTheme(_midnightPalette, Brightness.dark);

  static ThemeData _buildTheme(AppPalette p, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.primary,
        onPrimary: brightness == Brightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFFFFFFFF),
        primaryContainer: p.primaryContainer,
        onPrimaryContainer: p.onPrimaryContainer,
        secondary: p.accent,
        onSecondary: const Color(0xFFFFFFFF),
        secondaryContainer: p.accentContainer,
        onSecondaryContainer: p.onAccentContainer,
        tertiary: p.auroraLavender,
        onTertiary: const Color(0xFFFFFFFF),
        tertiaryContainer: brightness == Brightness.dark
            ? const Color(0xFF2D1B69)
            : const Color(0xFFEDE9FE),
        onTertiaryContainer: brightness == Brightness.dark
            ? const Color(0xFFDDD6FE)
            : const Color(0xFF4C1D95),
        surface: p.surface,
        onSurface: p.textPrimary,
        surfaceContainerHighest: p.surfaceAlt,
        onSurfaceVariant: p.textSecondary,
        error: p.danger,
        onError: const Color(0xFFFFFFFF),
        errorContainer: p.dangerContainer,
        onErrorContainer: brightness == Brightness.dark
            ? const Color(0xFFFECACA)
            : const Color(0xFF7F1D1D),
        outline: p.border,
        outlineVariant: p.borderStrong,
        shadow: const Color(0xFF000000),
        scrim: const Color(0xFF000000),
        inverseSurface: p.textPrimary,
        onInverseSurface: p.background,
        inversePrimary: p.primaryContainer,
      ),
      scaffoldBackgroundColor: p.background,
      extensions: [p],
      textTheme: _buildTextTheme(p),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0x30000000),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w300,
          color: p.primary,
        ),
        iconTheme: IconThemeData(color: p.textSecondary),
        actionsIconTheme: IconThemeData(color: p.textSecondary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border, width: 1),
        ),
        color: p.surface,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: const Color(0xFFFFFFFF),
          disabledBackgroundColor: p.border,
          disabledForegroundColor: p.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          side: BorderSide(color: p.border, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.danger, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: p.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: p.textMuted, fontSize: 14),
        prefixIconColor: p.textMuted,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.textMuted,
        indicatorColor: p.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: p.border,
        labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
      ),
      dividerTheme: DividerThemeData(
        color: p.border,
        space: 1,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        shadowColor: const Color(0x40000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: p.surface,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 17,
          fontWeight: FontWeight.w300,
          color: p.textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceAlt,
        contentTextStyle: GoogleFonts.inter(color: p.textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500, fontSize: 14, color: p.textPrimary),
        subtitleTextStyle: GoogleFonts.inter(fontSize: 12, color: p.textSecondary),
      ),
      splashColor: p.primary.withValues(alpha: 0.10),
      highlightColor: p.primary.withValues(alpha: 0.08),
    );
  }

  static TextTheme _buildTextTheme(AppPalette p) {
    final heading = GoogleFonts.spaceGroteskTextTheme();
    final inter = GoogleFonts.interTextTheme();
    return TextTheme(
      displayLarge:  heading.displayLarge?.copyWith(fontWeight: FontWeight.w300, color: p.textPrimary),
      displayMedium: heading.displayMedium?.copyWith(fontWeight: FontWeight.w300, color: p.textPrimary),
      displaySmall:  heading.displaySmall?.copyWith(fontWeight: FontWeight.w500, color: p.textPrimary),
      headlineLarge:  heading.headlineLarge?.copyWith(fontWeight: FontWeight.w300, color: p.textPrimary),
      headlineMedium: heading.headlineMedium?.copyWith(fontWeight: FontWeight.w500, color: p.textPrimary),
      headlineSmall:  heading.headlineSmall?.copyWith(fontWeight: FontWeight.w500, color: p.textPrimary),
      titleLarge:  heading.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: p.textPrimary),
      titleMedium: heading.titleMedium?.copyWith(fontWeight: FontWeight.w500, color: p.textPrimary),
      titleSmall:  heading.titleSmall?.copyWith(fontWeight: FontWeight.w500, color: p.textPrimary),
      bodyLarge:  inter.bodyLarge?.copyWith(color: p.textPrimary, height: 1.6),
      bodyMedium: inter.bodyMedium?.copyWith(color: p.textPrimary, height: 1.6),
      bodySmall:  inter.bodySmall?.copyWith(color: p.textSecondary, height: 1.5),
      labelLarge:  inter.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      labelMedium: inter.labelMedium?.copyWith(fontWeight: FontWeight.w500, color: p.textSecondary),
      labelSmall:  inter.labelSmall?.copyWith(color: p.textMuted),
    );
  }
}
