// UI-002: семантичні кольори живуть лише в AppTheme — екрани не повторюють їхні значення літералами.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  final tokens = <String, Color>{
    'AppTheme.backgroundColor': AppTheme.backgroundColor,
    'AppTheme.darkGreen': AppTheme.darkGreen,
    'AppTheme.accentOrange': AppTheme.accentOrange,
    'AppTheme.errorRed': AppTheme.errorRed,
    'AppTheme.danger': AppTheme.danger,
    'AppTheme.success': AppTheme.success,
    'AppTheme.warning': AppTheme.warning,
  };

  test('значення токенів не змінились (вигляд затверджено)', () {
    expect(AppTheme.danger, const Color(0xFFC62828));
    expect(AppTheme.success, const Color(0xFF2E7D32));
    expect(AppTheme.warning, const Color(0xFFB45309));
    expect(AppTheme.accentOrange, const Color(0xFFD97706));
    expect(AppTheme.backgroundColor, const Color(0xFFF4F1E1));
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

  testWidgets('стилі заголовків — ті самі, що були в екранах', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    expect(AppTheme.appBarTitle, GoogleFonts.merriweather(color: AppTheme.darkGreen));
    expect(AppTheme.heading(20), GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen));
    expect(AppTheme.heading(18, weight: FontWeight.w700),
        GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.darkGreen));
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
