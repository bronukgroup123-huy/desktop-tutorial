import 'package:flutter/material.dart';

/// Фірмовий стиль (план v8.2, Частина 5; єдина дизайн-система — UI-004): бежевий фон, темно-зелене
/// «чорнило», один помаранчевий акцент; Merriweather — заголовки, Inter — текст.
///
/// Правила, яких тримається весь застосунок:
/// - текст — [darkGreen] або [textMuted] (обидва з контрастом ≥ 4,5 на фоні й на білих картках, WCAG AA);
///   прозорість для тексту не використовується — лише для тла, рамок і декору;
/// - шрифти вбудовані (assets/fonts), тож однакові з першого запуску й без інтернету;
/// - кнопки, поля, чипи, картки й шапки беруть вигляд із теми — екрани не задають його самі.
class AppTheme {
  const AppTheme._();

  // ── Шрифти ──────────────────────────────────────────────────────────────
  /// Текст інтерфейсу.
  static const String sans = 'Inter';

  /// Заголовки.
  static const String serif = 'Merriweather';

  // ── Кольори ─────────────────────────────────────────────────────────────
  static const Color backgroundColor = Color(0xFFF4F1E1);

  /// Картки, аркуші, поля.
  static const Color surface = Colors.white;

  /// Основне «чорнило»: текст, іконки, основні кнопки (контраст 8,0 на фоні).
  static const Color darkGreen = Color(0xFF14532D);

  /// Другорядний текст: підписи, пояснення, лічильники (4,9 на фоні, 5,4 на білому).
  static const Color textMuted = Color(0xFF417351);

  /// Єдиний помаранчевий: акцентні кнопки з білим текстом (5,6), іконки й текст попереджень (4,9 на фоні).
  static const Color accentOrange = Color(0xFFA84E08);

  /// Яскравий помаранчевий — лише на темному тлі (шапка профілю, полиця трофеїв), де темніший губиться.
  static const Color accentOnDark = Color(0xFFD97706);

  /// Аліас для наявних екранів.
  static const Color orange = accentOrange;
  static const Color errorRed = Color(0xFFB91C1C);

  // Семантичні кольори (UI-002): одне значення на весь застосунок замість літералів у екранах.
  /// Небезпека: SOS, отруйні гриби, тривога, «не їсти» (5,0 на фоні).
  static const Color danger = Color(0xFFC62828);

  /// Добре / готово: їстівний, у сезоні, збережено офлайн, напрям правильний (4,5 на фоні).
  static const Color success = Color(0xFF2E7D32);

  /// Увага, але не небезпека: ліміт близько, застаріло, обережно. Той самий помаранчевий, що й акцент.
  static const Color warning = accentOrange;

  /// М'яке зелене тло іконок плиток, вибраних чипів.
  static const Color tint = Color(0xFFE3EEE5);

  /// М'яке червоне тло небезпечних дій.
  static const Color tintDanger = Color(0xFFFDECEA);

  /// Тонке тло й рамки (не для тексту).
  static Color get hairline => darkGreen.withValues(alpha: 0.12);

  // ── Радіуси ─────────────────────────────────────────────────────────────
  /// Картки, плитки, аркуші.
  static const double radiusCard = 16;

  /// Поля вводу, дрібні блоки всередині карток.
  static const double radiusField = 12;

  // ── Текст ───────────────────────────────────────────────────────────────
  /// Назва екрана в AppBar (UI-002): Merriweather, жирний, темно-зелений; розмір — з теми AppBar (22).
  static const TextStyle appBarTitle = TextStyle(fontFamily: serif, fontWeight: FontWeight.bold, color: darkGreen);

  /// Заголовок картки чи розділу (UI-002): Merriweather, жирний, темно-зелений.
  static TextStyle heading(double size, {FontWeight weight = FontWeight.bold, Color color = darkGreen}) =>
      TextStyle(fontFamily: serif, fontSize: size, fontWeight: weight, color: color);

  /// Ролі заголовків (UI-004): великий заголовок екрана — 24, назва блоку чи картки — 20,
  /// заголовок розділу — 17. Інших розмірів Merriweather у застосунку немає.
  static TextStyle get screenTitle => heading(24);
  static TextStyle get blockTitle => heading(20);
  static TextStyle get sectionTitle => heading(17);

  static ThemeData get lightTheme {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: darkGreen,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD9E8DC),
      onPrimaryContainer: darkGreen,
      secondary: accentOrange,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF6E3CF),
      onSecondaryContainer: Color(0xFF5A2A04),
      tertiary: textMuted,
      onTertiary: Colors.white,
      error: errorRed,
      onError: Colors.white,
      errorContainer: Color(0xFFFDECEA),
      onErrorContainer: Color(0xFF7A1C1C),
      surface: surface,
      onSurface: darkGreen,
      onSurfaceVariant: textMuted,
      // Теплі поверхні (меню, аркуші, діалоги, панель вкладок) — у тон фону, а не сіро-зелені з seed.
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFBF9F1),
      surfaceContainer: Color(0xFFF7F4E8),
      surfaceContainerHigh: Color(0xFFF1EDDD),
      surfaceContainerHighest: Color(0xFFEAE5D2),
      outline: textMuted,
      outlineVariant: Color(0xFFD5DDD2),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: darkGreen,
      onInverseSurface: backgroundColor,
      inversePrimary: Color(0xFFA5D6A7),
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: sans);
    final text = base.textTheme
        .apply(bodyColor: darkGreen, displayColor: darkGreen)
        .copyWith(
          headlineMedium: const TextStyle(fontFamily: serif, fontWeight: FontWeight.bold, color: darkGreen),
          titleLarge: const TextStyle(fontFamily: serif, fontWeight: FontWeight.bold, color: darkGreen),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        );
    const pill = StadiumBorder();
    const buttonText = TextStyle(fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w600);
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusField),
      borderSide: const BorderSide(color: Color(0xFFD5DDD2)),
    );
    return base.copyWith(
      scaffoldBackgroundColor: backgroundColor,
      textTheme: text,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: darkGreen,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontFamily: serif, fontSize: 22, fontWeight: FontWeight.bold, color: darkGreen),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radiusCard))),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: pill, textStyle: buttonText)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          textStyle: buttonText,
          foregroundColor: darkGreen,
          side: const BorderSide(color: textMuted),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: darkGreen, textStyle: buttonText)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: pill, textStyle: buttonText)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: const Color(0xFFD9E8DC),
          selectedForegroundColor: darkGreen,
          foregroundColor: darkGreen,
          side: const BorderSide(color: Color(0xFFD5DDD2)),
          textStyle: buttonText,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(side: BorderSide(color: Color(0xFFD5DDD2))),
        backgroundColor: surface,
        selectedColor: const Color(0xFFD9E8DC),
        labelStyle: const TextStyle(fontFamily: sans, fontSize: 13, fontWeight: FontWeight.w600, color: darkGreen),
        side: const BorderSide(color: Color(0xFFD5DDD2)),
        checkmarkColor: darkGreen,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(borderSide: const BorderSide(color: darkGreen, width: 1.5)),
        hintStyle: const TextStyle(color: textMuted),
        helperStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textMuted),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: darkGreen,
        textColor: darkGreen,
        subtitleTextStyle: TextStyle(fontFamily: sans, fontSize: 13, color: textMuted),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFDDE3DA), space: 1, thickness: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: darkGreen),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        titleTextStyle: TextStyle(fontFamily: serif, fontSize: 20, fontWeight: FontWeight.bold, color: darkGreen),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkGreen,
      ),
    );
  }
}
