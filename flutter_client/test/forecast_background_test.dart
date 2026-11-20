import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_client/features/forecast/forecast_background.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ресурси фону «Прогнозу» на місці й легкі', () {
    var total = 0;
    for (final f in ['base.webp', 'fog.png', 'fern.png', 'leaf.png', 'rays.png']) {
      final file = File('assets/forecast_bg/$f');
      expect(file.existsSync(), isTrue, reason: f);
      total += file.lengthSync();
    }
    expect(total, lessThan(400 * 1024));
  });

  // Картинки вантажаться в реальному часі (у «фальшивому» часі тесту декодування не завершується).
  setUpAll(() async => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('Фон малюється в будь-який момент петлі без помилок', (tester) async {
    await tester.runAsync(() => ForecastBgImages.load());
    await tester.pumpWidget(const MaterialApp(home: ForecastBackground()));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('forecast-bg')), findsOneWidget);
    // пройти всю 30-секундну петлю кроками — хмарка, промені, листки, краплі, відблиск
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // зупинити нескінченну анімацію
  });

  testWidgets('Без анімацій у системі — нерухомий кадр', (tester) async {
    await tester.runAsync(() => ForecastBgImages.load());
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(data: MediaQueryData(disableAnimations: true), child: ForecastBackground()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(tester.hasRunningAnimations, isFalse);
  });
}
