import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/data/models/region.dart';
import 'package:flutter_client/data/repositories/forest_zones_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fake_adapter.dart';

Map<String, dynamic> feature(String id) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [28.0, 50.0],
            [28.1, 50.0],
            [28.1, 50.1],
            [28.0, 50.0]
          ],
        ],
      },
      'properties': {'id': id, 'forest_type': 'pine', 'type_label': 'Сосновий ліс', 'type_color': '#81c784'},
    };

List<int> gzFile(List<String> ids) =>
    gzip.encode(utf8.encode(jsonEncode({'type': 'FeatureCollection', 'features': ids.map(feature).toList()})));

void main() {
  const files = RegionForestFiles(
    metaUrl: 'https://example.org/forests-zhytomyrska.json',
    dataUrl: 'https://example.org/forests-zhytomyrska.geojson.gz',
  );
  const region = GeoBounds(southWest: LatLng(50.0, 28.0), northEast: LatLng(50.9, 28.9));

  late Directory dir;
  late LocalStore store;
  late DateTime now;
  late bool online;
  late String version;
  late List<int> data;
  late bool missing;
  String? corruptSha;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mr_forest_file_');
    store = LocalStore(dir);
    now = DateTime(2026, 11, 10, 12);
    online = true;
    version = '2026-11-10T00:00:00Z';
    data = gzFile(['w1', 'w2']);
    missing = false;
    corruptSha = null;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FakeResponse server(RequestOptions req) {
    if (!online) return const FakeResponse.offline();
    if (missing) return const FakeResponse(404, 'Not Found');
    if (req.uri.toString() == files.metaUrl) {
      return FakeResponse(
          200,
          utf8.encode(jsonEncode({
            'slug': 'zhytomyrska',
            'version': version,
            'bytes': data.length,
            'sha256': corruptSha ?? sha256.convert(data).toString(),
          })));
    }
    if (req.uri.toString() == files.dataUrl) return FakeResponse(200, data);
    return const FakeResponse(500, null);
  }

  // Плитки (запасний шлях) — завжди один ліс 't'.
  FakeResponse tilesServer(RequestOptions req) {
    if (!online) return const FakeResponse.offline();
    return FakeResponse(200, {
      'data': {
        'type': 'FeatureCollection',
        'features': [feature('t')]
      },
    });
  }

  ForestZonesRepository repo(Dio filesDio) {
    final (api, _) = makeClient(tilesServer);
    return ForestZonesRepository(api, store, files: filesDio, now: () => now);
  }

  Future<ForestLoad> load(ForestZonesRepository r) => r.loadRegion('zhytomyrska', region, files: files).last;

  test('файл області завантажується один раз і зберігається на телефоні', () async {
    final (dio, adapter) = makeFilesDio(server);
    final r = await load(repo(dio));
    expect(r.zones.map((z) => z.id), ['w1', 'w2']);
    expect(r.complete, isTrue);
    expect(adapter.requests.map((q) => q.uri.toString()), [files.metaUrl, files.dataUrl]);
    expect(await store.readBytes(ForestZonesRepository.fileDataKey('zhytomyrska')), data);

    // Протягом доби — без мережі взагалі.
    adapter.requests.clear();
    final again = await load(repo(dio));
    expect(again.zones.length, 2);
    expect(adapter.requests, isEmpty);
  });

  test('через добу перевіряється лише опис; та сама версія — файл не качається', () async {
    final (dio, adapter) = makeFilesDio(server);
    await load(repo(dio));
    adapter.requests.clear();
    now = now.add(const Duration(hours: 25));
    final r = await load(repo(dio));
    expect(r.zones.length, 2);
    expect(adapter.requests.map((q) => q.uri.toString()), [files.metaUrl]);
  });

  test('нова версія — файл перекачується', () async {
    final (dio, adapter) = makeFilesDio(server);
    await load(repo(dio));
    now = now.add(const Duration(hours: 25));
    version = '2026-12-01T00:00:00Z';
    data = gzFile(['w1', 'w2', 'w3']);
    adapter.requests.clear();
    final r = await load(repo(dio));
    expect(r.zones.length, 3);
    expect(adapter.requests.length, 2);
  });

  test('без інтернету — файл з телефону, позначка offline', () async {
    final (dio, _) = makeFilesDio(server);
    await load(repo(dio));
    now = now.add(const Duration(days: 3));
    online = false;
    final events = await repo(dio).loadRegion('zhytomyrska', region, files: files).toList();
    // спершу — збережений файл одразу, потім — позначка «без інтернету» (версію не перевірено)
    expect(events.map((e) => (e.zones.length, e.offline)).toList(), [(2, false), (2, true)]);
  });

  test('застарілий файл показується одразу; та сама версія — без повторного розбору', () async {
    final (dio, adapter) = makeFilesDio(server);
    await load(repo(dio));
    now = now.add(const Duration(days: 3));
    final before = adapter.requests.length;
    final events = await repo(dio).loadRegion('zhytomyrska', region, files: files).toList();
    expect(events.length, 1, reason: 'версія та сама — друга подія не потрібна');
    expect(events.single.zones.length, 2);
    expect(adapter.requests.length - before, 1, reason: 'лише опис файлу, без повторного завантаження');
  });

  test('пошкоджений файл (sha256 не збігається) не зберігається', () async {
    corruptSha = '0' * 64;
    final (dio, _) = makeFilesDio(server);
    final r = await load(repo(dio));
    // Файлу немає → запасний шлях плитками.
    expect(r.zones.map((z) => z.id).toSet(), {'t'});
    expect(await store.readBytes(ForestZonesRepository.fileDataKey('zhytomyrska')), isNull);
  });

  test('файл для області ще не згенерований (404) → ліси плитками з сервера', () async {
    missing = true;
    final (dio, _) = makeFilesDio(server);
    final r = await load(repo(dio));
    expect(r.zones.map((z) => z.id).toSet(), {'t'});
    expect(r.total, 4);
  });

  test('після завантаження файлу старі плитки й файл іншої області видаляються', () async {
    await store.write('forests_v2_zhytomyrska_100_56', {'type': 'FeatureCollection', 'features': []});
    await store.writeBytes('forestsfile_kyivska.data', [1, 2, 3]);
    await store.write('forestsfile_kyivska.meta', {});
    final (dio, _) = makeFilesDio(server);
    await load(repo(dio));
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {'forestsfile_zhytomyrska.meta.json', 'forestsfile_zhytomyrska.data.bin'});
  });

  test('RegionGeometry читає адреси файлу лісів', () {
    final g = RegionGeometry.fromJson({
      'id': 1,
      'slug': 'zhytomyrska',
      'name': 'Житомирська',
      'bbox': [27.0, 49.5, 29.5, 51.5],
      'center': [28.5, 50.5],
      'zoom': 7,
      'geometry': null,
      'forests': {'meta_url': files.metaUrl, 'data_url': files.dataUrl},
    });
    expect(g.forests?.dataUrl, files.dataUrl);
    expect(
        RegionGeometry.fromJson({
          ...{
            'id': 1,
            'slug': 's',
            'name': 'n',
            'bbox': [0, 0, 1, 1],
            'center': [0.5, 0.5],
            'zoom': 7,
          }
        }).forests,
        isNull);
  });
}
