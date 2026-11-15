import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_client/features/catalog/catalog_photo.dart';
import 'package:flutter_test/flutter_test.dart';

/// Архів ustar, як пише tarfile.USTAR_FORMAT у build_app_catalog.py.
Uint8List tar(Map<String, List<int>> files) {
  final out = BytesBuilder();
  files.forEach((name, data) {
    final h = Uint8List(512);
    h.setAll(0, name.codeUnits);
    h.setAll(100, '0000644'.codeUnits);
    h.setAll(124, data.length.toRadixString(8).padLeft(11, '0').codeUnits);
    h.setAll(136, '00000000000'.codeUnits);
    h[156] = 0x30;
    h.setAll(257, 'ustar\x0000'.codeUnits);
    h.setAll(148, List.filled(8, 0x20));
    final sum = h.fold<int>(0, (a, b) => a + b);
    h.setAll(148, '${sum.toRadixString(8).padLeft(6, '0')}\x00 '.codeUnits);
    out.add(h);
    out.add(data);
    out.add(Uint8List((512 - data.length % 512) % 512));
  });
  out.add(Uint8List(1024));
  return out.toBytes();
}

void main() {
  test('Архів фото: мініатюри — thumbs.tar, фото виду — <id>.tar', () {
    expect(CatalogPhotoCache.bundleOf('flammulina_velutipes-0-t.webp'), 'thumbs.tar');
    expect(CatalogPhotoCache.bundleOf('flammulina_velutipes-3.webp'), 'flammulina_velutipes.tar');
    expect(CatalogPhotoCache.bundleOf('boletus_edulis-12.webp'), 'boletus_edulis.tar');
  });

  test('Розпаковка tar: імена й вміст, порожні блоки в кінці', () {
    final files = CatalogPhotoCache.untar(tar({'a-0.webp': List.filled(700, 7), 'a-1.webp': [1, 2, 3]}));
    expect(files.keys, ['a-0.webp', 'a-1.webp']);
    expect(files['a-0.webp']!.length, 700);
    expect(files['a-1.webp'], [1, 2, 3]);
    expect(CatalogPhotoCache.untar(Uint8List(10)), isEmpty);
  });

  test('Один архів на вид: завантажується раз, фото зберігаються на телефоні', () async {
    final dir = await Directory.systemTemp.createTemp('catalog_photos');
    addTearDown(() => dir.delete(recursive: true));
    final urls = <String>[];
    CatalogPhotoCache.clear();
    CatalogPhotoCache.directory = () async => dir;
    CatalogPhotoCache.fetcher = (url) async {
      urls.add(url);
      return tar({'x-0.webp': [10], 'x-1.webp': [11]});
    };
    final r = await Future.wait([CatalogPhotoCache.get('x-0.webp'), CatalogPhotoCache.get('x-1.webp')]);
    expect(r, [
      [10],
      [11]
    ]);
    expect(urls, hasLength(1));
    expect(urls.single, endsWith('/catalog-data/x.tar'));
    expect(File('${dir.path}/x-1.webp').readAsBytesSync(), [11]);
    // нове відкриття застосунку — з телефону, без мережі
    CatalogPhotoCache.clear();
    CatalogPhotoCache.fetcher = (_) async => fail('мережа не потрібна');
    expect(await CatalogPhotoCache.get('x-0.webp'), [10]);
  });

  test('Без мережі — null і повторна спроба наступного разу', () async {
    CatalogPhotoCache.clear();
    CatalogPhotoCache.directory = () async => null;
    var calls = 0;
    CatalogPhotoCache.fetcher = (_) async {
      calls++;
      return null;
    };
    expect(await CatalogPhotoCache.get('y-0.webp'), isNull);
    expect(await CatalogPhotoCache.get('y-0.webp'), isNull);
    expect(calls, 2);
  });
}
