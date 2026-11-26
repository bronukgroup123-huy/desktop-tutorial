import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/data/repositories/analysis_repository.dart';
import 'package:flutter_client/features/map/basemap_style.dart';
import 'package:flutter_client/features/safety/hike/compass_screen.dart';
import 'package:flutter_client/features/safety/hike/hike_card.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/fake_adapter.dart';
import 'safety_test.dart' show FakeDevice, frames;
import 'support/memory_store.dart';

class FakeHikeDevice implements HikeDevice {
  final positionsCtl = StreamController<TrackPoint>.broadcast();
  final headingCtl = StreamController<double?>.broadcast();
  final economyCalls = <bool>[];
  final notes = <(int, String, String)>[];
  final spoken = <String>[];
  int? batteryLevel = 80;
  bool allowLocation = true;

  @override
  Stream<TrackPoint> positions({required bool economy}) {
    economyCalls.add(economy);
    return positionsCtl.stream;
  }

  @override
  Stream<double?> heading() => headingCtl.stream;

  @override
  Future<int?> battery() async => batteryLevel;

  @override
  Future<void> notify(int id, String title, String body) async => notes.add((id, title, body));

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<bool> ensureLocation() async => allowLocation;
}

const start = (lat: 50.45, lng: 30.52);

/// Точка треку на [north] м на північ від старту через [minutes] хв.
TrackPoint walk(double north, int minutes, {double acc = 8}) =>
    (lat: start.lat + north / 111320, lng: start.lng, t: DateTime(2026, 9, 20, 10).add(Duration(minutes: minutes)), acc: acc);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => HikeController.now = DateTime.now);

  group('Геометрія', () {
    test('Відстань, азимут, кут стрілки, підписи', () {
      final north = (lat: start.lat + 0.01, lng: start.lng);
      expect(distanceM(start, north), closeTo(1112, 3));
      expect(bearingDeg(start, north), closeTo(0, 0.01));
      expect(bearingDeg(start, (lat: start.lat, lng: start.lng + 0.01)), closeTo(90, 0.1));
      expect(relativeDeg(10, 350), 20);
      expect(relativeDeg(350, 10), -20);
      expect(distanceLabel(1234), '1,2 км');
      expect(distanceLabel(347), '350 м');
      expect(cardinal(0), 'Пн');
      expect(cardinal(225), 'Пд-Зх');
      expect(declinationUa(24), 6.5);
      expect(declinationUa(30.5), closeTo(8.0, 0.1));
    });

    test('Компас з датчиків: телефон рівно, верх на північ — 0°; на схід — 90°', () {
      expect(headingFromSensors([0, 0, 9.8], [0, 20, -40]), closeTo(0, 0.01));
      expect(headingFromSensors([0, 0, 9.8], [-20, 0, -40]), closeTo(90, 0.01));
      expect(headingFromSensors([0, 0, 9.8], [0, 0, -40]), isNull); // магнітне поле вздовж гравітації
      expect(smoothAngle(350, 10, 0.5), closeTo(0, 0.01)); // через північ, без стрибка
    });

    test('Захід сонця (NOAA): Київ 17 листопада — близько 14:05 UTC, схід — близько 05:20 UTC', () {
      final t = sunTimes((lat: 50.45, lng: 30.52), DateTime(2026, 11, 17))!;
      final sunsetUtc = t.sunset.toUtc(), sunriseUtc = t.sunrise.toUtc();
      expect(sunsetUtc.hour * 60 + sunsetUtc.minute, closeTo(14 * 60 + 5, 12));
      expect(sunriseUtc.hour * 60 + sunriseUtc.minute, closeTo(5 * 60 + 20, 12));
    });

    test('Трек: погана точність і «стрибок» (підміна GPS) не беруться, надто близькі — пропуск', () {
      expect(checkTrackPoint(null, walk(0, 0)), isNull);
      expect(checkTrackPoint(walk(0, 0), walk(5, 1)), TrackReject.tooClose);
      expect(checkTrackPoint(walk(0, 0), walk(50, 1, acc: 250)), TrackReject.lowAccuracy);
      expect(checkTrackPoint(walk(0, 0), walk(5000, 1)), TrackReject.jump); // 5 км за хвилину
      expect(checkTrackPoint(walk(0, 0), walk(60, 1)), isNull);
    });

    test('«За маршрутом»: ціль — назад по треку на 40 м; залишок — по треку до старту', () {
      final track = [for (var i = 0; i <= 10; i++) walk(i * 20.0, i)];
      final b = backtrackTarget(track, (lat: start.lat + 200 / 111320, lng: start.lng));
      expect(b.nearest, 10);
      final back = distanceM(b.target, geoOf(track[10]));
      expect(back, inInclusiveRange(39, 61)); // ≥ 40 м назад по треку (крок — 20 м)
      expect(b.remainingM, closeTo(200, 2));
    });
  });

  group('Похід', () {
    late FakeHikeDevice device;
    late MemoryStore store;
    late ProviderContainer c;

    setUp(() {
      device = FakeHikeDevice();
      store = MemoryStore();
      c = ProviderContainer(overrides: [
        hikeDeviceProvider.overrideWithValue(device),
        localStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
    });

    test('Без маршруту похід не почати (ADR-022 §22.5 п.4); без дозволу геолокації — теж', () async {
      final ctrl = c.read(hikeProvider.notifier);
      expect(await ctrl.start(), isFalse);
      ctrl.addPoint(start.lat, start.lng);
      device.allowLocation = false;
      expect(await ctrl.start(), isFalse);
      device.allowLocation = true;
      expect(await ctrl.start(), isTrue);
      expect(c.read(hikeProvider).active, isTrue);
      expect(c.read(hikeProvider).route.single.label, 'Старт');
    });

    test('Трек: добрі точки — в трек; збої GPS — лічильник; пройдено; зберігається на телефоні; «Я вдома» стирає', () async {
      final ctrl = c.read(hikeProvider.notifier)..addPoint(start.lat, start.lng);
      await ctrl.start();
      ctrl.debugPosition(walk(0, 0));
      ctrl.debugPosition(walk(100, 2));
      ctrl.debugPosition(walk(110, 3, acc: 400)); // погана точність
      ctrl.debugPosition(walk(9000, 4)); // стрибок
      ctrl.debugPosition(walk(200, 5));
      final s = c.read(hikeProvider);
      expect(s.track.length, 3);
      expect(s.rejected, 2);
      expect(s.walkedM, closeTo(200, 2));
      expect(s.here, isNotNull);
      await ctrl.finish();
      expect(c.read(hikeProvider).hasRoute, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect((store.data[HikeController.storeKey] as Map)['status'], 'none');
    });

    test('Після перезапуску — той самий маршрут і трек, запис триває', () async {
      final saved = HikeState(
        route: const [(lat: 50.45, lng: 30.52, label: 'Старт')],
        status: HikeStatus.active,
        startedAt: DateTime(2026, 9, 20, 10),
        track: [walk(0, 0), walk(50, 1)],
      );
      store.data[HikeController.storeKey] = saved.toJson();
      c.read(hikeProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final s = c.read(hikeProvider);
      expect(s.active, isTrue);
      expect(s.track.length, 2);
      expect(device.economyCalls, [false]); // підписка на місця відновлена
    });

    test('«Час повертатися» — за годину до заходу сонця, один раз', () async {
      final sunset = sunTimes(start, DateTime(2026, 9, 20))!.sunset;
      HikeController.now = () => sunset.subtract(const Duration(minutes: 50));
      final ctrl = c.read(hikeProvider.notifier)..addPoint(start.lat, start.lng);
      await ctrl.start();
      ctrl.debugPosition(walk(0, 0));
      ctrl.debugPosition(walk(100, 2));
      final sunsetNotes = device.notes.where((n) => n.$1 == kSunsetNotification).toList();
      expect(sunsetNotes.length, 1);
      expect(sunsetNotes.single.$2, 'Час повертатися');
      expect(sunsetNotes.single.$3, contains('50 хв'));
    });

    test('Батарея ≤ 20 % — попередження й економний запис (рідше)', () async {
      device.batteryLevel = 18;
      final ctrl = c.read(hikeProvider.notifier)..addPoint(start.lat, start.lng);
      await ctrl.start();
      ctrl.debugPosition(walk(0, 0));
      await Future<void>.delayed(Duration.zero);
      final s = c.read(hikeProvider);
      expect(s.economy, isTrue);
      expect(s.battery, 18);
      expect(device.notes.where((n) => n.$1 == kBatteryNotification), hasLength(1));
      expect(device.economyCalls, [false, true]);
    });
  });

  test('Карта: маршрут — лінія й точки (старт позначено), трек — лінія', () {
    final r = routeGeoJson(const [(lat: 50.0, lng: 30.0, label: 'Старт'), (lat: 50.1, lng: 30.1, label: 'Точка 1')]);
    final f = r['features'] as List;
    expect(f.length, 3);
    expect((f[0] as Map)['geometry'], {'type': 'LineString', 'coordinates': [[30.0, 50.0], [30.1, 50.1]]});
    expect(((f[1] as Map)['properties'] as Map)['start'], isTrue);
    expect(trackGeoJson(const [(lat: 50.0, lng: 30.0)]), emptyFeatureCollection);
    expect(((trackGeoJson(const [(lat: 50.0, lng: 30.0), (lat: 50.1, lng: 30.0)])['features'] as List).single as Map)['geometry'],
        {'type': 'LineString', 'coordinates': [[30.0, 50.0], [30.0, 50.1]]});
  });

  group('Екрани походу', () {
    late FakeHikeDevice device;
    late FakeDevice phone;

    Widget app(Widget home, {AnalysisRepository? analysis}) => ProviderScope(
          overrides: [
            if (analysis != null) analysisRepositoryProvider.overrideWithValue(analysis),
            hikeDeviceProvider.overrideWithValue(device),
            safetyDeviceProvider.overrideWithValue(phone),
            localStoreProvider.overrideWithValue(MemoryStore()),
          ],
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: home))),
        );

    setUp(() {
      device = FakeHikeDevice();
      phone = FakeDevice(fix: const SafetyFix(lat: 50.45, lng: 30.52, accuracyM: 6));
    });

    testWidgets('Картка: «Старт тут» → маршрут → «Почати похід» → пройдено → «Повернутися» → «Я вдома»', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      // «Я вдома» → сервер каже, що похід біля ділянки прогнозу → «Знайшли?» (B3.11)
      final feedbackQueries = <Map<String, dynamic>>[];
      final (api, _) = makeClient((r) {
        feedbackQueries.add({'path': r.path, ...r.queryParameters});
        return const FakeResponse(200, {
          'data': {'ask': true, 'title': 'Знайшли гриби?', 'answers': [{'id': 'found', 'label': 'Так, знайшли'}]},
        });
      });
      await tester.pumpWidget(app(const HikeCard(), analysis: AnalysisRepository(api)));
      await tester.pump();
      expect(find.textContaining('Без маршруту похід не почати'), findsOneWidget);
      expect(find.byKey(const ValueKey('hike-start')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('route-start-here')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Старт'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hike-start')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Похід триває'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(HikeCard)));
      container.read(hikeProvider.notifier)
        ..debugPosition(walk(0, 0))
        ..debugPosition(walk(300, 5));
      await tester.pump();
      expect(find.textContaining('пройдено 300 м'), findsOneWidget);

      // «Повернутися» — назад по треку: стрілка й залишок.
      await tester.tap(find.byKey(const ValueKey('hike-return')));
      await frames(tester);
      expect(find.byKey(const ValueKey('return-screen')), findsOneWidget);
      expect(find.byKey(const ValueKey('return-distance')), findsOneWidget);
      expect(find.text('300 м'), findsOneWidget);
      expect(find.byKey(const ValueKey('return-no-compass')), findsOneWidget); // курсу ще немає
      device.headingCtl.add(0);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('return-no-compass')), findsNothing);
      // Прийшли до машини.
      container.read(hikeProvider.notifier).debugPosition(walk(10, 30));
      container.read(hikeProvider.notifier).debugPosition(walk(-2, 31));
      await tester.pump();
      expect(find.byKey(const ValueKey('return-arrived')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('return-home')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('return-home')));
      await frames(tester);
      expect(container.read(hikeProvider).hasRoute, isFalse);
      expect(find.textContaining('Без маршруту похід не почати'), findsOneWidget);
      // Завершення запису закінчується поза тестовим годинником (підписка на GPS) — даємо йому справжню мить.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await frames(tester);
      // Після «Я вдома» — «Знайшли?»: на сервер пішли середина треку й день (місце сервер лише перевіряє).
      expect(find.byKey(const ValueKey('trip-feedback-sheet')), findsOneWidget);
      expect(feedbackQueries.single['path'], '/v1-analysis/feedback');
      expect(feedbackQueries.single.keys, containsAll(['lat', 'lng', 'day']));
    });

    testWidgets('«Новий маршрут»: компасом навпростець до вибраної точки маршруту', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      final container = ProviderScope.containerOf(tester.element(find.byType(SizedBox).first));
      final ctrl = container.read(hikeProvider.notifier)
        ..addPoint(start.lat, start.lng)
        ..addPoint(start.lat, start.lng + 0.01, label: 'Дорога');
      await ctrl.start();
      ctrl.debugPosition(walk(0, 0));
      ctrl.startReturn(ReturnMode.direct, target: 1);
      await tester.pumpWidget(app(const SizedBox(height: 1400, child: ReturnScreen())));
      await tester.pump();
      expect(find.text('Дорога'), findsOneWidget);
      expect(find.textContaining('до «Дорога» навпростець'), findsOneWidget);
      expect(find.text('710 м'), findsOneWidget); // 0,01° довготи на 50,45° пн. ш.
      device.headingCtl.add(90); // дивимось на схід — стрілка прямо
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('compass-dial')), findsOneWidget);
    });
  });
}
