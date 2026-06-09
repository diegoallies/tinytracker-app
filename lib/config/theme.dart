import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  final Color text;
  final Color surface;
  final Color card;
  final Color muted;

  const AppPalette({
    required this.text,
    required this.surface,
    required this.card,
    required this.muted,
  });

  static const light = AppPalette(
    text: Color(0xFF2D2640),
    surface: Color(0xFFFAF8FC),
    card: Color(0xFFFFFFFF),
    muted: Color(0xFF8B85A0),
  );

  static const dark = AppPalette(
    text: Color(0xFFE8E4F0),
    surface: Color(0xFF14111C),
    card: Color(0xFF1F1A2B),
    muted: Color(0xFF9A93AE),
  );

  @override
  AppPalette copyWith({Color? text, Color? surface, Color? card, Color? muted}) {
    return AppPalette(
      text: text ?? this.text,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      muted: muted ?? this.muted,
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
    final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final surface = palette.surface;
    final card = palette.card;
    final text = palette.text;
    final muted = palette.muted;

    return base.copyWith(
      extensions: [palette],
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.pastelPurple,
        onSecondary: AppColors.primaryDark,
        surface: surface,
        onSurface: text,
        error: AppColors.error,
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? card : surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.pastelPurple.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.pastelPurple.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: text,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.bold,
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
          color: text,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: text,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          color: muted,
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
