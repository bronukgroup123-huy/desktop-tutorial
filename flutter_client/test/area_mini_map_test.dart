import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/features/analysis/analysis_result_view.dart';
import 'package:flutter_client/features/analysis/area_mini_map.dart';
import 'package:flutter_client/features/analysis/mushroom_stickers.dart';
import 'package:flutter_client/features/map/region_camera.dart';

import 'analysis_days_test.dart' show daysJson;

const bounds = GeoBounds(southWest: LatLng(50.20, 28.60), northEast: LatLng(50.245, 28.67));

StickerCamera camera() {
  const size = Size(360, 220);
  final fit = fitRegion(bounds, size, padding: const EdgeInsets.all(10));
  return StickerCamera(center: fit.center, zoom: fit.zoom, size: size);
}

const boletus = StickerSpecies(
  type: 'boletus_edulis', name: 'Білий гриб', level: 'peak', levelLabel: 'Пікова ймовірність',
  color: Color(0xff10b981), whenLabel: 'Хвиля зараз — 5-й день з 10',
);
const chanterelle = StickerSpecies(
  type: 'cantharellus_cibarius', name: 'Лисичка', level: 'low', levelLabel: 'Низька ймовірність',
  color: Color(0xfff97316), whenLabel: 'Хвилі зараз немає',
);

void main() {
  test('проєкція мінікарти: точка → екран → точка', () {
    final c = camera();
    const p = LatLng(50.22, 28.63);
    final back = c.toLatLng(c.toScreen(p));
    expect(back.latitude, closeTo(p.latitude, 1e-9));
    expect(back.longitude, closeTo(p.longitude, 1e-9));
    // кути ділянки — у межах мінікарти
    for (final corner in [bounds.southWest, bounds.northEast]) {
      final o = c.toScreen(corner);
      expect(o.dx, inInclusiveRange(0, 360));
      expect(o.dy, inInclusiveRange(0, 220));
    }
  });

  testWidgets('Мінікарта: гриби в лотку, перетягування на карту, пересування, «Прибрати»', (tester) async {
    var positions = <String, LatLng>{};
    final moved = <String, LatLng>{};
    final removed = <String>[];
    Widget board() => MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) => StickerBoard(
                  camera: camera(),
                  species: const [boletus, chanterelle],
                  positions: positions,
                  map: Container(key: const ValueKey('mini-map'), color: Colors.green.shade100),
                  onMove: (t, p) => setState(() {
                    moved[t] = p;
                    positions = {...positions, t: p};
                  }),
                  onRemove: (t) => setState(() {
                    removed.add(t);
                    positions = {...positions}..remove(t);
                  }),
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(board());
    // система гриби не розставляє — обидва в лотку
    expect(find.byKey(const ValueKey('tray-boletus_edulis')), findsOneWidget);
    expect(find.text('Перетягніть гриб на своє місце в лісі'), findsOneWidget);

    // перетягнути білий з лотка в центр мінікарти
    final mapCenter = tester.getCenter(find.byKey(const ValueKey('mini-map')));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('tray-boletus_edulis'))));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(mapCenter);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(moved.keys, ['boletus_edulis']);
    final p = moved['boletus_edulis']!;
    expect(p.latitude, inInclusiveRange(bounds.southWest.latitude - 0.01, bounds.northEast.latitude + 0.01));
    expect(p.longitude, inInclusiveRange(bounds.southWest.longitude - 0.01, bounds.northEast.longitude + 0.01));
    expect(find.byKey(const ValueKey('placed-boletus_edulis')), findsOneWidget);
    expect(find.byKey(const ValueKey('tray-boletus_edulis')), findsNothing);

    // затиснути й пересунути
    final before = moved['boletus_edulis']!;
    final g2 = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('placed-boletus_edulis'))));
    await tester.pump(const Duration(milliseconds: 600)); // довге натискання
    await g2.moveBy(const Offset(40, 20));
    await tester.pump();
    await g2.up();
    await tester.pump();
    final after = moved['boletus_edulis']!;
    expect(after.longitude, greaterThan(before.longitude)); // праворуч → на схід
    expect(after.latitude, lessThan(before.latitude)); // нижче → на південь

    // торкнутися — підказка з рівнем дня, «Прибрати» повертає в лоток
    await tester.tap(find.byKey(const ValueKey('placed-boletus_edulis')));
    await tester.pump();
    expect(find.text('Білий гриб · Пікова ймовірність'), findsOneWidget);
    expect(find.text('Хвиля зараз — 5-й день з 10'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-boletus_edulis')));
    await tester.pump();
    expect(removed, ['boletus_edulis']);
    expect(find.byKey(const ValueKey('tray-boletus_edulis')), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // зупинити анімацію
  });

  testWidgets('Гриб, якого цього дня немає серед найкращих, лишається на місці сірим', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StickerBoard(
          camera: camera(),
          species: const [chanterelle],
          positions: const {'boletus_edulis': LatLng(50.22, 28.63)},
          map: const SizedBox.expand(),
          onMove: (_, __) {},
          onRemove: (_) {},
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('placed-boletus_edulis')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('placed-boletus_edulis')));
    await tester.pump();
    expect(find.textContaining('Цього дня не серед найкращих'), findsOneWidget);
  });

  test('Місця грибів зберігаються на телефоні за ділянкою', () async {
    final dir = Directory.systemTemp.createTempSync('mr_stickers_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = StickerPositionsStore(LocalStore(dir));
    await store.save('AREA-1', {'boletus_edulis': const LatLng(50.22, 28.63)});
    expect(await store.load('area-1'), {'boletus_edulis': const LatLng(50.22, 28.63)});
    expect(await store.load('area-2'), isEmpty);
  });

  testWidgets('«Хвиля по днях» прокручує дні — гриби на мінікарті змінюються', (tester) async {
    final seen = <List<String?>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisResultView(
          result: AnalysisResult.fromJson(daysJson()),
          miniMapBuilder: (species) {
            seen.add([for (final s in species) '${s.name}:${s.level}']);
            return const SizedBox(height: 50);
          },
        ),
      ),
    ));
    expect(seen.last, ['Опеньок:low']); // сьогодні
    await tester.tap(find.byKey(const ValueKey('play-days')));
    await tester.pump();
    expect(find.text('Пауза'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(seen.last, ['Лисичка:medium']); // завтра
    await tester.pump(const Duration(milliseconds: 1300));
    expect(seen.last, isEmpty); // Пт 13 — видів немає
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('Хвиля по днях'), findsOneWidget); // дійшли до кінця
  });
}
