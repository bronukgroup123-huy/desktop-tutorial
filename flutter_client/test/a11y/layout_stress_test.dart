// UI-001: основні екрани не ламаються на малому екрані, з великим системним шрифтом
// і в альбомній орієнтації (RenderFlex overflow → виняток → тест падає).
import 'package:flutter/material.dart';
import 'package:flutter_client/core/app_theme.dart';
import 'package:flutter_client/data/models/avatars.dart';
import 'package:flutter_client/data/models/me.dart';
import 'package:flutter_client/data/models/trophies.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_client/features/profile/avatar_picker_screen.dart';
import 'package:flutter_client/features/profile/profile_hero.dart';
import 'package:flutter_client/features/profile/profile_screen.dart';
import 'package:flutter_client/features/profile/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../profile_test.dart' show FakeMe, avatarsJson, registered, trophiesJson;

/// Умови, в яких екран має лишатися цілим і придатним до користування.
const stressCases = <({String name, Size size, double text})>[
  (name: 'малий телефон 320×568', size: Size(320, 568), text: 1.0),
  (name: 'телефон 360×640, шрифт ×2', size: Size(360, 640), text: 2.0),
  (name: 'альбомна 640×360, шрифт ×1.3', size: Size(640, 360), text: 1.3),
];

Future<void> pumpStress(WidgetTester tester, Widget screen, ({String name, Size size, double text}) c,
    {List<Override> overrides = const []}) async {
  tester.view.physicalSize = c.size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(c.text)),
        child: child!,
      ),
      home: screen,
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final c in stressCases) {
    testWidgets('Вхід: ${c.name} — без переповнення, кнопки входу й гостя досяжні', (tester) async {
      await pumpStress(tester, const AuthScreen(), c);
      expect(tester.takeException(), isNull);
      for (final label in ['Увійти через Google', 'Продовжити без реєстрації']) {
        final f = find.textContaining(label);
        expect(f, findsWidgets, reason: label);
        await tester.ensureVisible(f.first);
        await tester.pump();
        expect(tester.getRect(f.first).bottom, lessThanOrEqualTo(c.size.height));
      }
    });
  }

  List<Override> profileOverrides() => [
        meProvider.overrideWith(() => FakeMe(Me.fromJson(registered()))),
        trophiesProvider.overrideWith((ref) async => TrophiesOverview.fromJson(trophiesJson())),
        avatarChoicesProvider.overrideWith((ref) async => AvatarChoices.fromJson(avatarsJson())),
      ];

  for (final c in stressCases) {
    for (final (name, screen) in [
      ('Профіль', const ProfileScreen()),
      ('Налаштування', const ProfileSettingsScreen()),
      ('Вибір аватара', const AvatarPickerScreen()),
    ]) {
      testWidgets('$name: ${c.name} — без переповнення', (tester) async {
        await pumpStress(tester, screen, c, overrides: profileOverrides());
        expect(tester.takeException(), isNull);
        // прокрутити до кінця — нижні елементи теж мають бути цілими
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          await tester.drag(scroll.first, const Offset(0, -3000));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('«Зменшити рух»: спори в шапці не анімуються — кадри не плануються', (tester) async {
    Widget hero(bool reduce) => MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: ProfileHeroBackground(levelId: 'master', child: SizedBox(width: 300, height: 300)),
          ),
        );
    await tester.pumpWidget(hero(true));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    // без налаштування — анімація йде
    await tester.pumpWidget(hero(false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });
}
