import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_client/data/api/api_exception.dart';
import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/repositories/forecast_repository.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/data/repositories/forest_zones_repository.dart';
import 'package:flutter_client/data/repositories/regions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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

  // Область 50.0–50.9 × 28.0–28.9 → 4 плитки по 0.5°.
  const region = GeoBounds(southWest: LatLng(50.0, 28.0), northEast: LatLng(50.9, 28.9));

  FakeResponse forestsServer(RequestOptions req) {
    if (!online) return const FakeResponse.offline();
    final inm = req.headers['If-None-Match'] as String?;
    etagSent.add(inm);
    if (inm == '"v1"') return const FakeResponse(304, null, headers: {'etag': '"v1"'});
    return const FakeResponse(200, {'data': fc}, headers: {'etag': '"v1"'});
  }

  Future<ForestLoad> loadAll(ForestZonesRepository repo, [String slug = 'zhytomyrska']) =>
      repo.loadRegion(slug, region).last;

  group('Ліси області плитками — один раз, далі з телефону', () {
    test('плитки 0.5° покривають область; кожна — окремий невеликий запит з bbox', () async {
      expect(ForestTile.cover(region).length, 4);
      final (api, adapter) = makeClient(forestsServer);
      final r = await loadAll(ForestZonesRepository(api, store, now: () => now));
      expect(adapter.requests.length, 4);
      expect(adapter.requests.map((q) => q.queryParameters['bbox']).toSet(), {
        '28.00000,50.00000,28.50000,50.50000',
        '28.50000,50.00000,29.00000,50.50000',
        '28.00000,50.50000,28.50000,51.00000',
        '28.50000,50.50000,29.00000,51.00000',
      });
      expect(adapter.requests.first.queryParameters['z'], 11);
      // той самий полігон у кількох плитках — на карті один раз
      expect(r.zones.length, 1);
      expect(r.complete, isTrue);
      expect(r.failed, 0);
    });

    test('потік віддає проміжні стани (ліси з\'являються поступово)', () async {
      final (api, _) = makeClient(forestsServer);
      final events = await ForestZonesRepository(api, store, now: () => now).loadRegion('zhytomyrska', region).toList();
      expect(events.first.done, 0);
      expect(events.last.done, 4);
    });

    test('протягом доби — жодного запиту в мережу', () async {
      final (api, adapter) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await loadAll(repo);
      now = now.add(const Duration(hours: 23));
      final r = await loadAll(repo);
      expect(adapter.requests.length, 4);
      expect(r.zones.length, 1);
    });

    test('через добу — перевірка ETag: 304 без тіла', () async {
      final (api, _) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await loadAll(repo);
      now = now.add(const Duration(hours: 25));
      final r = await loadAll(repo);
      expect(etagSent.where((e) => e == '"v1"').length, 4);
      expect(r.zones.length, 1);
    });

    test('без інтернету — плитки з телефону, позначка offline', () async {
      final (api, _) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await loadAll(repo);
      online = false;
      now = now.add(const Duration(days: 3));
      final r = await loadAll(repo);
      expect(r.offline, isTrue);
      expect(r.failed, 0);
      expect(r.zones.single.typeLabel, 'Сосновий ліс');
    });

    test('без інтернету і без копії — плитки рахуються як невдалі (банер на карті)', () async {
      online = false;
      final (api, _) = makeClient(forestsServer);
      final r = await loadAll(ForestZonesRepository(api, store, now: () => now));
      expect(r.failed, 4);
      expect(r.zones, isEmpty);
    });

    test('помилка сервера в одній плитці не ламає інші', () async {
      final (api, _) = makeClient((req) => req.queryParameters['bbox'] == '28.00000,50.00000,28.50000,50.50000'
          ? const FakeResponse(500, {'error': 'db_error'})
          : const FakeResponse(200, {'data': fc}, headers: {'etag': '"v1"'}));
      final r = await loadAll(ForestZonesRepository(api, store, now: () => now));
      expect(r.failed, 1);
      expect(r.zones.length, 1);
    });

    test('зміна області — плитки старої області видаляються (ADR-016)', () async {
      final (api, _) = makeClient(forestsServer);
      final repo = ForestZonesRepository(api, store, now: () => now);
      await loadAll(repo, 'zhytomyrska');
      await loadAll(repo, 'kyivska');
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
      expect(names.where((n) => n.contains('zhytomyrska')), isEmpty);
      expect(names.where((n) => n.startsWith(ForestTile.prefix('kyivska'))).length, 4);
    });

    test('порожні плитки старої версії кешу ігноруються і видаляються', () async {
      await store.write('forests_zhytomyrska_100_56', {'type': 'FeatureCollection', 'features': []}, savedAt: now);
      final (api, adapter) = makeClient(forestsServer);
      final r = await loadAll(ForestZonesRepository(api, store, now: () => now));
      expect(adapter.requests.length, 4, reason: 'стара копія не вважається свіжою');
      expect(r.zones.length, 1);
      expect(await store.read('forests_zhytomyrska_100_56'), isNull);
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
