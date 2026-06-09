import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  final Color text;
  final Color surface;
  final Color card;
  final Color muted;
  final Color border;

  const AppPalette({
    required this.text,
    required this.surface,
    required this.card,
    required this.muted,
    required this.border,
  });

  static const light = AppPalette(
    text: Color(0xFF2D2640),
    surface: Color(0xFFFAF8FC),
    card: Color(0xFFFFFFFF),
    muted: Color(0xFF8B85A0),
    border: Color(0xFFEDE8F4),
  );

  // Dark values tuned for separation: card sits clearly above surface and
  // borders are visible — "everything blends together" was the complaint.
  static const dark = AppPalette(
    text: Color(0xFFEDEAF6),
    surface: Color(0xFF120F1A),
    card: Color(0xFF262038),
    muted: Color(0xFFABA3C2),
    border: Color(0xFF3F3558),
  );

  @override
  AppPalette copyWith({
    Color? text,
    Color? surface,
    Color? card,
    Color? muted,
    Color? border,
  }) {
    return AppPalette(
      text: text ?? this.text,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      muted: muted ?? this.muted,
      border: border ?? this.border,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      text: Color.lerp(text, other.text, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

extension PaletteOnContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

class AppColors {
  static const Color primary = Color(0xFF9B72CF);
  static const Color primaryLight = Color(0xFFB794E0);
  static const Color primaryDark = Color(0xFF7B52AF);

  static const Color pastelPurple = Color(0xFFE8D5F5);
  static const Color pastelBlue = Color(0xFFD5E8F5);
  static const Color pastelPink = Color(0xFFF5D5E8);
  static const Color pastelGreen = Color(0xFFD5F5E8);
  static const Color pastelYellow = Color(0xFFF5F0D5);

  static const Color pastelPinkLight = Color(0xFFFFF0F5);
  static const Color pastelBlueLight = Color(0xFFF0F5FF);
  static const Color pastelYellowLight = Color(0xFFFFFBF0);
  static const Color pastelGreenLight = Color(0xFFF0FFF5);
  static const Color pastelPurpleLight = Color(0xFFF5F0FF);

  static const Color surface = Color(0xFFFAF8FC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF2D2640);
  static const Color muted = Color(0xFF8B85A0);

  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  static const Color poopYellow = Color(0xFFDAA520);
  static const Color poopGreen = Color(0xFF228B22);
  static const Color poopBrown = Color(0xFF8B4513);
  static const Color poopBlack = Color(0xFF1A1A1A);
  static const Color poopRed = Color(0xFFDC143C);
  static const Color poopWhite = Color(0xFFF5F5DC);
}

class AppTheme {
  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final surface = palette.surface;
    final card = palette.card;
    final text = palette.text;
    final muted = palette.muted;

    return base.copyWith(
      extensions: [palette],
      scaffoldBackgroundColor: surface,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.pastelPurple,
        onSecondary: AppColors.primaryDark,
        surface: surface,
        onSurface: text,
        surfaceContainerHighest: card,
        outline: palette.border,
        error: AppColors.error,
        onError: Colors.white,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.05),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          minimumSize: const Size(double.infinity, 52),
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 52),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 44),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? card : surface,
        hintStyle: GoogleFonts.inter(fontSize: 14, color: muted),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          height: 1.5,
          color: muted,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: card,
        showDragHandle: true,
        dragHandleColor: muted.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2E2740) : const Color(0xFF2D2640),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        elevation: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? card : AppColors.pastelPurpleLight,
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        side: BorderSide(color: palette.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : muted.withValues(alpha: 0.8),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : palette.border,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primary.withValues(alpha: 0.15),
        circularTrackColor: AppColors.primary.withValues(alpha: 0.15),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: text,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
          color: text,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          height: 1.4,
          color: text,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          height: 1.4,
          color: text,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          color: muted,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
