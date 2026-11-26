// UI-002 / UI-004: кольори й шрифти живуть лише в AppTheme — екрани не повторюють їхні значення; текстові
// кольори мають контраст WCAG AA (≥ 4,5) на фоні й на білих картках.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tokens = <String, Color>{
    'AppTheme.backgroundColor': AppTheme.backgroundColor,
    'AppTheme.darkGreen': AppTheme.darkGreen,
    'AppTheme.accentOrange': AppTheme.accentOrange,
    'AppTheme.errorRed': AppTheme.errorRed,
    'AppTheme.danger': AppTheme.danger,
    'AppTheme.success': AppTheme.success,
    'AppTheme.warning': AppTheme.warning,
    'AppTheme.textMuted': AppTheme.textMuted,
    'AppTheme.accentOnDark': AppTheme.accentOnDark,
  };

  double luminance(Color c) => c.computeLuminance();
  double contrast(Color a, Color b) {
    final (x, y) = (luminance(a), luminance(b));
    return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
  }

  test('значення токенів (UI-004: помаранчевий і приглушений текст — з контрастом AA)', () {
    expect(AppTheme.danger, const Color(0xFFC62828));
    expect(AppTheme.success, const Color(0xFF2E7D32));
    expect(AppTheme.accentOrange, const Color(0xFFA84E08));
    expect(AppTheme.warning, AppTheme.accentOrange);
    expect(AppTheme.textMuted, const Color(0xFF417351));
    expect(AppTheme.accentOnDark, const Color(0xFFD97706));
    expect(AppTheme.backgroundColor, const Color(0xFFF4F1E1));
  });

  test('текстові кольори читаються: контраст ≥ 4,5 на фоні й на білому', () {
    for (final c in [AppTheme.darkGreen, AppTheme.textMuted, AppTheme.accentOrange, AppTheme.danger, AppTheme.success]) {
      expect(contrast(c, AppTheme.backgroundColor), greaterThanOrEqualTo(4.5), reason: '$c на фоні');
      expect(contrast(c, Colors.white), greaterThanOrEqualTo(4.5), reason: '$c на білому');
    }
    // білий підпис на кнопках
    for (final c in [AppTheme.darkGreen, AppTheme.accentOrange, AppTheme.danger]) {
      expect(contrast(Colors.white, c), greaterThanOrEqualTo(4.5), reason: 'білий на $c');
    }
  });

  test('lib/ не дублює кольори токенів літералами Color(0x…)', () {
    String hex(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0');
    final literal = RegExp(r'Color\(0x([0-9a-fA-F]{8})\)');
    final byHex = {for (final e in tokens.entries) hex(e.value): e.key};
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('app_theme.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in literal.allMatches(lines[i])) {
          final token = byHex[m.group(1)!.toLowerCase()];
          if (token != null) found.add('${f.path}:${i + 1} → $token');
        }
      }
    }
    expect(found, isEmpty, reason: 'Замініть літерали на токени AppTheme');
  });

  test('стилі заголовків — вбудований Merriweather (без завантаження з інтернету)', () {
    expect(AppTheme.appBarTitle, const TextStyle(fontFamily: 'Merriweather', fontWeight: FontWeight.bold, color: AppTheme.darkGreen));
    expect(AppTheme.heading(20), const TextStyle(fontFamily: 'Merriweather', fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen));
    expect(AppTheme.lightTheme.textTheme.bodyMedium!.fontFamily, 'Inter');
  });

  test('lib/ не використовує google_fonts і не робить текст прозорим темно-зеленим', () {
    final found = <String>[];
    final translucentText = RegExp(r'TextStyle\([^)]*color: AppTheme\.darkGreen\.withValues');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      if (text.contains('google_fonts')) found.add('${f.path}: google_fonts');
      if (translucentText.hasMatch(text)) found.add('${f.path}: прозорий текст — AppTheme.textMuted');
    }
    expect(found, isEmpty);
  });

  test('lib/ не повторює стиль заголовка вручну', () {
    final manual = [
      RegExp(r'GoogleFonts\.merriweather\(color: AppTheme\.darkGreen\)'),
      RegExp(r'GoogleFonts\.merriweather\(\s*fontSize: [\d.]+,\s*fontWeight: FontWeight\.(bold|w700),\s*color: AppTheme\.darkGreen,?\s*\)'),
    ];
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('app_theme.dart')) continue;
      final text = f.readAsStringSync();
      for (final r in manual) {
        if (r.hasMatch(text)) found.add(f.path);
      }
    }
    expect(found, isEmpty, reason: 'Використайте AppTheme.appBarTitle / AppTheme.heading');
  });
}
