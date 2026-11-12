import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/data/repositories/analysis_repository.dart';
import 'package:flutter_client/data/models/forest_zone.dart';
import 'package:flutter_client/features/analysis/analysis_square.dart';
import 'package:flutter_client/features/analysis/forest_area.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fake_adapter.dart';

Map<String, dynamic> overviewJson() => {
      'sizes': [
        {'size_km': 5, 'label': '5×5 км', 'available': true, 'lock_label': null},
        {'size_km': 10, 'label': '10×10 км', 'available': false, 'lock_label': 'Доступно в Pro'},
      ],
      'areas': [
        {'id': 'area-1', 'slot': 1, 'lat': 50.4, 'lng': 30.5, 'size_km': 5, 'size_label': '5×5 км'},
      ],
      'usage': {'used': 2, 'limit': 5, 'label': 'Сьогодні: 2 з 5 аналізів'},
      'hint_label': 'Торкніться карти, щоб обрати центр ділянки',
    };

Map<String, dynamic> resultJson() => {
      'area': {
        'id': 'area-1',
        'slot': 1,
        'lat': 50.4501,
        'lng': 30.5234,
        'size_km': 5,
        'size_label': '5×5 км',
        'bbox': [30.488, 50.4276, 30.5588, 50.4726],
      },
      'date': '2026-11-11',
      'forest': {
        'summary_label': 'Ліс займає ≈ 9,4 км² з 25 км² ділянки',
        'types': [
          {
            'forest_type': 'pine',
            'type_label': 'Сосновий ліс',
            'type_color': '#81c784',
            'area_label': '≈ 8,4 км²',
            'age_label': '~60 р.',
          },
          {
            'forest_type': 'oak',
            'type_label': 'Дубовий ліс',
            'type_color': '#4caf50',
            'area_label': '≈ 1,0 км²',
            'age_label': null,
          },
        ],
      },
      'top1': {
        'mushroom_type': 'boletus_edulis',
        'name_ua': 'Білий гриб',
        'level': 'high',
        'level_label': 'Висока ймовірність',
        'level_color': '#22c55e',
        'when_label': 'Зараз — 3 дні після дощу',
        'where_label': 'Південні схили',
        'why_labels': ['Дощ 16 мм за останні 3 дні'],
        'forest_label': 'Сосновий ліс',
      },
      'alternative': null,
      'weather': {
        'icon': 'rain',
        'temp_label': '5°…12°, у середньому 9° за тиждень',
        'humidity_label': 'Вологість 82%',
        'rain_label': 'Опади: 6 мм за 3 дні, 14 мм за тиждень',
      },
      'warnings': ['Не збирайте гриби біля доріг.'],
      'usage': {'used': 3, 'limit': 5, 'label': 'Сьогодні: 3 з 5 аналізів'},
    };

void main() {
  test('AnalysisOverview: розміри з замком Pro, збережена ділянка, ліміт', () {
    final o = AnalysisOverview.fromJson(overviewJson());
    expect(o.sizes.map((s) => s.sizeKm), [5, 10]);
    expect(o.sizes.first.available, isTrue);
    expect(o.sizes.last.available, isFalse);
    expect(o.sizes.last.lockLabel, 'Доступно в Pro');
    expect(o.areas.single.center, const LatLng(50.4, 30.5));
    expect(o.areas.single.bounds, isNull);
    expect(o.usage.label, 'Сьогодні: 2 з 5 аналізів');
    expect(o.hintLabel, isNotEmpty);
  });

  test('AnalysisResult: ліс, види з рівнями, базова погода, межі ділянки', () {
    final r = AnalysisResult.fromJson(resultJson());
    expect(r.area.sizeLabel, '5×5 км');
    expect(r.area.bounds!.southWest, const LatLng(50.4276, 30.488));
    expect(r.area.bounds!.northEast, const LatLng(50.4726, 30.5588));
    expect(r.forestSummaryLabel, startsWith('Ліс займає'));
    expect(r.forestTypes.first.typeLabel, 'Сосновий ліс');
    expect(r.forestTypes.first.typeColor, const Color(0xFF81C784));
    expect(r.forestTypes.first.ageLabel, '~60 р.');
    expect(r.forestTypes.last.ageLabel, isNull);
    expect(r.top1!.species.levelLabel, 'Висока ймовірність');
    expect(r.top1!.forestLabel, 'Сосновий ліс');
    expect(r.alternative, isNull);
    expect(r.weather!.rainLabel, startsWith('Опади'));
    expect(r.warnings.single, contains('доріг'));
    expect(r.usage.used, 3);
    expect(r.noDataReason, isNull);
  });

  test('AnalysisResult: немає кандидатів і погоди', () {
    final json = resultJson();
    json['top1'] = null;
    json['weather'] = null;
    json['no_data_reason'] = 'out_of_season';
    final r = AnalysisResult.fromJson(json);
    expect(r.top1, isNull);
    expect(r.weather, isNull);
    expect(r.noDataReason, 'out_of_season');
  });

  test('AnalysisRepository: GET /v1-analysis і POST з центром та розміром', () async {
    final (api, adapter) = makeClient(
      (req) => FakeResponse(200, {'data': req.method == 'GET' ? overviewJson() : resultJson()}),
    );
    final repo = AnalysisRepository(api);

    expect((await repo.fetchOverview()).sizes.length, 2);
    expect(adapter.requests[0].path, '/v1-analysis');

    final result = await repo.createArea(center: const LatLng(50.4501, 30.5234), sizeKm: 5);
    expect(adapter.requests[1].method, 'POST');
    expect(adapter.requests[1].data, {'lat': 50.4501, 'lng': 30.5234, 'size_km': 5});
    expect(result.top1!.species.nameUa, 'Білий гриб');

    // Ліс із карти застосунку йде в тіло запиту.
    await repo.createArea(
      center: const LatLng(50.4501, 30.5234),
      sizeKm: 5,
      forest: {'forest_km2': 3.2, 'types': []},
    );
    expect((adapter.requests[2].data as Map)['forest'], {'forest_km2': 3.2, 'types': []});
  });

  test('AnalysisRepository: повторний аналіз за area_id і видалення ділянки', () async {
    final (api, adapter) = makeClient(
      (req) => FakeResponse(200, {
        'data': req.method == 'DELETE' ? {'deleted': true} : resultJson()
      }),
    );
    final repo = AnalysisRepository(api);
    await repo.analyzeArea('area-1', forest: {'forest_km2': 1.5, 'types': []});
    expect(adapter.requests[0].data, {
      'area_id': 'area-1',
      'forest': {'forest_km2': 1.5, 'types': []}
    });
    await repo.deleteArea('area-1');
    expect([adapter.requests[1].method, adapter.requests[1].path], ['DELETE', '/v1-analysis/areas/area-1']);
  });

  test('AnalysisOverview: ділянки з лімітом і останнім результатом; можна створити нову чи ні', () {
    final json = overviewJson();
    json['areas'] = <dynamic>[
      <String, dynamic>{
        ...(json['areas'] as List)[0] as Map<String, dynamic>,
        'usage': {'used': 2, 'limit': 5, 'label': 'Сьогодні: 2 з 5 аналізів'},
        'last_result': resultJson(),
        'last_analyzed_at': '2026-11-12T08:00:00Z',
      },
    ];
    json['can_create'] = false;
    json['create_hint_label'] = 'Видаліть стару';
    final o = AnalysisOverview.fromJson(json);
    final a = o.areas.single;
    expect([a.title, a.usage!.used, a.lastResult!.top1!.species.nameUa], ['Ділянка 1 · 5×5 км', 2, 'Білий гриб']);
    expect([o.canCreate, o.createHintLabel], [false, 'Видаліть стару']);
    expect(o.areaById('area-1'), same(a));
  });

  test('AnalysisRepository: без інтернету — збережені ділянки з часом збереження', () async {
    final dir = Directory.systemTemp.createTempSync('mr_analysis_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalStore(dir);
    var online = true;
    final (api, _) = makeClient(
      (_) => online ? FakeResponse(200, {'data': overviewJson()}) : const FakeResponse.offline(),
    );
    final repo = AnalysisRepository(api, store);
    expect((await repo.fetchOverview(userId: 'u1')).offlineSince, isNull);
    online = false;
    final cached = await repo.fetchOverview(userId: 'u1');
    expect([cached.areas.length, cached.offlineSince != null], [1, true]);
    // кеш іншого користувача не підставляється
    await expectLater(repo.fetchOverview(userId: 'u2'), throwsA(isA<ApiException>()));
  });

  test('AnalysisRepository: 10×10 без Pro → текст із сервера', () async {
    final (api, _) = makeClient((_) => const FakeResponse(403, {
          'error': 'pro_required',
          'message': 'Ділянка 10×10 км доступна в Pro. Безкоштовно — ділянка 5×5 км.',
        }));
    await expectLater(
      AnalysisRepository(api).createArea(center: const LatLng(50.45, 30.52), sizeKm: 10),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'pro_required')
          .having((e) => e.userMessage, 'userMessage', contains('Pro'))),
    );
  });

  test('squareAround: квадрат потрібного розміру з центром у точці', () {
    const center = LatLng(50.45, 30.52);
    const distance = Distance();
    for (final km in [5, 10]) {
      final sq = squareAround(center, km);
      expect(sq.length, 4);
      final width = distance.as(LengthUnit.Meter, sq[0], sq[1]);
      final height = distance.as(LengthUnit.Meter, sq[1], sq[2]);
      expect(width, closeTo(km * 1000, km * 15));
      expect(height, closeTo(km * 1000, km * 15));
      expect((sq[0].latitude + sq[2].latitude) / 2, closeTo(center.latitude, 1e-9));
      expect((sq[0].longitude + sq[2].longitude) / 2, closeTo(center.longitude, 1e-9));
    }
  });

  test('squareFromBounds: кути за межами із сервера', () {
    final sq = squareFromBounds(GeoBounds.fromBbox(const [30.488, 50.4276, 30.5588, 50.4726]));
    expect(sq, const [
      LatLng(50.4276, 30.488),
      LatLng(50.4276, 30.5588),
      LatLng(50.4726, 30.5588),
      LatLng(50.4726, 30.488),
    ]);
  });

  group('forestInSquare — ліс у ділянці з полігонів карти', () {
    const center = LatLng(50.45, 30.52);
    final square = squareAround(center, 5); // 25 км²
    double lat(double km) => km / 111.32;
    double lng(double km) => km / (111.32 * 0.6374); // cos(50.45°)

    ForestZone zone(String id, String? type, List<LatLng> outer, {List<List<LatLng>> holes = const []}) => ForestZone(
          id: id,
          forestType: type,
          standAgeYears: null,
          typeLabel: 'ліс',
          typeColor: const Color(0xFF81C784),
          polygons: [GeoPolygon(outer: outer, holes: holes)],
        );

    List<LatLng> rect(double dxKm, double dyKm, double wKm, double hKm) {
      final sw = LatLng(center.latitude + lat(dyKm), center.longitude + lng(dxKm));
      return [
        sw,
        LatLng(sw.latitude, sw.longitude + lng(wKm)),
        LatLng(sw.latitude + lat(hKm), sw.longitude + lng(wKm)),
        LatLng(sw.latitude + lat(hKm), sw.longitude),
      ];
    }

    test('ліс повністю всередині: площа 2×2 = 4 км²', () {
      final r = forestInSquare([zone('a', 'pine', rect(-1, -1, 2, 2))], square);
      expect(r.forestKm2, closeTo(4, 0.05));
      expect(r.byType['pine'], closeTo(4, 0.05));
    });

    test('великий масив, що виходить за межі, обрізається квадратом (не більше 25 км²)', () {
      final r = forestInSquare([zone('big', 'mixed', rect(-10, -10, 20, 20))], square);
      expect(r.forestKm2, closeTo(25, 0.1));
    });

    test('частковий перетин і «дірка» віднімається; поза квадратом — не рахується', () {
      final r = forestInSquare([
        zone('half', 'birch', rect(0, -1, 10, 2)), // у квадраті — 2.5×2 = 5 км²
        zone('holed', 'oak', rect(-2, 0.5, 1, 1.5), holes: [rect(-1.8, 0.7, 0.5, 0.5)]), // 1.5 − 0.25
        zone('far', 'pine', rect(20, 20, 2, 2)),
      ], square);
      expect(r.byType['birch'], closeTo(5, 0.05));
      expect(r.byType['oak'], closeTo(1.25, 0.05));
      expect(r.byType.containsKey('pine'), isFalse);
      final json = r.toJson();
      expect((json['types'] as List).first['forest_type'], 'birch');
    });

    test('лісів немає — 0', () {
      expect(forestInSquare(const [], square).forestKm2, 0);
    });
  });
}
