import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/safety/hike/compass_screen.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/hike/hike_nav.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'safety_hike_test.dart' show FakeHikeDevice, start, walk;
import 'safety_test.dart' show frames;
import 'support/memory_store.dart';

/// Точка на [north] м на північ і [east] м на схід від старту.
Geo at(double north, double east) =>
    (lat: start.lat + north / 111320, lng: start.lng + east / (111320 * 0.6374)); // cos(50,45°) ≈ 0,6374

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Шлях і підказки', () {
    // Г-подібний шлях: 300 м на північ, потім 300 м на схід.
    final plan = NavPlan([at(0, 0), at(150, 0), at(300, 0), at(300, 150), at(300, 300)], kinds: const ['own'], destination: 'Старт');

    test('Відрізки: «на північ» до повороту, далі «праворуч, на схід»', () {
      expect(plan.legs.length, 2);
      expect(plan.legs[0].bearing, closeTo(0, 1));
      expect(plan.legs[1].bearing, closeTo(90, 1));
      expect(plan.lengthM, closeTo(600, 3));
      final g = guide(plan, at(100, 2));
      expect(g.legIndex, 0);
      expect(g.toTurnM, closeTo(200, 3));
      expect(g.nextTurn, Turn.right);
      expect(g.offRoute, isFalse);
      expect(relativeDeg(g.aimBearing, 0), closeTo(0, 5)); // стрілка — вздовж шляху
      expect(legInstruction(g.leg), 'Йдіть на північ своїм слідом');
      expect(nextInstruction(g), 'Далі — праворуч, на схід своїм слідом');
      expect(g.remainingM, closeTo(502, 4));
    });

    test('Після повороту — другий відрізок, «до мети»; біля кінця — «на місці»', () {
      final g = guide(plan, at(300, 100), fromAlong: 380);
      expect(g.legIndex, 1);
      expect(g.lastLeg, isTrue);
      expect(g.toTurnM, closeTo(200, 3));
      expect(legInstruction(g.leg), 'Йдіть на схід своїм слідом');
      expect(guide(plan, at(300, 285)).arrived, isTrue);
    });

    test('Зійшли з маршруту — стрілка веде назад до шляху', () {
      final g = guide(plan, at(150, -100));
      expect(g.offRoute, isTrue);
      expect(g.offRouteM, closeTo(100, 3));
      expect(g.aimBearing, closeTo(90, 5)); // шлях — на схід від нас
    });

    test('Тремтіння GPS у треку не дає зайвих поворотів', () {
      final zigzag = [for (var i = 0; i <= 50; i++) at(i * 10.0, i.isEven ? 3 : -3)];
      final p = NavPlan(zigzag, kinds: const ['own'], destination: 'Старт');
      expect(p.legs.length, 1);
      expect(p.legs.single.bearing, closeTo(0, 2));
    });

    test('Короткі відрізки (крок зі стежки на дорогу, 3 м навпростець) — без окремих підказок', () {
      final p = NavPlan(
        [at(0, 0), at(0, 3), at(200, 3), at(210, 3), at(210, 300)],
        kinds: const ['direct', 'track', 'road', 'road'],
        destination: 'Старт',
        toleranceM: 0,
      );
      expect([for (final l in p.legs) l.kind], ['track', 'road']);
      expect(p.legs.first.lengthM, closeTo(213, 3));
    });

    test('Шлях проходить поруч сам із собою — ведемо далі, а не назад на пройдене', () {
      // Туди на північ, назад на південь за 20 м східніше.
      final p = NavPlan([at(0, 0), at(300, 0), at(300, 20), at(0, 20)], kinds: const ['own'], destination: 'Старт', toleranceM: 0);
      final g = guide(p, at(150, 10), fromAlong: 400);
      expect(g.along, greaterThan(400));
      expect(g.leg.bearing, closeTo(180, 2));
    });

    test('Повороти й підказки під ногами', () {
      expect(turnOf(10), Turn.straight);
      expect(turnOf(-30), Turn.slightLeft);
      expect(turnOf(90), Turn.right);
      expect(turnOf(-140), Turn.sharpLeft);
      expect(turnOf(175), Turn.uTurn);
      expect(cueOf(5), Cue.onTrack);
      expect(cueOf(30), Cue.slightRight);
      expect(cueOf(-90), Cue.left);
      expect(cueOf(170), Cue.turnAround);
      expect(directionWord(135), 'південний схід');
    });

    test('Голос: старт відрізка, «через 60 метрів поверніть праворуч», новий відрізок, зійшли й повернулись, на місці', () {
      var t = DateTime(2026, 9, 20, 10);
      final v = NavVoice(now: () => t);
      String? say(Geo here, {double? rel, double? along}) => v.next(guide(plan, here, fromAlong: along), relative: rel);
      expect(say(at(10, 0), rel: 0), 'Йдіть на північ своїм слідом, 290 метрів до повороту');
      expect(say(at(100, 0), rel: 0), 'Залишилось 500 метрів');
      expect(say(at(150, 0), rel: 0), isNull);
      expect(say(at(242, 0), rel: 0), 'Через 60 метрів поверніть праворуч, на схід');
      expect(say(at(260, 0), rel: 0), isNull);
      expect(say(at(300, 60), rel: 0, along: 300), 'Тепер йдіть на схід своїм слідом, 240 метрів до мети');
      expect(say(at(380, 150), rel: 0, along: 360), startsWith('Ви зійшли з маршруту на 80 метрів. Поверніться на південь'));
      expect(say(at(305, 160), rel: 0, along: 360), startsWith('Ви знову на маршруті'));
      // Телефон дивиться назад 4 с — «Розверніться», не частіше 12 с.
      expect(say(at(300, 170), rel: 170, along: 460), isNull);
      t = t.add(const Duration(seconds: 5));
      expect(say(at(300, 172), rel: 170, along: 470), 'Розверніться');
      t = t.add(const Duration(seconds: 5));
      expect(say(at(300, 174), rel: 170, along: 472), isNull);
      expect(say(at(300, 290), rel: 0, along: 474), 'Ви на місці');
      expect(say(at(300, 295), rel: 0, along: 590), isNull);
    });
  });

  group('Компас веде маршрутом', () {
    late FakeHikeDevice device;
    setUp(() => device = FakeHikeDevice());

    Widget app(Widget home) => ProviderScope(
          overrides: [hikeDeviceProvider.overrideWithValue(device), localStoreProvider.overrideWithValue(MemoryStore())],
          child: MaterialApp(home: home),
        );

    testWidgets('Похід триває: компас веде до наступної точки маршруту; стрілка, мітка й підказка — разом; «Додому»', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const SizedBox()));
      final container = ProviderScope.containerOf(tester.element(find.byType(SizedBox).first));
      final ctrl = container.read(hikeProvider.notifier)
        ..addPoint(start.lat, start.lng)
        ..addPoint(at(400, 0).lat, at(400, 0).lng, label: 'Галявина');
      await ctrl.start();
      ctrl.debugPosition(walk(0, 0));
      await tester.pumpWidget(app(const CompassScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('nav-instruction')), findsOneWidget);
      expect(find.text('Йдіть на північ за маршрутом'), findsOneWidget);
      expect(find.text('400 м до мети'), findsOneWidget);
      expect(find.textContaining('до «Галявина» за маршрутом'), findsOneWidget);
      // Дивимось на південь — «Розверніться»; на північ — «так тримати».
      device.headingCtl.add(180 - declinationUa(start.lng));
      await frames(tester);
      expect(find.text('Розверніться'), findsOneWidget);
      for (var i = 0; i < 8; i++) {
        device.headingCtl.add(-declinationUa(start.lng));
        await tester.pump();
      }
      await frames(tester);
      expect(find.text('Правильно — так тримати'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('compass-home')));
      await frames(tester);
      expect(find.byKey(const ValueKey('return-screen')), findsOneWidget);
      expect(container.read(hikeProvider).returnMode, ReturnMode.direct);
      expect(find.textContaining('Ви на місці'), findsOneWidget); // ще біля машини
    });

    testWidgets('«Додому» своїм слідом: Г-подібний трек — «на південь до повороту», далі «на захід»; голос синхронно', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const SizedBox()));
      final container = ProviderScope.containerOf(tester.element(find.byType(SizedBox).first));
      final ctrl = container.read(hikeProvider.notifier)..addPoint(start.lat, start.lng);
      await ctrl.start();
      var minute = 0;
      void go(Geo p) => ctrl.debugPosition((lat: p.lat, lng: p.lng, t: DateTime(2026, 9, 20, 10).add(Duration(minutes: minute++)), acc: 6));
      for (var n = 0; n <= 300; n += 50) {
        go(at(n.toDouble(), 0));
      }
      for (var e = 50; e <= 200; e += 50) {
        go(at(300, e.toDouble()));
      }
      ctrl.startReturn(ReturnMode.track);
      await tester.pumpWidget(app(const ReturnScreen()));
      await tester.tap(find.byKey(const ValueKey('voice-toggle')));
      await tester.pump();
      expect(find.text('Йдіть на захід своїм слідом'), findsOneWidget);
      expect(find.text('200 м до повороту'), findsOneWidget);
      expect(find.text('Далі — ліворуч, на південь своїм слідом'), findsOneWidget);
      expect(find.text('500 м'), findsOneWidget);
      expect(device.spoken.last, 'Йдіть на захід своїм слідом, 200 метрів до повороту');
      go(at(300, 40));
      await tester.pump();
      expect(device.spoken.last, 'Через 40 метрів поверніть ліворуч, на південь');
      go(at(260, 0));
      await tester.pump();
      expect(find.text('Йдіть на південь своїм слідом'), findsOneWidget);
      expect(device.spoken.last, startsWith('Тепер йдіть на південь своїм слідом'));
    });
  });
}
