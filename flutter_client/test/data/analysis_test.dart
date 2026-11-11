import 'package:flutter/painting.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/models/analysis.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/data/repositories/analysis_repository.dart';
import 'package:flutter_client/features/analysis/analysis_square.dart';
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

    final result = await repo.analyze(center: const LatLng(50.4501, 30.5234), sizeKm: 5);
    expect(adapter.requests[1].method, 'POST');
    expect(adapter.requests[1].data, {'lat': 50.4501, 'lng': 30.5234, 'size_km': 5});
    expect(result.top1!.species.nameUa, 'Білий гриб');
  });

  test('AnalysisRepository: 10×10 без Pro → текст із сервера', () async {
    final (api, _) = makeClient((_) => const FakeResponse(403, {
          'error': 'pro_required',
          'message': 'Ділянка 10×10 км доступна в Pro. Безкоштовно — ділянка 5×5 км.',
        }));
    await expectLater(
      AnalysisRepository(api).analyze(center: const LatLng(50.45, 30.52), sizeKm: 10),
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
}
