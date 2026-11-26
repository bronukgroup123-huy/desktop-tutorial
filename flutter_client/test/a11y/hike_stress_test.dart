// UI-001d: похід — компас веде маршрутом, «Додому» своїм слідом і напряму, вкладка «Безпека» з походом —
// ті самі умови, що layout_stress_test.dart (малий екран, шрифт ×2, альбомна). Падає на переповненні в lib/.
import 'package:flutter/material.dart';
import 'package:flutter_client/data/providers.dart';
import 'package:flutter_client/features/safety/hike/compass_screen.dart';
import 'package:flutter_client/features/safety/hike/hike_controller.dart';
import 'package:flutter_client/features/safety/hike/hike_device.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/safety_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../safety_hike_test.dart' show FakeHikeDevice;
import '../safety_nav_test.dart' show at;
import '../safety_test.dart' show FakeDevice;
import '../support/memory_store.dart';
import 'layout_stress_test.dart' show stressCases;
import 'tabs_stress_test.dart' show scrollAll;

/// Стан походу перед показом екрана.
typedef HikeSetup = Future<void> Function(HikeController ctrl);

Future<void> routeToGlade(HikeController ctrl) async {
  ctrl
    ..addPoint(at(0, 0).lat, at(0, 0).lng)
    ..addPoint(at(400, 0).lat, at(400, 0).lng, label: 'Галявина біля старого дуба й струмка');
  await ctrl.start();
  ctrl.debugPosition((lat: at(0, 0).lat, lng: at(0, 0).lng, t: DateTime(2026, 9, 20, 10), acc: 6));
}

/// Г-подібний трек: 300 м на північ, 200 м на схід.
Future<void> walkedL(HikeController ctrl) async {
  ctrl.addPoint(at(0, 0).lat, at(0, 0).lng);
  await ctrl.start();
  var minute = 0;
  void go(double n, double e) =>
      ctrl.debugPosition((lat: at(n, e).lat, lng: at(n, e).lng, t: DateTime(2026, 9, 20, 10).add(Duration(minutes: minute++)), acc: 6));
  for (var n = 0; n <= 300; n += 50) {
    go(n.toDouble(), 0);
  }
  for (var e = 50; e <= 200; e += 50) {
    go(300, e.toDouble());
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final screens = <(String, Widget, HikeSetup)>[
    ('Компас за маршрутом', const CompassScreen(), routeToGlade),
    ('«Додому» своїм слідом', const ReturnScreen(), (c) async {
      await walkedL(c);
      c.startReturn(ReturnMode.track);
    }),
    ('«Додому» напряму', const ReturnScreen(), (c) async {
      await walkedL(c);
      c.startReturn(ReturnMode.direct);
    }),
    ('Безпека: похід триває', const SafetyScreen(), routeToGlade),
  ];

  for (final c in stressCases) {
    for (final (name, screen, setup) in screens) {
      testWidgets('$name: ${c.name} — без переповнення', (tester) async {
        final overflows = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.toString();
          if (!text.contains('overflowed')) return original?.call(details);
          final where = text.split('\n').firstWhere((l) => l.contains('/lib/'), orElse: () => '');
          overflows.add('${details.exceptionAsString().split('\n').first} ${where.trim()}');
        };
        addTearDown(() => FlutterError.onError = original);
        tester.view.physicalSize = c.size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        final device = FakeHikeDevice();
        final container = ProviderContainer(overrides: [
          hikeDeviceProvider.overrideWithValue(device),
          safetyDeviceProvider.overrideWithValue(FakeDevice()),
          localStoreProvider.overrideWithValue(MemoryStore()),
        ]);
        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: SizedBox())));
        await setup(container.read(hikeProvider.notifier));
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
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
        await scrollAll(tester);
        FlutterError.onError = original;
        // Похід тримає таймери — прибрати дерево й контейнер до кінця тесту.
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        expect(overflows, isEmpty);
      });
    }
  }
}
