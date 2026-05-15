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
final AppPalette _daylightPalette = AppPalette(
  primary: const Color(0xFF0F766E),
  primaryHover: const Color(0xFF0D9488),
  primaryDark: const Color(0xFF0D5E57),
  primaryContainer: const Color(0xFFCCFBF1),
  onPrimaryContainer: const Color(0xFF134E4A),
  accent: const Color(0xFF0EA5E9),
  accentContainer: const Color(0xFFE0F2FE),
  onAccentContainer: const Color(0xFF0369A1),
  background: const Color(0xFFF8FAFC),
  surface: const Color(0xFFFFFFFF),
  surfaceAlt: const Color(0xFFF1F5F9),
  border: const Color(0xFFE2E8F0),
  borderStrong: const Color(0xFFCBD5E1),
  textPrimary: const Color(0xFF1E293B),
  textSecondary: const Color(0xFF64748B),
  textMuted: const Color(0xFF94A3B8),
  success: const Color(0xFF059669),
  successContainer: const Color(0xFFD1FAE5),
  warning: const Color(0xFFD97706),
  warningContainer: const Color(0xFFFEF3C7),
  danger: const Color(0xFFDC2626),
  dangerContainer: const Color(0xFFFEE2E2),
  glassTint: const Color(0x99FFFFFF),
  glassTintStrong: const Color(0xCCFFFFFF),
  glassTintHeavy: const Color(0xE6FFFFFF),
  glassBorder: const Color(0x33FFFFFF),
  glassBorderStrong: const Color(0x4DFFFFFF),
  auroraTeal: const Color(0xFF14B8A6),
  auroraSky: const Color(0xFF38BDF8),
  auroraLavender: const Color(0xFFA78BFA),
  auroraPeach: const Color(0xFFFDA4AF),
  cardShadow: [
    BoxShadow(
      color: const Color(0xFF1E293B).withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
  cardShadowHover: [
    BoxShadow(
      color: const Color(0xFF0F766E).withValues(alpha: 0.18),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: const Color(0xFF1E293B).withValues(alpha: 0.10),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ],
  drawerShadow: [
    BoxShadow(
      color: const Color(0xFF1E293B).withValues(alpha: 0.18),
      blurRadius: 40,
      offset: const Offset(-4, 0),
    ),
  ],
);

// ── Midnight palette ────────────────────────────────────────────────────────
final AppPalette _midnightPalette = AppPalette(
  primary: const Color(0xFF6366F1),
  primaryHover: const Color(0xFF818CF8),
  primaryDark: const Color(0xFF4338CA),
  primaryContainer: const Color(0xFF1E1B4B),
  onPrimaryContainer: const Color(0xFFC7D2FE),
  accent: const Color(0xFF10B981),
  accentContainer: const Color(0xFF064E3B),
  onAccentContainer: const Color(0xFF6EE7B7),
  background: const Color(0xFF0D0D12),
  surface: const Color(0xFF16161F),
  surfaceAlt: const Color(0xFF1E1E2A),
  border: const Color(0xFF2D2D3F),
  borderStrong: const Color(0xFF3D3D55),
  textPrimary: const Color(0xFFF9FAFB),
  textSecondary: const Color(0xFF94A3B8),
  textMuted: const Color(0xFF64748B),
  success: const Color(0xFF10B981),
  successContainer: const Color(0xFF064E3B),
  warning: const Color(0xFFF59E0B),
  warningContainer: const Color(0xFF451A03),
  danger: const Color(0xFFEF4444),
  dangerContainer: const Color(0xFF450A0A),
  glassTint: const Color(0x18FFFFFF),
  glassTintStrong: const Color(0x28FFFFFF),
  glassTintHeavy: const Color(0x40FFFFFF),
  glassBorder: const Color(0x22FFFFFF),
  glassBorderStrong: const Color(0x44FFFFFF),
  auroraTeal: const Color(0xFF6366F1),
  auroraSky: const Color(0xFF10B981),
  auroraLavender: const Color(0xFF7C3AED),
  auroraPeach: const Color(0xFFF59E0B),
  cardShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
  cardShadowHover: [
    BoxShadow(
      color: const Color(0xFF6366F1).withValues(alpha: 0.22),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ],
  drawerShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
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
  static const double glassBlurSigma = 18.0;
  static const double glassBlurSigmaHeavy = 28.0;

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
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: p.primary,
        ),
        iconTheme: IconThemeData(color: p.textSecondary),
        actionsIconTheme: IconThemeData(color: p.textSecondary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
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
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: p.surface,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
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
    final poppins = GoogleFonts.poppinsTextTheme();
    final inter = GoogleFonts.interTextTheme();
    return TextTheme(
      displayLarge:  poppins.displayLarge?.copyWith(fontWeight: FontWeight.w700, color: p.textPrimary),
      displayMedium: poppins.displayMedium?.copyWith(fontWeight: FontWeight.w700, color: p.textPrimary),
      displaySmall:  poppins.displaySmall?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      headlineLarge:  poppins.headlineLarge?.copyWith(fontWeight: FontWeight.w700, color: p.textPrimary),
      headlineMedium: poppins.headlineMedium?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      headlineSmall:  poppins.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      titleLarge:  poppins.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      titleMedium: poppins.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      titleSmall:  poppins.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      bodyLarge:  inter.bodyLarge?.copyWith(color: p.textPrimary, height: 1.6),
      bodyMedium: inter.bodyMedium?.copyWith(color: p.textPrimary, height: 1.6),
      bodySmall:  inter.bodySmall?.copyWith(color: p.textSecondary, height: 1.5),
      labelLarge:  inter.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
      labelMedium: inter.labelMedium?.copyWith(fontWeight: FontWeight.w500, color: p.textSecondary),
      labelSmall:  inter.labelSmall?.copyWith(color: p.textMuted),
    );
  }
}
