import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:latlong2/latlong.dart';

import 'package:flutter_client/data/models/geo.dart';
import 'package:flutter_client/features/map/basemap_style.dart';
import 'package:flutter_client/features/map/map_backdrop.dart';
import 'package:flutter_client/features/picks/mushroom_marker.dart';

void main() {
  final region = [
    const GeoPolygon(outer: [LatLng(49, 23), LatLng(49, 25), LatLng(50.5, 25), LatLng(50.5, 23), LatLng(49, 23)]),
  ];
  final style = offlineMapStyle(pmtilesPath: '/data/maps/basemap-lvivska.pmtiles', glyphsDir: '/data/glyphs', region: region);
  final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> layer(String id) => layers.firstWhere((l) => l['id'] == id);
  int index(String id) => layers.indexWhere((l) => l['id'] == id);

  test('офлайн карта MapLibre: дані й шрифт — з телефона (без інтернету)', () {
    expect((style['sources'] as Map)[basemapSource]['url'], 'pmtiles://file:///data/maps/basemap-lvivska.pmtiles');
    expect(style['glyphs'], 'file:///data/glyphs/{fontstack}/{range}.pbf');
    expect(jsonEncode(style).contains('http'), isFalse);
  });

  test('підписи: українська назва (name:uk, інакше name), один шрифт і оформлення', () {
    final labels = layers.where((l) => l['type'] == 'symbol' && l['source'] == basemapSource).toList();
    expect(labels, isNotEmpty);
    expect(jsonEncode(basemapLayers()).contains('name_en'), isFalse);
    for (final l in labels) {
      final layout = l['layout'] as Map;
      expect(layout['text-field'], [
        'coalesce',
        ['get', 'name:uk'],
        ['get', 'name'],
      ]);
      expect(layout['text-font'], [glyphFontStack]);
      expect((l['paint'] as Map)['text-halo-color'], '#ffffff');
    }
  });

  test('підписи за масштабом: міста раніше за села, річки — з z11, струмки й вулиці — з z14', () {
    expect(layer('label_city')['minzoom'], 6);
    expect(layer('label_town')['minzoom'], 9);
    expect(layer('label_village')['minzoom'], 11);
    expect(layer('label_hamlet')['minzoom'], 13);
    expect(layer('label_river')['minzoom'], 11);
    expect(layer('label_stream')['minzoom'], 14);
    expect(layer('label_road')['minzoom'], 14);
  });

  test('ліси: наш шар forests з кольором типу — під дорогами й підписами; лісів OSM немає', () {
    expect(layers.where((l) => jsonEncode(l['filter'] ?? []).contains('wood')), isEmpty);
    expect((layer('forests')['paint'] as Map)['fill-color'], ['coalesce', ['get', 'type_color'], '#b0bec5']);
    expect(index('forests'), lessThan(index('road_primary')));
    expect(index('forests'), lessThan(index('label_village')));
  });

  test('шари застосунку — поверх карти; маска «поза областю» з діркою на місці області', () {
    expect(index('app_mask'), greaterThan(index('label_city')));
    expect(index(MapLayers.picks), layers.length - 1, reason: 'тук-туки — найвище');
    final mask = (style['sources'] as Map)['app_mask']['data'] as Map;
    final rings = (mask['geometry'] as Map)['coordinates'] as List;
    expect(rings.length, 2);
    expect((rings[1] as List).first, [23.0, 49.0]);
    for (final id in [MapSources.areas, MapSources.analysis, MapSources.picks, MapSources.forestPin]) {
      expect((style['sources'] as Map)[id]['type'], 'geojson');
    }
  });

  test('лісовий фон має видимий шавлієвий fallback без зміни шарів карти', () {
    final maskPaint = layer('app_mask')['paint'] as Map;
    expect(maskPaint['fill-color'], '#e4ead9');
    expect(maskPaint['fill-opacity'], 0.92);
    expect(index('app_mask'), lessThan(index('app_region_border')));
  });

  testWidgets('лісова карта — компактний повторюваний офлайн-патерн', (tester) async {
    late Uint8List backdrop;
    await tester.runAsync(() async {
      backdrop = await buildMapBackdropPattern();
    });
    expect(backdrop.sublist(1, 4), 'PNG'.codeUnits);
    expect(backdrop.lengthInBytes, lessThan(256 * 1024));
    final raster = image.decodePng(backdrop)!;
    expect(raster.width, mapBackdropRasterSize);
    expect(raster.height, mapBackdropRasterSize);
    expect(mapBackdropRasterSize & (mapBackdropRasterSize - 1), 0,
        reason: 'MapLibre fill-pattern вимагає степінь двійки');
    expect(mapBackdropPixelRatio, 1,
        reason: 'декор не можна стискати у дрібний помітно повторюваний тайл');
    final colors = <int>{};
    for (var y = 0; y < raster.height; y += 16) {
      for (var x = 0; x < raster.width; x += 16) {
        final pixel = raster.getPixel(x, y);
        colors.add((pixel.r.toInt() << 24) |
            (pixel.g.toInt() << 16) |
            (pixel.b.toInt() << 8) |
            pixel.a.toInt());
      }
    }
    expect(colors.length, greaterThan(8),
        reason: 'патерн не повинен перетворитися на плаский колір');
    expect(raster.getPixel(0, 0).a, 255);
  });

  testWidgets('декоративний фон містить воду, галявини й різні гриби', (tester) async {
    late String source;
    await tester.runAsync(() async {
      source = await rootBundle.loadString(mapBackdropAsset);
    });

    expect(source, contains('id="water-features"'));
    expect(RegExp('data-feature="river"').allMatches(source), hasLength(1));
    expect(RegExp('data-feature="stream"').allMatches(source).length, greaterThanOrEqualTo(2));
    expect(RegExp('data-feature="lake"').allMatches(source).length, greaterThanOrEqualTo(3));
    expect(RegExp('data-feature="meadow"').allMatches(source).length, greaterThanOrEqualTo(6));
    expect(RegExp('<use href="#mushroom-').allMatches(source).length, greaterThanOrEqualTo(14));
    expect(source, contains('href="#mushroom-brown"'));
    expect(source, contains('href="#mushroom-red"'));
    expect(source, contains('href="#mushroom-gold"'));
  });

  testWidgets('маркер тук-тука картинкою для карти — PNG (публічний і приватний)', (tester) async {
    await tester.runAsync(() async {
      for (final private in [false, true]) {
        final png = await mushroomMarkerPng(color: const Color(0xFF4CAF50), isPrivate: private);
        expect(png.sublist(1, 4), 'PNG'.codeUnits);
      }
    });
  });
}
