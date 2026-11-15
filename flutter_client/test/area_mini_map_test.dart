import 'dart:io';
import 'dart:typed_data';


import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  Widget boardApp(Map<String, LatLng> Function() get, void Function(Map<String, LatLng>) set,
          {List<StickerSpecies> species = const [boletus, chanterelle], List<String>? removed}) =>
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => StickerBoard(
                camera: camera(),
                species: species,
                positions: get(),
                map: Container(key: const ValueKey('mini-map'), color: Colors.green.shade100),
                onMove: (t, p) => setState(() => set({...get(), t: p})),
                onRemove: (t) => setState(() {
                  removed?.add(t);
                  set({...get()}..remove(t));
                }),
              ),
            ),
          ),
        ),
      );

  Future<void> longDrag(WidgetTester tester, Finder from, Offset to) async {
    final g = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 600)); // довге натискання
    await g.moveTo(to);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600)); // кошик стискається
    await g.up();
    await tester.pump();
  }

  testWidgets('Кошик: спочатку карта порожня, гриби в кошику; заглянути, назва, перенести на карту', (tester) async {
    var positions = <String, LatLng>{};
    await tester.pumpWidget(boardApp(() => positions, (p) => positions = p));
    // система гриби не розставляє — карта порожня, кошик у кутку
    expect(find.byKey(const ValueKey('placed-boletus_edulis')), findsNothing);
    expect(find.byKey(const ValueKey('basket')), findsOneWidget);
    expect(find.byKey(const ValueKey('basket-boletus_edulis')), findsNothing);

    // заглянути в кошик — вигляд згори з грибами
    await tester.tap(find.byKey(const ValueKey('basket')));
    await tester.pump(); // старт анімації «заглядання»
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('basket-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('basket-boletus_edulis')), findsOneWidget);
    expect(find.byKey(const ValueKey('basket-cantharellus_cibarius')), findsOneWidget);

    // торкнутися гриба — назва і рівень; торкнутися повз — закрити (кошик лишається відкритим)
    await tester.tap(find.byKey(const ValueKey('basket-boletus_edulis')));
    await tester.pump();
    expect(find.text('Білий гриб · Пікова ймовірність'), findsOneWidget);
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('basket-open'))) + const Offset(30, 30));
    await tester.pump();
    expect(find.text('Білий гриб · Пікова ймовірність'), findsNothing);
    expect(find.byKey(const ValueKey('basket-open')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('basket-boletus_edulis')));
    await tester.pump();

    // затиснути й перенести на карту (у лівий верхній квадрант)
    final mapBox = tester.getRect(find.byKey(const ValueKey('mini-map')));
    final target = mapBox.topLeft + Offset(mapBox.width * 0.3, mapBox.height * 0.4);
    await longDrag(tester, find.byKey(const ValueKey('basket-boletus_edulis')), target);
    expect(positions.keys, ['boletus_edulis']);
    final placed = camera().toScreen(positions['boletus_edulis']!);
    expect((placed - (target - mapBox.topLeft)).distance, lessThan(1.5)); // «ніжка» — під пальцем
    expect(find.byKey(const ValueKey('placed-boletus_edulis')), findsOneWidget);
    expect(find.byKey(const ValueKey('basket-open')), findsNothing); // кошик стиснувся в куток
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Кошик: пересунути гриб на карті, перенести назад у кошик — прибрати', (tester) async {
    var positions = <String, LatLng>{'boletus_edulis': const LatLng(50.215, 28.62)};
    final removed = <String>[];
    await tester.pumpWidget(boardApp(() => positions, (p) => positions = p, removed: removed));
    final before = positions['boletus_edulis']!;
    final from = find.byKey(const ValueKey('placed-boletus_edulis'));
    await longDrag(tester, from, tester.getCenter(from) + const Offset(40, 20));
    final after = positions['boletus_edulis']!;
    expect(after.longitude, greaterThan(before.longitude));
    expect(after.latitude, lessThan(before.latitude));

    // торкнутися — лише вид і рівень (без фази хвилі); торкнутися будь-де — закрити
    await tester.tap(find.byKey(const ValueKey('placed-boletus_edulis')));
    await tester.pump();
    expect(find.text('Білий гриб · Пікова ймовірність'), findsOneWidget);
    expect(find.textContaining('Хвиля'), findsNothing);
    await tester.tapAt(tester.getRect(find.byKey(const ValueKey('mini-map'))).topLeft + const Offset(20, 20));
    await tester.pump();
    expect(find.text('Білий гриб · Пікова ймовірність'), findsNothing);

    // назад у кошик
    await longDrag(tester, find.byKey(const ValueKey('placed-boletus_edulis')),
        tester.getCenter(find.byKey(const ValueKey('basket'))));
    expect(removed, ['boletus_edulis']);
    expect(positions, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Порожній кошик — без напису', (tester) async {
    var positions = <String, LatLng>{};
    await tester.pumpWidget(boardApp(() => positions, (p) => positions = p, species: const []));
    await tester.tap(find.byKey(const ValueKey('basket')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('basket-open')), findsOneWidget);
    expect(find.textContaining('немає'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Гриб, якого цього дня немає серед грибів зі шансом, лишається на місці сірим', (tester) async {
    var positions = <String, LatLng>{'boletus_edulis': const LatLng(50.22, 28.63)};
    await tester.pumpWidget(boardApp(() => positions, (p) => positions = p, species: const [chanterelle]));
    await tester.tap(find.byKey(const ValueKey('placed-boletus_edulis')));
    await tester.pump();
    expect(find.textContaining('Цього дня шансу немає'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('Знімок мінікарти: один на ділянку, лише з тим самим підписом (інакше — перезняти)', () async {
    final dir = Directory.systemTemp.createTempSync('mr_minimap_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = MiniMapSnapshotStore(LocalStore(dir));
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    expect(await store.load('AREA-1', 'v1|map7|t1|360'), isNull);
    await store.save('AREA-1', 'v1|map7|t1|360', png);
    expect(await store.load('area-1', 'v1|map7|t1|360'), png);
    // новий аналіз або нова карта — інший підпис, старий знімок не показується
    expect(await store.load('area-1', 'v1|map7|t2|360'), isNull);
    await store.save('area-1', 'v1|map7|t2|360', Uint8List.fromList([1]));
    expect(await store.load('area-1', 'v1|map7|t2|360'), [1]);
    expect(dir.listSync().length, 2); // один .bin + один .json, без накопичення
  });

  testWidgets('ⓘ на знімку — звідки дані карти (ODbL)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: MapAttributionButton()))));
    await tester.tap(find.byKey(const ValueKey('map-attribution')));
    await tester.pumpAndSettle();
    expect(find.textContaining('© OpenStreetMap contributors'), findsOneWidget);
  });

  test('Місця грибів зберігаються на телефоні за ділянкою', () async {
    final dir = Directory.systemTemp.createTempSync('mr_stickers_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = StickerPositionsStore(LocalStore(dir));
    await store.save('AREA-1', {'boletus_edulis': const LatLng(50.22, 28.63)});
    expect(await store.load('area-1'), {'boletus_edulis': const LatLng(50.22, 28.63)});
    expect(await store.load('area-2'), isEmpty);
  });

  testWidgets('«Хвиля по днях» — один значок: є доступ — прокручує дні з грибами кошика', (tester) async {
    final seen = <List<String?>>[];
    final json = {
      ...daysJson(),
      'week_animation': {'allowed': true, 'locked_label': null},
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisResultView(
          result: AnalysisResult.fromJson(json),
          miniMapBuilder: (species) {
            seen.add([for (final s in species) '${s.name}:${s.level}']);
            return const SizedBox(height: 50);
          },
        ),
      ),
    ));
    expect(seen.last, ['Опеньок:low']); // сьогодні (без кошика в даних — найкращий вид)
    await tester.tap(find.byKey(const ValueKey('play-days')));
    await tester.pump();
    expect(find.byTooltip('Пауза'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(seen.last, ['Лисичка:medium']);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(seen.last, isEmpty);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byTooltip('Хвиля по днях'), findsOneWidget);
  });

  testWidgets('«Хвиля по днях» без доступу — той самий значок, натискання пояснює (Pro / «Слідопит»)', (tester) async {
    final base = daysJson();
    final days = [for (final d in base['days'] as List) Map<String, dynamic>.from(d as Map)];
    days[0]['basket'] = [
      {'mushroom_type': 'boletus_edulis', 'name_ua': 'Білий гриб', 'level': 'high', 'level_label': 'Висока ймовірність',
       'level_color': '#22c55e', 'when_label': 'Хвиля зараз — 2-й день з 10'},
    ];
    final json = {
      ...base,
      'days': days,
      'week_animation': {'allowed': false, 'locked_label': 'Анімація тижня — у Pro або з рівня «Слідопит»'},
    };
    final seen = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisResultView(
          result: AnalysisResult.fromJson(json),
          miniMapBuilder: (species) {
            seen.add([for (final s in species) s.name]);
            return const SizedBox(height: 50);
          },
        ),
      ),
    ));
    expect(seen.last, ['Білий гриб']); // кошик — з повного списку дня
    // без замка на самому значку (замки в смужці — це дні 4–7)
    expect(find.descendant(of: find.byKey(const ValueKey('play-days')), matching: find.byIcon(Icons.lock_outline_rounded)), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('play-days')), matching: find.byIcon(Icons.play_circle_outline_rounded)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-days')));
    await tester.pump();
    expect(find.text('Анімація тижня — у Pro або з рівня «Слідопит»'), findsOneWidget);
    expect(find.byTooltip('Пауза'), findsNothing);
  });

  testWidgets('Кожен гриб рушія має власну іконку, і вона малюється (20 SVG із книжкових описів)', (tester) async {
    for (final type in speciesWithIcon) {
      final svg = await rootBundle.loadString('assets/stickers/$type.svg');
      final info = await vg.loadPicture(SvgStringLoader(svg), null);
      expect(info.size.width, greaterThan(0), reason: type);
      info.picture.dispose();
    }
    expect(speciesWithIcon.length, 20);
  });

  testWidgets('Стікер: іконка саме цього гриба + мітка рівня; без шансу — сірий без мітки', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Row(children: [
          MushroomSticker(species: chanterelle),
          MushroomSticker(
            species: StickerSpecies(type: 'boletus_edulis', name: 'Білий гриб', level: null, levelLabel: '',
                color: Color(0xff94a3b8), whenLabel: ''),
          ),
        ]),
      ),
    ));
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.byKey(const ValueKey('level-dot-cantharellus_cibarius')), findsOneWidget);
    expect(find.byKey(const ValueKey('level-dot-boletus_edulis')), findsNothing);
    expect(find.byType(ColorFiltered), findsOneWidget); // сірий — лише той, що без шансу
  });
}
