import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/repositories/forecast_repository.dart';
import 'package:flutter_client/data/repositories/forest_zones_repository.dart';
import 'package:flutter_client/data/repositories/regions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adapter.dart';

const fc = {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'id': 'a',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [[[28.0, 50.0], [28.1, 50.0], [28.1, 50.1], [28.0, 50.0]]],
      },
      'properties': {'id': 'a', 'forest_type': 'pine', 'type_label': 'Сосновий ліс', 'type_color': '#81c784'},
    },
  ],
};

void main() {
  late Directory dir;
  late LocalStore store;
  var now = DateTime(2026, 11, 10, 12);
  var online = true;
  var etagSent = <String?>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mr_offline_');
    store = LocalStore(dir);
    now = DateTime(2026, 11, 10, 12);
    online = true;
    etagSent = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FakeResponse forestsServer(RequestOptions req) {
    if (!online) return const FakeResponse.offline();
    final inm = req.headers['If-None-Match'] as String?;
    etagSent.add(inm);
    if (inm == '"v1"') return const FakeResponse(304, null, headers: {'etag': '"v1"'});
    return const FakeResponse(200, {'data': fc}, headers: {'etag': '"v1"'});
  }

  group('Ліси області — один раз, далі з телефону', () {
    test('перше відкриття: завантаження всієї області і збереження', () async {
      final (api, adapter) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      final r = await repo.regionForests('zhytomyrska');
      expect(r.value.single.typeLabel, 'Сосновий ліс');
      expect(r.offline, isFalse);
      expect(adapter.requests.single.queryParameters, {'z': 11, 'limit': 10000});
      expect(adapter.requests.single.queryParameters.containsKey('bbox'), isFalse);
    });

    test('протягом доби — жодного запиту в мережу', () async {
      final (api, adapter) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await repo.regionForests('zhytomyrska');
      now = now.add(const Duration(hours: 23));
      await repo.regionForests('zhytomyrska');
      await repo.regionForests('zhytomyrska');
      expect(adapter.requests.length, 1);
    });

    test('через добу — перевірка ETag: 304 без тіла, дані з телефону', () async {
      final (api, _) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await repo.regionForests('zhytomyrska');
      now = now.add(const Duration(hours: 25));
      final r = await repo.regionForests('zhytomyrska');
      expect(etagSent, [null, '"v1"']);
      expect(r.value.length, 1);
      expect(r.savedAt, now);
    });

    test('без інтернету — збережена копія з позначкою offline', () async {
      final (api, _) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await repo.regionForests('zhytomyrska');
      online = false;
      now = now.add(const Duration(days: 3));
      final r = await repo.regionForests('zhytomyrska');
      expect(r.offline, isTrue);
      expect(r.value.single.typeLabel, 'Сосновий ліс');
    });

    test('без інтернету і без копії — помилка мережі', () async {
      online = false;
      final (api, _) = makeClient(forestsServer);
      await expectLater(
        ForestZonesRepository(api, store, now: () => now).regionForests('zhytomyrska'),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'network', true)),
      );
    });

    test('зміна області — ліси старої області видаляються (ADR-016)', () async {
      final (api, _) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await repo.regionForests('zhytomyrska');
      await repo.regionForests('kyivska');
      expect(await store.read('forests_zhytomyrska'), isNull);
      expect(await store.read('forests_kyivska'), isNotNull);
    });
  });

  test('Кордон області: без інтернету — збережена копія', () async {
    final geometry = {
      'id': 6, 'slug': 'zhytomyrska', 'name': 'Житомирська',
      'bbox': [27.2, 49.6, 30.6, 51.6], 'center': [28.7, 50.5], 'zoom': 7,
      'geometry': {'type': 'Polygon', 'coordinates': [[[27.2, 49.6], [30.6, 49.6], [30.6, 51.6], [27.2, 49.6]]]},
    };
    final (api1, _) = makeClient((_) => FakeResponse(200, {'data': geometry}));
    await RegionsRepository(api1, store, now: () => now).fetchGeometry('zhytomyrska');

    final (api2, adapter2) = makeClient((_) => const FakeResponse.offline());
    final g = await RegionsRepository(api2, store, now: () => now.add(const Duration(days: 30))).fetchGeometry('zhytomyrska');
    expect(g.name, 'Житомирська');
    expect(adapter2.requests.length, 1, reason: 'спробував оновити, але взяв копію');
  });

  group('Прогноз офлайн', () {
    const body = {
      'data': {'regionName': 'Житомирська', 'date': '2026-11-10', 'forest': '', 'top1': null, 'alternative': null, 'warnings': []},
    };

    test('без інтернету — останній прогноз для точки з часом збереження', () async {
      final (api1, _) = makeClient((_) => const FakeResponse(200, body));
      await ForecastRepository(api1, store, now: () => now).fetchForecast(lat: 50.2501, lng: 28.6601, date: now);

      final (api2, _) = makeClient((_) => const FakeResponse.offline());
      final r = await ForecastRepository(api2, store, now: () => now).fetchForecast(lat: 50.2504, lng: 28.6598, date: now);
      expect(r.offline, isTrue);
      expect(r.savedAt, now);
      expect(r.value.regionName, 'Житомирська');
    });

    test('помилка сервера (не мережа) не підміняється кешем', () async {
      final (api1, _) = makeClient((_) => const FakeResponse(200, body));
      await ForecastRepository(api1, store, now: () => now).fetchForecast(lat: 50.25, lng: 28.66, date: now);
      final (api2, _) = makeClient((_) => const FakeResponse(403, {'error': 'outside_home_region', 'message': 'Поза областю'}));
      await expectLater(
        ForecastRepository(api2, store, now: () => now).fetchForecast(lat: 50.25, lng: 28.66, date: now),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'outside_home_region')),
      );
    });
  });
}
