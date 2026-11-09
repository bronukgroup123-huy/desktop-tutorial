import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Фірмовий стиль (план v8.2, Частина 5): бежевий фон, темно-зелений, оранжевий акцент;
/// Merriweather — заголовки, Inter — текст.
class AppTheme {
  const AppTheme._();

  static const Color backgroundColor = Color(0xFFF4F1E1);
  static const Color darkGreen = Color(0xFF14532D);
  static const Color accentOrange = Color(0xFFD97706);

  /// Аліас для наявних екранів.
  static const Color orange = accentOrange;
  static const Color errorRed = Color(0xFFB91C1C);

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: darkGreen,
        primary: darkGreen,
        secondary: accentOrange,
        surface: backgroundColor,
        error: errorRed,
      ),
      scaffoldBackgroundColor: backgroundColor,
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineMedium: GoogleFonts.merriweather(
          fontWeight: FontWeight.bold,
          color: darkGreen,
        ),
        titleLarge: GoogleFonts.merriweather(
          fontWeight: FontWeight.bold,
          color: darkGreen,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkGreen,
      ),
    );
  }
}
