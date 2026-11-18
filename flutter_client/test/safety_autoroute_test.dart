import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/safety/hike/compass_screen.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/hike/hike_geo.dart';
import 'package:flutter_client/features/safety/safety_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'safety_hike_test.dart' show FakeHikeDevice;
import 'safety_test.dart' show frames;
import 'safety_trails_test.dart' show car, graph;
import 'support/memory_store.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => HikeController.now = DateTime.now);

  late FakeHikeDevice device;
  late ProviderContainer c;
  var minute = 0;
  setUp(() {
    device = FakeHikeDevice();
    minute = 0;
    c = ProviderContainer(overrides: [
      hikeDeviceProvider.overrideWithValue(device),
      localStoreProvider.overrideWithValue(MemoryStore()),
      homeRegionSlugProvider.overrideWithValue('test'),
      trailGraphProvider.overrideWith((ref, slug) async => graph),
    ]);
    HikeController.now = () => DateTime(2026, 9, 20, 10).add(Duration(minutes: minute));
  });
  tearDown(() => c.dispose());

  HikeController ctrl() => c.read(hikeProvider.notifier);
  void go(double lat, double lng) {
    minute++;
    ctrl().debugPosition((lat: lat, lng: lng, t: DateTime(2026, 9, 20, 10).add(Duration(minutes: minute)), acc: 6));
  }

  /// Іти від [a] до [b] кроками ~50 м.
  void walkLine(Geo a, Geo b) {
    final n = (distanceM(a, b) / 50).ceil();
    for (var i = 1; i <= n; i++) {
      go(a.lat + (b.lat - a.lat) * i / n, a.lng + (b.lng - a.lng) * i / n);
    }
  }

  Future<void> startAtCar() async {
    ctrl().addPoint(car.lat, car.lng, label: 'Машина');
    await ctrl().start();
    go(car.lat, car.lng);
  }

  test('«Додому»: слід довгий (петляли) — стежками коротше на 30 %+ → «Стежками», з причиною', () async {
    await startAtCar();
    const j = (lat: 50.456, lng: 30.52), k = (lat: 50.456, lng: 30.53), w = (lat: 50.456, lng: 30.51);
    walkLine(car, j);
    walkLine(j, w); // за річку й назад
    walkLine(w, j);
    walkLine(j, k);
    walkLine(k, const (lat: 50.453, lng: 30.53));
    walkLine(const (lat: 50.453, lng: 30.53), const (lat: 50.453, lng: 30.5292));
    await ctrl().goHome();
    final h = c.read(hikeProvider);
    expect(h.returnMode, ReturnMode.auto);
    expect(h.homeReason, startsWith('Дорогами й стежками коротше на'));
    expect(h.home!.kinds, containsAll(['path', 'track', 'road']));
    final t = c.read(navTargetProvider)!;
    expect(t.label, 'до «Машина» дорогами й стежками');
    expect([for (final l in t.plan.legs) l.kind], ['direct', 'path', 'track', 'road']);
  });

  test('«Додому»: слід не довший — лишаємо свій слід, пояснюємо чому', () async {
    await startAtCar();
    walkLine(car, const (lat: 50.456, lng: 30.52));
    walkLine(const (lat: 50.456, lng: 30.52), const (lat: 50.456, lng: 30.525));
    await ctrl().goHome();
    final h = c.read(hikeProvider);
    expect(h.returnMode, ReturnMode.track);
    expect(h.homeReason, startsWith('Ваш слід надійніший'));
  });

  test('Мережі стежок немає на телефоні — «Стежками» не вмикається, пояснення', () async {
    c.dispose();
    c = ProviderContainer(overrides: [
      hikeDeviceProvider.overrideWithValue(device),
      localStoreProvider.overrideWithValue(MemoryStore()),
      homeRegionSlugProvider.overrideWithValue('test'),
      trailGraphProvider.overrideWith((ref, slug) async => null),
    ]);
    await startAtCar();
    walkLine(car, const (lat: 50.453, lng: 30.52));
    await ctrl().goHome();
    expect(c.read(hikeProvider).returnMode, ReturnMode.track);
    expect(c.read(hikeProvider).homeReason, contains('завантажте офлайн-карту'));
  });

  test('Зійшли з маршруту стежками > 60 м — маршрут перебудовано (не частіше раз на 30 с)', () async {
    await startAtCar();
    walkLine(car, const (lat: 50.456, lng: 30.52));
    walkLine(const (lat: 50.456, lng: 30.52), const (lat: 50.456, lng: 30.53));
    walkLine(const (lat: 50.456, lng: 30.53), const (lat: 50.453, lng: 30.53));
    ctrl().startReturn(ReturnMode.auto);
    await pumpEventQueue();
    final first = c.read(hikeProvider).home!;
    // Відійшли на захід, у бік озера, на ~200 м.
    minute += 1;
    go(50.4532, 30.527);
    await pumpEventQueue();
    final second = c.read(hikeProvider).home!;
    expect(identical(first, second), isFalse);
    expect(second.points.first.lng, closeTo(30.527, 0.0001));
  });

  test('Маршрут «Автоматичний»: між точками — стежками; «Власний» — пряма', () async {
    ctrl().addPoint(car.lat, car.lng, label: 'Машина');
    expect(await ctrl().addAutoPoint(50.4545, 30.5299), isTrue); // біля стежки на сході
    final h = c.read(hikeProvider);
    expect(h.routeLegs.single!.kinds, containsAll(['road', 'track', 'path']));
    final path = routePath(h);
    expect(path.points.length, greaterThan(3));
    ctrl().addPoint(50.46, 30.54, label: 'Галявина');
    expect(routePath(c.read(hikeProvider)).kinds.last, 'route');
    ctrl().removeLast();
    expect(c.read(hikeProvider).route.length, 2);
    expect(c.read(hikeProvider).routeLegs.length, 1);
  });

  testWidgets('Екран «Додому»: «Стежками» — підказка дорогою, причина вибору', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await startAtCar();
      const j = (lat: 50.456, lng: 30.52), k = (lat: 50.456, lng: 30.53), w = (lat: 50.456, lng: 30.51);
      walkLine(car, j);
      walkLine(j, w);
      walkLine(w, j);
      walkLine(j, k);
      walkLine(k, const (lat: 50.4545, lng: 30.53));
      await ctrl().goHome();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: ReturnScreen())));
    await frames(tester);
    expect(find.byKey(const ValueKey('home-reason')), findsOneWidget);
    expect(find.text('Йдіть на північ стежкою'), findsOneWidget);
    expect(find.text('Далі — ліворуч, на захід лісовою дорогою'), findsOneWidget);
    expect(find.textContaining('до «Машина» дорогами й стежками'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
