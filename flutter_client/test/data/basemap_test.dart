import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter_client/data/local/local_store.dart';
import 'package:flutter_client/data/models/region.dart';
import 'package:flutter_client/data/repositories/basemap_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adapter.dart';

void main() {
  const files = RegionForestFiles(
    metaUrl: 'https://example.org/basemap-lvivska.json',
    dataUrl: 'https://example.org/basemap-lvivska.pmtiles',
  );

  late Directory dir;
  late LocalStore store;
  late List<int> data;
  late bool missing;
  String? corruptSha;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mr_basemap_');
    store = LocalStore(Directory('${dir.path}/store'));
    data = List<int>.generate(300000, (i) => i % 251);
    missing = false;
    corruptSha = null;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FakeResponse server(RequestOptions req) {
    if (missing) return const FakeResponse(404, 'Not Found');
    if (req.uri.toString() == files.metaUrl) {
      return FakeResponse(
        200,
        utf8.encode(jsonEncode({
          'slug': 'lvivska',
          'version': '2026-11-14T00:00:00Z',
          'bytes': data.length,
          'sha256': corruptSha ?? sha256.convert(data).toString(),
        })),
      );
    }
    if (req.uri.toString() == files.dataUrl) return FakeResponse(200, data);
    return const FakeResponse(500, null);
  }

  BasemapRepository repo(Dio dio) =>
      BasemapRepository(store, files: dio, directory: () async => Directory('${dir.path}/basemaps'));

  test('карта області: розмір з опису, завантаження один раз, далі — з телефону', () async {
    final (dio, adapter) = makeFilesDio(server);
    final r = repo(dio);
    expect(await r.local('lvivska'), isNull);
    final meta = await r.remote(files);
    expect([meta!.bytes, meta.sizeLabel], [300000, '≈ 1 МБ']);

    // стара карта іншої області видаляється
    File('${dir.path}/basemaps/basemap-kyivska.pmtiles')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    final progress = await r.download('lvivska', files).toList();
    expect(progress.last, 1.0);
    final local = await r.local('lvivska');
    expect(local, isNotNull);
    expect(File(local!.path).readAsBytesSync(), data);
    expect(File('${dir.path}/basemaps/basemap-kyivska.pmtiles').existsSync(), isFalse);

    // далі мережа не потрібна
    final before = adapter.requests.length;
    expect(await r.local('lvivska'), isNotNull);
    expect(adapter.requests.length, before);
  });

  test('пошкоджений файл (sha256) не зберігається; карти для області ще немає (404) → null', () async {
    corruptSha = '0' * 64;
    final (dio, _) = makeFilesDio(server);
    final r = repo(dio);
    await expectLater(r.download('lvivska', files).toList(), throwsA(isA<FormatException>()));
    expect(await r.local('lvivska'), isNull);
    expect(Directory('${dir.path}/basemaps').listSync().whereType<File>(), isEmpty);

    missing = true;
    expect(await r.remote(files), isNull);
  });
}
