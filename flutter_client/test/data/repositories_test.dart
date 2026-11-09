import 'dart:io';

import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/data/repositories/forecast_repository.dart';
import 'package:flutter_client/data/repositories/forest_zones_repository.dart';
import 'package:flutter_client/data/repositories/me_repository.dart';
import 'package:flutter_client/data/repositories/regions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fake_adapter.dart';
import 'models_test.dart' show meJson;

LocalStore tempStore() => LocalStore(Directory.systemTemp.createTempSync('mr_test_'));

void main() {
  test('MeRepository.completeOnboarding: PATCH /v1-me зі slug і версією умов', () async {
    final (api, adapter) = makeClient((_) => FakeResponse(200, {
          'data': meJson(region: {'id': 10, 'slug': 'kyivska', 'name': 'Київська'}),
        }));
    final me = await MeRepository(api).completeOnboarding(regionSlug: 'kyivska', termsVersion: '2026-11');
    final req = adapter.requests.single;
    expect(req.method, 'PATCH');
    expect(req.path, '/v1-me');
    expect(req.data, {'home_region_slug': 'kyivska', 'accept_terms_version': '2026-11'});
    expect(me.homeRegion!.slug, 'kyivska');
  });

  test('RegionsRepository: список з /regions і кешування геометрії', () async {
    final (api, adapter) = makeClient((req) {
      if (req.path == '/regions') {
        return const FakeResponse(200, {
          'data': [
            {'id': 10, 'name': 'Київська', 'slug': 'kyivska', 'koatuu': null, 'katottg': 'UA'},
          ],
        });
      }
      return const FakeResponse(200, {
        'data': {
          'id': 10,
          'slug': 'kyivska',
          'name': 'Київська',
          'bbox': [29.3, 49.2, 32.2, 51.6],
          'center': [30.6, 50.4],
          'zoom': 6,
          'geometry': {'type': 'Polygon', 'coordinates': [[[29.3, 49.2], [32.2, 49.2], [32.2, 51.6], [29.3, 49.2]]]},
        },
      });
    });
    final repo = RegionsRepository(api, tempStore());
    expect((await repo.fetchRegions()).single.slug, 'kyivska');

    await repo.fetchGeometry('kyivska');
    await repo.fetchGeometry('kyivska');
    final geometryCalls = adapter.requests.where((r) => r.path.endsWith('/geometry')).toList();
    expect(geometryCalls.length, 1, reason: 'друге звернення — з кешу');
    expect(geometryCalls.single.path, '/v1-regions/kyivska/geometry');
    expect(geometryCalls.single.queryParameters['detail'], 'medium');
  });

  test('ForestZonesRepository: bbox і z у query', () async {
    final (api, adapter) = makeClient((_) => const FakeResponse(200, {
          'data': {'type': 'FeatureCollection', 'features': []},
        }));
    await ForestZonesRepository(api, tempStore()).fetchForestZones(
      bounds: const GeoBounds(southWest: LatLng(50.2, 30.2), northEast: LatLng(50.7, 30.9)),
      zoom: 11,
    );
    final q = adapter.requests.single.queryParameters;
    expect(q['bbox'], '30.20000,50.20000,30.90000,50.70000');
    expect(q['z'], 11);
  });

  test('ForecastRepository: дата YYYY-MM-DD, forestType лише якщо задано', () async {
    final (api, adapter) = makeClient((_) => const FakeResponse(200, {
          'data': {'regionName': null, 'date': '2026-01-05', 'forest': '', 'top1': null, 'alternative': null, 'warnings': []},
        }));
    await ForecastRepository(api, tempStore()).fetchForecast(lat: 50.4, lng: 30.5, date: DateTime(2026, 1, 5));
    expect(adapter.requests.single.data, {'lat': 50.4, 'lng': 30.5, 'date': '2026-01-05'});
  });
}
