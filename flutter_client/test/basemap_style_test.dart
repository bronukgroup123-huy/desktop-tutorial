import 'dart:convert';
import 'dart:ui' show Color;

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

  test('теплова карта (B3.5): своє джерело, шар під ділянками й точками, колір за рівнем', () {
    expect((style['sources'] as Map)[MapSources.heat]['type'], 'geojson');
    expect(index('app_heat_fill'), greaterThan(index('app_region_border')));
    expect(index('app_heat_fill'), lessThan(index('app_areas_fill')));
    expect(index('app_heat_fill'), lessThan(index(MapLayers.picks)));
    expect(jsonEncode(layer('app_heat_fill')['paint']), contains('level'));
  });

  test('лісовий фон має видимий шавлієвий fallback без зміни шарів карти', () {
    final maskPaint = layer('app_mask')['paint'] as Map;
    expect(maskPaint['fill-color'], '#e4ead9');
    expect(maskPaint['fill-opacity'], 0.92);
    expect(index('app_mask'), lessThan(index('app_region_border')));
  });

  testWidgets('лісова карта — справжній офлайн-растр із прозорим вирізом області', (tester) async {
    late MapBackdropImage backdrop;
    await tester.runAsync(() async {
      backdrop = await buildMapBackdropImage(
        bounds: const GeoBounds(southWest: LatLng(49, 23), northEast: LatLng(50.5, 25)),
        region: region,
      );
    });
    expect(backdrop.png.sublist(1, 4), 'PNG'.codeUnits);
    expect(backdrop.png.lengthInBytes, lessThan(512 * 1024));
    final raster = image.decodePng(backdrop.png)!;
    expect(raster.width, mapBackdropRasterSize);
    expect(raster.height, mapBackdropRasterSize);
    expect(raster.getPixel(raster.width ~/ 2, raster.height ~/ 2).a, 0, reason: 'область має бути прозорою');
    expect(raster.getPixel(8, 8).a, greaterThan(0), reason: 'фон поза областю має бути видимим');
    expect(backdrop.extent.southWest.latitude, lessThan(49));
    expect(backdrop.extent.southWest.longitude, lessThan(23));
    expect(backdrop.extent.northEast.latitude, greaterThan(50.5));
    expect(backdrop.extent.northEast.longitude, greaterThan(25));
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
