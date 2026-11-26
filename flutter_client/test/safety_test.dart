import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_client/features/safety/safety_device.dart';
import 'package:flutter_client/features/safety/safety_screen.dart';
import 'package:flutter_client/features/safety/sos_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class FakeDevice implements SafetyDevice {
  FakeDevice({this.fix, this.error});

  SafetyFix? fix;
  LocateError? error;
  final dialed = <String>[];
  final copied = <String>[];
  final sirens = <bool>[];
  final torches = <bool>[];
  final awake = <bool>[];
  int locates = 0;

  @override
  Future<void> dial(String number) async => dialed.add(number);

  @override
  Future<({SafetyFix? fix, LocateError? error})> locate() async {
    locates++;
    return (fix: fix, error: fix == null ? (error ?? LocateError.unavailable) : null);
  }

  @override
  Future<void> copy(String text) async => copied.add(text);

  @override
  Future<void> siren(bool on) async => sirens.add(on);

  @override
  Future<bool> torch(bool on) async {
    torches.add(on);
    return true;
  }

  @override
  Future<void> keepAwake(bool on) async => awake.add(on);
}

/// Кілька кадрів поспіль — перехід між екранами (без pumpAndSettle: сигнал блимає безкінечно).
Future<void> frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
}

Widget app(FakeDevice d, Widget home) => ProviderScope(
      overrides: [safetyDeviceProvider.overrideWithValue(d)],
      child: MaterialApp(home: home),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('Координати: десяткові для 112 і градуси; погана точність — збої GPS', () {
    const f = SafetyFix(lat: 50.451234, lng: 30.523411, accuracyM: 12);
    expect(f.decimal, '50.45123, 30.52341');
    expect(f.dms, '50°27′04.4″ пн. ш., 30°31′24.3″ сх. д.');
    expect(f.lowAccuracy, isFalse);
    expect(const SafetyFix(lat: 50, lng: 30, accuracyM: 350).lowAccuracy, isTrue);
  });

  test('Світловий сигнал — SOS азбукою Морзе: ··· — — — ··· і пауза слова', () {
    final s = morseSos(unit: const Duration(milliseconds: 100));
    final on = [for (final x in s) if (x.on) x.d.inMilliseconds ~/ 100];
    expect(on, [1, 1, 1, 3, 3, 3, 1, 1, 1]);
    expect(s.last, (on: false, d: const Duration(milliseconds: 700)));
    expect(s[5].d.inMilliseconds, 300); // між літерами — 3 одиниці
  });

  test('Сирена — справжній WAV (PCM 16 біт, моно), звук не тиша', () {
    final w = sirenWav(sampleRate: 8000, seconds: 0.5);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    final data = ByteData.sublistView(w);
    expect(data.getUint32(40, Endian.little), 4000 * 2);
    var peak = 0;
    for (var i = 44; i < w.length; i += 2) {
      peak = data.getInt16(i, Endian.little).abs() > peak ? data.getInt16(i, Endian.little).abs() : peak;
    }
    expect(peak, greaterThan(20000));
  });

  testWidgets('SOS: коротке натискання — нічого; утримати 3 с — екран SOS із сиреною', (tester) async {
    phone(tester);
    final d = FakeDevice(fix: const SafetyFix(lat: 50.45, lng: 30.52, accuracyM: 8));
    await tester.pumpWidget(app(d, const SafetyScreen()));
    final sos = find.byKey(const ValueKey('sos-hold'));
    // Коротко — не спрацьовує.
    final g1 = await tester.startGesture(tester.getCenter(sos));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await g1.up();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('sos-screen')), findsNothing);
    // Утримати 3 с.
    final g2 = await tester.startGesture(tester.getCenter(sos));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pump();
    await g2.up();
    await frames(tester);
    expect(find.byKey(const ValueKey('sos-screen')), findsOneWidget);
    expect(d.sirens, [true]);
    expect(d.awake, contains(true));
    expect(find.text('50.45000, 30.52000'), findsOneWidget); // координати одразу
    await tester.tap(find.byKey(const ValueKey('sos-call-112')));
    expect(d.dialed, ['112']);
    await tester.tap(find.byKey(const ValueKey('sos-siren')));
    await tester.pump();
    expect(d.sirens.last, isFalse);
    await tester.ensureVisible(find.byKey(const ValueKey('sos-close')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sos-close')));
    await frames(tester);
    expect(find.byKey(const ValueKey('sos-screen')), findsNothing);
    expect(d.awake.last, isFalse);
  });

  testWidgets('Мої координати: великими цифрами, «Скопіювати»; погана точність — попередження', (tester) async {
    final d = FakeDevice(fix: const SafetyFix(lat: 50.451234, lng: 30.523411, accuracyM: 260));
    await tester.pumpWidget(app(d, const Scaffold(body: SingleChildScrollView(child: MyCoordinatesCard()))));
    await tester.pump();
    await tester.pump();
    expect(find.text('50.45123, 30.52341'), findsOneWidget);
    expect(find.textContaining('можливі збої GPS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coords-copy')));
    await tester.pump();
    expect(d.copied, ['50.45123, 30.52341']);
    expect(find.text('Координати скопійовано'), findsOneWidget);
  });

  testWidgets('Немає дозволу на геолокацію — пояснення; на вкладці координати — лише за ⟳', (tester) async {
    final d = FakeDevice(error: LocateError.denied);
    await tester.pumpWidget(app(d, const SafetyScreen()));
    await tester.pump();
    expect(d.locates, 0); // вкладка не питає дозвіл сама
    await tester.scrollUntilVisible(find.byKey(const ValueKey('coords-refresh')), 150, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('coords-refresh')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Дозвольте доступ до геолокації'), findsOneWidget);
  });

  testWidgets('Екстрені номери: 112, 101, 102, 103 — дотик відкриває набір', (tester) async {
    phone(tester);
    final d = FakeDevice();
    await tester.pumpWidget(app(d, const SafetyScreen()));
    for (final n in ['112', '101', '102', '103']) {
      final tile = find.byKey(ValueKey('call-$n'));
      await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
    }
    expect(d.dialed, ['112', '101', '102', '103']);
  });

  testWidgets('Світловий сигнал: екран і спалах блимають за Морзе, дотик — вийти, спалах вимкнено', (tester) async {
    final d = FakeDevice();
    await tester.pumpWidget(app(d, const SafetyScreen()));
    phone(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('open-light-signal')), 300, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open-light-signal')));
    await tester.pump();
    await frames(tester);
    expect(find.byKey(const ValueKey('light-signal')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(d.torches.where((x) => x).length, greaterThanOrEqualTo(3));
    expect(d.torches, contains(false));
    await tester.tap(find.byKey(const ValueKey('light-signal')));
    await frames(tester);
    expect(find.byKey(const ValueKey('light-signal')), findsNothing);
    expect(d.torches.last, isFalse);
    expect(d.awake.last, isFalse);
  });
}
