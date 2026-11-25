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

  // Семантичні кольори (UI-002): одне значення на весь застосунок замість літералів у екранах.
  /// Небезпека: SOS, отруйні гриби, тривога, «не їсти».
  static const Color danger = Color(0xFFC62828);

  /// Добре / готово: їстівний, у сезоні, збережено офлайн, напрям правильний.
  static const Color success = Color(0xFF2E7D32);

  /// Увага, але не небезпека: ліміт близько, застаріло, обережно.
  static const Color warning = Color(0xFFB45309);

  /// Назва екрана в AppBar (UI-002): Merriweather темно-зеленим; розмір — з теми AppBar.
  static TextStyle get appBarTitle => GoogleFonts.merriweather(color: darkGreen);

  /// Заголовок картки чи розділу (UI-002): Merriweather, жирний, темно-зелений.
  static TextStyle heading(double size, {FontWeight weight = FontWeight.bold, Color color = darkGreen}) =>
      GoogleFonts.merriweather(fontSize: size, fontWeight: weight, color: color);

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
